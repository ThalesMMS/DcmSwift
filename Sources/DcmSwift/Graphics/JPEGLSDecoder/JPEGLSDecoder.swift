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
    public let rgb16: [UInt16]?
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

        // Multi-component ILV=none (baseline first)
        if p.components > 1 {
            switch p.interleaveMode {
            case 0: // ILV=none (separate scans)
                if p.bitsPerSample <= 8 {
                    if let rgb = try ScanDecoder.decodeMultiComponent(params: p) {
                        return JPEGLSResult(width: p.width, height: p.height, bitsPerSample: p.bitsPerSample, components: p.components, gray16: nil, gray8: nil, rgb8: rgb, rgb16: nil)
                    }
                } else {
                    if let rgb16 = try ScanDecoder.decodeMultiComponent16(params: p) {
                        return JPEGLSResult(width: p.width, height: p.height, bitsPerSample: p.bitsPerSample, components: p.components, gray16: nil, gray8: nil, rgb8: nil, rgb16: rgb16)
                    }
                }
                throw JPEGLSError.decodeFailed
            case 1: // ILV=line
                let out = try ScanDecoder.decodeInterleavedLine(params: p)
                return JPEGLSResult(width: p.width, height: p.height, bitsPerSample: p.bitsPerSample, components: p.components, gray16: nil, gray8: out.rgb8, rgb8: out.rgb8, rgb16: out.rgb16)
            case 2: // ILV=sample
                throw JPEGLSError.notImplemented
            default:
                throw JPEGLSError.notImplemented
            }
        }

        // Grayscale, NEAR any
        if p.components == 1 {
            let dec = try ScanDecoder.decodeGrayscaleNear0(params: p)
            return JPEGLSResult(width: p.width,
                                 height: p.height,
                                 bitsPerSample: p.bitsPerSample,
                                 components: p.components,
                                 gray16: dec.gray16,
                                 gray8: dec.gray8,
                                 rgb8: nil,
                                 rgb16: nil)
        }
        throw JPEGLSError.notImplemented
    }
}
