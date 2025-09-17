//  J2KNativeDecoder.swift
//  DcmSwift
//
//  Thin wrapper placeholder for native 16-bit JPEG2000/HTJ2K decoders (OpenJPH/OpenJPEG).
//  At runtime, prefer this path when `settings.decoderPrefer16Bit == true`.
//  Falls back to platform decoders if not available.

import Foundation
import OpenJPH

public struct J2KNativeResult {
    public let width: Int
    public let height: Int
    public let components: Int
    public let bitsPerSample: Int
    public let isSigned: Bool
    public let pixels8: [UInt8]?
    public let pixels16: [UInt16]?
}

public enum J2KNativeDecoder {
    /// Decode JPEG 2000 / HTJ2K codestream using the native OpenJPH backend.
    /// Returns `nil` if the codestream cannot be handled by the native decoder.
    public static func decode(_ codestream: Data) -> J2KNativeResult? {
        guard !codestream.isEmpty else { return nil }

        return codestream.withUnsafeBytes { rawBuffer -> J2KNativeResult? in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            var image = ojph_decoded_image()
            var errorMessage = [CChar](repeating: 0, count: 256)
            let status = ojph_decode_image(base,
                                           codestream.count,
                                           &image,
                                           &errorMessage,
                                           errorMessage.count)

            guard status == OJPH_STATUS_OK else {
                ojph_free_image(&image)
                return nil
            }

            defer { ojph_free_image(&image) }

            let width = Int(image.width)
            let height = Int(image.height)
            let components = Int(image.components)
            let bits = Int(image.bit_depth)
            let isSigned = image.is_signed != 0
            let sampleCount = Int(image.pixel_count)

            if let pixels16 = image.pixels16 {
                let buffer = UnsafeBufferPointer(start: pixels16, count: sampleCount)
                return J2KNativeResult(width: width,
                                       height: height,
                                       components: components,
                                       bitsPerSample: bits,
                                       isSigned: isSigned,
                                       pixels8: nil,
                                       pixels16: Array(buffer))
            }

            if let pixels8 = image.pixels8 {
                let buffer = UnsafeBufferPointer(start: pixels8, count: sampleCount)
                return J2KNativeResult(width: width,
                                       height: height,
                                       components: components,
                                       bitsPerSample: bits,
                                       isSigned: isSigned,
                                       pixels8: Array(buffer),
                                       pixels16: nil)
            }

            return nil
        }
    }
}
