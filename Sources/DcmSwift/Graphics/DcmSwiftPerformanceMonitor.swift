//
//  DcmSwiftPerformanceMonitor.swift
//  DcmSwift
//
//  Lightweight performance monitoring for DcmSwift package
//

import Foundation

#if canImport(os)
import os
#endif

#if canImport(os.signpost)
import os.signpost
#endif

#if canImport(Metal)
import Metal
#endif

/// Lightweight performance monitor for DcmSwift operations
@MainActor
public final class DcmSwiftPerformanceMonitor {
    public static let shared = DcmSwiftPerformanceMonitor()

#if canImport(os.signpost)
    private let signpostLog: OSLog
    private let enabled: Bool
#else
    private let enabled: Bool = false
#endif

    private init() {
#if canImport(os.signpost)
        self.signpostLog = OSLog(
            subsystem: "com.dcmswift.performance",
            category: "dcmswift"
        )
        self.enabled = UserDefaults.standard.bool(forKey: "settings.perfMetricsEnabled")
#endif
    }

    // MARK: - GPU Operations

    public func startGPUOperation(_ operation: GPUOperation) -> GPUOperationToken {
        let token = GPUOperationToken(
            id: UUID(),
            operation: operation,
            startTime: CFAbsoluteTimeGetCurrent()
        )

#if canImport(os.signpost)
        if enabled {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.begin,
                       log: signpostLog,
                       name: "GPUOperation",
                       signpostID: signpostID,
                       "Operation: %{public}@", operation.rawValue)
        }
#endif

        return token
    }

    public func endGPUOperation(_ token: GPUOperationToken, success: Bool = true) {
        let duration = CFAbsoluteTimeGetCurrent() - token.startTime

#if canImport(os.signpost)
        if enabled {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.end,
                       log: signpostLog,
                       name: "GPUOperation",
                       signpostID: signpostID,
                       "Operation: %{public}@, Duration: %.3fms, Success: %{public}@",
                       token.operation.rawValue, duration * 1000, success ? "true" : "false")
        }
#else
        _ = success
        _ = duration
#endif
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
