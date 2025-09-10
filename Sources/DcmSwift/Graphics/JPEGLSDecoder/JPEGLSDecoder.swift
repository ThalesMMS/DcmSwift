//
//  JPEGLSDecoder.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 
//  JPEG-LS scaffolding behind a feature flag. Full implementation is non-trivial.
//  Enable with environment variable: DCMSWIFT_ENABLE_JPEGLS=1
//

import Foundation

public enum JPEGLSError: Error { case disabled, notImplemented, decodeFailed }

public struct JPEGLSResult {
    public let width: Int
    public let height: Int
    public let bitsPerSample: Int
    public let components: Int
    public let gray16: [UInt16]?
    public let gray8: [UInt8]?
    public let rgb8: [UInt8]?
}

public enum JPEGLSDecoder {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DCMSWIFT_ENABLE_JPEGLS"] == "1"
    }

    /// Placeholder entry point. Returns `.disabled` unless feature flag is set.
    /// When enabled, currently throws `.notImplemented` to avoid silent fallthrough.
    public static func decode(_ codestream: Data,
                              expectedWidth: Int,
                              expectedHeight: Int,
                              expectedComponents: Int,
                              bitsPerSample: Int) throws -> JPEGLSResult {
        guard isEnabled else { throw JPEGLSError.disabled }
        // Parse headers
        let p = try JPEGLSParser.parse(codestream)
        // Basic validation against expected
        if expectedWidth > 0 && p.width != expectedWidth { /* tolerate */ }
        if expectedHeight > 0 && p.height != expectedHeight { /* tolerate */ }
        if expectedComponents > 0 && p.components != expectedComponents { /* tolerate */ }

        // Only NEAR=0 grayscale supported in first cut (scaffold)
        if p.components == 1 && p.near == 0 {
            _ = JLSState(bitsPerSample: p.bitsPerSample)
            // Decode scan (not implemented yet)
            _ = try? ScanDecoder.decodeGrayscaleNear0(params: p)
            throw JPEGLSError.notImplemented
        } else {
            throw JPEGLSError.notImplemented
        }
    }
}
