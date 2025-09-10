//
//  RLEDecoder.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
//
//  DICOM RLE (Annex G) decoder. Supports common cases:
//  - Mono 8-bit (1 segment)
//  - Mono 16-bit (2 segments; value = seg0 | seg1<<8)
//  - RGB 8-bit (3 segments; interleaved RGB)
//

import Foundation

enum RLEError: Error { case truncated, badHeader, segmentsMismatch, unsupported }

struct RLEHeader {
    let numberOfSegments: Int
    let offsets: [Int] // up to 15 entries
}

final class RLEDecoder {
    static func decode(frameData: Data,
                       rows: Int,
                       cols: Int,
                       bitsAllocated: Int,
                       samplesPerPixel: Int) throws -> (pixels8: [UInt8]?, pixels16: [UInt16]?) {
        guard frameData.count >= 64 else { throw RLEError.truncated }

        // Parse 64-byte header (LE)
        func le32(_ d: Data, _ o: Int) -> Int {
            Int(UInt32(littleEndian: d.subdata(in: o..<(o+4)).withUnsafeBytes { $0.load(as: UInt32.self) }))
        }
        let numSeg = le32(frameData, 0)
        if numSeg <= 0 || numSeg > 15 { throw RLEError.badHeader }
        var offsets: [Int] = []
        for i in 0..<15 { offsets.append(le32(frameData, 4 + i*4)) }
        let header = RLEHeader(numberOfSegments: numSeg, offsets: offsets)

        let bytesPerSample = max(1, (bitsAllocated + 7) / 8)
        let expectedSegments = bytesPerSample * max(1, samplesPerPixel)
        if header.numberOfSegments < expectedSegments { throw RLEError.segmentsMismatch }

        // Compute segment boundaries relative to start of first segment (after header)
        let base = 64
        var segRanges: [Range<Int>] = []
        for i in 0..<header.numberOfSegments {
            let start = base + header.offsets[i]
            let nextOff = (i+1 < header.numberOfSegments) ? base + header.offsets[i+1] : frameData.count
            if start < base || start > frameData.count || nextOff < start || nextOff > frameData.count { throw RLEError.truncated }
            segRanges.append(start..<nextOff)
        }

        // Decompress each segment
        var planes: [[UInt8]] = []
        planes.reserveCapacity(expectedSegments)
        for i in 0..<expectedSegments {
            let r = segRanges[i]
            let out = try decodeSegment(frameData, start: r.lowerBound, end: r.upperBound)
            planes.append(out)
        }

        let pixelCount = rows * cols
        // Validate lengths (some encoders may pad lines, but typical images match exactly)
        for p in planes { if p.count < pixelCount { throw RLEError.truncated } }

        if samplesPerPixel == 1 {
            if bytesPerSample == 1 {
                // Mono 8-bit
                return (pixels8: Array(planes[0][0..<pixelCount]), pixels16: nil)
            } else if bytesPerSample == 2 {
                // Mono 16-bit; little-endian: LSB plane then MSB plane
                var out = [UInt16](repeating: 0, count: pixelCount)
                let p0 = planes[0]
                let p1 = planes[1]
                for i in 0..<pixelCount { out[i] = UInt16(p0[i]) | (UInt16(p1[i]) << 8) }
                return (pixels8: nil, pixels16: out)
            } else {
                throw RLEError.unsupported
            }
        } else if samplesPerPixel == 3 && bytesPerSample == 1 {
            // RGB 8-bit; output interleaved RGB
            var out = [UInt8](repeating: 0, count: pixelCount * 3)
            let r = planes[0], g = planes[1], b = planes[2]
            var j = 0
            for i in 0..<pixelCount { out[j] = r[i]; out[j+1] = g[i]; out[j+2] = b[i]; j += 3 }
            return (pixels8: out, pixels16: nil)
        } else {
            // Not implemented general case (e.g., 16-bit RGB)
            throw RLEError.unsupported
        }
    }

    private static func decodeSegment(_ data: Data, start: Int, end: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(end - start)
        var i = start
        while i < end {
            let control = Int(Int8(bitPattern: data[i])); i += 1
            if control >= 0 {
                let count = control + 1
                if i + count > end { throw RLEError.truncated }
                out.append(contentsOf: data[i..<(i+count)])
                i += count
            } else if control >= -127 {
                let count = (-control) + 1
                if i >= end { throw RLEError.truncated }
                let b = data[i]; i += 1
                out.append(contentsOf: repeatElement(b, count: count))
            } else {
                // -128: NOP
            }
        }
        return out
    }
}

