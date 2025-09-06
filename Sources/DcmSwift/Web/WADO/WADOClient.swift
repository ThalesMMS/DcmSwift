//
//  WADOClient.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/**
 WADO (Web Access to DICOM Objects) client implementation.
 
 Supports both WADO-RS (RESTful) and WADO-URI (URI-based) protocols for retrieving
 DICOM objects, metadata, and rendered images from a DICOMWeb server.
 
 ## WADO-RS (RESTful Services)
 - Retrieve studies, series, instances
 - Fetch metadata in JSON/XML format
 - Access bulk data and pixel data
 - Request rendered images (JPEG, PNG)
 
 ## WADO-URI (URI-based)
 - Simple URL-based retrieval
 - Direct image rendering
 - Legacy compatibility
 
 Reference: DICOM PS3.18 Section 6 (WADO-RS) and Section 8 (WADO-URI)
 
 ## Example Usage:
 ```swift
 let wado = WADOClient(baseURL: URL(string: "https://server.com/dicom-web")!)
 
 // Retrieve a study
 let study = try await wado.retrieveStudy(studyUID: "1.2.840.113619.2.55.3")
 
 // Get rendered image
 let jpeg = try await wado.retrieveRenderedInstance(
     studyUID: "1.2.840.113619.2.55.3",
     seriesUID: "1.2.840.113619.2.55.3.604688",
     instanceUID: "1.2.840.113619.2.55.3.604688.11",
     format: .jpeg
 )
 ```
 */
public class WADOClient: DICOMWebClient {
    
    // MARK: - WADO-RS Endpoints
    
    /// WADO-RS base path
    private let wadoRSPath = "studies"
    
    // MARK: - Study Level Retrieval
    
    /**
     Retrieves all instances in a study
     
     - Parameter studyUID: The Study Instance UID
     - Returns: Array of DICOM files
     
     - Note: This retrieves the full DICOM objects, not just metadata
     
     ## Endpoint:
     `GET /studies/{studyUID}`
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveStudy(studyUID: String) async throws -> [DicomFile] {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for study \(studyUID)")
        }
        
        // Create request with appropriate headers
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("multipart/related; type=\"application/dicom\"", forHTTPHeaderField: "Accept")
        
        // Add authentication if configured
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Extract Content-Type and boundary
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") else {
            throw DICOMWebError.missingBoundaryInHeader
        }
        
        guard let boundary = DICOMWebUtils.extractBoundary(from: contentType) else {
            throw DICOMWebError.missingBoundaryInHeader
        }
        
        // Parse multipart response
        let parts = try MultipartParser.parse(data: data, boundary: boundary)
        
        // Convert each part to DicomFile
        var dicomFiles: [DicomFile] = []
        for partData in parts {
            // Create DicomInputStream from part data
            let inputStream = DicomInputStream(data: partData)
            
            do {
                // Read DICOM dataset
                let dataset = try inputStream.readDataset()
                
                // Create DicomFile with the dataset
                let dicomFile = DicomFile()
                dicomFile.dataset = dataset
                
                // Note: Transfer syntax extraction would need headers parsing
                // For now, using default transfer syntax
                
                dicomFiles.append(dicomFile)
            } catch {
                // Log warning but continue processing other parts
                Logger.warning("[WADOClient] Failed to parse DICOM part: \(error)")
            }
        }
        
        Logger.info("[WADOClient] Retrieved \(dicomFiles.count) instances from study \(studyUID)")
        return dicomFiles
    }
    
    /// Extracts transfer syntax UID from Content-Type header
    private func extractTransferSyntax(from contentType: String) -> String? {
        let components = contentType.components(separatedBy: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("transfer-syntax=") {
                let syntax = trimmed.dropFirst("transfer-syntax=".count)
                return String(syntax).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
    
    // MARK: - Series Level Retrieval
    
    /**
     Retrieves all instances in a series
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
     - Returns: Array of DICOM files
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}`
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveSeries(
        studyUID: String,
        seriesUID: String
    ) async throws -> [DicomFile] {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for series \(seriesUID)")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("multipart/related; type=\"application/dicom\"", forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Extract boundary
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              let boundary = DICOMWebUtils.extractBoundary(from: contentType) else {
            throw DICOMWebError.missingBoundaryInHeader
        }
        
        // Parse multipart response
        let parts = try MultipartParser.parse(data: data, boundary: boundary)
        
        // Convert to DicomFiles
        var dicomFiles: [DicomFile] = []
        for partData in parts {
            let inputStream = DicomInputStream(data: partData)
            do {
                let dataset = try inputStream.readDataset()
                let dicomFile = DicomFile()
                dicomFile.dataset = dataset
                dicomFiles.append(dicomFile)
            } catch {
                Logger.warning("[WADOClient] Failed to parse DICOM part: \(error)")
            }
        }
        
        Logger.info("[WADOClient] Retrieved \(dicomFiles.count) instances from series \(seriesUID)")
        return dicomFiles
    }
    
    // MARK: - Instance Level Retrieval
    
    /**
     Retrieves a specific DICOM instance
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID
     - Returns: DICOM file
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}`
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> DicomFile {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for instance \(instanceUID)")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("multipart/related; type=\"application/dicom\"", forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Check if response is multipart
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("multipart") {
            // Parse multipart response
            guard let boundary = DICOMWebUtils.extractBoundary(from: contentType) else {
                throw DICOMWebError.missingBoundaryInHeader
            }
            
            let parts = try MultipartParser.parse(data: data, boundary: boundary)
            
            guard let firstPart = parts.first else {
                throw DICOMWebError.noDataReceived
            }
            
            // Convert first part to DicomFile
            let inputStream = DicomInputStream(data: firstPart)
            let dataset = try inputStream.readDataset()
            let dicomFile = DicomFile()
            dicomFile.dataset = dataset
            
            Logger.info("[WADOClient] Retrieved instance \(instanceUID)")
            return dicomFile
        } else {
            // Single part response - direct DICOM data
            let inputStream = DicomInputStream(data: data)
            let dataset = try inputStream.readDataset()
            let dicomFile = DicomFile()
            dicomFile.dataset = dataset
            
            Logger.info("[WADOClient] Retrieved instance \(instanceUID)")
            return dicomFile
        }
    }
    
    // MARK: - Metadata Retrieval
    
    /**
     Retrieves metadata for a study in JSON format
     
     - Parameter studyUID: The Study Instance UID
     - Returns: JSON metadata as array of dictionaries (one per instance)
     
     ## Endpoint:
     `GET /studies/{studyUID}/metadata`
     
     ## Response Format:
     Returns an array of DICOM JSON objects, each representing an instance's metadata
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveStudyMetadata(studyUID: String) async throws -> [[String: Any]] {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/metadata") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for study metadata \(studyUID)")
        }
        
        // Create request with JSON accept header
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        // Add authentication if configured
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Parse JSON response
        do {
            guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                throw DICOMWebError.parsingFailed("Response is not a valid JSON array")
            }
            
            Logger.info("[WADOClient] Retrieved metadata for \(jsonArray.count) instances from study \(studyUID)")
            return jsonArray
        } catch {
            throw DICOMWebError.parsingFailed("Failed to parse JSON response: \(error.localizedDescription)")
        }
    }
    
    /**
     Retrieves metadata for a series in JSON format
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
     - Returns: JSON metadata as array of dictionaries (one per instance in the series)
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/metadata`
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveSeriesMetadata(
        studyUID: String,
        seriesUID: String
    ) async throws -> [[String: Any]] {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/metadata") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for series metadata \(seriesUID)")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Parse JSON response
        do {
            guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                throw DICOMWebError.parsingFailed("Response is not a valid JSON array")
            }
            
            Logger.info("[WADOClient] Retrieved metadata for \(jsonArray.count) instances from series \(seriesUID)")
            return jsonArray
        } catch {
            throw DICOMWebError.parsingFailed("Failed to parse JSON response: \(error.localizedDescription)")
        }
    }
    
    /**
     Retrieves metadata for a specific instance in JSON format
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID
     - Returns: JSON metadata as dictionary
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/metadata`
     
     ## Note:
     Unlike study and series metadata which return arrays, instance metadata
     typically returns an array with a single element
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveInstanceMetadata(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> [String: Any] {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)/metadata") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for instance metadata \(instanceUID)")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Parse JSON response
        do {
            // Instance metadata returns an array with typically one element
            guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
                  let firstInstance = jsonArray.first else {
                throw DICOMWebError.parsingFailed("Response is not a valid JSON array or is empty")
            }
            
            Logger.info("[WADOClient] Retrieved metadata for instance \(instanceUID)")
            return firstInstance
        } catch {
            throw DICOMWebError.parsingFailed("Failed to parse JSON response: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Rendered Image Retrieval
    
    public enum ImageFormat {
        case jpeg
        case png
        case gif
        
        var mimeType: String {
            switch self {
            case .jpeg: return "image/jpeg"
            case .png: return "image/png"
            case .gif: return "image/gif"
            }
        }
    }
    
    /**
     Retrieves a rendered (not DICOM) image
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID
        - format: Desired image format (JPEG, PNG, etc.)
        - quality: JPEG quality 1-100 (optional, only for JPEG)
        - viewport: Window width/center in format "width,center" (optional)
        - presentationUID: Presentation State UID to apply (optional)
        - annotations: Include annotations ("patient", "technique", or "patient,technique")
     
     - Returns: Rendered image data
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/rendered`
     
     ## Query Parameters:
     - `quality`: JPEG compression quality (1-100)
     - `viewport`: Windowing parameters (e.g., "512,40" for width 512, center 40)
     - `presentationUID`: Apply specific presentation state
     - `annotation`: Burned-in annotations
     
     ## Reference:
     DICOM PS3.18 Section 10.4.1.1.3 - Rendered Resources
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveRenderedInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        format: ImageFormat = .jpeg,
        quality: Int? = nil,
        viewport: String? = nil,
        presentationUID: String? = nil,
        annotations: String? = nil
    ) async throws -> Data {
        // Build base URL
        guard var urlComponents = URLComponents(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)/rendered") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for rendered instance")
        }
        
        // Add query parameters
        var queryItems: [URLQueryItem] = []
        
        if let quality = quality, format == .jpeg {
            queryItems.append(URLQueryItem(name: "quality", value: "\(quality)"))
        }
        
        if let viewport = viewport {
            queryItems.append(URLQueryItem(name: "viewport", value: viewport))
        }
        
        if let presentationUID = presentationUID {
            queryItems.append(URLQueryItem(name: "presentationUID", value: presentationUID))
        }
        
        if let annotations = annotations {
            queryItems.append(URLQueryItem(name: "annotation", value: annotations))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        guard let url = urlComponents.url else {
            throw DICOMWebError.invalidURL("Failed to construct URL with query parameters")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(format.mimeType, forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Validate content type
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            let expectedTypes = [format.mimeType, "image/*"]
            let hasValidType = expectedTypes.contains { contentType.contains($0) }
            
            if !hasValidType {
                Logger.warning("[WADOClient] Unexpected content type: \(contentType), expected: \(format.mimeType)")
            }
        }
        
        Logger.info("[WADOClient] Retrieved rendered image for instance \(instanceUID), size: \(data.count) bytes")
        return data
    }
    
    // MARK: - Frames Retrieval
    
    /**
     Retrieves specific frames from a multi-frame instance
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID
        - frameNumbers: Array of frame numbers (1-based indexing)
        - mediaType: Preferred media type (default: application/octet-stream)
     
     - Returns: Array of frame data (one Data object per frame)
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frameList}`
     
     ## Notes:
     - Frame numbers use 1-based indexing (first frame is 1, not 0)
     - Multiple frames return a multipart response
     - Single frame returns the raw frame data
     
     ## Reference:
     DICOM PS3.18 Section 10.4.1.1.6 - Pixel Data Resources
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveFrames(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        frameNumbers: [Int],
        mediaType: String = "application/octet-stream"
    ) async throws -> [Data] {
        guard !frameNumbers.isEmpty else {
            throw DICOMWebError.invalidRequest("Frame numbers array cannot be empty")
        }
        
        // Build frame list (comma-separated)
        let frameList = frameNumbers.map { String($0) }.joined(separator: ",")
        
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)/frames/\(frameList)") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for frames")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Set Accept header based on number of frames
        if frameNumbers.count == 1 {
            request.setValue(mediaType, forHTTPHeaderField: "Accept")
        } else {
            request.setValue("multipart/related; type=\"\(mediaType)\"", forHTTPHeaderField: "Accept")
        }
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Parse response based on Content-Type
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("multipart") {
            // Multiple frames - parse multipart response
            guard let boundary = DICOMWebUtils.extractBoundary(from: contentType) else {
                throw DICOMWebError.missingBoundaryInHeader
            }
            
            let parts = try MultipartParser.parse(data: data, boundary: boundary)
            
            var frames: [Data] = []
            for partData in parts {
                frames.append(partData)
            }
            
            Logger.info("[WADOClient] Retrieved \(frames.count) frames from instance \(instanceUID)")
            return frames
        } else {
            // Single frame - return as single element array
            Logger.info("[WADOClient] Retrieved single frame from instance \(instanceUID)")
            return [data]
        }
    }
    
    /**
     Retrieves rendered frames from a multi-frame instance
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID
        - frameNumbers: Array of frame numbers (1-based indexing)
        - format: Image format for rendered frames
        - viewport: Windowing parameters (optional)
     
     - Returns: Array of rendered frame data
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frameList}/rendered`
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveRenderedFrames(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        frameNumbers: [Int],
        format: ImageFormat = .jpeg,
        viewport: String? = nil
    ) async throws -> [Data] {
        guard !frameNumbers.isEmpty else {
            throw DICOMWebError.invalidRequest("Frame numbers array cannot be empty")
        }
        
        // Build frame list
        let frameList = frameNumbers.map { String($0) }.joined(separator: ",")
        
        // Build URL with query parameters
        guard var urlComponents = URLComponents(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)/frames/\(frameList)/rendered") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for rendered frames")
        }
        
        // Add viewport parameter if specified
        if let viewport = viewport {
            urlComponents.queryItems = [URLQueryItem(name: "viewport", value: viewport)]
        }
        
        guard let url = urlComponents.url else {
            throw DICOMWebError.invalidURL("Failed to construct URL with query parameters")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Set Accept header
        if frameNumbers.count == 1 {
            request.setValue(format.mimeType, forHTTPHeaderField: "Accept")
        } else {
            request.setValue("multipart/related; type=\"\(format.mimeType)\"", forHTTPHeaderField: "Accept")
        }
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Parse response
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("multipart") {
            // Multiple frames
            guard let boundary = DICOMWebUtils.extractBoundary(from: contentType) else {
                throw DICOMWebError.missingBoundaryInHeader
            }
            
            let parts = try MultipartParser.parse(data: data, boundary: boundary)
            
            var frames: [Data] = []
            for partData in parts {
                frames.append(partData)
            }
            
            Logger.info("[WADOClient] Retrieved \(frames.count) rendered frames")
            return frames
        } else {
            // Single frame
            Logger.info("[WADOClient] Retrieved single rendered frame")
            return [data]
        }
    }
    
    // MARK: - Bulk Data Retrieval
    
    /**
     Retrieves bulk data (like pixel data) via a BulkDataURI
     
     - Parameter bulkDataURI: The URI pointing to bulk data
     - Returns: Bulk data
     
     ## Note:
     Bulk data URIs are provided in metadata responses for large binary elements.
     These URIs typically point to specific elements like Pixel Data (7FE0,0010).
     
     ## Example:
     When retrieving metadata, large binary elements are replaced with BulkDataURI:
     ```
     {
       "7FE00010": {
         "vr": "OB",
         "BulkDataURI": "https://server/studies/1.2.3/series/4.5.6/instances/7.8.9/bulkdata/7FE00010"
       }
     }
     ```
     
     ## Reference:
     DICOM PS3.18 Section 10.4.1.1.5 - Bulkdata Resources
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveBulkData(bulkDataURI: URL) async throws -> Data {
        // Create request for the bulk data URI
        var request = URLRequest(url: bulkDataURI)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        
        // Add authentication if the URI is from our server
        if bulkDataURI.host == baseURL.host {
            addAuthenticationHeaders(to: &request)
        }
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        Logger.info("[WADOClient] Retrieved bulk data from \(bulkDataURI), size: \(data.count) bytes")
        return data
    }
    
    /**
     Retrieves all bulk data for a study
     
     - Parameter studyUID: The Study Instance UID
     - Returns: Dictionary mapping BulkDataURIs to their data
     
     ## Endpoint:
     `GET /studies/{studyUID}/bulkdata`
     
     ## Note:
     This retrieves ALL bulk data for a study, which can be very large.
     Consider using instance-level or specific element retrieval for better performance.
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveStudyBulkData(studyUID: String) async throws -> [String: Data] {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/bulkdata") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for study bulk data")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("multipart/related; type=\"application/octet-stream\"", forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        // Parse multipart response
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              let boundary = DICOMWebUtils.extractBoundary(from: contentType) else {
            throw DICOMWebError.missingBoundaryInHeader
        }
        
        let parts = try MultipartParser.parse(data: data, boundary: boundary)
        
        // Build dictionary of URI to data
        var bulkDataMap: [String: Data] = [:]
        // Note: Simple implementation - assumes each part is bulk data in order
        // In production, would need to parse Content-Location headers
        for (index, partData) in parts.enumerated() {
            bulkDataMap["bulk-\(index)"] = partData
        }
        
        Logger.info("[WADOClient] Retrieved \(bulkDataMap.count) bulk data elements for study \(studyUID)")
        return bulkDataMap
    }
    
    /**
     Retrieves pixel data for an instance
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID
     
     - Returns: Pixel data
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/pixeldata`
     
     ## Note:
     This is a convenience method specifically for retrieving pixel data.
     For compressed pixel data, the server may return multiple fragments.
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrievePixelData(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> Data {
        // Build URL
        guard let url = URL(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)/pixeldata") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for pixel data")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        Logger.info("[WADOClient] Retrieved pixel data for instance \(instanceUID), size: \(data.count) bytes")
        return data
    }
    
    // MARK: - WADO-URI Support
    
    /**
     Retrieves DICOM object using WADO-URI protocol (legacy)
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID (objectUID in WADO-URI)
        - contentType: Desired content type (default: "application/dicom")
        - anonymize: Whether to anonymize the object ("yes" or "no")
        - transferSyntax: Specific transfer syntax UID (optional)
        - charset: Character set (optional)
        - frameNumber: Specific frame number for multi-frame images (optional)
        - rows: Image height for rendered images (optional)
        - columns: Image width for rendered images (optional)
        - region: Region of interest (optional, format: "x1,y1,x2,y2")
        - windowCenter: Window center for rendered images (optional)
        - windowWidth: Window width for rendered images (optional)
        - quality: JPEG quality 1-100 (optional)
     
     - Returns: Object data
     
     ## Example URI:
     `GET /wado?requestType=WADO&studyUID=1.2.3&seriesUID=4.5.6&objectUID=7.8.9&contentType=image/jpeg`
     
     ## Notes:
     WADO-URI is the legacy protocol. New implementations should prefer WADO-RS.
     This method provides compatibility with older PACS systems.
     
     ## Reference:
     DICOM PS3.18 Section 9 - URI Service
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveViaURI(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        contentType: String = "application/dicom",
        anonymize: Bool = false,
        transferSyntax: String? = nil,
        charset: String? = nil,
        frameNumber: Int? = nil,
        rows: Int? = nil,
        columns: Int? = nil,
        region: String? = nil,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        quality: Int? = nil
    ) async throws -> Data {
        // Build query parameters
        guard var urlComponents = URLComponents(string: "\(baseURL.absoluteString)/wado") else {
            throw DICOMWebError.invalidURL("Failed to construct WADO-URI URL")
        }
        
        // Required parameters
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "requestType", value: "WADO"),
            URLQueryItem(name: "studyUID", value: studyUID),
            URLQueryItem(name: "seriesUID", value: seriesUID),
            URLQueryItem(name: "objectUID", value: instanceUID),  // Note: WADO-URI uses "objectUID"
            URLQueryItem(name: "contentType", value: contentType)
        ]
        
        // Optional parameters
        if anonymize {
            queryItems.append(URLQueryItem(name: "anonymize", value: "yes"))
        }
        
        if let transferSyntax = transferSyntax {
            queryItems.append(URLQueryItem(name: "transferSyntax", value: transferSyntax))
        }
        
        if let charset = charset {
            queryItems.append(URLQueryItem(name: "charset", value: charset))
        }
        
        if let frameNumber = frameNumber {
            queryItems.append(URLQueryItem(name: "frameNumber", value: "\(frameNumber)"))
        }
        
        if let rows = rows {
            queryItems.append(URLQueryItem(name: "rows", value: "\(rows)"))
        }
        
        if let columns = columns {
            queryItems.append(URLQueryItem(name: "columns", value: "\(columns)"))
        }
        
        if let region = region {
            queryItems.append(URLQueryItem(name: "region", value: region))
        }
        
        if let windowCenter = windowCenter {
            queryItems.append(URLQueryItem(name: "windowCenter", value: "\(windowCenter)"))
        }
        
        if let windowWidth = windowWidth {
            queryItems.append(URLQueryItem(name: "windowWidth", value: "\(windowWidth)"))
        }
        
        if let quality = quality, contentType.contains("jpeg") {
            queryItems.append(URLQueryItem(name: "quality", value: "\(quality)"))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw DICOMWebError.invalidURL("Failed to construct URL with query parameters")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // WADO-URI doesn't use Accept header, content type is in query parameter
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        Logger.info("[WADOClient] Retrieved object via WADO-URI, size: \(data.count) bytes")
        return data
    }
    
    /**
     Builds a WADO-URI URL for direct access
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - instanceUID: The SOP Instance UID
        - contentType: Desired content type
        - additionalParams: Additional query parameters as dictionary
     
     - Returns: Complete WADO-URI URL
     
     ## Example:
     ```swift
     let url = wadoClient.buildWADOURI(
         studyUID: "1.2.3",
         seriesUID: "4.5.6", 
         instanceUID: "7.8.9",
         contentType: "image/jpeg"
     )
     // Returns: https://server/wado?requestType=WADO&studyUID=1.2.3&seriesUID=4.5.6&objectUID=7.8.9&contentType=image/jpeg
     ```
     */
    public func buildWADOURI(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        contentType: String = "application/dicom",
        additionalParams: [String: String] = [:]
    ) -> URL? {
        guard var urlComponents = URLComponents(string: "\(baseURL.absoluteString)/wado") else {
            return nil
        }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "requestType", value: "WADO"),
            URLQueryItem(name: "studyUID", value: studyUID),
            URLQueryItem(name: "seriesUID", value: seriesUID),
            URLQueryItem(name: "objectUID", value: instanceUID),
            URLQueryItem(name: "contentType", value: contentType)
        ]
        
        // Add additional parameters
        for (key, value) in additionalParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        urlComponents.queryItems = queryItems
        return urlComponents.url
    }
    
    // MARK: - Thumbnail Retrieval
    
    /**
     Retrieves a thumbnail image for an instance
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID  
        - instanceUID: The SOP Instance UID
        - viewport: Viewport specification for thumbnail size (e.g., "rows=128,columns=128" or "128")
        - format: Image format for the thumbnail (default: JPEG)
     
     - Returns: Thumbnail image data
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/thumbnail`
     
     ## Notes:
     - Thumbnails are typically 64x64, 128x128, or 256x256 pixels
     - The server may return a different size based on its configuration
     - Format is usually JPEG for efficiency
     
     ## Reference:
     DICOM PS3.18 Section 10.4.1.1.4 - Thumbnail Resources
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveThumbnail(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        viewport: String = "128",
        format: ImageFormat = .jpeg
    ) async throws -> Data {
        // Build base URL
        guard var urlComponents = URLComponents(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)/thumbnail") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for thumbnail")
        }
        
        // Add viewport query parameter if specified
        var queryItems: [URLQueryItem] = []
        
        // Support both simple size (e.g., "128") and full viewport specification
        if viewport.contains("=") {
            // Full viewport specification like "rows=128,columns=128"
            queryItems.append(URLQueryItem(name: "viewport", value: viewport))
        } else {
            // Simple size specification, convert to rows/columns
            queryItems.append(URLQueryItem(name: "viewport", value: "rows=\(viewport),columns=\(viewport)"))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        guard let url = urlComponents.url else {
            throw DICOMWebError.invalidURL("Failed to construct URL with query parameters")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(format.mimeType, forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        Logger.info("[WADOClient] Retrieved thumbnail for instance \(instanceUID), size: \(data.count) bytes")
        return data
    }
    
    /**
     Retrieves a thumbnail for a series (representative image)
     
     - Parameters:
        - studyUID: The Study Instance UID
        - seriesUID: The Series Instance UID
        - viewport: Viewport specification for thumbnail size
        - format: Image format for the thumbnail
     
     - Returns: Thumbnail image data
     
     ## Endpoint:
     `GET /studies/{studyUID}/series/{seriesUID}/thumbnail`
     */
    @available(macOS 12.0, iOS 15.0, *)
    public func retrieveSeriesThumbnail(
        studyUID: String,
        seriesUID: String,
        viewport: String = "128",
        format: ImageFormat = .jpeg
    ) async throws -> Data {
        // Build URL
        guard var urlComponents = URLComponents(string: "\(baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/thumbnail") else {
            throw DICOMWebError.invalidURL("Failed to construct URL for series thumbnail")
        }
        
        // Add viewport parameter
        var queryItems: [URLQueryItem] = []
        if viewport.contains("=") {
            queryItems.append(URLQueryItem(name: "viewport", value: viewport))
        } else {
            queryItems.append(URLQueryItem(name: "viewport", value: "rows=\(viewport),columns=\(viewport)"))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        guard let url = urlComponents.url else {
            throw DICOMWebError.invalidURL("Failed to construct URL with query parameters")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(format.mimeType, forHTTPHeaderField: "Accept")
        
        // Add authentication
        addAuthenticationHeaders(to: &request)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        Logger.info("[WADOClient] Retrieved thumbnail for series \(seriesUID), size: \(data.count) bytes")
        return data
    }
}

// MARK: - Response Models

/**
 Represents a WADO-RS multipart response
 */
internal struct WADOMultipartResponse {
    let contentType: String
    let boundary: String
    let parts: [WADOPart]
}

/**
 Represents a single part in a multipart response
 */
internal struct WADOPart {
    let contentType: String
    let contentLocation: String?
    let data: Data
}