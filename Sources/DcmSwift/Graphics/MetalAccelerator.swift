//
//  MetalAccelerator.swift
//  DcmSwift
//
//  Lightweight helper to load the module's Metal shaders via SPM's Bundle.module
//  and to set up commonly used compute pipelines. Keep behind feature flags and
//  compile guards; always provide a safe CPU fallback.
//

import Foundation

#if canImport(Metal)
import Metal

public final class MetalAccelerator {
    public static let shared = MetalAccelerator()

    public let device: MTLDevice?
    public let library: MTLLibrary?
    public let windowLevelPipelineState: MTLComputePipelineState?
    public let commandQueue: MTLCommandQueue?

    public var isAvailable: Bool { windowLevelPipelineState != nil }

    private init() {
        let debug = UserDefaults.standard.bool(forKey: "settings.debugLogsEnabled")
        // Allow opt-out via env/UD flag
        if ProcessInfo.processInfo.environment["DCMSWIFT_DISABLE_METAL"] == "1" {
            device = nil; library = nil; windowLevelPipelineState = nil; commandQueue = nil
            if debug { print("[MetalAccelerator] Disabled via DCMSWIFT_DISABLE_METAL=1") }
            return
        }

        guard let dev = MTLCreateSystemDefaultDevice() else {
            device = nil; library = nil; windowLevelPipelineState = nil; commandQueue = nil
            if debug { print("[MetalAccelerator] No Metal device available") }
            return
        }
        device = dev
        commandQueue = dev.makeCommandQueue()

        // Load the module's compiled metallib. Prefer the modern API that understands SPM bundles.
        var lib: MTLLibrary? = nil
        if #available(iOS 14.0, macOS 11.0, *) {
            lib = try? dev.makeDefaultLibrary(bundle: .module)
            if debug { print("[MetalAccelerator] makeDefaultLibrary(bundle: .module) -> \(lib != nil ? "ok" : "nil")") }
        }
        // If not available (older OS), try to load a known metallib name from the bundle as a best-effort.
        if lib == nil {
            if let url = Bundle.module.url(forResource: "default", withExtension: "metallib") {
                lib = try? dev.makeLibrary(URL: url)
                if debug { print("[MetalAccelerator] makeLibrary(URL: default.metallib) -> \(lib != nil ? "ok" : "nil")") }
            } else if debug {
                print("[MetalAccelerator] default.metallib not found in Bundle.module")
            }
        }
        library = lib

        // Prepare commonly used pipelines
        if let f = library?.makeFunction(name: "windowLevelKernel"), let d = device {
            windowLevelPipelineState = try? d.makeComputePipelineState(function: f)
            if debug { print("[MetalAccelerator] Pipeline windowLevelKernel -> \(windowLevelPipelineState != nil ? "ok" : "nil")") }
        } else {
            windowLevelPipelineState = nil
            if debug { print("[MetalAccelerator] windowLevelKernel function not found in library") }
        }
    }
}

#else

// Non-Apple platforms or when Metal is unavailable
public final class MetalAccelerator {
    public static let shared = MetalAccelerator()
    public let isAvailable: Bool = false
    private init() {}
}

#endif