//
//  MetalShaders.swift
//  DcmSwift
//
//  Convenience API mirroring the Xcode 12 SPM pattern for loading
//  module-local Metal shaders using Bundle.module. This sits alongside
//  MetalAccelerator and can be used directly by hosts if desired.
//

import Foundation

#if canImport(Metal)
import Metal

// A metal device for access to the GPU.
public var metalDevice: MTLDevice?

// A metal library loaded from the package's resource bundle.
public var packageMetalLibrary: MTLLibrary?

/// Initialize Metal and load the module's default metallib.
/// Uses makeDefaultLibrary(bundle: .module) so the shaders are found when
/// DcmSwift is consumed from another app.
public func setupMetal() {
    metalDevice = MTLCreateSystemDefaultDevice()

    guard let device = metalDevice else { return }
    if #available(iOS 14.0, macOS 11.0, *) {
        packageMetalLibrary = try? device.makeDefaultLibrary(bundle: .module)
    } else if let url = Bundle.module.url(forResource: "default", withExtension: "metallib") {
        packageMetalLibrary = try? device.makeLibrary(URL: url)
    }

    #if DEBUG
    if let names = packageMetalLibrary?.functionNames {
        print("[DcmSwift/Metal] functions=", names)
    }
    #endif
}

#else

public func setupMetal() { /* Metal not available on this platform */ }

#endif

