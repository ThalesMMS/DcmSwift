//
//  J2KCodestreamParser.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
//
//  Minimal parser to extract SIZ info from a JPEG 2000 codestream.
//

import Foundation

public struct J2KCodestreamInfo {
    public let width: Int
    public let height: Int
    public let components: Int
    public let bitsPerComponent: Int
    public let isSigned: Bool
}

public enum J2KParseError: Error { case truncated, sizNotFound, invalid }

public enum J2KCodestreamParser {
    /// Parses the SIZ marker segment to extract basic image parameters.
    /// Expects a raw JPEG 2000 codestream beginning with SOC (0xFF4F).
    public static func parseSIZ(_ data: Data) throws -> J2KCodestreamInfo {
        guard data.count >= 4 else { throw J2KParseError.truncated }

        // Search SOC (0xFF4F) then SIZ (0xFF51)
        var i = 0
        while i + 1 < data.count {
            if data[i] == 0xFF && data[i+1] == 0x4F { i += 2; break }
            i += 1
        }
        // Walk markers until SIZ
        while i + 3 < data.count {
            if data[i] != 0xFF { i += 1; continue }
            let marker = Int(data[i+1])
            if marker == 0x51 { // SIZ
                // length (Lsiz) at i+2..i+3, then payload
                let Lsiz = Int(UInt16(data[i+2]) << 8 | UInt16(data[i+3]))
                let start = i + 4
                let end = start + Lsiz - 2
                guard end <= data.count else { throw J2KParseError.truncated }
                // Offsets per spec
                func be16(_ o: Int) -> Int { Int((UInt16(data[o]) << 8) | UInt16(data[o+1])) }
                func be32(_ o: Int) -> Int { Int((UInt32(data[o]) << 24) | (UInt32(data[o+1]) << 16) | (UInt32(data[o+2]) << 8) | UInt32(data[o+3])) }
                let Xsiz = be32(start + 4)
                let Ysiz = be32(start + 8)
                let XOsiz = be32(start + 12)
                let YOsiz = be32(start + 16)
                let Csiz = be16(start + 36)
                let comp0 = start + 38 // first component parameters (Ssizi, XRsizi, YRsizi)
                guard comp0 < end else { throw J2KParseError.truncated }
                let Ssizi = Int(data[comp0])
                let bits = (Ssizi & 0x7F) + 1
                let signed = (Ssizi & 0x80) != 0
                let width = Xsiz - XOsiz
                let height = Ysiz - YOsiz
                return J2KCodestreamInfo(width: width, height: height, components: Csiz, bitsPerComponent: bits, isSigned: signed)
            }
            // Skip variable length marker segment: next two bytes are length
            if marker == 0x4F || marker == 0x90 { // SOC, SOT (no length for SOC, SOT has length but we can scan)
                i += 2
            } else {
                let L = Int(UInt16(data[i+2]) << 8 | UInt16(data[i+3]))
                i += 2 + 2 + max(0, L - 2)
            }
        }
        throw J2KParseError.sizNotFound
    }
}

