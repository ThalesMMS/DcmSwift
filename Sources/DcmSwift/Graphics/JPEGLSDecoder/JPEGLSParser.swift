//
//  JPEGLSParser.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 
//  Parses minimal JPEG-LS headers to extract image parameters and locate the entropy-coded segment.
//

import Foundation

struct JPEGLSParams {
    let width: Int
    let height: Int
    let components: Int
    let bitsPerSample: Int
    let near: Int
    let interleaveMode: UInt8 // 0=none,1=line,2=sample
    let entropyData: Data     // stuffed entropy-coded bytes between SOS and EOI/next marker (first scan)
    let scanEntropies: [Data] // one per SOS when ILV=none
    let scanComponents: [UInt8] // component selector per scan
    let scanNEARs: [Int]
}

enum JPEGLSParseError: Error { case invalid, truncated, unsupported }

enum JPEGLSParser {
    static func parse(_ data: Data) throws -> JPEGLSParams {
        var i = 0
        func need(_ n: Int) throws { if i + n > data.count { throw JPEGLSParseError.truncated } }
        func u8() throws -> UInt8 { try need(1); defer { i += 1 }; return data[i] }
        func u16() throws -> Int { try need(2); defer { i += 2 }; return Int(UInt16(data[i]) << 8 | UInt16(data[i+1])) }
        func skip(_ n: Int) throws { try need(n); i += n }

        // Expect SOI
        guard data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 else { throw JPEGLSParseError.invalid }
        i = 2

        var width = 0, height = 0, comps = 0, bps = 0
        var near: Int = 0
        var ilv: UInt8 = 0
        var entropyStart = 0
        var entropyEnd = 0
        var scans: [Data] = []
        var scanCS: [UInt8] = []
        var scanNEAR: [Int] = []

        while i + 1 < data.count {
            if data[i] != 0xFF { i += 1; continue }
            // Skip fill bytes 0xFF
            while i < data.count && data[i] == 0xFF { i += 1 }
            guard i < data.count else { break }
            let marker = data[i]; i += 1

            if marker == 0xD9 { // EOI
                break
            } else if marker == 0xDA { // SOS (Start of Scan)
                let Ls = try u16()
                let Ns = try u8()
                // Component selectors (Ns bytes); for ILV=none, Ns=1 per scan
                var cs: [UInt8] = []
                for _ in 0..<Int(Ns) { cs.append(try u8()) }
                let thisNear = Int(try u8())
                let thisIlv = try u8()
                _ = try u8() // mapping table selector (unused in baseline)
                // Entropy-coded data begins here until next marker 0xFF D9 or any 0xFF marker
                entropyStart = i
                // Find next marker (handle byte stuffing: 0xFF 0x00 -> data 0xFF)
                var j = i
                while j + 1 < data.count {
                    if data[j] == 0xFF {
                        let nxt = data[j+1]
                        if nxt == 0x00 { j += 2; continue } // stuffed 0xFF byte
                        entropyEnd = j
                        break
                    }
                    j += 1
                }
                if entropyEnd == 0 { entropyEnd = data.count }
                // Record this scan
                let seg = data.subdata(in: entropyStart..<entropyEnd)
                scans.append(seg)
                scanCS.append(cs.first ?? 1)
                scanNEAR.append(thisNear)
                // Persist main near/ilv from first scan
                if scans.count == 1 { near = thisNear; ilv = thisIlv }
                i = entropyEnd
            } else if marker == 0xF7 { // SOF55 (JPEG-LS frame header)
                let Lf = try u16(); _ = Lf
                bps = Int(try u8())
                height = try u16()
                width = try u16()
                comps = Int(try u8())
                // For JPEG-LS, component spec fields follow (3 bytes each), skip them
                try skip(3 * comps)
            } else if marker == 0xF8 { // LSE (JPEG-LS parameters) optional
                let Ls = try u16()
                // If present, could override thresholds/near, but we keep defaults for baseline
                try skip(Ls - 2)
            } else if marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
                // SOI, TEM, RSTn have no payload
                continue
            } else {
                // Other marker with length
                let L = try u16()
                try skip(L - 2)
            }
        }

        guard width > 0, height > 0, comps > 0, bps > 0, !scans.isEmpty else { throw JPEGLSParseError.invalid }
        let entropy = scans.first ?? Data()
        return JPEGLSParams(width: width, height: height, components: comps, bitsPerSample: bps, near: near, interleaveMode: ilv, entropyData: entropy, scanEntropies: scans, scanComponents: scanCS, scanNEARs: scanNEAR)
    }
}
