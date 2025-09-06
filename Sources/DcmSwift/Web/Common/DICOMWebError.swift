//
//  DICOMWebError.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/// Errors that can occur during DICOMweb operations
public enum DICOMWebError: LocalizedError {
    
    /// Invalid URL formation
    case invalidURL(String)
    
    /// Network request failed
    case networkError(statusCode: Int, description: String?)
    
    /// Failed to parse response data
    case parsingFailed(String)
    
    /// Missing boundary in multipart response header
    case missingBoundaryInHeader
    
    /// Invalid multipart response structure
    case invalidMultipartResponse(String)
    
    /// Authentication failed
    case authenticationFailed(String)
    
    /// No data received in response
    case noDataReceived
    
    /// Invalid DICOM data format
    case invalidDICOMData(String)
    
    /// Server returned an error response
    case serverError(statusCode: Int, message: String?)
    
    /// Request timeout
    case requestTimeout
    
    /// Invalid query parameters
    case invalidQueryParameters(String)
    
    /// Unsupported media type
    case unsupportedMediaType(String)
    
    /// Invalid JSON response
    case invalidJSON
    
    /// Invalid XML response
    case invalidXML
    
    /// No data received
    case noData
    
    /// Invalid request parameters
    case invalidRequest(String)
    
    /// Failed to encode data
    case encodingFailed(String)
    
    /// Validation error
    case validationError(String)
    
    /// Missing transfer syntax
    case missingTransferSyntax
    
    /// Unsupported format
    case unsupportedFormat(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkError(let code, let description):
            return "Network error (HTTP \(code)): \(description ?? "Unknown error")"
        case .parsingFailed(let reason):
            return "Failed to parse response: \(reason)"
        case .missingBoundaryInHeader:
            return "Missing boundary in multipart response header"
        case .invalidMultipartResponse(let reason):
            return "Invalid multipart response: \(reason)"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .noDataReceived:
            return "No data received in response"
        case .invalidDICOMData(let reason):
            return "Invalid DICOM data: \(reason)"
        case .serverError(let code, let message):
            return "Server error (HTTP \(code)): \(message ?? "Unknown server error")"
        case .requestTimeout:
            return "Request timed out"
        case .invalidQueryParameters(let reason):
            return "Invalid query parameters: \(reason)"
        case .unsupportedMediaType(let type):
            return "Unsupported media type: \(type)"
        case .invalidJSON:
            return "Invalid JSON response"
        case .invalidXML:
            return "Invalid XML response"
        case .noData:
            return "No data received"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .encodingFailed(let reason):
            return "Failed to encode data: \(reason)"
        case .validationError(let reason):
            return "Validation error: \(reason)"
        case .missingTransferSyntax:
            return "Missing transfer syntax in response"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        }
    }
}