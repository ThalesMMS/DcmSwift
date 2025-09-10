// STOWClient.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import Foundation

/**
 STOW-RS (Store Over the Web) Client
 
 Implements DICOM PS3.18 Chapter 10.5 - Store Transaction
 Provides RESTful storage capabilities for DICOM instances, metadata and bulk data.
 */
public actor STOWClient {
    private let baseURL: URL
    private let session: URLSession
    
    // MARK: - Initialization
    
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    // MARK: - Store DICOM Instances
    
    /**
     Store one or more DICOM instances
     
     - Parameters:
        - instances: Array of DICOM data to store
        - studyInstanceUID: Optional study UID for URL-based storage
     
     - Returns: Store response with success/failure information
     */
    public func storeInstances(
        _ instances: [Data],
        studyInstanceUID: String? = nil
    ) async throws -> StoreResponse {
        
        let path = studyInstanceUID != nil ? "studies/\(studyInstanceUID!)" : "studies"
        let url = baseURL.appendingPathComponent(path)
        
        // Generate multipart boundary
        let boundary = "DICOMwebBoundary\(UUID().uuidString)"
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/related; type=\"application/dicom\"; boundary=\(boundary)", 
                        forHTTPHeaderField: "Content-Type")
        request.setValue("application/dicom+xml", forHTTPHeaderField: "Accept")
        
        // Build multipart body
        let body = buildMultipartBody(instances: instances, boundary: boundary)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        // Check for success (200 OK or 202 Accepted)
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Parse XML response (DICOM PS3.18 Section 10.5.1.2.1)
        return try parseStoreResponse(data)
    }
    
    /**
     Store DICOM files
     
     - Parameters:
        - files: Array of DicomFile objects to store
        - studyInstanceUID: Optional study UID for URL-based storage
     
     - Returns: Store response with success/failure information
     */
    public func storeFiles(
        _ files: [DicomFile],
        studyInstanceUID: String? = nil
    ) async throws -> StoreResponse {
        
        // Convert DicomFile objects to Data
        var instances: [Data] = []
        for file in files {
            // Create temporary file for output
            let tempPath = NSTemporaryDirectory() + UUID().uuidString + ".dcm"
            let outputStream = DicomOutputStream(filePath: tempPath)
            
            // Write file to stream
            _ = try? outputStream.write(dataset: file.dataset)
            
            // Read data and clean up
            if let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)) {
                instances.append(data)
                try? FileManager.default.removeItem(atPath: tempPath)
            }
        }
        
        return try await storeInstances(instances, studyInstanceUID: studyInstanceUID)
    }
    
    // MARK: - Store Metadata
    
    /**
     Store DICOM metadata (without bulk data)
     
     - Parameters:
        - metadata: Array of DICOM JSON metadata objects
        - studyInstanceUID: Optional study UID
     
     - Returns: Store response
     */
    public func storeMetadata(
        _ metadata: [[String: Any]],
        studyInstanceUID: String? = nil
    ) async throws -> StoreResponse {
        
        let path = studyInstanceUID != nil ? "studies/\(studyInstanceUID!)" : "studies"
        let url = baseURL.appendingPathComponent(path)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dicom+xml", forHTTPHeaderField: "Accept")
        
        // Convert metadata to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: metadata)
        request.httpBody = jsonData
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        return try parseStoreResponse(data)
    }
    
    // MARK: - Store with Rendered Data
    
    /**
     Store rendered images (JPEG, PNG, etc.) as DICOM Secondary Capture
     
     - Parameters:
        - imageData: Rendered image data
        - mimeType: MIME type of the image (e.g., "image/jpeg")
        - patientName: Patient name for the created instance
        - patientID: Patient ID for the created instance
        - studyDescription: Study description
        - seriesDescription: Series description
        - studyInstanceUID: Optional specific study UID
        - seriesInstanceUID: Optional specific series UID
        - sopInstanceUID: Optional specific instance UID
     
     - Returns: Store response
     */
    public func storeRenderedImage(
        _ imageData: Data,
        mimeType: String,
        patientName: String? = nil,
        patientID: String? = nil,
        studyDescription: String? = nil,
        seriesDescription: String? = nil,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil
    ) async throws -> StoreResponse {
        
        // Create minimal DICOM metadata for Secondary Capture
        let dataset = DataSet()
        
        // Patient Module
        if let name = patientName {
            dataset.set(value: name, forTagName: "PatientName")
        }
        if let id = patientID {
            dataset.set(value: id, forTagName: "PatientID")
        }
        
        // Study Module
        let finalStudyUID = studyInstanceUID ?? "2.25.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        dataset.set(value: finalStudyUID, forTagName: "StudyInstanceUID")
        dataset.set(value: Date().dicomDateString(), forTagName: "StudyDate")
        dataset.set(value: Date().dicomTimeString(), forTagName: "StudyTime")
        if let desc = studyDescription {
            dataset.set(value: desc, forTagName: "StudyDescription")
        }
        
        // Series Module
        let finalSeriesUID = seriesInstanceUID ?? "2.25.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        dataset.set(value: finalSeriesUID, forTagName: "SeriesInstanceUID")
        dataset.set(value: "OT", forTagName: "Modality") // Other
        dataset.set(value: "1", forTagName: "SeriesNumber")
        if let desc = seriesDescription {
            dataset.set(value: desc, forTagName: "SeriesDescription")
        }
        
        // Instance Module
        let finalSOPUID = sopInstanceUID ?? "2.25.\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        dataset.set(value: finalSOPUID, forTagName: "SOPInstanceUID")
        dataset.set(value: "1.2.840.10008.5.1.4.1.1.7", forTagName: "SOPClassUID") // Secondary Capture
        dataset.set(value: "1", forTagName: "InstanceNumber")
        
        // Image Module
        dataset.set(value: "DERIVED\\SECONDARY", forTagName: "ImageType")
        
        // Add pixel data
        dataset.set(value: imageData, forTagName: "PixelData")
        
        // Convert to DICOM format
        let tempPath = NSTemporaryDirectory() + UUID().uuidString + ".dcm"
        let outputStream = DicomOutputStream(filePath: tempPath)
        _ = try? outputStream.write(dataset: dataset)
        
        // Read data and clean up
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)) else {
            throw DICOMWebError.encodingFailed("Failed to read encoded DICOM data")
        }
        try? FileManager.default.removeItem(atPath: tempPath)
        
        return try await storeInstances([data], studyInstanceUID: finalStudyUID)
    }
    
    // MARK: - Bulk Operations
    
    /**
     Store multiple studies with different patient data
     
     - Parameters:
        - studies: Dictionary mapping study UID to array of instance data
     
     - Returns: Dictionary mapping study UID to store response
     */
    public func storeMultipleStudies(
        _ studies: [String: [Data]]
    ) async throws -> [String: StoreResponse] {
        
        var responses: [String: StoreResponse] = [:]
        
        for (studyUID, instances) in studies {
            do {
                let response = try await storeInstances(instances, studyInstanceUID: studyUID)
                responses[studyUID] = response
            } catch {
                // Create error response
                responses[studyUID] = StoreResponse(
                    retrieveURL: nil,
                    referencedSOPSequence: [],
                    failedSOPSequence: instances.enumerated().map { index, _ in
                        FailedSOPInstance(
                            referencedSOPClassUID: "Unknown",
                            referencedSOPInstanceUID: "Unknown.\(index)",
                            failureReason: error.localizedDescription
                        )
                    }
                )
            }
        }
        
        return responses
    }
    
    // MARK: - Helper Methods
    
    private func buildMultipartBody(instances: [Data], boundary: String) -> Data {
        var body = Data()
        
        for instance in instances {
            // Add boundary
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            
            // Add headers
            body.append("Content-Type: application/dicom\r\n".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
            
            // Add DICOM data
            body.append(instance)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    private func parseStoreResponse(_ data: Data) throws -> StoreResponse {
        // Try to parse as XML (standard response)
        if let xmlString = String(data: data, encoding: .utf8) {
            return try parseXMLResponse(xmlString)
        }
        
        // Try to parse as JSON (some servers return JSON)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try parseJSONResponse(json)
        }
        
        // If empty response with success status, assume all succeeded
        if data.isEmpty {
            return StoreResponse(
                retrieveURL: nil,
                referencedSOPSequence: [],
                failedSOPSequence: []
            )
        }
        
        throw DICOMWebError.parsingFailed("Unable to parse store response")
    }
    
    private func parseXMLResponse(_ xml: String) throws -> StoreResponse {
        // Simple XML parsing for DICOM store response
        // This is a basic implementation - consider using XMLParser for production
        
        var retrieveURL: String?
        var referencedSOPs: [ReferencedSOPInstance] = []
        var failedSOPs: [FailedSOPInstance] = []
        
        // Extract RetrieveURL if present
        if let urlRange = xml.range(of: "<RetrieveURL>(.+?)</RetrieveURL>", options: .regularExpression) {
            retrieveURL = String(xml[urlRange]).replacingOccurrences(of: "<RetrieveURL>", with: "")
                .replacingOccurrences(of: "</RetrieveURL>", with: "")
        }
        
        // Extract Referenced SOP Instances
        let referencedPattern = "<ReferencedSOPSequence>(.+?)</ReferencedSOPSequence>"
        let referencedMatches = xml.matches(of: referencedPattern)
        
        for match in referencedMatches {
            let matchRange = Range(match.range, in: xml)!
            let matchString = String(xml[matchRange])
            if let classUID = extractXMLValue(from: matchString, tag: "ReferencedSOPClassUID"),
               let instanceUID = extractXMLValue(from: matchString, tag: "ReferencedSOPInstanceUID") {
                
                let retrieveURL = extractXMLValue(from: matchString, tag: "RetrieveURL")
                referencedSOPs.append(ReferencedSOPInstance(
                    referencedSOPClassUID: classUID,
                    referencedSOPInstanceUID: instanceUID,
                    retrieveURL: retrieveURL
                ))
            }
        }
        
        // Extract Failed SOP Instances
        let failedPattern = "<FailedSOPSequence>(.+?)</FailedSOPSequence>"
        let failedMatches = xml.matches(of: failedPattern)
        
        for match in failedMatches {
            let matchRange = Range(match.range, in: xml)!
            let matchString = String(xml[matchRange])
            if let classUID = extractXMLValue(from: matchString, tag: "ReferencedSOPClassUID"),
               let instanceUID = extractXMLValue(from: matchString, tag: "ReferencedSOPInstanceUID") {
                
                let reason = extractXMLValue(from: matchString, tag: "FailureReason") ?? "Unknown error"
                failedSOPs.append(FailedSOPInstance(
                    referencedSOPClassUID: classUID,
                    referencedSOPInstanceUID: instanceUID,
                    failureReason: reason
                ))
            }
        }
        
        return StoreResponse(
            retrieveURL: retrieveURL,
            referencedSOPSequence: referencedSOPs,
            failedSOPSequence: failedSOPs
        )
    }
    
    private func extractXMLValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>(.+?)</\(tag)>"
        if let range = xml.range(of: pattern, options: .regularExpression) {
            let value = String(xml[range])
                .replacingOccurrences(of: "<\(tag)>", with: "")
                .replacingOccurrences(of: "</\(tag)>", with: "")
            return value.isEmpty ? nil : value
        }
        return nil
    }
    
    private func parseJSONResponse(_ json: [String: Any]) throws -> StoreResponse {
        // Parse JSON response format (non-standard but used by some servers)
        
        var referencedSOPs: [ReferencedSOPInstance] = []
        var failedSOPs: [FailedSOPInstance] = []
        
        if let references = json["00081199"] as? [String: Any],  // ReferencedSOPSequence
           let items = references["Value"] as? [[String: Any]] {
            for item in items {
                if let classUID = extractJSONValue(from: item, tag: "00081150") as? String,  // ReferencedSOPClassUID
                   let instanceUID = extractJSONValue(from: item, tag: "00081155") as? String {  // ReferencedSOPInstanceUID
                    
                    let retrieveURL = extractJSONValue(from: item, tag: "00081190") as? String  // RetrieveURL
                    referencedSOPs.append(ReferencedSOPInstance(
                        referencedSOPClassUID: classUID,
                        referencedSOPInstanceUID: instanceUID,
                        retrieveURL: retrieveURL
                    ))
                }
            }
        }
        
        if let failures = json["00081198"] as? [String: Any],  // FailedSOPSequence
           let items = failures["Value"] as? [[String: Any]] {
            for item in items {
                if let classUID = extractJSONValue(from: item, tag: "00081150") as? String,
                   let instanceUID = extractJSONValue(from: item, tag: "00081155") as? String {
                    
                    let reason = extractJSONValue(from: item, tag: "00081197") as? String ?? "Unknown error"  // FailureReason
                    failedSOPs.append(FailedSOPInstance(
                        referencedSOPClassUID: classUID,
                        referencedSOPInstanceUID: instanceUID,
                        failureReason: reason
                    ))
                }
            }
        }
        
        let retrieveURL = extractJSONValue(from: json, tag: "00081190") as? String
        
        return StoreResponse(
            retrieveURL: retrieveURL,
            referencedSOPSequence: referencedSOPs,
            failedSOPSequence: failedSOPs
        )
    }
    
    private func extractJSONValue(from json: [String: Any], tag: String) -> Any? {
        guard let attribute = json[tag] as? [String: Any],
              let value = attribute["Value"] as? [Any],
              !value.isEmpty else {
            return nil
        }
        return value.count == 1 ? value[0] : value
    }
}

// MARK: - Response Models

public struct StoreResponse {
    public let retrieveURL: String?
    public let referencedSOPSequence: [ReferencedSOPInstance]
    public let failedSOPSequence: [FailedSOPInstance]
    
    public var isCompleteSuccess: Bool {
        return !referencedSOPSequence.isEmpty && failedSOPSequence.isEmpty
    }
    
    public var isPartialSuccess: Bool {
        return !referencedSOPSequence.isEmpty && !failedSOPSequence.isEmpty
    }
    
    public var isCompleteFailure: Bool {
        return referencedSOPSequence.isEmpty && !failedSOPSequence.isEmpty
    }
    
    public var successCount: Int {
        return referencedSOPSequence.count
    }
    
    public var failureCount: Int {
        return failedSOPSequence.count
    }
}

public struct ReferencedSOPInstance {
    public let referencedSOPClassUID: String
    public let referencedSOPInstanceUID: String
    public let retrieveURL: String?
}

public struct FailedSOPInstance {
    public let referencedSOPClassUID: String
    public let referencedSOPInstanceUID: String
    public let failureReason: String
}


// MARK: - String Extension for Regex

private extension String {
    func matches(of pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.matches(in: self, options: [], range: range)
    }
}