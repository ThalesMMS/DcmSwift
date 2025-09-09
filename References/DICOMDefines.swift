//
//  DICOMDefines.swift
//  DICOMViewer
//
//  Swift version of Define.h constants and utilities
//  Created by Swift Migration on 2025-08-28.
//  Copyright © 2025 DICOM Viewer. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Network Status Definitions

/// Network status enumeration (replacing kIsNetwork macros)
@objc enum NetworkStatus: Int {
    case noConnection = 0
    case anyConnection = 1  // kIsNetwork
    case wwanConnection = 2  // kIsWWANNetwork  
    case wifiConnection = 3  // kIsWiFiNetwork
    
    var isConnected: Bool {
        return self != .noConnection
    }
    
    var connectionType: String {
        switch self {
        case .noConnection:
            return "No Connection"
        case .anyConnection:
            return "Connected"
        case .wwanConnection:
            return "Cellular"
        case .wifiConnection:
            return "Wi-Fi"
        }
    }
}

// MARK: - Legacy Objective-C Compatibility

/// Legacy Objective-C compatibility
/// Note: Property names prefixed with 'value' to avoid macro conflicts
@objc class DICOMDefines: NSObject {
    @objc static let valueIsNetwork: Int = 1
    @objc static let valueIsWWANNetwork: Int = 2
    @objc static let valueIsWiFiNetwork: Int = 3
}

// MARK: - Logging System

/// Swift logging utility (replacing PPLog macro)
public func DICOMLog(_ items: Any..., 
                     file: String = #file, 
                     function: String = #function, 
                     line: Int = #line) {
    #if DEBUG
    let fileName = (file as NSString).lastPathComponent
    let timestamp = DateFormatter.localizedString(from: Date(), 
                                                  dateStyle: .none, 
                                                  timeStyle: .medium)
    let message = items.map { "\($0)" }.joined(separator: " ")
    print("[\(timestamp)] \(fileName):\(line) \(function): \(message)")
    #endif
}

/// Objective-C compatible logging
@objc public class DICOMLogger: NSObject {
    @objc static func log(_ message: String, 
                          file: String = #file, 
                          function: String = #function, 
                          line: Int = #line) {
        DICOMLog(message, file: file, function: function, line: line)
    }
}

// MARK: - Screen Dimension Utilities

/// Screen dimension utilities (modern Swift approach)
@MainActor
struct DICOMScreenDimensions {
    static var width: CGFloat {
        return UIScreen.main.bounds.width
    }
    
    static var height: CGFloat {
        return UIScreen.main.bounds.height
    }
    
    static var size: CGSize {
        return UIScreen.main.bounds.size
    }
    
    static var scale: CGFloat {
        return UIScreen.main.scale
    }
    
    static var safeAreaInsets: UIEdgeInsets {
        if #available(iOS 15.0, *) {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            return windowScene?.windows.first?.safeAreaInsets ?? .zero
        } else {
            // iOS 13-14 (minimum deployment target is iOS 13.0)
            return UIApplication.shared.windows.first?.safeAreaInsets ?? .zero
        }
    }
}

// MARK: - Legacy MedFilm Compatibility

/// MedFilm legacy constants for compatibility
/// Note: Property names changed to avoid macro conflicts
@MainActor
@objc class MedFilmConstants: NSObject {
    @objc static var screenWidth: CGFloat {
        return UIScreen.main.bounds.width
    }
    
    @objc static var screenHeight: CGFloat {
        return UIScreen.main.bounds.height
    }
}

// MARK: - Type Definitions

typealias CompletionHandler = () -> Void
typealias ErrorHandler = (Error?) -> Void
typealias ProgressHandler = (Double) -> Void
typealias DataHandler = (Data?) -> Void

// MARK: - Extension Notes
// Note: String extensions removed to avoid conflicts with UIKit+Extensions.swift
// Use the extensions from UIKit+Extensions.swift instead

// MARK: - DICOM Constants and Standards

struct DICOMConstants {
    // DICOM file extensions
    static let supportedExtensions = ["dcm", "dicom", "dic"]
    
    // DICOM transfer syntaxes
    struct TransferSyntax {
        static let implicitVRLittleEndian = "1.2.840.10008.1.2"
        static let explicitVRLittleEndian = "1.2.840.10008.1.2.1"
        static let explicitVRBigEndian = "1.2.840.10008.1.2.2"
        static let jpegBaseline = "1.2.840.10008.1.2.4.50"
        static let jpegLossless = "1.2.840.10008.1.2.4.57"
    }
    
    // Window/Level presets
    struct WindowLevel {
        static let defaultWidth: Double = 400
        static let defaultCenter: Double = 40
    }
    
    // Network functionality removed
}

// MARK: - Module Import Bridge

/// This class ensures that modules imported by Define.h are available
/// Note: The actual imports are handled by the module system in Swift
@objc class DefineImportBridge: NSObject {
    
    @objc static func ensureImports() {
        // In Swift, we don't need explicit imports like Define.h
        // The Swift module system handles this automatically
        // This method exists only for Objective-C compatibility
        
        #if DEBUG
        DICOMLog("Import bridge initialized - All required modules available")
        #endif
    }
}

// MARK: - Global Utility Functions

/// Check network connectivity (modern implementation)
func isNetworkAvailable() -> Bool {
    // This would use Network framework in real implementation
    // For now, returning true as placeholder
    return true
}

/// Get current network type
func getCurrentNetworkType() -> NetworkStatus {
    // This would check actual network status
    // For now, returning wifi as placeholder
    return .wifiConnection
}

// MARK: - System Notifications

extension Notification.Name {
    static let dicomFileImported = Notification.Name("DICOMFileImported")
    static let networkStatusChanged = Notification.Name("NetworkStatusChanged")
    static let windowLevelChanged = Notification.Name("WindowLevelChanged")
    static let imageTransformChanged = Notification.Name("ImageTransformChanged")
}