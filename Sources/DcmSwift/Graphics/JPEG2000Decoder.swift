//
//  JPEG2000Decoder.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
//
//  Decodes JPEG 2000 Part 1 codestreams by wrapping into JP2 and using ImageIO.
//

import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
import CoreGraphics

public enum JPEG2000DecodeError: Error { case decodeFailed, notAvailable }

public struct J2KDecodedFrame {
    public let width: Int
    public let height: Int
    public let bitsPerComponent: Int
    public let components: Int
    public let isSigned: Bool
    public let cgImage: CGImage
}

public enum JPEG2000Decoder {
    /// Decode a raw JPEG 2000 codestream by constructing a JP2 container and delegating to ImageIO.
    public static func decodeCodestream(_ codestream: Data) throws -> J2KDecodedFrame {
        let info = try J2KCodestreamParser.parseSIZ(codestream)
        let jp2 = try JP2Builder.makeJP2(from: codestream, info: info)
#if canImport(ImageIO)
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(jp2 as CFData, opts),
              let cgimg = CGImageSourceCreateImageAtIndex(src, 0, opts) else {
            throw JPEG2000DecodeError.decodeFailed
        }
        return J2KDecodedFrame(width: cgimg.width, height: cgimg.height,
                                bitsPerComponent: cgimg.bitsPerComponent,
                                components: cgimg.colorSpace?.numberOfComponents ?? info.components,
                                isSigned: info.isSigned, cgImage: cgimg)
#else
        throw JPEG2000DecodeError.notAvailable
#endif
    }
}

