#if canImport(UIKit)
import UIKit
import CoreGraphics
import Foundation

/// Lightweight view for displaying DICOM pixel buffers (grayscale).
/// - Focuses on efficient redraws (post-window/level cache) and CGContext reuse.
/// - Supports 8-bit and 16-bit input. For 16-bit, uses a LUT (external or derived from the window).
@MainActor
public final class DCMImgView: UIView {

    // MARK: - Pixel State
    private var pix8: [UInt8]? = nil
    private var pix16: [UInt16]? = nil
    private var imgWidth: Int = 0
    private var imgHeight: Int = 0

    /// Number of samples per pixel. Currently expected = 1 (grayscale).
    public var samplesPerPixel: Int = 1

    // MARK: - Window/Level
    public var winCenter: Int = 0 { didSet { updateWindowLevel() } }
    public var winWidth: Int = 0  { didSet { updateWindowLevel() } }
    private var winMin: Int = 0
    private var winMax: Int = 0
    private var lastWinMin: Int = Int.min
    private var lastWinMax: Int = Int.min

    // MARK: - LUT for 16-bit→8-bit
    /// Optional external LUT. If present, it's used instead of deriving from the window.
    private var lut16: [UInt8]? = nil

    // MARK: - Post-window 8-bit image cache
    private var cachedImageData: [UInt8]? = nil
    private var cachedImageDataValid: Bool = false

    // MARK: - Context/CoreGraphics
    private var colorspace: CGColorSpace?
    private var bitmapContext: CGContext?
    private var bitmapImage: CGImage?

    private var lastContextWidth: Int = 0
    private var lastContextHeight: Int = 0
    private var lastSamplesPerPixel: Int = 0

    // MARK: - Public API

    /// Set 8-bit pixels (grayscale) and apply window.
    public func setPixels8(_ pixels: [UInt8], width: Int, height: Int,
                           windowWidth: Int, windowCenter: Int) {
        pix8 = pixels
        pix16 = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        setWindow(center: windowCenter, width: windowWidth)
        cachedImageDataValid = false
        recomputeImage()
        setNeedsDisplay()
    }

    /// Set 16-bit pixels (grayscale) and apply window (or external LUT if provided).
    public func setPixels16(_ pixels: [UInt16], width: Int, height: Int,
                            windowWidth: Int, windowCenter: Int) {
        pix16 = pixels
        pix8 = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        setWindow(center: windowCenter, width: windowWidth)
        cachedImageDataValid = false
        recomputeImage()
        setNeedsDisplay()
    }

    /// Adjust window/level explicitly.
    public func setWindow(center: Int, width: Int) {
        winCenter = center
        winWidth  = width
    }

    /// Set an optional 16→8 LUT (expected size ≥ 65536).
    public func setLUT16(_ lut: [UInt8]?) {
        lut16 = lut
        cachedImageDataValid = false
        recomputeImage()
        setNeedsDisplay()
    }

    // MARK: - Drawing

    public override func draw(_ rect: CGRect) {
        guard let image = bitmapImage,
              let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }

    // MARK: - Window/Level trigger

    private func updateWindowLevel() {
        let newMin = winCenter - winWidth / 2
        let newMax = winCenter + winWidth / 2

        // If nothing changed, skip recomputation.
        if newMin == lastWinMin && newMax == lastWinMax {
            setNeedsDisplay()
            return
        }

        winMin = newMin
        winMax = newMax
        lastWinMin = newMin
        lastWinMax = newMax

        // Changing the window invalidates the cache and any derived LUT.
        if lut16 == nil {
            // Derived LUT will be generated in recomputeImage() when needed.
        }
        cachedImageDataValid = false
        recomputeImage()
        setNeedsDisplay()
    }

    // MARK: - Image construction (core)

    private func recomputeImage() {
        guard imgWidth > 0, imgHeight > 0 else { return }
        guard !cachedImageDataValid else { return }

        // Ensure context reuse if dimensions/SPP match.
        if !shouldReuseContext(width: imgWidth, height: imgHeight, samples: samplesPerPixel) {
            resetImage()
            colorspace = (samplesPerPixel == 1) ? CGColorSpaceCreateDeviceGray()
                                                : CGColorSpaceCreateDeviceRGB()
            lastContextWidth = imgWidth
            lastContextHeight = imgHeight
            lastSamplesPerPixel = samplesPerPixel
        }

        // Allocate/reuse 8-bit buffer (single channel).
        let pixelCount = imgWidth * imgHeight
        if cachedImageData == nil || cachedImageData!.count != pixelCount * samplesPerPixel {
            cachedImageData = Array(repeating: 0, count: pixelCount * samplesPerPixel)
        }

        // Paths: direct 8-bit or 16-bit with LUT (external or derived from window)
        if let src8 = pix8 {
            applyWindowTo8(src8, into: &cachedImageData!)
        } else if let src16 = pix16 {
            let lut = lut16 ?? buildDerivedLUT16(winMin: winMin, winMax: winMax)
            applyLUTTo16(src16, lut: lut, into: &cachedImageData!)
        } else {
            // Nothing to do
            return
        }

        cachedImageDataValid = true

        // Build CGImage from the 8-bit buffer.
        guard let cs = colorspace else { return }
        cachedImageData!.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            // We don't permanently pin 'data' in the context to avoid retaining unnecessary memory:
            // create the context, call makeImage(), and discard the data pointer.
            if let ctx = CGContext(data: base,
                                   width: imgWidth,
                                   height: imgHeight,
                                   bitsPerComponent: 8,
                                   bytesPerRow: imgWidth * samplesPerPixel,
                                   space: cs,
                                   bitmapInfo: samplesPerPixel == 1
                                       ? CGImageAlphaInfo.none.rawValue
                                       : CGImageAlphaInfo.noneSkipLast.rawValue) {
                bitmapContext = ctx
                bitmapImage = ctx.makeImage()
            } else {
                bitmapContext = nil
                bitmapImage = nil
            }
        }
    }

    // MARK: - 8-bit window/level

    private func applyWindowTo8(_ src: [UInt8], into dst: inout [UInt8]) {
        let numPixels = imgWidth * imgHeight
        guard src.count >= numPixels, dst.count >= numPixels else {
            print("[DCMImgView] Error: pixel buffers too small. Expected \(numPixels), got src: \(src.count) dst: \(dst.count)")
            return
        }
        let denom = max(winMax - winMin, 1)

        // Parallel CPU path for large images
        if numPixels > 2_000_000 {
            let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let chunkSize = (numPixels + threads - 1) / threads
            src.withUnsafeBufferPointer { inBuf in
                dst.withUnsafeMutableBufferPointer { outBuf in
                    let inBase = inBuf.baseAddress!
                    let outBase = outBuf.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: threads) { chunk in
                        let start = chunk * chunkSize
                        if start >= numPixels { return }
                        let end = min(start + chunkSize, numPixels)
                        var i = start
                        let fastEnd = end & ~3
                        while i < fastEnd {
                            let v0 = Int(inBase[i]);     let c0 = min(max(v0 - winMin, 0), denom)
                            let v1 = Int(inBase[i+1]);   let c1 = min(max(v1 - winMin, 0), denom)
                            let v2 = Int(inBase[i+2]);   let c2 = min(max(v2 - winMin, 0), denom)
                            let v3 = Int(inBase[i+3]);   let c3 = min(max(v3 - winMin, 0), denom)
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
        } else {
            // Sequential path for small images
            src.withUnsafeBufferPointer { inBuf in
                dst.withUnsafeMutableBufferPointer { outBuf in
                    var i = 0
                    let end = numPixels & ~3
                    while i < end {
                        let v0 = Int(inBuf[i]);     let c0 = min(max(v0 - winMin, 0), denom)
                        let v1 = Int(inBuf[i+1]);   let c1 = min(max(v1 - winMin, 0), denom)
                        let v2 = Int(inBuf[i+2]);   let c2 = min(max(v2 - winMin, 0), denom)
                        let v3 = Int(inBuf[i+3]);   let c3 = min(max(v3 - winMin, 0), denom)
                        outBuf[i]   = UInt8(c0 * 255 / denom)
                        outBuf[i+1] = UInt8(c1 * 255 / denom)
                        outBuf[i+2] = UInt8(c2 * 255 / denom)
                        outBuf[i+3] = UInt8(c3 * 255 / denom)
                        i += 4
                    }
                    while i < numPixels {
                        let v = Int(inBuf[i])
                        let clamped = min(max(v - winMin, 0), denom)
                        outBuf[i] = UInt8(clamped * 255 / denom)
                        i += 1
                    }
                }
            }
        }
    }

    // MARK: - 16-bit via LUT

    /// Build a LUT derived from window/level (MONOCHROME2).
    private func buildDerivedLUT16(winMin: Int, winMax: Int) -> [UInt8] {
        // Minimum size 65536; if more than 16 effective bits, clamp at 65536.
        let size = 65536
        var lut = [UInt8](repeating: 0, count: size)
        let denom = max(winMax - winMin, 1)
        // Generate clamped linear mapping.
        for v in 0..<size {
            let c = min(max(v - winMin, 0), denom)
            lut[v] = UInt8(c * 255 / denom)
        }
        return lut
    }

    private func applyLUTTo16(_ src: [UInt16], lut: [UInt8], into dst: inout [UInt8]) {
        let numPixels = imgWidth * imgHeight
        guard src.count >= numPixels, dst.count >= numPixels, lut.count >= 65536 else {
            print("[DCMImgView] Error: buffer sizes invalid. Pixels expected \(numPixels), got src \(src.count) dst \(dst.count); LUT \(lut.count)")
            return
        }

        // Try GPU (stub currently returns false)
        let usedGPU = dst.withUnsafeMutableBufferPointer { outBuf in
            src.withUnsafeBufferPointer { inBuf in
                processPixelsGPU(inputPixels: inBuf.baseAddress!,
                                 outputPixels: outBuf.baseAddress!,
                                 pixelCount: numPixels,
                                 winMin: winMin,
                                 winMax: winMax)
            }
        }
        if usedGPU { return }

        // Parallel CPU for large images
        if numPixels > 2_000_000 {
            let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let chunkSize = (numPixels + threads - 1) / threads
            src.withUnsafeBufferPointer { inBuf in
                lut.withUnsafeBufferPointer { lutBuf in
                    dst.withUnsafeMutableBufferPointer { outBuf in
                        let inBase = inBuf.baseAddress!
                        let lutBase = lutBuf.baseAddress!
                        let outBase = outBuf.baseAddress!
                        DispatchQueue.concurrentPerform(iterations: threads) { chunk in
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
        } else {
            // Sequential path for small images
            src.withUnsafeBufferPointer { inBuf in
                lut.withUnsafeBufferPointer { lutBuf in
                    dst.withUnsafeMutableBufferPointer { outBuf in
                        var i = 0
                        let end = numPixels & ~3
                        while i < end {
                            outBuf[i]   = lutBuf[Int(inBuf[i])]
                            outBuf[i+1] = lutBuf[Int(inBuf[i+1])]
                            outBuf[i+2] = lutBuf[Int(inBuf[i+2])]
                            outBuf[i+3] = lutBuf[Int(inBuf[i+3])]
                            i += 4
                        }
                        while i < numPixels {
                            outBuf[i] = lutBuf[Int(inBuf[i])]
                            i += 1
                        }
                    }
                }
            }
        }
    }

    // MARK: - Context helpers

    private func shouldReuseContext(width: Int, height: Int, samples: Int) -> Bool {
        return width == lastContextWidth &&
               height == lastContextHeight &&
               samples == lastSamplesPerPixel
    }

    private func resetImage() {
        bitmapContext = nil
        bitmapImage = nil
    }

    // MARK: - GPU (stub)

    private func processPixelsGPU(inputPixels: UnsafePointer<UInt16>,
                                  outputPixels: UnsafeMutablePointer<UInt8>,
                                  pixelCount: Int,
                                  winMin: Int,
                                  winMax: Int) -> Bool {
        // Metal/Accelerate integration could go here.
        return false
    }
}
#endif
