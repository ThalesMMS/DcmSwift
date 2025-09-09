#if canImport(UIKit)
import UIKit
import CoreGraphics
import Foundation
#if canImport(Metal)
import Metal
#endif
#if canImport(Accelerate)
import Accelerate
#endif

/// Lightweight view for displaying DICOM pixel buffers (grayscale).
/// - Focuses on efficient redraws (post-window/level cache) and CGContext reuse.
/// - Supports 8-bit and 16-bit input. For 16-bit, uses a LUT (external or derived from the window).
@MainActor
public final class DicomPixelView: UIView {

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

    // Raw RGB(A) buffer (pass-through, no windowing). When set, we ignore pix8/pix16.
    private var pixRGBA: [UInt8]? = nil

#if canImport(Metal)
    // Reusable GPU buffers for window/level compute pipeline
    private var gpuInBuffer: MTLBuffer? = nil
    private var gpuOutBuffer: MTLBuffer? = nil
#endif

    // MARK: - Context/CoreGraphics
    private var colorspace: CGColorSpace?
    private var bitmapContext: CGContext?
    private var bitmapImage: CGImage?

    private var lastContextWidth: Int = 0
    private var lastContextHeight: Int = 0
    private var lastSamplesPerPixel: Int = 0

    // Performance metrics (optional)
    public var enablePerfMetrics: Bool = false
    private var debugLogsEnabled: Bool { UserDefaults.standard.bool(forKey: "settings.debugLogsEnabled") }

    // MARK: - Public API

    /// Set 8-bit pixels (grayscale) and apply window.
    public func setPixels8(_ pixels: [UInt8], width: Int, height: Int,
                           windowWidth: Int, windowCenter: Int) {
        pix8 = pixels
        pix16 = nil
        pixRGBA = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        setWindow(center: windowCenter, width: windowWidth)
    }

    /// Set 16-bit pixels (grayscale) and apply window (or external LUT if provided).
    public func setPixels16(_ pixels: [UInt16], width: Int, height: Int,
                            windowWidth: Int, windowCenter: Int) {
        pix16 = pixels
        pix8 = nil
        pixRGBA = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        setWindow(center: windowCenter, width: windowWidth)
    }

    /// Set 24-bit RGB or BGR pixels. Internally converted to RGBA (noneSkipLast) for fast drawing.
    public func setPixelsRGB(_ pixels: [UInt8], width: Int, height: Int, bgr: Bool = false) {
        let count = width * height
        guard pixels.count >= count * 3 else { return }

        // Convert to RGBA (noneSkipLast): 4 bytes per pixel, alpha unused.
        var rgba = [UInt8](repeating: 0, count: count * 4)
        pixels.withUnsafeBufferPointer { srcBuf in
            rgba.withUnsafeMutableBufferPointer { dstBuf in
                let s = srcBuf.baseAddress!
                let d = dstBuf.baseAddress!
                var i = 0
                var j = 0
                if bgr {
                    while i < count {
                        let b = s[j]
                        let g = s[j+1]
                        let r = s[j+2]
                        d[i*4+0] = r
                        d[i*4+1] = g
                        d[i*4+2] = b
                        d[i*4+3] = 255
                        i += 1; j += 3
                    }
                } else {
                    while i < count {
                        let r = s[j]
                        let g = s[j+1]
                        let b = s[j+2]
                        d[i*4+0] = r
                        d[i*4+1] = g
                        d[i*4+2] = b
                        d[i*4+3] = 255
                        i += 1; j += 3
                    }
                }
            }
        }
        pixRGBA = rgba
        pix8 = nil
        pix16 = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 4
        // Windowing does not apply for true color; preserve current WL but do not recompute mapping.
        cachedImageDataValid = false
        Task {
            await self.recomputeImage()
            self.setNeedsDisplay()
        }
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
        Task {
            await self.recomputeImage()
            self.setNeedsDisplay()
        }
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
        Task {
            await self.recomputeImage()
            self.setNeedsDisplay()
        }
    }

    // MARK: - Image construction (core)

    private func recomputeImage() async {
        let t0 = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0
        if debugLogsEnabled {
            print("[DicomPixelView] recomputeImage start size=\(imgWidth)x\(imgHeight) spp=\(samplesPerPixel) cacheValid=\(cachedImageDataValid)")
        }
        guard imgWidth > 0, imgHeight > 0 else { return }
        guard !cachedImageDataValid else {
            if debugLogsEnabled { print("[DicomPixelView] skip recompute (cache valid)") }
            return
        }

        // Ensure context reuse if dimensions/SPP match.
        if !shouldReuseContext(width: imgWidth, height: imgHeight, samples: samplesPerPixel) {
            resetImage()
            colorspace = (samplesPerPixel == 1) ? CGColorSpaceCreateDeviceGray()
                                                : CGColorSpaceCreateDeviceRGB()
            lastContextWidth = imgWidth
            lastContextHeight = imgHeight
            lastSamplesPerPixel = samplesPerPixel
            if debugLogsEnabled { print("[DicomPixelView] context reset for size/SPP") }
        } else if debugLogsEnabled {
            print("[DicomPixelView] context reused")
        }

        // Allocate/reuse target buffer
        let pixelCount = imgWidth * imgHeight
        if cachedImageData == nil || cachedImageData!.count != pixelCount * samplesPerPixel {
            cachedImageData = Array(repeating: 0, count: pixelCount * samplesPerPixel)
        }

        // Paths: direct 8-bit or 16-bit
        if let rgba = pixRGBA {
            // Color path: pass-through RGBA buffer
            cachedImageData = rgba
            if debugLogsEnabled { print("[DicomPixelView] path=RGBA passthrough") }
        } else if let src8 = pix8 {
            if debugLogsEnabled { print("[DicomPixelView] path=8-bit CPU WL") }
            do {
                try await applyWindowTo8Concurrent(src: src8,
                                                   width: imgWidth,
                                                   height: imgHeight,
                                                   winMin: winMin,
                                                   winMax: winMax,
                                                   into: &cachedImageData!)
            } catch {
                print("[DicomPixelView] Error applying window: \(error)")
            }
        } else if let src16 = pix16 {
            do {
                if let extLUT = lut16 {
                    if debugLogsEnabled { print("[DicomPixelView] path=16-bit external LUT CPU") }
                    try await applyLUTTo16Concurrent(src: src16,
                                                     width: imgWidth,
                                                     height: imgHeight,
                                                     lut: extLUT,
                                                     into: &cachedImageData!)
                } else if applyWindowTo16GPU(src16, into: &cachedImageData!) {
                    if debugLogsEnabled { print("[DicomPixelView] path=16-bit GPU WL") }
                } else {
                    if debugLogsEnabled { print("[DicomPixelView] path=16-bit CPU LUT fallback") }
                    let lut = buildDerivedLUT16(winMin: winMin, winMax: winMax)
                    try await applyLUTTo16Concurrent(src: src16,
                                                     width: imgWidth,
                                                     height: imgHeight,
                                                     lut: lut,
                                                     into: &cachedImageData!)
                }
            } catch {
                print("[DicomPixelView] Error applying LUT: \(error)")
            }
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
        if enablePerfMetrics {
            let dt = CFAbsoluteTimeGetCurrent() - t0
            print("[PERF][DicomPixelView] recomputeImage dt=\(String(format: "%.3f", dt*1000)) ms, spp=\(samplesPerPixel), size=\(imgWidth)x\(imgHeight)")
        }
    }

    // MARK: - 16-bit window/level

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

    private func applyWindowTo16GPU(_ src: [UInt16], into dst: inout [UInt8]) -> Bool {
        let numPixels = imgWidth * imgHeight
        return dst.withUnsafeMutableBufferPointer { outBuf in
            src.withUnsafeBufferPointer { inBuf in
                processPixelsGPU(inputPixels: inBuf.baseAddress!,
                                 outputPixels: outBuf.baseAddress!,
                                 pixelCount: numPixels,
                                 winMin: winMin,
                                 winMax: winMax)
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

    /// Clear cached image and intermediate buffers to free memory.
    public func clearCache() {
        cachedImageData = nil
        cachedImageDataValid = false
        resetImage()
#if canImport(Metal)
        gpuInBuffer = nil
        gpuOutBuffer = nil
#endif
    }

    /// Rough memory usage estimate for current buffers (bytes).
    public func estimatedMemoryUsage() -> Int {
        let pixelCount = imgWidth * imgHeight
        let current = cachedImageData?.count ?? 0
        let src8 = pix8?.count ?? 0
        let src16 = (pix16?.count ?? 0) * 2
        let rgba = pixRGBA?.count ?? 0
        return current + src8 + src16 + rgba + pixelCount // CG overhead estimate
    }

    // MARK: - GPU (stub)

    private func processPixelsGPU(inputPixels: UnsafePointer<UInt16>,
                                  outputPixels: UnsafeMutablePointer<UInt8>,
                                  pixelCount: Int,
                                  winMin: Int,
                                  winMax: Int) -> Bool {
#if canImport(Metal)
        let accel = MetalAccelerator.shared
        guard accel.isAvailable,
              let device = accel.device,
              let pso = accel.windowLevelPipelineState,
              let queue = accel.commandQueue
        else { return false }
        let t0 = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0

        // Match CPU mapping using winMin/denom directly
        let width = max(1, winMax - winMin)

        let inLen = pixelCount * MemoryLayout<UInt16>.stride
        let outLen = pixelCount * MemoryLayout<UInt8>.stride

        if gpuInBuffer == nil || gpuInBuffer!.length < inLen {
            gpuInBuffer = device.makeBuffer(length: inLen, options: .storageModeShared)
        }
        if gpuOutBuffer == nil || gpuOutBuffer!.length < outLen {
            gpuOutBuffer = device.makeBuffer(length: outLen, options: .storageModeShared)
        }
        guard let inBuf = gpuInBuffer, let outBuf = gpuOutBuffer else { return false }
        memcpy(inBuf.contents(), inputPixels, inLen)

        var uCount = UInt32(pixelCount)
        var sWinMin = Int32(winMin)
        var uDenom = UInt32(width)
        var invert: Bool = false

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return false }

        enc.setComputePipelineState(pso)
        enc.setBuffer(inBuf, offset: 0, index: 0)
        enc.setBuffer(outBuf, offset: 0, index: 1)
        
        // --- CONFLICT RESOLVED HERE ---
        // Using the more efficient setBytes and the more modern dispatchThreads API
        enc.setBytes(&uCount, length: MemoryLayout<UInt32>.stride, index: 2)
        enc.setBytes(&sWinMin, length: MemoryLayout<Int32>.stride, index: 3)
        enc.setBytes(&uDenom, length: MemoryLayout<UInt32>.stride, index: 4)
        enc.setBytes(&invert, length: MemoryLayout<Bool>.stride, index: 5)

        let w = min(pso.threadExecutionWidth, pso.maxTotalThreadsPerThreadgroup)
        let threadsPerThreadgroup = MTLSize(width: w, height: 1, depth: 1)
        let threadsPerGrid = MTLSize(width: pixelCount, height: 1, depth: 1)
        enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        // --- END OF CONFLICT RESOLUTION ---

        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()

        memcpy(outputPixels, outBuf.contents(), outLen)

        if enablePerfMetrics {
            let dt = CFAbsoluteTimeGetCurrent() - t0
            print("[PERF][DicomPixelView] GPU WL dt=\(String(format: "%.3f", dt*1000)) ms for \(pixelCount) px")
        }
        return true
#else
        return false
#endif
    }
}
#endif