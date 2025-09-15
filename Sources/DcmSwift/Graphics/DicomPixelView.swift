//  DicomPixelView.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.

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
#if canImport(os)
import os
import os.signpost
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

    /// Number of samples per pixel for the displayed image.
    public var samplesPerPixel: Int = 1
    /// Number of samples per pixel in the source data (used for 16-bit RGB).
    private var srcSamplesPerPixel: Int = 1

    // MARK: - Window/Level
    public var winCenter: Int = 0 { didSet { updateWindowLevel() } }
    public var winWidth: Int = 0  { didSet { updateWindowLevel() } }
    private var winMin: Int = 0
    private var winMax: Int = 0
    private var lastWinMin: Int = Int.min
    private var lastWinMax: Int = Int.min
    private var inverted: Bool = false

    // MARK: - LUT for 16-bit→8-bit
    /// Optional external LUT. If present, it's used instead of deriving from the window.
    private var lut16: [UInt8]? = nil

    // MARK: - Post-window 8-bit image cache
    private var cachedImageData: [UInt8]? = nil
    private var cachedImageDataValid: Bool = false

    // Raw RGB(A) buffer (pass-through, no windowing). When set, we ignore pix8/pix16.
    private var pixRGBA: [UInt8]? = nil

    // Debounce work item for window/level updates
    private var pendingWLRecompute: DispatchWorkItem? = nil

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
#if canImport(os)
    private let spLog = OSLog(subsystem: "com.isis.dicomviewer", category: .pointsOfInterest)
#endif

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
        srcSamplesPerPixel = 1
        setWindow(center: windowCenter, width: windowWidth)
        // --- CONFLICT RESOLVED ---
        // Adopting the immediate recompute call from the 'codex' branch for consistency.
        cachedImageDataValid = false
        recomputeImmediately()
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
        srcSamplesPerPixel = 1
        setWindow(center: windowCenter, width: windowWidth)
        // --- CONFLICT RESOLVED ---
        // Adopting the immediate recompute call from the 'codex' branch.
        cachedImageDataValid = false
        recomputeImmediately()
    }

    /// Set inversion for window/level mapping.
    public func setInvert(_ inv: Bool) {
        if inv == inverted { return }
        inverted = inv
        cachedImageDataValid = false
        recomputeImmediately()
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
        srcSamplesPerPixel = 4
        // Windowing does not apply for true color; preserve current WL but do not recompute mapping.
        cachedImageDataValid = false
        // --- CONFLICT RESOLVED ---
        // Adopting the immediate recompute call from the 'codex' branch.
        recomputeImmediately()
    }

    /// Set 16-bit RGB or RGBA pixels and apply window/level via GPU if possible.
    public func setPixels16RGB(_ pixels: [UInt16], width: Int, height: Int,
                               windowWidth: Int, windowCenter: Int,
                               samples: Int = 3) {
        let count = width * height
        guard pixels.count >= count * samples else { return }
        pix16 = pixels
        pix8 = nil
        pixRGBA = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 4 // output as RGBA
        srcSamplesPerPixel = samples
        setWindow(center: windowCenter, width: windowWidth)
        cachedImageDataValid = false
        recomputeImmediately()
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
        // --- CONFLICT RESOLVED ---
        // Adopting the immediate recompute call from the 'codex' branch.
        recomputeImmediately()
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
        // --- CONFLICT RESOLVED ---
        // Adopting the debounced recompute call from the 'codex' branch.
        scheduleRecompute()
    }

    // MARK: - Image construction (core)

    // --- CONFLICT RESOLVED ---
    // Adopting the debouncing logic from the 'codex' branch.
    /// Debounced recompute to batch rapid window/level adjustments.
    private func scheduleRecompute() {
        pendingWLRecompute?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.recomputeImage()
            self.setNeedsDisplay()
        }
        pendingWLRecompute = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16), execute: work)
    }

    /// Force an immediate recompute, cancelling any pending work.
    private func recomputeImmediately() {
        pendingWLRecompute?.cancel()
        pendingWLRecompute = nil
        recomputeImage()
        setNeedsDisplay()
    }

    private func recomputeImage() {
        let t0 = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0
#if canImport(os)
        if enablePerfMetrics {
            let spid = OSSignpostID(log: spLog)
            os_signpost(.begin, log: spLog, name: "DicomPixelView.recomputeImage", signpostID: spid)
            defer { os_signpost(.end, log: spLog, name: "DicomPixelView.recomputeImage", signpostID: spid) }
        }
#endif
        
        // Enhanced performance monitoring for rendering operations
        // Note: Frame rendering performance monitoring removed for now
        // as DcmSwiftPerformanceMonitor doesn't have frame-specific methods
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
            // Prefer GPU WL even for 8-bit to avoid CPU cost; fallback to CPU if unavailable.
            if applyWindowTo8GPU(src8, into: &cachedImageData!) {
                if debugLogsEnabled { print("[DicomPixelView] path=8-bit GPU WL") }
            } else {
                if debugLogsEnabled { print("[DicomPixelView] path=8-bit CPU WL") }
                let t = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0
                applyWindowTo8(src8, into: &cachedImageData!)
                if enablePerfMetrics {
                    let dt = (CFAbsoluteTimeGetCurrent() - t) * 1000
                    print("[PERF][DicomPixelView] WL8.ms=\(String(format: "%.3f", dt))")
                }
            }
        } else if let src16 = pix16 {
            // Adopting the logic from the 'codex' branch for 16-bit processing.
            if let extLUT = lut16 {
                // Try GPU first
                let gpuToken = DcmSwiftPerformanceMonitor.shared.startGPUOperation(GPUOperation.windowLevelCompute)
                let gpuSuccess = applyLUTTo16GPU(src16, lut: extLUT, into: &cachedImageData!, components: srcSamplesPerPixel)
                DcmSwiftPerformanceMonitor.shared.endGPUOperation(gpuToken, success: gpuSuccess)
                
                if gpuSuccess {
                    if debugLogsEnabled { print("[DicomPixelView] path=16-bit external LUT GPU") }
                } else {
                    if debugLogsEnabled { print("[DicomPixelView] path=16-bit external LUT CPU") }
                    let t = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0
                    applyLUTTo16CPU(src16, lut: extLUT, into: &cachedImageData!, components: srcSamplesPerPixel)
                    if enablePerfMetrics {
                        let dt = (CFAbsoluteTimeGetCurrent() - t) * 1000
                        print("[PERF][DicomPixelView] LUT16CPU.ms=\(String(format: "%.3f", dt)) comps=\(srcSamplesPerPixel)")
                    }
                }
            } else {
                let gpuToken = DcmSwiftPerformanceMonitor.shared.startGPUOperation(GPUOperation.windowLevelCompute)
                let gpuSuccess = applyWindowTo16GPU(src16, srcSamples: srcSamplesPerPixel, into: &cachedImageData!)
                DcmSwiftPerformanceMonitor.shared.endGPUOperation(gpuToken, success: gpuSuccess)
                
                if gpuSuccess {
                    if debugLogsEnabled { print("[DicomPixelView] path=16-bit GPU WL") }
                } else {
                    if debugLogsEnabled { print("[DicomPixelView] path=16-bit CPU LUT fallback") }
                    let tL = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0
                    let lut = buildDerivedLUT16(winMin: winMin, winMax: winMax)
                    let tA = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0
                    applyLUTTo16CPU(src16, lut: lut, into: &cachedImageData!, components: srcSamplesPerPixel)
                    if enablePerfMetrics {
                        let dtL = (CFAbsoluteTimeGetCurrent() - tL) * 1000
                        let dtA = (CFAbsoluteTimeGetCurrent() - tA) * 1000
                        print("[PERF][DicomPixelView] LUTgen.ms=\(String(format: "%.3f", dtL)) apply.ms=\(String(format: "%.3f", dtA)) comps=\(srcSamplesPerPixel)")
                    }
                }
            }
        } else {
            // Nothing to do
            return
        }

        cachedImageDataValid = true

        // Build CGImage from the 8-bit buffer.
        guard let cs = colorspace else { return }
        let tCG = enablePerfMetrics ? CFAbsoluteTimeGetCurrent() : 0
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
            let dtCG = (CFAbsoluteTimeGetCurrent() - tCG) * 1000
            print("[PERF][DicomPixelView] CGImageBuild.ms=\(String(format: "%.3f", dtCG))")
        }
        if enablePerfMetrics {
            let dt = CFAbsoluteTimeGetCurrent() - t0
            print("[PERF][DicomPixelView] recomputeImage dt=\(String(format: "%.3f", dt*1000)) ms, spp=\(samplesPerPixel), size=\(imgWidth)x\(imgHeight)")
        }
    }

    // MARK: - 8-bit window/level
    private func applyWindowTo8(_ src: [UInt8], into dst: inout [UInt8]) {
        let numPixels = imgWidth * imgHeight
        guard src.count >= numPixels, dst.count >= numPixels else {
            print("[DicomPixelView] Error: pixel buffers too small. Expected \(numPixels), got src: \(src.count) dst: \(dst.count)")
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
                            let v0 = Int(inBase[i]);    let c0 = min(max(v0 - winMin, 0), denom)
                            let v1 = Int(inBase[i+1]);  let c1 = min(max(v1 - winMin, 0), denom)
                            let v2 = Int(inBase[i+2]);  let c2 = min(max(v2 - winMin, 0), denom)
                            let v3 = Int(inBase[i+3]);  let c3 = min(max(v3 - winMin, 0), denom)
                            var o0 = UInt8(c0 * 255 / denom)
                            var o1 = UInt8(c1 * 255 / denom)
                            var o2 = UInt8(c2 * 255 / denom)
                            var o3 = UInt8(c3 * 255 / denom)
                            if inverted {
                                o0 = 255 &- o0; o1 = 255 &- o1; o2 = 255 &- o2; o3 = 255 &- o3
                            }
                            outBase[i]   = o0
                            outBase[i+1] = o1
                            outBase[i+2] = o2
                            outBase[i+3] = o3
                            i += 4
                        }
                        while i < end {
                            let v = Int(inBase[i])
                            let clamped = min(max(v - winMin, 0), denom)
                            var o = UInt8(clamped * 255 / denom)
                            if inverted { o = 255 &- o }
                            outBase[i] = o
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
                        let v0 = Int(inBuf[i]);    let c0 = min(max(v0 - winMin, 0), denom)
                        let v1 = Int(inBuf[i+1]);  let c1 = min(max(v1 - winMin, 0), denom)
                        let v2 = Int(inBuf[i+2]);  let c2 = min(max(v2 - winMin, 0), denom)
                        let v3 = Int(inBuf[i+3]);  let c3 = min(max(v3 - winMin, 0), denom)
                        var o0 = UInt8(c0 * 255 / denom)
                        var o1 = UInt8(c1 * 255 / denom)
                        var o2 = UInt8(c2 * 255 / denom)
                        var o3 = UInt8(c3 * 255 / denom)
                        if inverted {
                            o0 = 255 &- o0; o1 = 255 &- o1; o2 = 255 &- o2; o3 = 255 &- o3
                        }
                        outBuf[i]   = o0
                        outBuf[i+1] = o1
                        outBuf[i+2] = o2
                        outBuf[i+3] = o3
                        i += 4
                    }
                    while i < numPixels {
                        let v = Int(inBuf[i])
                        let clamped = min(max(v - winMin, 0), denom)
                        var o = UInt8(clamped * 255 / denom)
                        if inverted { o = 255 &- o }
                        outBuf[i] = o
                        i += 1
                    }
                }
            }
        }
    }

    // MARK: - 16-bit window/level

    /// Build a LUT derived from window/level (MONOCHROME2).
    private func buildDerivedLUT16(winMin: Int, winMax: Int) -> [UInt8] {
        let size = 65536
        let denom = max(winMax - winMin, 1)

#if canImport(Accelerate)
        var ramp = [Float](repeating: 0, count: size)
        var start: Float = 0
        var step: Float = 1
        vDSP_vramp(&start, &step, &ramp, 1, vDSP_Length(size))

        var fMin = Float(winMin)
        var fMax = Float(winMax)
        vDSP_vclip(ramp, 1, &fMin, &fMax, &ramp, 1, vDSP_Length(size))

        var negMin = -fMin
        vDSP_vsadd(ramp, 1, &negMin, &ramp, 1, vDSP_Length(size))

        var scale = Float(255) / Float(denom)
        vDSP_vsmul(ramp, 1, &scale, &ramp, 1, vDSP_Length(size))

        var lut = [UInt8](repeating: 0, count: size)
        lut.withUnsafeMutableBufferPointer { ptr in
            vDSP_vfixu8(ramp, 1, ptr.baseAddress!, 1, vDSP_Length(size))
        }
        return lut
#else
        var lut = [UInt8](repeating: 0, count: size)
        for v in 0..<size {
            let c = min(max(v - winMin, 0), denom)
            lut[v] = UInt8(c * 255 / denom)
        }
        return lut
#endif
    }

    private func applyLUTTo16CPU(_ src: [UInt16], lut: [UInt8], into dst: inout [UInt8], components: Int = 1) {
        let numPixels = imgWidth * imgHeight
        let expectedSrc = numPixels * components
        let expectedDst = numPixels * samplesPerPixel
        guard src.count >= expectedSrc, dst.count >= expectedDst, lut.count >= 65536 else {
            print("[DicomPixelView] Error: buffer sizes invalid. Pixels expected \(numPixels), got src \(src.count) dst \(dst.count); LUT \(lut.count)")
            return
        }
        #if canImport(Accelerate)
        if components == 1 {
            var indices = [Float](repeating: 0, count: numPixels)
            src.withUnsafeBufferPointer { inBuf in
                indices.withUnsafeMutableBufferPointer { idxBuf in
                    vDSP_vfltu16(inBuf.baseAddress!, 1, idxBuf.baseAddress!, 1, vDSP_Length(numPixels))
                }
            }
            var lutF = [Float](repeating: 0, count: lut.count)
            lut.withUnsafeBufferPointer { lutBuf in
                lutF.withUnsafeMutableBufferPointer { out in
                    vDSP_vfltu8(lutBuf.baseAddress!, 1, out.baseAddress!, 1, vDSP_Length(lut.count))
                }
            }
            var resultF = [Float](repeating: 0, count: numPixels)
            vDSP_vindex(lutF, indices, 1, &resultF, 1, vDSP_Length(numPixels))
            dst.withUnsafeMutableBufferPointer { out in
                vDSP_vfixu8(resultF, 1, out.baseAddress!, 1, vDSP_Length(numPixels))
                if inverted {
                    var i = 0
                    while i < numPixels { out[i] = 255 &- out[i]; i += 1 }
                }
            }
            return
        }
        #endif

        // Manual LUT application (works for grayscale and multi-channel)
        src.withUnsafeBufferPointer { inBuf in
            lut.withUnsafeBufferPointer { lutBuf in
                dst.withUnsafeMutableBufferPointer { outBuf in
                    for i in 0..<numPixels {
                        let inBase = i * components
                        let outBase = i * samplesPerPixel
                        for c in 0..<components {
                            let v = lutBuf[Int(inBuf[inBase + c])]
                            outBuf[outBase + c] = inverted ? (255 &- v) : v
                        }
                        if components < samplesPerPixel {
                            outBuf[outBase + 3] = 255
                        }
                    }
                }
            }
        }
    }

    private func applyWindowTo8GPU(_ src: [UInt8], into dst: inout [UInt8]) -> Bool {
#if canImport(Metal)
        let accel = MetalAccelerator.shared
        guard accel.isAvailable else { return false }
        let numPixels = imgWidth * imgHeight
        // Widen 8-bit input to 16-bit temporary buffer to reuse the same shader
        var temp16 = [UInt16](repeating: 0, count: numPixels)
        let limit = min(src.count, numPixels)
        var i = 0
        while i < limit { temp16[i] = UInt16(src[i]); i += 1 }
        return dst.withUnsafeMutableBufferPointer { outBuf in
            temp16.withUnsafeBufferPointer { inBuf in
                processPixelsGPU(inputPixels: inBuf.baseAddress!,
                                  outputPixels: outBuf.baseAddress!,
                                  pixelCount: numPixels,
                                  winMin: winMin,
                                  winMax: winMax,
                                  inComponents: 1)
            }
        }
#else
        return false
#endif
    }


    private func applyWindowTo16GPU(_ src: [UInt16], srcSamples: Int, into dst: inout [UInt8]) -> Bool {
        let numPixels = imgWidth * imgHeight
        return dst.withUnsafeMutableBufferPointer { outBuf in
            src.withUnsafeBufferPointer { inBuf in
                processPixelsGPU(inputPixels: inBuf.baseAddress!,
                                 outputPixels: outBuf.baseAddress!,
                                 pixelCount: numPixels,
                                 winMin: winMin,
                                 winMax: winMax,
                                 inComponents: srcSamples)
            }
        }
    }
    
    private func applyLUTTo16GPU(_ src: [UInt16], lut: [UInt8], into dst: inout [UInt8], components: Int = 1) -> Bool {
#if canImport(Metal)
        let accel = MetalAccelerator.shared
        guard let pso = accel.voiLUTPipelineState, let queue = accel.commandQueue else { return false }
        let numPixels = imgWidth * imgHeight
        let inLen = numPixels * components * MemoryLayout<UInt16>.stride
        let outLen = numPixels * samplesPerPixel * MemoryLayout<UInt8>.stride
        // Expect a 65536-entry 8-bit LUT
        guard lut.count >= 65536 else { return false }
        let cache = MetalBufferCache.shared
        guard let inBuf = cache.buffer(length: inLen),
              let outBuf = cache.buffer(length: outLen),
              let lutBuf = cache.buffer(length: 65536) else { return false }
        src.withUnsafeBytes { memcpy(inBuf.contents(), $0.baseAddress!, inLen) }
        lut.withUnsafeBytes { memcpy(lutBuf.contents(), $0.baseAddress!, 65536) }
        var uCount = UInt32(numPixels)
        var invert: Bool = self.inverted
        var uComp = UInt32(components)
        var uOutComp = UInt32(samplesPerPixel)
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return false }
        enc.setComputePipelineState(pso)
        enc.setBuffer(inBuf, offset: 0, index: 0)
        enc.setBuffer(lutBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        enc.setBytes(&uCount, length: MemoryLayout<UInt32>.stride, index: 3)
        enc.setBytes(&invert, length: MemoryLayout<Bool>.stride, index: 4)
        enc.setBytes(&uComp, length: MemoryLayout<UInt32>.stride, index: 5)
        enc.setBytes(&uOutComp, length: MemoryLayout<UInt32>.stride, index: 6)
        let w = min(pso.threadExecutionWidth, pso.maxTotalThreadsPerThreadgroup)
        let threadsPerThreadgroup = MTLSize(width: w, height: 1, depth: 1)
        let groups = MTLSize(width: (numPixels + w - 1) / w, height: 1, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerThreadgroup)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        dst.withUnsafeMutableBytes { memcpy($0.baseAddress!, outBuf.contents(), outLen) }
        cache.recycle(inBuf)
        cache.recycle(outBuf)
        cache.recycle(lutBuf)
        return true
#else
        return false
#endif
    }
    // --- END CONFLICT RESOLUTION ---

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
    }

    // MARK: - Rendered image accessors

    /// Return the currently rendered CGImage (if available).
    public func currentCGImage() -> CGImage? { bitmapImage }

    /// Present a pre-rendered CGImage directly, skipping window/level computation.
    /// - Parameters:
    ///   - image: The CGImage to display.
    ///   - samplesPerPixel: 1 for grayscale, 4 for RGBA.
    public func setRenderedCGImage(_ image: CGImage, samplesPerPixel: Int) {
        self.samplesPerPixel = samplesPerPixel
        self.colorspace = (samplesPerPixel == 1) ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        self.lastSamplesPerPixel = samplesPerPixel
        self.lastContextWidth = image.width
        self.lastContextHeight = image.height
        self.bitmapContext = nil
        self.bitmapImage = image
        self.cachedImageDataValid = true
        setNeedsDisplay()
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
                                  winMax: Int,
                                  inComponents: Int) -> Bool {
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

        let inLen = pixelCount * inComponents * MemoryLayout<UInt16>.stride
        let outLen = pixelCount * samplesPerPixel * MemoryLayout<UInt8>.stride

        let cache = MetalBufferCache.shared
        guard let inBuf = cache.buffer(length: inLen),
              let outBuf = cache.buffer(length: outLen) else { return false }
        memcpy(inBuf.contents(), inputPixels, inLen)

        var uCount = UInt32(pixelCount)
        var sWinMin = Int32(winMin)
        var uDenom = UInt32(width)
        var invert: Bool = self.inverted
        var uComp = UInt32(inComponents)
        var uOutComp = UInt32(samplesPerPixel)

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return false }

        enc.setComputePipelineState(pso)
        enc.setBuffer(inBuf, offset: 0, index: 0)
        enc.setBuffer(outBuf, offset: 0, index: 1)
        
        // Using the more efficient setBytes and the more modern dispatchThreads API
        enc.setBytes(&uCount, length: MemoryLayout<UInt32>.stride, index: 2)
        enc.setBytes(&sWinMin, length: MemoryLayout<Int32>.stride, index: 3)
        enc.setBytes(&uDenom, length: MemoryLayout<UInt32>.stride, index: 4)
        enc.setBytes(&invert, length: MemoryLayout<Bool>.stride, index: 5)
        enc.setBytes(&uComp, length: MemoryLayout<UInt32>.stride, index: 6)
        enc.setBytes(&uOutComp, length: MemoryLayout<UInt32>.stride, index: 7)

        let w = min(pso.threadExecutionWidth, pso.maxTotalThreadsPerThreadgroup)
        let threadsPerThreadgroup = MTLSize(width: w, height: 1, depth: 1)
        // Compute threadgroup count to avoid non-uniform threadgroups on devices that don't support it
        let groups = MTLSize(width: (pixelCount + w - 1) / w, height: 1, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerThreadgroup)
        
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()

        memcpy(outputPixels, outBuf.contents(), outLen)
        cache.recycle(inBuf)
        cache.recycle(outBuf)

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
