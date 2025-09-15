//
//  ScanDecoder.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
// 
//  JPEG-LS scan decoder scaffold. Currently not implemented.
//

import Foundation

enum JLSSCANError: Error { case notImplemented, decodeFailed }

enum ScanDecoder {
    static func decodeGrayscaleNear0(params: JPEGLSParams) throws -> (gray8: [UInt8]?, gray16: [UInt16]?) {
        // Parse entropy data (byte-stuffed) into a bitstream
        let bs = BitStream(unstuff(params.entropyData))

        let width = params.width
        let height = params.height
        let bps = params.bitsPerSample
        let maxval = (1 << bps) - 1
        let range = maxval + 1
        let qbpp = Int(ceil(log2(Double(range)))) + 1
        let limit = 2 * ((1 << qbpp) + min(1 << qbpp, range - (1 << qbpp)))

        var state = JLSState(bitsPerSample: bps, near: params.near)

        // Output buffers
        if bps <= 8 {
            var out = [UInt8](repeating: 0, count: width * height)
            try decodeLoop(bs: bs, width: width, height: height, maxval: maxval, qbpp: qbpp, limit: limit, near: params.near, state: &state) { idx, px in
                out[idx] = UInt8(px & 0xFF)
            }
            return (gray8: out, gray16: nil)
        } else {
            var out = [UInt16](repeating: 0, count: width * height)
            try decodeLoop(bs: bs, width: width, height: height, maxval: maxval, qbpp: qbpp, limit: limit, near: params.near, state: &state) { idx, px in
                out[idx] = UInt16(px & 0xFFFF)
            }
            return (gray8: nil, gray16: out)
        }
    }

    static func decodeMultiComponent(params: JPEGLSParams) throws -> [UInt8]? {
        guard params.components > 1, params.bitsPerSample <= 8 else { throw JLSSCANError.notImplemented }
        // ILV=none: decode each scan independently
        let width = params.width, height = params.height
        var planes: [[UInt8]] = []
        for (idx, seg) in params.scanEntropies.enumerated() {
            let bs = BitStream(unstuff(seg))
            var state = JLSState(bitsPerSample: params.bitsPerSample, near: params.scanNEARs[safe: idx] ?? params.near)
            var out = [UInt8](repeating: 0, count: width * height)
            let maxval = (1 << params.bitsPerSample) - 1
            let range = maxval + 1
            let qbpp = Int(ceil(log2(Double(range)))) + 1
            let limit = 2 * ((1 << qbpp) + min(1 << qbpp, range - (1 << qbpp)))
            try decodeLoop(bs: bs, width: width, height: height, maxval: maxval, qbpp: qbpp, limit: limit, near: params.near, state: &state) { i, px in
                out[i] = UInt8(px & 0xFF)
            }
            planes.append(out)
        }
        guard !planes.isEmpty else { throw JLSSCANError.decodeFailed }
        // Interleave RGB (or first 3 components)
        let comps = min(params.components, planes.count)
        var interleaved = [UInt8](repeating: 0, count: width * height * comps)
        var j = 0
        for i in 0..<(width * height) {
            for c in 0..<comps { interleaved[j] = planes[c][i]; j += 1 }
        }
        return interleaved
    }

    static func decodeMultiComponent16(params: JPEGLSParams) throws -> [UInt16]? {
        guard params.components > 1, params.bitsPerSample > 8 else { throw JLSSCANError.notImplemented }
        let width = params.width, height = params.height
        var planes: [[UInt16]] = []
        for (idx, seg) in params.scanEntropies.enumerated() {
            let bs = BitStream(unstuff(seg))
            var state = JLSState(bitsPerSample: params.bitsPerSample, near: params.scanNEARs[safe: idx] ?? params.near)
            var out = [UInt16](repeating: 0, count: width * height)
            let maxval = (1 << params.bitsPerSample) - 1
            let range = maxval + 1
            let qbpp = Int(ceil(log2(Double(range)))) + 1
            let limit = 2 * ((1 << qbpp) + min(1 << qbpp, range - (1 << qbpp)))
            try decodeLoop(bs: bs, width: width, height: height, maxval: maxval, qbpp: qbpp, limit: limit, near: params.near, state: &state) { i, px in
                out[i] = UInt16(px & 0xFFFF)
            }
            planes.append(out)
        }
        guard !planes.isEmpty else { throw JLSSCANError.decodeFailed }
        let comps = min(params.components, planes.count)
        var interleaved = [UInt16](repeating: 0, count: width * height * comps)
        var j = 0
        for i in 0..<(width * height) {
            for c in 0..<comps { interleaved[j] = planes[c][i]; j += 1 }
        }
        return interleaved
    }

    static func decodeInterleavedLine(params: JPEGLSParams) throws -> (rgb8: [UInt8]?, rgb16: [UInt16]?) {
        let comps = params.components
        let width = params.width
        let height = params.height
        let bps = params.bitsPerSample
        let maxval = (1 << bps) - 1
        let range = maxval + 1
        let qbpp = Int(ceil(log2(Double(range)))) + 1
        let limit = 2 * ((1 << qbpp) + min(1 << qbpp, range - (1 << qbpp)))

        // Single scan bitstream
        let bs = BitStream(unstuff(params.entropyData))

        // Per-component state and row buffers
        var states: [JLSState] = (0..<comps).map { _ in JLSState(bitsPerSample: bps, near: params.near) }
        var prevRows: [[Int]] = (0..<comps).map { _ in [Int](repeating: 0, count: width) }
        var currRow: [Int] = [Int](repeating: 0, count: width) // reused per component per line

        if bps <= 8 {
            var planes: [[UInt8]] = (0..<comps).map { _ in [UInt8](repeating: 0, count: width * height) }
            for y in 0..<height {
                for c in 0..<comps {
                    // decode one line for component c
                    currRow = [Int](repeating: 0, count: width)
                    try decodeLine(bs: bs, width: width, maxval: maxval, qbpp: qbpp, limit: limit, near: params.near, state: &states[c], prevRow: &prevRows[c]) { x, px in
                        planes[c][y * width + x] = UInt8(px & 0xFF)
                    }
                }
            }
            // interleave into RGBx
            var interleaved = [UInt8](repeating: 0, count: width * height * comps)
            var j = 0
            for i in 0..<(width * height) {
                for c in 0..<comps { interleaved[j] = planes[c][i]; j += 1 }
            }
            return (rgb8: interleaved, rgb16: nil)
        } else {
            var planes: [[UInt16]] = (0..<comps).map { _ in [UInt16](repeating: 0, count: width * height) }
            for y in 0..<height {
                for c in 0..<comps {
                    currRow = [Int](repeating: 0, count: width)
                    try decodeLine(bs: bs, width: width, maxval: maxval, qbpp: qbpp, limit: limit, near: params.near, state: &states[c], prevRow: &prevRows[c]) { x, px in
                        planes[c][y * width + x] = UInt16(px & 0xFFFF)
                    }
                }
            }
            var interleaved = [UInt16](repeating: 0, count: width * height * comps)
            var j = 0
            for i in 0..<(width * height) {
                for c in 0..<comps { interleaved[j] = planes[c][i]; j += 1 }
            }
            return (rgb8: nil, rgb16: interleaved)
        }
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

private extension ScanDecoder {
    typealias OutWriter = (_ index: Int, _ value: Int) -> Void

    static func decodeLoop(bs: BitStream,
                           width: Int,
                           height: Int,
                           maxval: Int,
                           qbpp: Int,
                           limit: Int,
                           near: Int,
                           state: inout JLSState,
                           write: OutWriter) throws {
        var prevRow = [Int](repeating: 0, count: width)
        var currRow = [Int](repeating: 0, count: width)
        var outIndex = 0

        for _ in 0..<height {
            var x = 0
            while x < width {
                // Neighbors: a=left, b=up, c=up-left, d=up-right (replicate at borders)
                let b = prevRow[x]
                let a = (x == 0) ? b : currRow[x - 1]
                let c = (x == 0) ? b : prevRow[x - 1]
                let d = (x + 1 < width) ? prevRow[x + 1] : b

                // Run mode when neighboring samples are equal within NEAR
                if abs(a - b) <= near && abs(b - c) <= near && abs(a - c) <= near {
                    // Decode run
                    var runRemaining = width - x
                    while runRemaining > 0 {
                        let J = min(7, state.RUNindex >> 2)
                        guard let bit = bs.readBits(1) else { throw JLSSCANError.notImplemented }
                        if bit == 1 {
                            let runLen = 1 << J
                            let m = min(runLen, runRemaining)
                            for _ in 0..<m { currRow[x] = a; write(outIndex, a); outIndex += 1; x += 1 }
                            runRemaining -= m
                            if m == runLen {
                                if state.RUNindex < 31 { state.RUNindex += 1 }
                                if runRemaining == 0 { break }
                                continue
                            } else {
                                break // hit end of line
                            }
                        } else {
                            // remainder
                            let Jbits = J
                            let r = (Jbits == 0) ? 0 : Int(bs.readBits(Jbits) ?? 0)
                            let m = min(r, runRemaining)
                            for _ in 0..<m { currRow[x] = a; write(outIndex, a); outIndex += 1; x += 1 }
                            runRemaining -= m
                            state.RUNindex = 0
                            if runRemaining > 0 {
                                // Run-interruption (RI) sample
                                let b2 = prevRow[x]
                                let RItype = (abs(a - b2) <= near) ? 1 : 0
                                // Compute k for RI context
                                var k = 0
                                while (state.N_RI[RItype] << k) < state.A_RI[RItype] { k += 1 }
                                guard let mval = Golomb.decodeRice(bs, k: k) else { throw JLSSCANError.notImplemented }
                                var errVal: Int
                                if RItype == 1 {
                                    // a == b
                                    errVal = mval
                                } else {
                                    // a != b
                                    let sign = (a > b2) ? 1 : 0
                                    if k == 0 && mval == 0 {
                                        if 2 * state.Nn[0] < state.N_RI[0] { errVal = 0 } else { errVal = 1 }
                                    } else {
                                        errVal = mval
                                    }
                                    if sign == 1 { errVal = -errVal - 1 }
                                    if errVal < 0 { state.Nn[0] += 1 }
                                }
                                // Reconstruct and output
                                var Rx = a + errVal
                                if Rx < 0 { Rx = 0 } else if Rx > maxval { Rx = maxval }
                                currRow[x] = Rx
                                write(outIndex, Rx); outIndex += 1; x += 1
                                state.A_RI[RItype] += abs(errVal)
                                state.N_RI[RItype] += 1
                            }
                            break
                        }
                    }
                    continue
                }

                // Regular mode
                var g1 = d - b
                var g2 = b - c
                var g3 = c - a
                let Q1 = quantize(g1, T1: state.T1, T2: state.T2, T3: state.T3)
                let Q2 = quantize(g2, T1: state.T1, T2: state.T2, T3: state.T3)
                let Q3 = quantize(g3, T1: state.T1, T2: state.T2, T3: state.T3)
                var sign = 1
                var q1 = Q1, q2 = Q2, q3 = Q3
                if q1 < 0 || (q1 == 0 && q2 < 0) || (q1 == 0 && q2 == 0 && q3 < 0) {
                    sign = -1
                    q1 = -q1; q2 = -q2; q3 = -q3
                    g1 = -g1; g2 = -g2; g3 = -g3
                }
                let ctx = contextIndex(q1: q1, q2: q2, q3: q3)

                // Compute predictor Px (LOCO-I median)
                let minAB = min(a, b)
                let maxAB = max(a, b)
                var Px: Int
                if c >= maxAB { Px = minAB }
                else if c <= minAB { Px = maxAB }
                else { Px = a + b - c }
                // bias correction via C[ctx]
                if sign == 1 { Px += state.C[ctx] } else { Px -= state.C[ctx] }
                if Px < 0 { Px = 0 } else if Px > maxval { Px = maxval }

                // Determine Golomb parameter k
                var k = 0
                while (state.N[ctx] << k) < state.A[ctx] { k += 1 }

                // Decode mapped error value
                guard let MErr = Golomb.decode(bs, k: k, limit: limit, qbpp: qbpp) else { throw JLSSCANError.notImplemented }

                // Unmap error
                var Errval: Int
                if (MErr & 1) == 0 { // even
                    Errval = MErr >> 1
                } else {
                    Errval = -((MErr + 1) >> 1)
                }
                // Near-lossless scaling
                if near > 0 { Errval *= (near + 1) }
                Errval *= sign

                // Reconstruct sample
                var Rx = Px + Errval
                if Rx < 0 { Rx = 0 } else if Rx > maxval { Rx = maxval }
                currRow[x] = Rx
                write(outIndex, Rx)
                outIndex += 1; x += 1

                // Update context variables
                state.A[ctx] += abs(Errval)
                if state.N[ctx] == state.RESET {
                    state.A[ctx] >>= 1
                    if state.B[ctx] < 0 { state.B[ctx] = -(((-state.B[ctx]) >> 1)) } else { state.B[ctx] >>= 1 }
                    state.N[ctx] >>= 1
                }
                state.N[ctx] += 1
                // Update bias B and C
                state.B[ctx] += Errval
                if state.B[ctx] <= -state.N[ctx] {
                    state.B[ctx] += state.N[ctx]
                    if state.C[ctx] > -128 { state.C[ctx] -= 1 }
                } else if state.B[ctx] > 0 {
                    state.B[ctx] -= state.N[ctx]
                    if state.C[ctx] < 127 { state.C[ctx] += 1 }
                }
            }

            // Next line
            prevRow = currRow
            // Do not clear currRow; it will be overwritten
        }
    }

    static func decodeLine(bs: BitStream,
                           width: Int,
                           maxval: Int,
                           qbpp: Int,
                           limit: Int,
                           near: Int,
                           state: inout JLSState,
                           prevRow: inout [Int],
                           write: (_ x: Int, _ value: Int) -> Void) throws {
        var currRow = [Int](repeating: 0, count: width)
        var x = 0
        while x < width {
            let b = prevRow[x]
            let a = (x == 0) ? b : currRow[x - 1]
            let c = (x == 0) ? b : prevRow[x - 1]
            let d = (x + 1 < width) ? prevRow[x + 1] : b

            if abs(a - b) <= near && abs(b - c) <= near && abs(a - c) <= near {
                var runRemaining = width - x
                while runRemaining > 0 {
                    let J = min(7, state.RUNindex >> 2)
                    guard let bit = bs.readBits(1) else { throw JLSSCANError.notImplemented }
                    if bit == 1 {
                        let runLen = 1 << J
                        let m = min(runLen, runRemaining)
                        for _ in 0..<m { currRow[x] = a; write(x, a); x += 1 }
                        runRemaining -= m
                        if m == runLen {
                            if state.RUNindex < 31 { state.RUNindex += 1 }
                            if runRemaining == 0 { break }
                            continue
                        } else {
                            break
                        }
                    } else {
                        let Jbits = J
                        let r = (Jbits == 0) ? 0 : Int(bs.readBits(Jbits) ?? 0)
                        let m = min(r, runRemaining)
                        for _ in 0..<m { currRow[x] = a; write(x, a); x += 1 }
                        runRemaining -= m
                        state.RUNindex = 0
                        if runRemaining > 0 {
                            let b2 = prevRow[x]
                            let RItype = (abs(a - b2) <= near) ? 1 : 0
                            var k = 0
                            while (state.N_RI[RItype] << k) < state.A_RI[RItype] { k += 1 }
                            guard let mval = Golomb.decodeRice(bs, k: k) else { throw JLSSCANError.notImplemented }
                            var errVal: Int
                            if RItype == 1 {
                                errVal = mval
                            } else {
                                let sign = (a > b2) ? 1 : 0
                                if k == 0 && mval == 0 {
                                    if 2 * state.Nn[0] < state.N_RI[0] { errVal = 0 } else { errVal = 1 }
                                } else {
                                    errVal = mval
                                }
                                if sign == 1 { errVal = -errVal - 1 }
                                if errVal < 0 { state.Nn[0] += 1 }
                            }
                            var Rx = a + (near > 0 ? errVal * (near + 1) : errVal)
                            if Rx < 0 { Rx = 0 } else if Rx > maxval { Rx = maxval }
                            currRow[x] = Rx
                            write(x, Rx); x += 1
                            state.A_RI[RItype] += abs(errVal)
                            state.N_RI[RItype] += 1
                        }
                        break
                    }
                }
                continue
            }

            var g1 = d - b
            var g2 = b - c
            var g3 = c - a
            let Q1 = quantize(g1, T1: state.T1, T2: state.T2, T3: state.T3)
            let Q2 = quantize(g2, T1: state.T1, T2: state.T2, T3: state.T3)
            let Q3 = quantize(g3, T1: state.T1, T2: state.T2, T3: state.T3)
            var sign = 1
            var q1 = Q1, q2 = Q2, q3 = Q3
            if q1 < 0 || (q1 == 0 && q2 < 0) || (q1 == 0 && q2 == 0 && q3 < 0) {
                sign = -1
                q1 = -q1; q2 = -q2; q3 = -q3
                g1 = -g1; g2 = -g2; g3 = -g3
            }
            let ctx = contextIndex(q1: q1, q2: q2, q3: q3)

            let minAB = min(a, b)
            let maxAB = max(a, b)
            var Px: Int
            if c >= maxAB { Px = minAB }
            else if c <= minAB { Px = maxAB }
            else { Px = a + b - c }
            if sign == 1 { Px += state.C[ctx] } else { Px -= state.C[ctx] }
            if Px < 0 { Px = 0 } else if Px > maxval { Px = maxval }

            var k = 0
            while (state.N[ctx] << k) < state.A[ctx] { k += 1 }
            guard let MErr = Golomb.decode(bs, k: k, limit: limit, qbpp: qbpp) else { throw JLSSCANError.notImplemented }
            var Errval: Int
            if (MErr & 1) == 0 { Errval = MErr >> 1 } else { Errval = -((MErr + 1) >> 1) }
            if near > 0 { Errval *= (near + 1) }
            Errval *= sign

            var Rx = Px + Errval
            if Rx < 0 { Rx = 0 } else if Rx > maxval { Rx = maxval }
            currRow[x] = Rx
            write(x, Rx)
            x += 1

            state.A[ctx] += abs(Errval)
            if state.N[ctx] == state.RESET {
                state.A[ctx] >>= 1
                if state.B[ctx] < 0 { state.B[ctx] = -(((-state.B[ctx]) >> 1)) } else { state.B[ctx] >>= 1 }
                state.N[ctx] >>= 1
            }
            state.N[ctx] += 1
            state.B[ctx] += Errval
            if state.B[ctx] <= -state.N[ctx] {
                state.B[ctx] += state.N[ctx]
                if state.C[ctx] > -128 { state.C[ctx] -= 1 }
            } else if state.B[ctx] > 0 {
                state.B[ctx] -= state.N[ctx]
                if state.C[ctx] < 127 { state.C[ctx] += 1 }
            }
        }
        prevRow = currRow
    }

    static func quantize(_ g: Int, T1: Int, T2: Int, T3: Int) -> Int {
        if g <= -T3 { return -4 }
        if g <= -T2 { return -3 }
        if g <= -T1 { return -2 }
        if g < 0 { return -1 }
        if g == 0 { return 0 }
        if g < T1 { return 1 }
        if g < T2 { return 2 }
        if g < T3 { return 3 }
        return 4
    }

    // Canonical mapping of (q1,q2,q3) with q in [0..4] (non-negative after sign folding) into 365 regular contexts
    static var ctxMap: [Int] = buildCtxMap()

    static func contextIndex(q1: Int, q2: Int, q3: Int) -> Int {
        // q1,q2,q3 are non-negative in -4..4 folded to 0..4 ranges by caller
        let key = (q1 + 4) * 81 + (q2 + 4) * 9 + (q3 + 4)
        return ctxMap[key]
    }

    static func buildCtxMap() -> [Int] {
        // Map 9^3 keys (0..728) to 365 canonical indices by folding sign symmetry and collapsing (0,0,0) to index 0
        var map = [Int](repeating: 0, count: 9 * 9 * 9)
        var indexByTriple: [String: Int] = [:]
        var nextIndex = 1 // reserve 0 for (0,0,0)
        for q1 in -4...4 {
            for q2 in -4...4 {
                for q3 in -4...4 {
                    var a = q1, b = q2, c = q3
                    var s = 1
                    if a < 0 || (a == 0 && b < 0) || (a == 0 && b == 0 && c < 0) {
                        s = -1; a = -a; b = -b; c = -c
                    }
                    let canon = "\(a),\(b),\(c)"
                    let key = (q1 + 4) * 81 + (q2 + 4) * 9 + (q3 + 4)
                    if a == 0 && b == 0 && c == 0 {
                        map[key] = 0
                    } else {
                        if let idx = indexByTriple[canon] {
                            map[key] = idx
                        } else {
                            indexByTriple[canon] = nextIndex
                            map[key] = nextIndex
                            nextIndex += 1
                        }
                    }
                }
            }
        }
        // nextIndex should be 365
        return map
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
