//
//  JPEGBaselineDecoder.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
//
//  Decodes DICOM JPEG Baseline/Extended codestreams using ImageIO.
//

import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
import CoreGraphics

public enum JPEGDecodeError: Error { case decodeFailed, jpeg12Unsupported, notAvailable }

public enum JPEGBaselineDecoder {
    /// Attempts to decode a raw JPEG codestream to CGImage using ImageIO.
    /// Note: Some platforms may not support 12-bit JPEG; in that case, throws .jpeg12Unsupported.
    public static func decode(_ codestream: Data) throws -> CGImage {
#if canImport(ImageIO)
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(codestream as CFData, opts) else {
            throw JPEGDecodeError.decodeFailed
        }
        guard let img = CGImageSourceCreateImageAtIndex(src, 0, opts) else {
            // Heuristic: if ImageIO cannot create image, likely unsupported (e.g., 12-bit)
            throw JPEGDecodeError.jpeg12Unsupported
        }
        return img
#else
        throw JPEGDecodeError.notAvailable
#endif
    }
}

