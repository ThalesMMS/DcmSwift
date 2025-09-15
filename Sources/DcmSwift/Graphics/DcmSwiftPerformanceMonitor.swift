//
//  DcmSwiftPerformanceMonitor.swift
//  DcmSwift
//
//  Lightweight performance monitoring for DcmSwift package
//

import Foundation
import os.signpost

#if canImport(Metal)
import Metal
#endif

/// Lightweight performance monitor for DcmSwift operations
@MainActor
public final class DcmSwiftPerformanceMonitor {
    public static let shared = DcmSwiftPerformanceMonitor()
    
    private let signpostLog: OSLog
    private let enabled: Bool
    
    private init() {
        self.signpostLog = OSLog(
            subsystem: "com.dcmswift.performance",
            category: "dcmswift"
        )
        self.enabled = UserDefaults.standard.bool(forKey: "settings.perfMetricsEnabled")
    }
    
    // MARK: - GPU Operations
    
    public func startGPUOperation(_ operation: GPUOperation) -> GPUOperationToken {
        let token = GPUOperationToken(
            id: UUID(),
            operation: operation,
            startTime: CFAbsoluteTimeGetCurrent()
        )
        
        if enabled {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.begin,
                       log: signpostLog,
                       name: "GPUOperation",
                       signpostID: signpostID,
                       "Operation: %{public}@", operation.rawValue)
        }
        
        return token
    }
    
    public func endGPUOperation(_ token: GPUOperationToken, success: Bool = true) {
        let duration = CFAbsoluteTimeGetCurrent() - token.startTime
        
        if enabled {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.end,
                       log: signpostLog,
                       name: "GPUOperation",
                       signpostID: signpostID,
                       "Operation: %{public}@, Duration: %.3fms, Success: %{public}@",
                       token.operation.rawValue, duration * 1000, success ? "true" : "false")
        }
    }
}

// MARK: - Supporting Types

public struct GPUOperationToken {
    public let id: UUID
    public let operation: GPUOperation
    public let startTime: CFAbsoluteTime
}

public enum GPUOperation: String, CaseIterable {
    case windowLevelCompute = "window_level_compute"
    case textureUpload = "texture_upload"
    case renderPass = "render_pass"
    case bufferCopy = "buffer_copy"
}
