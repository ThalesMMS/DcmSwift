#if canImport(UIKit)
import UIKit
import CoreGraphics

/// A lightweight view for displaying DICOM pixel buffers.
///
/// The implementation focuses on efficient redraws.  Processed
/// pixel data are cached so that repeated window/level operations
/// can reuse previously computed bytes.  Additionally the underlying
/// CGContext is reused when the image dimensions and samples per
/// pixel are unchanged, avoiding expensive reallocations.
public final class DCMImgView: UIView {
    // MARK: - Pixel buffers
    private var pix8: [UInt8]? = nil
    private var pix16: [UInt16]? = nil
    private var imgWidth: Int = 0
    private var imgHeight: Int = 0

    // MARK: - Window/level
    public var winCenter: Int = 0 { didSet { updateWindowLevel() } }
    public var winWidth: Int = 0 { didSet { updateWindowLevel() } }
    private var winMin: Int = 0
    private var winMax: Int = 0
    private var lastWinMin: Int = -1
    private var lastWinMax: Int = -1

    // MARK: - Caching
    /// Cached 8-bit image data after window/level processing
    private var cachedImageData: [UInt8]? = nil
    private var cachedImageValid: Bool = false

    // Track context characteristics for reuse
    private var lastContextWidth: Int = 0
    private var lastContextHeight: Int = 0
    private var lastSamplesPerPixel: Int = 0

    private var bitmapContext: CGContext? = nil
    private var bitmapImage: CGImage? = nil
    public var samplesPerPixel: Int = 1

    // MARK: - Public API
    /// Assign 8-bit pixels
    public func setPixels8(_ pixels: [UInt8], width: Int, height: Int,
                           windowWidth: Int, windowCenter: Int) {
        pix8 = pixels
        pix16 = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        winWidth = windowWidth
        winCenter = windowCenter
        cachedImageValid = false
        updateWindowLevel()
    }

    /// Assign 16-bit pixels
    public func setPixels16(_ pixels: [UInt16], width: Int, height: Int,
                            windowWidth: Int, windowCenter: Int) {
        pix16 = pixels
        pix8 = nil
        imgWidth = width
        imgHeight = height
        samplesPerPixel = 1
        winWidth = windowWidth
        winCenter = windowCenter
        cachedImageValid = false
        updateWindowLevel()
    }

    // MARK: - Drawing
    public override func draw(_ rect: CGRect) {
        guard let image = bitmapImage,
              let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }

    // MARK: - Window/Level
    private func updateWindowLevel() {
        let newMin = winCenter - winWidth / 2
        let newMax = winCenter + winWidth / 2

        // If window has not changed, reuse existing image data
        if newMin == lastWinMin && newMax == lastWinMax {
            setNeedsDisplay()
            return
        }

        winMin = newMin
        winMax = newMax
        lastWinMin = newMin
        lastWinMax = newMax
        cachedImageValid = false
        recomputeImage()
        setNeedsDisplay()
    }

    // MARK: - Image construction
    private func recomputeImage() {
        guard imgWidth > 0, imgHeight > 0 else { return }
        guard let ctx = createContext(width: imgWidth, height: imgHeight, samples: samplesPerPixel) else { return }
        let pixelCount = imgWidth * imgHeight
        if cachedImageData == nil || cachedImageData!.count != pixelCount * samplesPerPixel {
            cachedImageData = Array(repeating: 0, count: pixelCount * samplesPerPixel)
        }

        if let src = pix8 {
            for i in 0..<pixelCount {
                let v = Int(src[i])
                let clamped = min(max(v - winMin, 0), max(winMax - winMin, 1))
                cachedImageData![i] = UInt8(clamped * 255 / max(winMax - winMin, 1))
            }
        } else if let src16 = pix16 {
            for i in 0..<pixelCount {
                let v = Int(src16[i])
                let clamped = min(max(v - winMin, 0), max(winMax - winMin, 1))
                cachedImageData![i] = UInt8(clamped * 255 / max(winMax - winMin, 1))
            }
        }

        cachedImageDataValid = true
        if let dest = ctx.data, let data = cachedImageData {
            data.withUnsafeBytes { buffer in
                if let base = buffer.baseAddress {
                    memcpy(dest, base, buffer.count)
                }
            }
        }
        bitmapImage = ctx.makeImage()
    }

    /// Create or reuse an existing bitmap context.
    private func createContext(width: Int, height: Int, samples: Int) -> CGContext? {
        if let ctx = bitmapContext,
           width == lastContextWidth,
           height == lastContextHeight,
           samples == lastSamplesPerPixel {
            return ctx
        }
        let colorSpace: CGColorSpace = (samples == 1) ? CGColorSpaceCreateDeviceGray()
                                                      : CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * samples
        bitmapContext = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: samples == 1 ? CGImageAlphaInfo.none.rawValue
                                                           : CGImageAlphaInfo.noneSkipLast.rawValue)
        lastContextWidth = width
        lastContextHeight = height
        lastSamplesPerPixel = samples
        return bitmapContext
    }
}
#endif
