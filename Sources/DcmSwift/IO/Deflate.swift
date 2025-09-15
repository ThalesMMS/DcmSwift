//
//  Deflate.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//
//  Inflate (zlib) helper for Deflated Explicit VR Little Endian datasets.
//

import Foundation
@_implementationOnly import Compression

enum DeflateError: Error { case notAvailable, inflateFailed }

enum DeflateCodec {
    static func inflateZlib(_ data: Data) throws -> Data {
        return try data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data in
            guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { throw DeflateError.inflateFailed }
            // Try with a growing buffer
            var dstCapacity = max(256 * 1024, data.count * 4)
            for _ in 0..<6 {
                var out = Data(count: dstCapacity)
                let decoded = out.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
                    let dstBase = dstPtr.bindMemory(to: UInt8.self).baseAddress!
                    return compression_decode_buffer(dstBase, dstCapacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
                }
                if decoded > 0 {
                    out.removeSubrange(decoded..<out.count)
                    return out
                }
                dstCapacity <<= 1
            }
            throw DeflateError.inflateFailed
        }
    }
}
