import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

let pixelCount = 1024 * 1024
var pixels = (0..<pixelCount).map { _ in UInt16.random(in: 0...65535) }
let winWidth = 400
let winCenter = 40
let slope = 1
let intercept = 0

func naiveWindowLevel(_ src: [UInt16]) -> [UInt8] {
    let ww = Double(max(winWidth, 1))
    let wc = Double(winCenter)
    let slopeD = Double(slope)
    let interceptD = Double(intercept)
    let lower = wc - ww / 2.0
    let upper = wc + ww / 2.0
    var dst = [UInt8](repeating: 0, count: src.count)
    for i in 0..<src.count {
        let raw = Double(src[i])
        let modality = raw * slopeD + interceptD
        if modality <= lower {
            dst[i] = 0
        } else if modality >= upper {
            dst[i] = 255
        } else {
            dst[i] = UInt8(((modality - lower) / ww) * 255.0)
        }
    }
    return dst
}

func vDSPWindowLevel(_ src: [UInt16]) -> [UInt8] {
#if canImport(Accelerate)
    let pixelCount = src.count
    var floatPixels = [Float](repeating: 0, count: pixelCount)
    vDSP.integerToFloatingPoint(src, result: &floatPixels)
    var m = Float(slope)
    var b = Float(intercept)
    vDSP_vsmsa(floatPixels, 1, &m, &b, &floatPixels, 1, vDSP_Length(pixelCount))
    var wc = Float(winCenter)
    var ww = Float(max(winWidth,1))
    var lo = wc - ww/2.0
    var hi = wc + ww/2.0
    vDSP_vclip(floatPixels, 1, &lo, &hi, &floatPixels, 1, vDSP_Length(pixelCount))
    var negLo = -lo
    vDSP_vsadd(floatPixels, 1, &negLo, &floatPixels, 1, vDSP_Length(pixelCount))
    var scale = Float(255) / ww
    vDSP_vsmul(floatPixels, 1, &scale, &floatPixels, 1, vDSP_Length(pixelCount))
    var out = [UInt8](repeating: 0, count: pixelCount)
    out.withUnsafeMutableBufferPointer { ptr in
        vDSP_vfixu8(floatPixels, 1, ptr.baseAddress!, 1, vDSP_Length(pixelCount))
    }
    return out
#else
    return naiveWindowLevel(src)
#endif
}

var t0 = Date()
_ = naiveWindowLevel(pixels)
var t1 = Date()
let naiveTime = t1.timeIntervalSince(t0)

t0 = Date()
_ = vDSPWindowLevel(pixels)
t1 = Date()
let vDSPTime = t1.timeIntervalSince(t0)

print(String(format: "Naive window/level: %.3f ms", naiveTime * 1000))
print(String(format: "vDSP window/level: %.3f ms", vDSPTime * 1000))

// Benchmark LUT application
func buildLUT(winMin: Int, winMax: Int) -> [UInt8] {
    let size = 65536
    let denom = max(winMax - winMin, 1)
    var lut = [UInt8](repeating: 0, count: size)
    for v in 0..<size {
        let c = min(max(v - winMin, 0), denom)
        lut[v] = UInt8(c * 255 / denom)
    }
    return lut
}

let lut = buildLUT(winMin: 0, winMax: winWidth)

func naiveLUT(_ src: [UInt16], lut: [UInt8]) -> [UInt8] {
    var dst = [UInt8](repeating: 0, count: src.count)
    for i in 0..<src.count { dst[i] = lut[Int(src[i])] }
    return dst
}

func vDSPLUT(_ src: [UInt16], lut: [UInt8]) -> [UInt8] {
#if canImport(Accelerate)
    let count = src.count
    var indices = [Float](repeating: 0, count: count)
    vDSP.integerToFloatingPoint(src, result: &indices)
    var lutF = [Float](repeating: 0, count: lut.count)
    vDSP.integerToFloatingPoint(lut, result: &lutF)
    var resultF = [Float](repeating: 0, count: count)
    vDSP_vlint(lutF, 1, indices, 1, &resultF, 1, vDSP_Length(count), vDSP_Length(lut.count))
    var out = [UInt8](repeating: 0, count: count)
    out.withUnsafeMutableBufferPointer { ptr in
        vDSP_vfixu8(resultF, 1, ptr.baseAddress!, 1, vDSP_Length(count))
    }
    return out
#else
    return naiveLUT(src, lut: lut)
#endif
}

t0 = Date()
_ = naiveLUT(pixels, lut: lut)
t1 = Date()
let naiveLUTTime = t1.timeIntervalSince(t0)

t0 = Date()
_ = vDSPLUT(pixels, lut: lut)
t1 = Date()
let vDSPLUTTime = t1.timeIntervalSince(t0)

print(String(format: "Naive LUT: %.3f ms", naiveLUTTime * 1000))
print(String(format: "vDSP LUT: %.3f ms", vDSPLUTTime * 1000))
