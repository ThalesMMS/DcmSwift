//
//  DICOMWebClient.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/**
 Base class for DICOMWeb REST API clients.
 
 This class provides common functionality for all DICOMWeb services including:
 - HTTP/HTTPS communication
 - Authentication (Basic, OAuth2, Token-based)
 - Content negotiation (JSON, XML, multipart)
 - Error handling for DICOMWeb responses
 
 DICOMWeb Standard Reference:
 https://www.dicomstandard.org/dicomweb
 
 ## Supported Services
 - WADO-RS: Web Access to DICOM Objects - RESTful Services
 - WADO-URI: Web Access to DICOM Objects - URI Based
 - QIDO-RS: Query based on ID for DICOM Objects - RESTful Services
 - STOW-RS: Store Over the Web - RESTful Services
 - UPS-RS: Unified Procedure Step - RESTful Services (future)
 
 ## Example Usage:
 ```swift
 let client = DICOMWebClient(baseURL: "https://dicom.example.com/dicom-web")
 client.setAuthentication(.bearer(token: "abc123"))
 ```
 */
public class DICOMWebClient {
    
    // MARK: - Properties
    
    /// Base URL for the DICOMWeb server
    public var baseURL: URL
    
    /// URLSession for network requests
    internal let session: URLSession
    
    /// Authentication method
    public enum Authentication {
        case none
        case basic(username: String, password: String)
        case bearer(token: String)
        case oauth2(token: String)
        // TODO: Add more authentication methods as needed
    }
    
    private var authentication: Authentication = .none
    
    /// Supported media types for DICOMWeb
    public struct MediaTypes {
        static let dicomJSON = "application/dicom+json"
        static let dicomXML = "application/dicom+xml"
        static let dicom = "application/dicom"
        static let multipartRelated = "multipart/related"
        static let octetStream = "application/octet-stream"
        static let jpeg = "image/jpeg"
        static let png = "image/png"
    }
    
    // MARK: - Initialization
    
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    // MARK: - Authentication
    
    public func setAuthentication(_ auth: Authentication) {
        self.authentication = auth
    }
    
    // MARK: - Request Building
    
    /**
     Creates a URLRequest with proper headers for DICOMWeb
     
     - Parameters:
        - url: The URL for the request
        - method: HTTP method (GET, POST, PUT, DELETE)
        - accept: Accept header for content negotiation
        - contentType: Content-Type header for request body
     */
    internal func createRequest(
        url: URL,
        method: String,
        accept: String? = nil,
        contentType: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Set Accept header
        if let accept = accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        
        // Set Content-Type header
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        // Apply authentication
        switch authentication {
        case .none:
            break
        case .basic(let username, let password):
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        case .bearer(let token), .oauth2(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    /**
     Adds authentication headers to an existing URLRequest
     
     - Parameter request: The request to modify (inout)
     */
    internal func addAuthenticationHeaders(to request: inout URLRequest) {
        switch authentication {
        case .none:
            break
        case .basic(let username, let password):
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        case .bearer(let token), .oauth2(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    // MARK: - Response Handling
    
    /**
     Processes a DICOMWeb response and handles common error cases
     
     - Parameters:
        - data: Response data
        - response: URLResponse
        - error: Network error if any
     
     - Throws: DICOMWebError for various error conditions
     */
    internal func processResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) throws -> Data {
        // TODO: Implement comprehensive error handling
        // - Check HTTP status codes
        // - Parse DICOMWeb error responses
        // - Handle network errors
        
        if let error = error {
            throw DICOMWebError.networkError(statusCode: 0, description: error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DICOMWebError.parsingFailed("Invalid response type - not an HTTP response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DICOMWebError.networkError(
                statusCode: httpResponse.statusCode,
                description: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        guard let data = data else {
            throw DICOMWebError.noData
        }
        
        return data
    }
    
    // MARK: - Async/Await Support
    
    @available(macOS 12.0, iOS 15.0, *)
    internal func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        return try processResponse(data: data, response: response, error: nil)
    }
    
    // MARK: - Legacy Completion Handler Support
    
    internal func performRequest(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        session.dataTask(with: request) { [weak self] data, response, error in
            do {
                let data = try self?.processResponse(
                    data: data,
                    response: response,
                    error: error
                )
                completion(.success(data ?? Data()))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}