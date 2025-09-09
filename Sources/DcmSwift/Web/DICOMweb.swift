//
//  DICOMWeb.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//
/**
 DICOMweb Client Facade
 
 High-level interface for all DICOMweb services (WADO-RS, QIDO-RS, STOW-RS).
 Provides a unified API for interacting with DICOMweb servers.
 */
import Foundation
public class DICOMweb {
    
    // MARK: - Properties
    
    /// WADO-RS client for retrieval operations
    public let wado: WADOClient
    
    /// QIDO-RS client for search operations
    public let qido: QIDOClient
    
    /// STOW-RS client for storage operations
    public let stow: STOWClient
    
    /// Base URL of the DICOMweb server
    public let baseURL: URL
    
    /// Custom URLSession for network requests
    private let session: URLSession
    
    // MARK: - Initialization
    
    /**
     Initialize DICOMweb client with server URL
     
     - Parameters:
        - baseURL: The base URL of the DICOMweb server (e.g., "https://server.com/dicomweb")
        - session: Optional custom URLSession (defaults to shared)
        - authorizationHeader: Optional authorization header value (e.g., "Bearer token")
     */
    public init(baseURL: URL, session: URLSession? = nil, authorizationHeader: String? = nil) {
        self.baseURL = baseURL
        
        // Configure session with authorization if provided
        if let authHeader = authorizationHeader {
            let configuration = URLSessionConfiguration.default
            configuration.httpAdditionalHeaders = ["Authorization": authHeader]
            self.session = URLSession(configuration: configuration)
        } else {
            self.session = session ?? .shared
        }
        
        // Initialize service clients
        self.wado = WADOClient(baseURL: baseURL, session: self.session)
        self.qido = QIDOClient(baseURL: baseURL, session: self.session)
        self.stow = STOWClient(baseURL: baseURL, session: self.session)
    }
    
    /**
     Convenience initializer with string URL
     
     - Parameters:
        - urlString: The base URL string of the DICOMweb server
        - session: Optional custom URLSession
        - authorizationHeader: Optional authorization header value
     
     - Throws: Error if URL string is invalid
     */
    public convenience init(urlString: String, session: URLSession? = nil, authorizationHeader: String? = nil) throws {
        guard let url = URL(string: urlString) else {
            throw DICOMWebError.invalidURL("Invalid URL string: \(urlString)")
        }
        self.init(baseURL: url, session: session, authorizationHeader: authorizationHeader)
    }
    
    // MARK: - Common Workflows
    
    /**
     Search and retrieve workflow: Find studies and download them
     
     - Parameters:
        - patientID: Patient ID to search for
        - modality: Optional modality filter
     
     - Returns: Array of retrieved DICOM files
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func searchAndRetrieve(
        patientID: String,
        modality: String? = nil
    ) async throws -> [DicomFile] {
        
        // Search for studies
        let studies = try await qido.searchForStudies(
            patientID: patientID,
            modality: modality
        )
        
        var allFiles: [DicomFile] = []
        
        // Retrieve each study
        for study in studies {
            if let studyUID = QIDOClient.extractValue(from: study, tag: "0020000D") as? String {
                let files = try await wado.retrieveStudy(studyUID: studyUID)
                allFiles.append(contentsOf: files)
            }
        }
        
        return allFiles
    }
    
    /**
     Store and verify workflow: Upload DICOM files and confirm storage
     
     - Parameters:
        - files: Array of DicomFile objects to store
        - verifyStorage: Whether to verify files were stored (default: true)
     
     - Returns: Store response with success/failure information
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func storeAndVerify(
        _ files: [DicomFile],
        verifyStorage: Bool = true
    ) async throws -> StoreResponse {
        
        // Store the files
        let response = try await stow.storeFiles(files)
        
        // Optionally verify storage
        if verifyStorage && response.isCompleteSuccess {
            for sopInstance in response.referencedSOPSequence {
                // Query to verify instance exists
                let results = try await qido.searchForInstances(
                    sopInstanceUID: sopInstance.referencedSOPInstanceUID
                )
                
                if results.isEmpty {
                    throw DICOMWebError.verificationFailed(
                        "Instance \(sopInstance.referencedSOPInstanceUID) not found after storage"
                    )
                }
            }
        }
        
        return response
    }
    
    /**
     Get study metadata with series and instance counts
     
     - Parameters:
        - studyUID: Study Instance UID
     
     - Returns: Study metadata with counts
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func getStudyDetails(studyUID: String) async throws -> StudyDetails {
        
        // Get study metadata
        let studyMetadata = try await wado.retrieveStudyMetadata(studyUID: studyUID)
        
        // Get series for this study
        let series = try await qido.searchForSeries(studyInstanceUID: studyUID)
        
        // Count instances
        var totalInstances = 0
        var modalityCounts: [String: Int] = [:]
        
        for seriesItem in series {
            if let modality = QIDOClient.extractValue(from: seriesItem, tag: "00080060") as? String {
                modalityCounts[modality, default: 0] += 1
            }
            
            if let seriesUID = QIDOClient.extractValue(from: seriesItem, tag: "0020000E") as? String {
                let instances = try await qido.searchForInstances(
                    studyInstanceUID: studyUID,
                    seriesInstanceUID: seriesUID
                )
                totalInstances += instances.count
            }
        }
        
        return StudyDetails(
            studyUID: studyUID,
            metadata: studyMetadata,
            seriesCount: series.count,
            instanceCount: totalInstances,
            modalityCounts: modalityCounts
        )
    }
    
    /**
     Download study as ZIP archive (if server supports it)
     
     - Parameters:
        - studyUID: Study Instance UID
        - outputURL: Local file URL to save the ZIP
     
     - Returns: URL of saved ZIP file
     */
    public func downloadStudyAsZIP(
        studyUID: String,
        outputURL: URL
    ) async throws -> URL {
        
        // Request ZIP format (server-specific)
        let url = baseURL.appendingPathComponent("studies/\(studyUID)")
        var request = URLRequest(url: url)
        request.setValue("application/zip", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                description: "Failed to download ZIP"
            )
        }
        
        // Save to file
        try data.write(to: outputURL)
        return outputURL
    }
    
    // MARK: - Batch Operations
    
    /**
     Batch search for multiple patients
     
     - Parameters:
        - patientIDs: Array of patient IDs
        - includefield: Additional fields to include
     
     - Returns: Dictionary mapping patient ID to their studies
     */
    public func batchSearchPatients(
        patientIDs: [String],
        includefield: [String]? = nil
    ) async throws -> [String: [[String: Any]]] {
        
        var results: [String: [[String: Any]]] = [:]
        
        // Use TaskGroup for concurrent searches
        try await withThrowingTaskGroup(of: (String, [[String: Any]]).self) { group in
            for patientID in patientIDs {
                group.addTask {
                    let studies = try await self.qido.searchForStudies(
                        patientID: patientID,
                        includefield: includefield
                    )
                    return (patientID, studies)
                }
            }
            
            for try await (patientID, studies) in group {
                results[patientID] = studies
            }
        }
        
        return results
    }
    
    /**
     Batch retrieve multiple studies
     
     - Parameters:
        - studyUIDs: Array of study UIDs to retrieve
     
     - Returns: Dictionary mapping study UID to retrieved files
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func batchRetrieveStudies(
        studyUIDs: [String]
    ) async throws -> [String: [DicomFile]] {
        
        var results: [String: [DicomFile]] = [:]
        
        try await withThrowingTaskGroup(of: (String, [DicomFile]).self) { group in
            for studyUID in studyUIDs {
                group.addTask {
                    let files = try await self.wado.retrieveStudy(studyUID: studyUID)
                    return (studyUID, files)
                }
            }
            
            for try await (studyUID, files) in group {
                results[studyUID] = files
            }
        }
        
        return results
    }
    
    // MARK: - Server Capabilities
    
    /**
     Check server capabilities by testing endpoints
     
     - Returns: Server capabilities information
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func checkServerCapabilities() async -> ServerCapabilities {
        // Start with basic capabilities document
        var capabilitiesDict: [String: Any] = [:]
        
        // Test WADO-RS
        var wadoSupported = false
        do {
            _ = try await wado.retrieveStudyMetadata(studyUID: "test")
            wadoSupported = true
        } catch {
            // Expected to fail with test UID
            if case DICOMWebError.networkError(let code, _) = error {
                wadoSupported = (code == 404 || code == 400)
            }
        }
        capabilitiesDict["wadoRSSupported"] = wadoSupported
        
        // Test QIDO-RS
        var qidoSupported = false
        do {
            _ = try await qido.searchForStudies(limit: 1)
            qidoSupported = true
        } catch {
            qidoSupported = false
        }
        capabilitiesDict["qidoRSSupported"] = qidoSupported
        
        // Test STOW-RS (HEAD request)
        var stowSupported = false
        let stowURL = baseURL.appendingPathComponent("studies")
        var request = URLRequest(url: stowURL)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                stowSupported = (httpResponse.statusCode != 404)
            }
        } catch {
            stowSupported = false
        }
        capabilitiesDict["stowRSSupported"] = stowSupported
        
        return ServerCapabilities(from: capabilitiesDict)
    }
}

// MARK: - Supporting Types

public struct StudyDetails {
    public let studyUID: String
    public let metadata: [[String: Any]]
    public let seriesCount: Int
    public let instanceCount: Int
    public let modalityCounts: [String: Int]
}


// MARK: - Error Extension

extension DICOMWebError {
    static func verificationFailed(_ message: String) -> DICOMWebError {
        return .validationError(message)
    }
}