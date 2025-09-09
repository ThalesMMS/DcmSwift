//
//  DicomNetworkError.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import Foundation

/**
 Centralized error handling for DICOM network operations.
 
 This enum provides structured error types for all network-related failures
 in DcmSwift, replacing string-based error messages with typed errors that
 can be properly handled by calling code.
 */
public enum DicomNetworkError: LocalizedError {
    
    // MARK: - Connection Errors
    
    /// Failed to establish connection to remote AE
    case connectionFailed(host: String, port: Int, underlying: Error?)
    
    /// Connection timeout occurred
    case connectionTimeout(host: String, port: Int)
    
    /// TLS connection failed or is unstable
    case tlsConnectionFailed(host: String, message: String)
    
    /// Remote AE rejected the association
    case associationRejected(reason: String)
    
    /// Association aborted unexpectedly
    case associationAborted
    
    // MARK: - Protocol Errors
    
    /// Invalid or missing presentation context
    case invalidPresentationContext(abstractSyntax: String?)
    
    /// No accepted transfer syntax found
    case noAcceptedTransferSyntax
    
    /// PDU encoding failed
    case pduEncodingFailed(messageType: String)
    
    /// PDU decoding failed
    case pduDecodingFailed(expectedType: String, receivedType: String?)
    
    /// Invalid DIMSE message format
    case invalidDIMSEMessage(command: String, reason: String)
    
    // MARK: - Query/Retrieve Errors
    
    /// C-FIND query failed
    case findFailed(reason: String)
    
    /// C-GET retrieve failed
    case getFailed(reason: String)
    
    /// C-MOVE retrieve failed
    case moveFailed(reason: String)
    
    /// C-STORE operation failed
    case storeFailed(sopInstanceUID: String?, reason: String)
    
    /// No matching results found for query
    case noMatchingResults
    
    // MARK: - Data Transfer Errors
    
    /// Fragment timeout - didn't receive all data fragments in time
    case fragmentTimeout(messageID: UInt16, expectedFragments: Int?, receivedFragments: Int)
    
    /// Data corruption detected during transfer
    case dataCorruption(sopInstanceUID: String?)
    
    /// Failed to save received data
    case saveFailed(path: String, underlying: Error?)
    
    /// Insufficient storage space
    case insufficientStorage(required: Int64, available: Int64)
    
    // MARK: - Configuration Errors
    
    /// Invalid AE title format
    case invalidAETitle(aeTitle: String)
    
    /// Invalid port number
    case invalidPort(port: Int)
    
    /// Missing required configuration
    case missingConfiguration(parameter: String)
    
    // MARK: - Internal Errors
    
    /// Channel not ready for operation
    case channelNotReady
    
    /// Operation cancelled by user
    case operationCancelled
    
    /// Unknown or unexpected error
    case unknown(message: String)
    
    // MARK: - LocalizedError Implementation
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let host, let port, let underlying):
            if let underlying = underlying {
                return "Failed to connect to \(host):\(port) - \(underlying.localizedDescription)"
            }
            return "Failed to connect to \(host):\(port)"
            
        case .connectionTimeout(let host, let port):
            return "Connection timeout to \(host):\(port)"
            
        case .tlsConnectionFailed(let host, let message):
            return "TLS connection failed to \(host): \(message)"
            
        case .associationRejected(let reason):
            return "Association rejected: \(reason)"
            
        case .associationAborted:
            return "Association aborted unexpectedly"
            
        case .invalidPresentationContext(let abstractSyntax):
            if let syntax = abstractSyntax {
                return "Invalid presentation context for \(syntax)"
            }
            return "Invalid presentation context"
            
        case .noAcceptedTransferSyntax:
            return "No accepted transfer syntax found"
            
        case .pduEncodingFailed(let messageType):
            return "Failed to encode PDU message: \(messageType)"
            
        case .pduDecodingFailed(let expected, let received):
            if let received = received {
                return "PDU decode failed - expected \(expected), received \(received)"
            }
            return "PDU decode failed - expected \(expected)"
            
        case .invalidDIMSEMessage(let command, let reason):
            return "Invalid DIMSE message \(command): \(reason)"
            
        case .findFailed(let reason):
            return "C-FIND query failed: \(reason)"
            
        case .getFailed(let reason):
            return "C-GET retrieve failed: \(reason)"
            
        case .moveFailed(let reason):
            return "C-MOVE retrieve failed: \(reason)"
            
        case .storeFailed(let sopInstanceUID, let reason):
            if let uid = sopInstanceUID {
                return "C-STORE failed for \(uid): \(reason)"
            }
            return "C-STORE failed: \(reason)"
            
        case .noMatchingResults:
            return "No matching results found"
            
        case .fragmentTimeout(let messageID, let expected, let received):
            if let expected = expected {
                return "Fragment timeout for message \(messageID) - expected \(expected), received \(received)"
            }
            return "Fragment timeout for message \(messageID) - received \(received) fragments"
            
        case .dataCorruption(let sopInstanceUID):
            if let uid = sopInstanceUID {
                return "Data corruption detected for \(uid)"
            }
            return "Data corruption detected"
            
        case .saveFailed(let path, let underlying):
            if let underlying = underlying {
                return "Failed to save to \(path): \(underlying.localizedDescription)"
            }
            return "Failed to save to \(path)"
            
        case .insufficientStorage(let required, let available):
            return "Insufficient storage - required: \(required) bytes, available: \(available) bytes"
            
        case .invalidAETitle(let aeTitle):
            return "Invalid AE title: '\(aeTitle)' (must be 1-16 characters, no spaces)"
            
        case .invalidPort(let port):
            return "Invalid port number: \(port) (must be 1-65535)"
            
        case .missingConfiguration(let parameter):
            return "Missing required configuration: \(parameter)"
            
        case .channelNotReady:
            return "Network channel not ready"
            
        case .operationCancelled:
            return "Operation cancelled by user"
            
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .tlsConnectionFailed:
            return "TLS connections may be unstable. Consider using regular DICOM transport if problems persist."
            
        case .invalidAETitle:
            return "AE titles must be 1-16 characters, uppercase letters, numbers, and spaces only."
            
        case .fragmentTimeout:
            return "Large data transfers may require adjusting timeout settings or checking network stability."
            
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Check network connectivity and verify the remote AE is running."
            
        case .connectionTimeout:
            return "Verify the host address and port, and check firewall settings."
            
        case .tlsConnectionFailed:
            return "Try using non-TLS connection or verify TLS certificates."
            
        case .associationRejected:
            return "Verify AE titles and check PACS configuration."
            
        case .noAcceptedTransferSyntax:
            return "Check that the PACS supports the required transfer syntaxes."
            
        case .insufficientStorage:
            return "Free up disk space or change the storage location."
            
        case .invalidPort:
            return "Use a port number between 1 and 65535."
            
        default:
            return nil
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Check if this is a recoverable network error
    public var isRecoverable: Bool {
        switch self {
        case .connectionTimeout, .fragmentTimeout, .operationCancelled:
            return true
        case .connectionFailed, .tlsConnectionFailed:
            return true
        default:
            return false
        }
    }
    
    /// Check if this error suggests retrying with different settings
    public var shouldRetryWithDifferentSettings: Bool {
        switch self {
        case .tlsConnectionFailed, .noAcceptedTransferSyntax, .invalidPresentationContext:
            return true
        default:
            return false
        }
    }
    
    /// Convert legacy NetworkError to DicomNetworkError
    public static func from(_ networkError: NetworkError) -> DicomNetworkError {
        switch networkError {
        case .notReady:
            return .channelNotReady
        case .cantBind:
            return .connectionFailed(host: "unknown", port: 0, underlying: networkError)
        case .timeout:
            return .connectionTimeout(host: "unknown", port: 0)
        case .connectionResetByPeer:
            return .associationAborted
        case .transitionNotFound:
            return .unknown(message: "Protocol transition not found")
        case .internalError:
            return .unknown(message: "Internal network error")
        case .errorComment(let message):
            return .unknown(message: message)
        case .associationRejected(let reason):
            return .associationRejected(reason: reason)
        case .callingAETitleNotRecognized:
            return .invalidAETitle(aeTitle: "Calling AE title not recognized")
        case .calledAETitleNotRecognized:
            return .invalidAETitle(aeTitle: "Called AE title not recognized")
        }
    }
}

// MARK: - Error Code Support

extension DicomNetworkError {
    /// Unique error code for each error type
    public var errorCode: Int {
        switch self {
        // Connection errors (1000-1099)
        case .connectionFailed: return 1001
        case .connectionTimeout: return 1002
        case .tlsConnectionFailed: return 1003
        case .associationRejected: return 1004
        case .associationAborted: return 1005
            
        // Protocol errors (1100-1199)
        case .invalidPresentationContext: return 1101
        case .noAcceptedTransferSyntax: return 1102
        case .pduEncodingFailed: return 1103
        case .pduDecodingFailed: return 1104
        case .invalidDIMSEMessage: return 1105
            
        // Query/Retrieve errors (1200-1299)
        case .findFailed: return 1201
        case .getFailed: return 1202
        case .moveFailed: return 1203
        case .storeFailed: return 1204
        case .noMatchingResults: return 1205
            
        // Data transfer errors (1300-1399)
        case .fragmentTimeout: return 1301
        case .dataCorruption: return 1302
        case .saveFailed: return 1303
        case .insufficientStorage: return 1304
            
        // Configuration errors (1400-1499)
        case .invalidAETitle: return 1401
        case .invalidPort: return 1402
        case .missingConfiguration: return 1403
            
        // Internal errors (1900-1999)
        case .channelNotReady: return 1901
        case .operationCancelled: return 1902
        case .unknown: return 1999
        }
    }
    
    /// Error domain for NSError bridging
    public static var errorDomain: String {
        return "com.opale.DcmSwift.NetworkError"
    }
}

// MARK: - NSError Bridging

extension DicomNetworkError {
    /// Convert to NSError for Objective-C compatibility
    public var nsError: NSError {
        return NSError(
            domain: Self.errorDomain,
            code: self.errorCode,
            userInfo: [
                NSLocalizedDescriptionKey: self.errorDescription ?? "Unknown error",
                NSLocalizedFailureReasonErrorKey: self.failureReason ?? "",
                NSLocalizedRecoverySuggestionErrorKey: self.recoverySuggestion ?? ""
            ]
        )
    }
}