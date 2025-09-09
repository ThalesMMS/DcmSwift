import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

enum WindowingError: Error {
    case invalidBufferSizes(expected: Int, src: Int, dst: Int)
    case invalidLUTSize(expected: Int, actual: Int)
}

@available(macOS 10.15, iOS 13, *)
internal func applyWindowTo8Concurrent(src: [UInt8], width: Int, height: Int, winMin: Int, winMax: Int, into dst: inout [UInt8]) async throws {
    let numPixels = width * height
    guard src.count >= numPixels, dst.count >= numPixels else {
        throw WindowingError.invalidBufferSizes(expected: numPixels, src: src.count, dst: dst.count)
    }
    let denom = max(winMax - winMin, 1)
#if canImport(Accelerate)
    if numPixels > 4096 {
        var floatSrc = src.map { Float($0) }
        var lower = Float(winMin)
        var upper = Float(winMax)
        vDSP_vclip(floatSrc, 1, &lower, &upper, &floatSrc, 1, vDSP_Length(numPixels))
        var subtract = Float(winMin)
        vDSP_vsadd(floatSrc, 1, &(-subtract), &floatSrc, 1, vDSP_Length(numPixels))
        var scale = Float(255) / Float(denom)
        vDSP_vsmul(floatSrc, 1, &scale, &floatSrc, 1, vDSP_Length(numPixels))
        var u8 = [UInt8](repeating: 0, count: numPixels)
        vDSP_vfixu8(floatSrc, 1, &u8, 1, vDSP_Length(numPixels))
        dst.replaceSubrange(0..<numPixels, with: u8)
        return
    }
#endif
    if numPixels > 2_000_000 {
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = (numPixels + threads - 1) / threads
        try await withThrowingTaskGroup(of: Void.self) { group in
            src.withUnsafeBufferPointer { inBuf in
                dst.withUnsafeMutableBufferPointer { outBuf in
                    let inBase = inBuf.baseAddress!
                    let outBase = outBuf.baseAddress!
                    for chunk in 0..<threads {
                        group.addTask {
                            try Task.checkCancellation()
                            let start = chunk * chunkSize
                            if start >= numPixels { return }
                            let end = min(start + chunkSize, numPixels)
                            var i = start
                            let fastEnd = end & ~3
                            while i < fastEnd {
                                let v0 = Int(inBase[i]);    let c0 = min(max(v0 - winMin, 0), denom)
                                let v1 = Int(inBase[i+1]);  let c1 = min(max(v1 - winMin, 0), denom)
                                let v2 = Int(inBase[i+2]);  let c2 = min(max(v2 - winMin, 0), denom)
                                let v3 = Int(inBase[i+3]);  let c3 = min(max(v3 - winMin, 0), denom)
                                outBase[i]   = UInt8(c0 * 255 / denom)
                                outBase[i+1] = UInt8(c1 * 255 / denom)
                                outBase[i+2] = UInt8(c2 * 255 / denom)
                                outBase[i+3] = UInt8(c3 * 255 / denom)
                                i += 4
                            }
                            while i < end {
                                let v = Int(inBase[i])
                                let clamped = min(max(v - winMin, 0), denom)
                                outBase[i] = UInt8(clamped * 255 / denom)
                                i += 1
                            }
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    } else {
        var i = 0
        let end = numPixels & ~3
        while i < end {
            let v0 = Int(src[i]);    let c0 = min(max(v0 - winMin, 0), denom)
            let v1 = Int(src[i+1]);  let c1 = min(max(v1 - winMin, 0), denom)
            let v2 = Int(src[i+2]);  let c2 = min(max(v2 - winMin, 0), denom)
            let v3 = Int(src[i+3]);  let c3 = min(max(v3 - winMin, 0), denom)
            dst[i]   = UInt8(c0 * 255 / denom)
            dst[i+1] = UInt8(c1 * 255 / denom)
            dst[i+2] = UInt8(c2 * 255 / denom)
            dst[i+3] = UInt8(c3 * 255 / denom)
            i += 4
        }
        while i < numPixels {
            let v = Int(src[i])
            let clamped = min(max(v - winMin, 0), denom)
            dst[i] = UInt8(clamped * 255 / denom)
            i += 1
        }
    }
}

@available(macOS 10.15, iOS 13, *)
internal func applyLUTTo16Concurrent(src: [UInt16], width: Int, height: Int, lut: [UInt8], into dst: inout [UInt8]) async throws {
    let numPixels = width * height
    guard src.count >= numPixels, dst.count >= numPixels else {
        throw WindowingError.invalidBufferSizes(expected: numPixels, src: src.count, dst: dst.count)
    }
    guard lut.count >= 65536 else {
        throw WindowingError.invalidLUTSize(expected: 65536, actual: lut.count)
    }
    if numPixels > 2_000_000 {
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = (numPixels + threads - 1) / threads
        try await withThrowingTaskGroup(of: Void.self) { group in
            src.withUnsafeBufferPointer { inBuf in
                lut.withUnsafeBufferPointer { lutBuf in
                    dst.withUnsafeMutableBufferPointer { outBuf in
                        let inBase = inBuf.baseAddress!
                        let lutBase = lutBuf.baseAddress!
                        let outBase = outBuf.baseAddress!
                        for chunk in 0..<threads {
                            group.addTask {
                                try Task.checkCancellation()
                                let start = chunk * chunkSize
                                if start >= numPixels { return }
                                let end = min(start + chunkSize, numPixels)
                                var i = start
                                let fastEnd = end & ~3
                                while i < fastEnd {
                                    outBase[i]   = lutBase[Int(inBase[i])]
                                    outBase[i+1] = lutBase[Int(inBase[i+1])]
                                    outBase[i+2] = lutBase[Int(inBase[i+2])]
                                    outBase[i+3] = lutBase[Int(inBase[i+3])]
                                    i += 4
                                }
                                while i < end {
                                    outBase[i] = lutBase[Int(inBase[i])]
                                    i += 1
                                }
                            }
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    } else {
        var i = 0
        let end = numPixels & ~3
        while i < end {
            dst[i]   = lut[Int(src[i])]
            dst[i+1] = lut[Int(src[i+1])]
            dst[i+2] = lut[Int(src[i+2])]
            dst[i+3] = lut[Int(src[i+3])]
            i += 4
        }
        while i < numPixels {
            dst[i] = lut[Int(src[i])]
            i += 1
        }
    }
}

