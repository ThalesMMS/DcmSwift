//
//  ScanDecoder.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 
//  JPEG-LS scan decoder scaffold. Currently not implemented.
//

import Foundation

enum JLSSCANError: Error { case notImplemented }

enum ScanDecoder {
    static func decodeGrayscaleNear0(params: JPEGLSParams) throws -> (gray8: [UInt8]?, gray16: [UInt16]?) {
        // Parse entropy data (byte-stuffed) into a bitstream
        let bs = BitStream(unstuff(params.entropyData))
        _ = bs
        // TODO: Implement RUN/REGULAR modes for NEAR=0, 8/16-bit grayscale
        throw JLSSCANError.notImplemented
    }

    private static func unstuff(_ data: Data) -> Data {
        // Remove 0x00 stuffing after 0xFF bytes inside entropy-coded segment
        var out = Data(); out.reserveCapacity(data.count)
        var i = 0
        while i < data.count {
            let b = data[i]; i += 1
            out.append(b)
            if b == 0xFF {
                if i < data.count && data[i] == 0x00 { i += 1 } // drop stuffed 0x00
            }
        }
        return out
    }
}

