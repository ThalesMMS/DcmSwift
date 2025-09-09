import Foundation

/**
 QIDO-RS (Query based on ID for DICOM Objects) Client
 
 Implements DICOM PS3.18 Chapter 10.6 - Search Transaction
 Provides RESTful query capabilities for studies, series, and instances.
 */
public actor QIDOClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        
        // Configure decoder for DICOM JSON Model
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Study Level Queries
    
    /**
     Search for studies matching the specified criteria
     
     - Parameters:
        - patientName: Patient name (supports wildcards with *)
        - patientID: Patient ID
        - studyDate: Study date in YYYYMMDD format or range (YYYYMMDD-YYYYMMDD)
        - studyInstanceUID: Specific study UID
        - accessionNumber: Accession number
        - modality: Modalities in study (comma-separated for multiple)
        - referringPhysicianName: Referring physician name
        - limit: Maximum number of results
        - offset: Number of results to skip (for pagination)
        - fuzzyMatching: Enable fuzzy matching for text fields
        - includefield: Additional fields to include (ALL, or specific tags)
     
     - Returns: Array of study metadata as dictionaries
     */
    public func searchForStudies(
        patientName: String? = nil,
        patientID: String? = nil,
        studyDate: String? = nil,
        studyInstanceUID: String? = nil,
        accessionNumber: String? = nil,
        modality: String? = nil,
        referringPhysicianName: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fuzzyMatching: Bool = false,
        includefield: [String]? = nil
    ) async throws -> [[String: Any]] {
        
        var components = URLComponents(url: baseURL.appendingPathComponent("studies"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        
        // Add query parameters
        if let patientName = patientName {
            queryItems.append(URLQueryItem(name: "PatientName", value: patientName))
        }
        if let patientID = patientID {
            queryItems.append(URLQueryItem(name: "PatientID", value: patientID))
        }
        if let studyDate = studyDate {
            queryItems.append(URLQueryItem(name: "StudyDate", value: studyDate))
        }
        if let studyInstanceUID = studyInstanceUID {
            queryItems.append(URLQueryItem(name: "StudyInstanceUID", value: studyInstanceUID))
        }
        if let accessionNumber = accessionNumber {
            queryItems.append(URLQueryItem(name: "AccessionNumber", value: accessionNumber))
        }
        if let modality = modality, !modality.isEmpty {
            // Support multi-modality by splitting and adding repeated params
            let tokens = modality.uppercased()
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "\\", with: " ")
                .split{ !$0.isLetter }
                .map { String($0) }
            if tokens.count > 1 {
                for m in tokens { queryItems.append(URLQueryItem(name: "ModalitiesInStudy", value: m)) }
            } else {
                queryItems.append(URLQueryItem(name: "ModalitiesInStudy", value: modality))
            }
        }
        if let referringPhysicianName = referringPhysicianName {
            queryItems.append(URLQueryItem(name: "ReferringPhysicianName", value: referringPhysicianName))
        }
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset = offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if fuzzyMatching {
            queryItems.append(URLQueryItem(name: "fuzzymatching", value: "true"))
        }
        if let includefield = includefield {
            for field in includefield {
                queryItems.append(URLQueryItem(name: "includefield", value: field))
            }
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else {
            throw DICOMWebError.invalidURL("Invalid URL constructed")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            throw DICOMWebError.networkError(statusCode: httpResponse.statusCode, description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        
        // Parse JSON response
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DICOMWebError.parsingFailed("Invalid JSON response")
        }
        
        return jsonArray
    }
    
    // MARK: - Series Level Queries
    
    /**
     Search for series within a study or across all studies
     
     - Parameters:
        - studyInstanceUID: Study UID (optional, searches all studies if nil)
        - modality: Series modality
        - seriesInstanceUID: Specific series UID
        - seriesNumber: Series number
        - performedProcedureStepStartDate: Procedure date
        - limit: Maximum number of results
        - offset: Number of results to skip
        - includefield: Additional fields to include
     
     - Returns: Array of series metadata as dictionaries
     */
    public func searchForSeries(
        studyInstanceUID: String? = nil,
        modality: String? = nil,
        seriesInstanceUID: String? = nil,
        seriesNumber: String? = nil,
        performedProcedureStepStartDate: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        includefield: [String]? = nil
    ) async throws -> [[String: Any]] {
        
        let path = studyInstanceUID != nil ? "studies/\(studyInstanceUID!)/series" : "series"
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        
        if let modality = modality {
            queryItems.append(URLQueryItem(name: "Modality", value: modality))
        }
        if let seriesInstanceUID = seriesInstanceUID {
            queryItems.append(URLQueryItem(name: "SeriesInstanceUID", value: seriesInstanceUID))
        }
        if let seriesNumber = seriesNumber {
            queryItems.append(URLQueryItem(name: "SeriesNumber", value: seriesNumber))
        }
        if let performedProcedureStepStartDate = performedProcedureStepStartDate {
            queryItems.append(URLQueryItem(name: "PerformedProcedureStepStartDate", value: performedProcedureStepStartDate))
        }
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset = offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if let includefield = includefield {
            for field in includefield {
                queryItems.append(URLQueryItem(name: "includefield", value: field))
            }
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else {
            throw DICOMWebError.invalidURL("Invalid URL constructed")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            throw DICOMWebError.networkError(statusCode: httpResponse.statusCode, description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DICOMWebError.parsingFailed("Invalid JSON response")
        }
        
        return jsonArray
    }
    
    // MARK: - Instance Level Queries
    
    /**
     Search for instances within a series, study, or across all instances
     
     - Parameters:
        - studyInstanceUID: Study UID (optional)
        - seriesInstanceUID: Series UID (optional)
        - sopInstanceUID: Specific instance UID
        - sopClassUID: SOP Class UID
        - instanceNumber: Instance number
        - limit: Maximum number of results
        - offset: Number of results to skip
        - includefield: Additional fields to include
     
     - Returns: Array of instance metadata as dictionaries
     */
    public func searchForInstances(
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        sopClassUID: String? = nil,
        instanceNumber: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        includefield: [String]? = nil
    ) async throws -> [[String: Any]] {
        
        let path: String
        if let studyUID = studyInstanceUID, let seriesUID = seriesInstanceUID {
            path = "studies/\(studyUID)/series/\(seriesUID)/instances"
        } else if let studyUID = studyInstanceUID {
            path = "studies/\(studyUID)/instances"
        } else {
            path = "instances"
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        
        if let sopInstanceUID = sopInstanceUID {
            queryItems.append(URLQueryItem(name: "SOPInstanceUID", value: sopInstanceUID))
        }
        if let sopClassUID = sopClassUID {
            queryItems.append(URLQueryItem(name: "SOPClassUID", value: sopClassUID))
        }
        if let instanceNumber = instanceNumber {
            queryItems.append(URLQueryItem(name: "InstanceNumber", value: instanceNumber))
        }
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset = offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if let includefield = includefield {
            for field in includefield {
                queryItems.append(URLQueryItem(name: "includefield", value: field))
            }
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else {
            throw DICOMWebError.invalidURL("Invalid URL constructed")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            throw DICOMWebError.networkError(statusCode: httpResponse.statusCode, description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DICOMWebError.parsingFailed("Invalid JSON response")
        }
        
        return jsonArray
    }
    
    // MARK: - Advanced Query Methods
    
    /**
     Search using arbitrary DICOM tags and values
     
     - Parameters:
        - resourceType: "studies", "series", or "instances"
        - queryParameters: Dictionary of DICOM tag names/keywords to values
        - limit: Maximum number of results
        - offset: Number of results to skip
     
     - Returns: Array of metadata as dictionaries
     */
    public func searchWithParameters(
        resourceType: String,
        queryParameters: [String: String],
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> [[String: Any]] {
        
        var components = URLComponents(url: baseURL.appendingPathComponent(resourceType), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        
        for (key, value) in queryParameters {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset = offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else {
            throw DICOMWebError.invalidURL("Invalid URL constructed")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            throw DICOMWebError.networkError(statusCode: httpResponse.statusCode, description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DICOMWebError.parsingFailed("Invalid JSON response")
        }
        
        return jsonArray
    }
    
    // MARK: - Convenience Methods
    
    /**
     Search for all studies for a specific patient
     
     - Parameters:
        - patientID: The patient ID to search for
        - includefield: Additional fields to include
     
     - Returns: Array of study metadata
     */
    public func getPatientStudies(patientID: String, includefield: [String]? = nil) async throws -> [[String: Any]] {
        return try await searchForStudies(patientID: patientID, includefield: includefield)
    }
    
    /**
     Get all series in a study with specific modality
     
     - Parameters:
        - studyUID: The study instance UID
        - modality: Filter by modality (e.g., "CT", "MR", "US")
     
     - Returns: Array of series metadata
     */
    public func getStudySeries(studyUID: String, modality: String? = nil) async throws -> [[String: Any]] {
        return try await searchForSeries(studyInstanceUID: studyUID, modality: modality)
    }
    
    /**
     Count the number of matching results without retrieving them
     
     - Parameters:
        - resourceType: "studies", "series", or "instances"
        - queryParameters: Search criteria
     
     - Returns: Total count of matching items
     */
    public func countMatches(resourceType: String, queryParameters: [String: String]) async throws -> Int {
        // Request with limit=0 to get count in response header
        var params = queryParameters
        params["limit"] = "0"
        
        var components = URLComponents(url: baseURL.appendingPathComponent(resourceType), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw DICOMWebError.invalidURL("Invalid URL constructed")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        request.httpMethod = "HEAD"  // Use HEAD to get headers only
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        // Look for X-Total-Count header
        if let countHeader = httpResponse.value(forHTTPHeaderField: "X-Total-Count"),
           let count = Int(countHeader) {
            return count
        }
        
        // Fallback: do actual query with high limit
        let results = try await searchWithParameters(resourceType: resourceType, queryParameters: queryParameters, limit: 10000)
        return results.count
    }
    
    // MARK: - Worklist Query (MWL)
    
    /**
     Search for scheduled procedure steps (Modality Worklist)
     
     - Parameters:
        - scheduledStationAETitle: AE Title of the scheduled station
        - scheduledProcedureStepStartDate: Date or date range
        - modality: Scheduled modality
        - patientName: Patient name
        - patientID: Patient ID
     
     - Returns: Array of worklist items
     */
    public func searchWorklistItems(
        scheduledStationAETitle: String? = nil,
        scheduledProcedureStepStartDate: String? = nil,
        modality: String? = nil,
        patientName: String? = nil,
        patientID: String? = nil
    ) async throws -> [[String: Any]] {
        
        var components = URLComponents(url: baseURL.appendingPathComponent("workitems"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        
        if let aeTitle = scheduledStationAETitle {
            queryItems.append(URLQueryItem(name: "ScheduledStationAETitle", value: aeTitle))
        }
        if let startDate = scheduledProcedureStepStartDate {
            queryItems.append(URLQueryItem(name: "ScheduledProcedureStepStartDate", value: startDate))
        }
        if let modality = modality {
            queryItems.append(URLQueryItem(name: "Modality", value: modality))
        }
        if let patientName = patientName {
            queryItems.append(URLQueryItem(name: "PatientName", value: patientName))
        }
        if let patientID = patientID {
            queryItems.append(URLQueryItem(name: "PatientID", value: patientID))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else {
            throw DICOMWebError.invalidURL("Invalid URL constructed")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.networkError(statusCode: 0, description: "Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            throw DICOMWebError.networkError(statusCode: httpResponse.statusCode, description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DICOMWebError.parsingFailed("Invalid JSON response")
        }
        
        return jsonArray
    }
}

// MARK: - Helper Extensions

extension QIDOClient {
    
    /**
     Parse DICOM JSON model to extract specific attribute values
     
     - Parameters:
        - jsonObject: DICOM JSON object
        - tag: DICOM tag (e.g., "00100020" for PatientID)
     
     - Returns: The value of the attribute if found
     */
    public static func extractValue(from jsonObject: [String: Any], tag: String) -> Any? {
        guard let attribute = jsonObject[tag] as? [String: Any],
              let value = attribute["Value"] as? [Any],
              !value.isEmpty else {
            return nil
        }
        
        // Return first value for single-valued attributes
        if value.count == 1 {
            return value[0]
        }
        
        // Return array for multi-valued attributes
        return value
    }
    
    /**
     Extract common study-level attributes from DICOM JSON
     */
    public static func extractStudyInfo(from jsonObject: [String: Any]) -> (
        studyUID: String?,
        studyDate: String?,
        studyDescription: String?,
        patientName: String?,
        patientID: String?
    ) {
        let studyUID = extractValue(from: jsonObject, tag: "0020000D") as? String
        let studyDate = extractValue(from: jsonObject, tag: "00080020") as? String
        let studyDescription = extractValue(from: jsonObject, tag: "00081030") as? String
        
        // Patient name might be a complex object
        let patientNameValue = extractValue(from: jsonObject, tag: "00100010")
        let patientName: String?
        if let nameDict = patientNameValue as? [String: Any] {
            patientName = nameDict["Alphabetic"] as? String
        } else {
            patientName = patientNameValue as? String
        }
        
        let patientID = extractValue(from: jsonObject, tag: "00100020") as? String
        
        return (studyUID, studyDate, studyDescription, patientName, patientID)
    }
}
