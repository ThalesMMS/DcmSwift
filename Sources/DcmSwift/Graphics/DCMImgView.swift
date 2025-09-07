#if canImport(UIKit)
import UIKit
import CoreGraphics
import Foundation

public final class DCMImgView: UIView {
    // MARK: - Image State
    private var pix16: [UInt16]? = nil
    private var lut16: [UInt8]? = nil
    private var imgWidth: Int = 0
    private var imgHeight: Int = 0
    private var winMin: Int = 0
    private var winMax: Int = 65535

    private var colorspace: CGColorSpace?
    private var bitmapContext: CGContext?
    private var bitmapImage: CGImage?

    private var cachedImageData: [UInt8]?
    private var cachedImageDataValid = false

    private var lastContextWidth: Int = 0
    private var lastContextHeight: Int = 0
    private var lastSamplesPerPixel: Int = 0

    // MARK: - Context Helpers
    private func shouldReuseContext(width: Int, height: Int, samples: Int) -> Bool {
        return width == lastContextWidth && height == lastContextHeight && samples == lastSamplesPerPixel
    }

    private func resetImage() {
        bitmapContext = nil
        bitmapImage = nil
    }

    // MARK: - GPU Stub
    private func processPixelsGPU(inputPixels: UnsafePointer<UInt16>,
                                  outputPixels: UnsafeMutablePointer<UInt8>,
                                  pixelCount: Int,
                                  winMin: Int,
                                  winMax: Int) -> Bool {
        // GPU processing not available in this build.
        return false
    }

    /// Creates a CGImage from the 16-bit grayscale pixel buffer
    /// This version detects large images and processes them in
    /// parallel chunks when GPU processing is unavailable.
    public func createImage16() {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let pix = pix16, let lut = lut16 else { return }
        let numPixels = imgWidth * imgHeight

        guard pix.count >= numPixels else {
            print("[DCMImgView] Error: pixel array too small. Expected \(numPixels), got \(pix.count)")
            return
        }

        var imageData = [UInt8](repeating: 0, count: numPixels)

        let gpuSuccess = imageData.withUnsafeMutableBufferPointer { imageBuffer in
            pix.withUnsafeBufferPointer { pixBuffer in
                processPixelsGPU(inputPixels: pixBuffer.baseAddress!,
                                  outputPixels: imageBuffer.baseAddress!,
                                  pixelCount: numPixels,
                                  winMin: winMin,
                                  winMax: winMax)
            }
        }

        if !gpuSuccess {
            if numPixels > 2_000_000 {
                let threads = ProcessInfo.processInfo.activeProcessorCount
                let chunkSize = numPixels / threads
                pix.withUnsafeBufferPointer { pixBuffer in
                    lut.withUnsafeBufferPointer { lutBuffer in
                        imageData.withUnsafeMutableBufferPointer { imageBuffer in
                            let pixBase = pixBuffer.baseAddress!
                            let lutBase = lutBuffer.baseAddress!
                            let imageBase = imageBuffer.baseAddress!
                            DispatchQueue.concurrentPerform(iterations: threads) { chunk in
                                let start = chunk * chunkSize
                                let end = (chunk == threads - 1) ? numPixels : start + chunkSize
                                var i = start
                                while i < end - 3 {
                                    imageBase[i] = lutBase[Int(pixBase[i])]
                                    imageBase[i+1] = lutBase[Int(pixBase[i+1])]
                                    imageBase[i+2] = lutBase[Int(pixBase[i+2])]
                                    imageBase[i+3] = lutBase[Int(pixBase[i+3])]
                                    i += 4
                                }
                                while i < end {
                                    imageBase[i] = lutBase[Int(pixBase[i])]
                                    i += 1
                                }
                            }
                        }
                    }
                }
            } else {
                pix.withUnsafeBufferPointer { pixBuffer in
                    lut.withUnsafeBufferPointer { lutBuffer in
                        imageData.withUnsafeMutableBufferPointer { imageBuffer in
                            var i = 0
                            let end = numPixels - 3
                            while i < end {
                                imageBuffer[i] = lutBuffer[Int(pixBuffer[i])]
                                imageBuffer[i+1] = lutBuffer[Int(pixBuffer[i+1])]
                                imageBuffer[i+2] = lutBuffer[Int(pixBuffer[i+2])]
                                imageBuffer[i+3] = lutBuffer[Int(pixBuffer[i+3])]
                                i += 4
                            }
                            while i < numPixels {
                                imageBuffer[i] = lutBuffer[Int(pixBuffer[i])]
                                i += 1
                            }
                        }
                    }
                }
            }
        }

        cachedImageData = imageData
        cachedImageDataValid = true

        if !shouldReuseContext(width: imgWidth, height: imgHeight, samples: 1) {
            resetImage()
            colorspace = CGColorSpaceCreateDeviceGray()
            lastContextWidth = imgWidth
            lastContextHeight = imgHeight
            lastSamplesPerPixel = 1
        }

        imageData.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            let ctx = CGContext(data: ptr,
                                width: imgWidth,
                                height: imgHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: imgWidth,
                                space: colorspace!,
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            bitmapContext = ctx
            bitmapImage = ctx?.makeImage()
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] createImage16: \(String(format: "%.2f", elapsed))ms | pixels: \(numPixels)")
    }
}
#endif

