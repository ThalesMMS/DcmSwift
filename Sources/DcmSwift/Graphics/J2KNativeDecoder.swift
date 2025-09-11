//  J2KNativeDecoder.swift
//  DcmSwift
//
//  Thin wrapper placeholder for native 16-bit JPEG2000/HTJ2K decoders (OpenJPH/OpenJPEG).
//  At runtime, prefer this path when `settings.decoderPrefer16Bit == true`.
//  Falls back to platform decoders if not available.

import Foundation

public enum J2KNativeDecoderError: Error {
    case notAvailable
}

public struct J2KNativeResult {
    public let pixels: [UInt16]
    public let width: Int
    public let height: Int
    public let bitsPerSample: Int
}

public enum J2KNativeDecoder {
    /// Decode JPEG 2000 / HTJ2K codestream to 16-bit grayscale when available.
    /// Returns nil if the native decoder is not linked or cannot decode the data.
    public static func decodeU16(_ codestream: Data) -> J2KNativeResult? {
        // Placeholder: integrate OpenJPH/OpenJPEG via C wrappers and return result here.
        // Keep signature stable so the higher-level PixelService can switch seamlessly.
        return nil
    }
}

