//
//  DCMImgView.swift
//
//  This UIView
//  subclass renders DICOM images stored as raw pixel buffers.
//  It supports 8‑bit and 16‑bit grayscale images as well as
//  24‑bit RGB images.  Window/level adjustments are applied
//  through lookup tables; clients can modify the window centre
//  and width via the corresponding properties and call
//  ``updateWindowLevel()`` to refresh the display.  The view
//  automatically scales the image to fit while preserving its
//  aspect ratio.
//

public import UIKit
import Metal
import MetalKit

// MARK: - DICOM 2D View Class

/// A UIView for displaying 2D DICOM images.  The view is agnostic
/// of how the pixel data were loaded; clients must supply raw
/// buffers via ``setPixels8`` or ``setPixels16``.  Internally the
/// view constructs a CGImage on demand and draws it within its
/// bounds, preserving aspect ratio.  No rotation or flipping is
/// applied; if your images require orientation correction you
/// should perform that prior to assigning the pixels.
public final class DCMImgView: UIView {
    
    // MARK: - Properties
    
    // MARK: Image Parameters
    /// Horizontal and vertical offsets used for panning.  Not
    /// currently exposed publicly but retained for completeness.
    private var hOffset: Int = 0
    private var vOffset: Int = 0
    private var hMax: Int = 0
    private var vMax: Int = 0
    private var imgWidth: Int = 0
    private var imgHeight: Int = 0
    private var panWidth: Int = 0
    private var panHeight: Int = 0
    private var newImage: Bool = false
    /// Windowing parameters used to map pixel intensities to 0–255.
    private var winMin: Int = 0
    private var winMax: Int = 65535
    /// Cache for window/level to avoid recomputation
    private var lastWinMin: Int = -1
    private var lastWinMax: Int = -1
    /// Cache the processed image data to avoid recreating CGImage
    private var cachedImageData: [UInt8]?
    private var cachedImageDataValid: Bool = false
    
    /// Window center value for DICOM windowing
    var winCenter: Int = 0 {
        didSet { updateWindowLevel() }
    }
    
    /// Window width value for DICOM windowing
    var winWidth: Int = 0 {
        didSet { updateWindowLevel() }
    }
    /// Factors controlling how rapidly mouse drags affect the
    /// window/level.  Not used directly in this class but provided
    /// for compatibility with the Objective‑C version.
    /// Factor controlling window width sensitivity
    var changeValWidth: Double = 0.5
    
    /// Factor controlling window center sensitivity
    var changeValCentre: Double = 0.5
    /// Whether the underlying 16‑bit pixel data were originally
    /// signed.  If true the centre is adjusted by the minimum
    /// possible Int16 before calculating the window range.
    /// Whether the underlying 16-bit pixel data were originally signed
    var signed16Image: Bool = false {
        didSet { updateWindowLevel() }
    }
    
    /// Number of samples per pixel; 1 for grayscale, 3 for RGB
    var samplesPerPixel: Int = 1
    
    /// Indicates whether a pixel buffer has been provided
    private var imageAvailable: Bool = false
    // MARK: Data Storage
    
    /// 8-bit pixel buffer for grayscale images
    private var pix8: [UInt8]? = nil
    
    /// 16-bit pixel buffer for high-depth grayscale images
    private var pix16: [UInt16]? = nil
    
    /// 24-bit pixel buffer for RGB color images
    private var pix24: [UInt8]? = nil
    
    // MARK: Lookup Tables
    
    /// 8-bit lookup table for intensity mapping
    private var lut8: [UInt8]? = nil
    
    /// 16-bit lookup table for intensity mapping
    private var lut16: [UInt8]? = nil
    
    // MARK: Graphics Resources
    
    /// Core Graphics color space for image rendering
    private var colorspace: CGColorSpace?
    
    /// Core Graphics bitmap context
    private var bitmapContext: CGContext?
    
    /// Final CGImage for display
    private var bitmapImage: CGImage?
    
    // OPTIMIZATION: Context reuse tracking
    private var lastContextWidth: Int = 0
    private var lastContextHeight: Int = 0
    private var lastSamplesPerPixel: Int = 0
    
    // OPTIMIZATION: GPU-accelerated processing
    private static let metalDevice = MTLCreateSystemDefaultDevice()
    private static var metalCommandQueue: MTLCommandQueue?
    private static var windowLevelComputeShader: MTLComputePipelineState?
    
    // Setup Metal on first use
    private static let setupMetalOnce: Void = {
        setupMetal()
    }()
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Initialise default window parameters
        winMin = 0
        winMax = 65535
        changeValWidth = 0.5
        changeValCentre = 0.5
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        winMin = 0
        winMax = 65535
        changeValWidth = 0.5
        changeValCentre = 0.5
    }
    // MARK: - UIView Overrides
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let image = bitmapImage else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        let height = rect.size.height
        // Flip the coordinate system vertically to match CGImage origin
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -height)
        // Compute aspect‑fit rectangle
        let imageAspect = CGFloat(imgWidth) / CGFloat(imgHeight)
        let viewAspect = rect.size.width / rect.size.height
        var drawRect = CGRect(origin: .zero, size: .zero)
        if imageAspect > viewAspect {
            // Fit to width
            drawRect.size.width = rect.size.width
            drawRect.size.height = rect.size.width / imageAspect
            drawRect.origin.x = rect.origin.x
            drawRect.origin.y = rect.origin.y + (rect.size.height - drawRect.size.height) / 2.0
        } else {
            // Fit to height
            drawRect.size.height = rect.size.height
            drawRect.size.width = rect.size.height * imageAspect
            drawRect.origin.x = rect.origin.x + (rect.size.width - drawRect.size.width) / 2.0
            drawRect.origin.y = rect.origin.y
        }
        context.draw(image, in: drawRect)
        context.restoreGState()
    }
    // MARK: - Window/Level Operations
    /// Recalculates the window range from the current center and width
    public func resetValues() {
        winMax = winCenter + Int(Double(winWidth) * 0.5)
        winMin = winMax - winWidth
    }
    /// Frees previously created images and contexts
    private func resetImage() {
        colorspace = nil
        bitmapImage = nil
        bitmapContext = nil
        // Reset context tracking
        lastContextWidth = 0
        lastContextHeight = 0
        lastSamplesPerPixel = 0
    }
    
    /// Smart context reuse - only recreate when dimensions or format changes
    private func shouldReuseContext(width: Int, height: Int, samples: Int) -> Bool {
        return bitmapContext != nil && 
               lastContextWidth == width && 
               lastContextHeight == height && 
               lastSamplesPerPixel == samples
    }
    // MARK: - Lookup Table Generation
    
    /// Generates an 8-bit lookup table mapping original pixel values
    /// into 0–255 based on the current window
    public func computeLookUpTable8() {
        let startTime = CFAbsoluteTimeGetCurrent()
        if lut8 == nil { lut8 = Array(repeating: 0, count: 256) }
        let maxVal = winMax == 0 ? 255 : winMax
        var range = maxVal - winMin
        if range < 1 { range = 1 }
        let factor = 255.0 / Double(range)
        for i in 0..<256 {
            if i <= winMin {
                lut8?[i] = 0
            } else if i >= maxVal {
                lut8?[i] = 255
            } else {
                let value = Double(i - winMin) * factor
                lut8?[i] = UInt8(max(0.0, min(255.0, value)))
            }
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] computeLookUpTable8: \(String(format: "%.2f", elapsed))ms")
    }
    /// Generates a 16-bit lookup table mapping original pixel values
    /// into 0–255 with optimized memory operations
    public func computeLookUpTable16() {
        let startTime = CFAbsoluteTimeGetCurrent()
        if lut16 == nil { lut16 = Array(repeating: 0, count: 65536) }
        guard var lut = lut16 else { return }
        
        let maxVal = winMax == 0 ? 65535 : winMax
        var range = maxVal - winMin
        if range < 1 { range = 1 }
        let factor = 255.0 / Double(range)
        
        // ULTRA OPTIMIZATION for narrow windows (like CT)
        // Only compute the exact range needed
        let minIndex = max(0, winMin)
        let maxIndex = min(65535, maxVal)
        
        // Use memset for bulk operations - much faster than loops
        lut.withUnsafeMutableBufferPointer { buffer in
            // Fill everything below window with 0
            if minIndex > 0 {
                memset(buffer.baseAddress!, 0, minIndex)
            }
            
            // Fill everything above window with 255
            if maxIndex < 65535 {
                memset(buffer.baseAddress!.advanced(by: maxIndex + 1), 255, 65535 - maxIndex)
            }
            
            // Compute only the window range (ensure valid range)
            if minIndex <= maxIndex {
                for i in minIndex...maxIndex {
                    let value = Double(i - winMin) * factor
                    buffer[i] = UInt8(max(0.0, min(255.0, value)))
                }
            } else {
                // Invalid window range - use default linear mapping
                print("⚠️ [DCMImgView] Invalid window range: min=\(minIndex) > max=\(maxIndex), using default")
                for i in 0..<65536 {
                    buffer[i] = UInt8((i >> 8) & 0xFF) // Simple 16-to-8 bit reduction
                }
            }
        }
        
        lut16 = lut
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] computeLookUpTable16: \(String(format: "%.2f", elapsed))ms | computed: \(maxIndex - minIndex + 1) values")
    }
    // MARK: - Image Creation Methods
    
    /// Creates a CGImage from the 8-bit grayscale pixel buffer
    public func createImage8() {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let pix = pix8 else { return }
        let numPixels = imgWidth * imgHeight
        var imageData = [UInt8](repeating: 0, count: numPixels)
        for i in 0..<imgHeight {
            let rowStart = i * imgWidth
            for j in 0..<imgWidth {
                let original = Int(pix[rowStart + j])
                imageData[rowStart + j] = lut8?[original] ?? 0
            }
        }
        // OPTIMIZATION: Reuse context if dimensions match
        if !shouldReuseContext(width: imgWidth, height: imgHeight, samples: 1) {
            resetImage()
            colorspace = CGColorSpaceCreateDeviceGray()
            lastContextWidth = imgWidth
            lastContextHeight = imgHeight
            lastSamplesPerPixel = 1
        }
        
        // Create a bitmap context using our imageData.  We use
        // `.none` alpha since grayscale images have no alpha channel.
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
        print("[PERF] createImage8: \(String(format: "%.2f", elapsed))ms")
    }
    /// Creates a CGImage from the 16-bit grayscale pixel buffer
    /// Uses ultra-optimized processing for maximum performance
    public func createImage16() {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let pix = pix16 else { return }
        guard let lut = lut16 else { return }
        let numPixels = imgWidth * imgHeight
        
        // Validate pixel array size
        guard pix.count >= numPixels else {
            print("[DCMImgView] Error: pixel array too small. Expected \(numPixels), got \(pix.count)")
            return
        }
        
        var imageData = [UInt8](repeating: 0, count: numPixels)
        
        // OPTIMIZATION: Try GPU acceleration first, then fall back to CPU
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
            // GPU fallback - use optimized CPU processing
            // Use parallel processing only for very large images
            if numPixels > 2000000 {  // Only for huge X-ray images (>1400x1400)
                // Use concurrent processing for very large images
                let chunkSize = numPixels / 4  // Process in 4 chunks
            
            // Swift 6 concurrency-safe buffer access
            // Create local copies of buffer base addresses for concurrent access
            pix.withUnsafeBufferPointer { pixBuffer in
                lut.withUnsafeBufferPointer { lutBuffer in
                    imageData.withUnsafeMutableBufferPointer { imageBuffer in
                        // Get raw pointers that are safe to pass to concurrent code
                        let pixBase = pixBuffer.baseAddress!
                        let lutBase = lutBuffer.baseAddress!
                        let imageBase = imageBuffer.baseAddress!
                        
                        // Use nonisolated(unsafe) to explicitly handle raw pointers in concurrent code
                        // This is safe because we're only reading from pixBase/lutBase and writing to non-overlapping regions of imageBase
                        nonisolated(unsafe) let unsafePixBase = pixBase
                        nonisolated(unsafe) let unsafeLutBase = lutBase
                        nonisolated(unsafe) let unsafeImageBase = imageBase
                        
                        DispatchQueue.concurrentPerform(iterations: 4) { chunk in
                            let start = chunk * chunkSize
                            let end = (chunk == 3) ? numPixels : start + chunkSize
                            
                            // Use raw pointers for concurrent access
                            var i = start
                            while i < end - 3 {
                                unsafeImageBase[i] = unsafeLutBase[Int(unsafePixBase[i])]
                                unsafeImageBase[i+1] = unsafeLutBase[Int(unsafePixBase[i+1])]
                                unsafeImageBase[i+2] = unsafeLutBase[Int(unsafePixBase[i+2])]
                                unsafeImageBase[i+3] = unsafeLutBase[Int(unsafePixBase[i+3])]
                                i += 4
                            }
                            // Handle remaining pixels
                            while i < end {
                                unsafeImageBase[i] = unsafeLutBase[Int(unsafePixBase[i])]
                                i += 1
                            }
                        }
                    }
                }
            }
        } else {
            // Use optimized single-threaded processing for CT and smaller images
            pix.withUnsafeBufferPointer { pixBuffer in
                lut.withUnsafeBufferPointer { lutBuffer in
                    imageData.withUnsafeMutableBufferPointer { imageBuffer in
                        // Process with loop unrolling for better performance
                        var i = 0
                        let end = numPixels - 3
                        
                        // Process 4 pixels at a time
                        while i < end {
                            imageBuffer[i] = lutBuffer[Int(pixBuffer[i])]
                            imageBuffer[i+1] = lutBuffer[Int(pixBuffer[i+1])]
                            imageBuffer[i+2] = lutBuffer[Int(pixBuffer[i+2])]
                            imageBuffer[i+3] = lutBuffer[Int(pixBuffer[i+3])]
                            i += 4
                        }
                        
                        // Handle remaining pixels
                        while i < numPixels {
                            imageBuffer[i] = lutBuffer[Int(pixBuffer[i])]
                            i += 1
                        }
                    }
                }
            }
            } // End CPU fallback block
        }
        
        // Cache the processed image data
        cachedImageData = imageData
        cachedImageDataValid = true
        
        // OPTIMIZATION: Reuse context if dimensions match
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
    /// Creates a CGImage from the 24-bit RGB pixel buffer
    /// Handles BGR to RGB conversion with proper color mapping
    public func createImage24() {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let pix = pix24 else { return }
        let numBytes = imgWidth * imgHeight * 4
        var imageData = [UInt8](repeating: 0, count: numBytes)
        let width4 = imgWidth * 4
        let width3 = imgWidth * 3
        for i in 0..<imgHeight {
            let srcRow = i * width3
            let dstRow = i * width4
            for j in stride(from: 0, to: width4, by: 4) {
                let m = (j / 4) * 3
                // In CoreGraphics the order is BGRA (little endian)
                imageData[dstRow + j + 3] = 0 // alpha
                let blue = Int(pix[srcRow + m])
                let green = Int(pix[srcRow + m + 1])
                let red = Int(pix[srcRow + m + 2])
                imageData[dstRow + j + 2] = lut8?[blue] ?? UInt8(blue)
                imageData[dstRow + j + 1] = lut8?[green] ?? UInt8(green)
                imageData[dstRow + j]     = lut8?[red] ?? UInt8(red)
            }
        }
        // OPTIMIZATION: Reuse context if dimensions match  
        if !shouldReuseContext(width: imgWidth, height: imgHeight, samples: 3) {
            resetImage()
            colorspace = CGColorSpaceCreateDeviceRGB()
            lastContextWidth = imgWidth
            lastContextHeight = imgHeight
            lastSamplesPerPixel = 3
        }
        
        imageData.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            let ctx = CGContext(data: ptr,
                                width: imgWidth,
                                height: imgHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: width4,
                                space: colorspace!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            bitmapContext = ctx
            bitmapImage = ctx?.makeImage()
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] createImage24: \(String(format: "%.2f", elapsed))ms")
    }
    /// Updates the lookup tables and refreshes the displayed image
    /// Optimized to avoid unnecessary recomputations
    func updateWindowLevel() {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard imageAvailable else { return }
        resetValues()
        
        // Check if window values have actually changed
        let windowChanged = (winMin != lastWinMin || winMax != lastWinMax)
        
        if windowChanged {
            // Invalidate image cache when window changes
            cachedImageDataValid = false
            
            // Only recompute LUT if window has changed
            if pix16 != nil {
                computeLookUpTable16()
                createImage16()
            } else if pix24 != nil {
                computeLookUpTable8()
                createImage24()
            } else if pix8 != nil {
                computeLookUpTable8()
                createImage8()
            }
            
            // Update cache
            lastWinMin = winMin
            lastWinMax = winMax
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[PERF] updateWindowLevel (recomputed): \(String(format: "%.2f", elapsed))ms")
        } else {
            // Window hasn't changed, just redraw existing image
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[PERF] updateWindowLevel (cached): \(String(format: "%.2f", elapsed))ms")
        }
        
        setNeedsDisplay()
    }
    // MARK: - Pixel Data Assignment
    /// Assigns an 8-bit pixel buffer and computes the initial lookup table and image
    func setPixels8(_ pixel: [UInt8], width: Int, height: Int,
                    windowWidth winW: Double, windowCenter winC: Double,
                    samplesPerPixel spp: Int, resetScroll: Bool = true) {
        samplesPerPixel = spp
        imgWidth = width
        imgHeight = height
        winWidth = Int(winW)
        winCenter = Int(winC)
        changeValWidth = 0.1
        changeValCentre = 0.1
        if spp == 1 {
            pix8 = pixel
            pix24 = nil
            pix16 = nil
            imageAvailable = true
            resetValues()
            computeLookUpTable8()
            createImage8()
        } else if spp == 3 {
            pix24 = pixel
            pix8 = nil
            pix16 = nil
            imageAvailable = true
            resetValues()
            computeLookUpTable8()
            createImage24()
        }
        setNeedsDisplay()
    }
    /// Assigns a 16-bit pixel buffer with optimized processing
    /// Automatically adjusts sensitivity based on window characteristics
    func setPixels16(_ pixel: [UInt16], width: Int, height: Int,
                     windowWidth winW: Double, windowCenter winC: Double,
                     samplesPerPixel spp: Int, resetScroll: Bool = true) {
        let startTime = CFAbsoluteTimeGetCurrent()
        samplesPerPixel = spp
        imgWidth = width
        imgHeight = height
        winWidth = Int(winW)
        winCenter = Int(winC)
        // Adjust window centre for signed data
        if signed16Image {
            winCenter -= Int(Int16.min)
        }
        // Adjust sensitivity based on window width
        if winWidth < 5000 {
            changeValWidth = 2
            changeValCentre = 2
        } else if winWidth > 40000 {
            changeValWidth = 50
            changeValCentre = 50
        } else {
            changeValWidth = 25
            changeValCentre = 25
        }
        pix16 = pixel
        pix8 = nil
        pix24 = nil
        imageAvailable = true
        cachedImageDataValid = false  // Invalidate cache on new image
        resetValues()
        computeLookUpTable16()
        createImage16()
        setNeedsDisplay()
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] setPixels16 total: \(String(format: "%.2f", elapsed))ms | size: \(width)x\(height)")
    }
    // MARK: - Public Interface
    
    /// Returns a UIImage constructed from the current CGImage
    func dicomImage() -> UIImage? {
        guard let cgImage = bitmapImage else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - DCMImgView Metal GPU Acceleration

extension DCMImgView {
    
    /// Setup Metal GPU acceleration for window/level processing
    private static func setupMetal() {
        guard let device = metalDevice else {
            print("[DCMImgView] Metal device not available, using CPU fallback")
            return
        }
        
        metalCommandQueue = device.makeCommandQueue()
        
        // Create Metal compute shader for window/level processing
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        kernel void windowLevelKernel(const device uint16_t* inputPixels [[buffer(0)]],
                                      device uint8_t* outputPixels [[buffer(1)]],
                                      constant int& winMin [[buffer(2)]],
                                      constant int& winMax [[buffer(3)]],
                                      constant uint& pixelCount [[buffer(4)]],
                                      uint index [[thread_position_in_grid]]) {
            if (index >= pixelCount) return;
            
            uint16_t pixel = inputPixels[index];
            uint8_t result;
            
            if (pixel <= winMin) {
                result = 0;
            } else if (pixel >= winMax) {
                result = 255;
            } else {
                int range = winMax - winMin;
                if (range < 1) range = 1;
                float factor = 255.0 / float(range);
                float value = float(pixel - winMin) * factor;
                result = uint8_t(clamp(value, 0.0f, 255.0f));
            }
            
            outputPixels[index] = result;
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let kernelFunction = library.makeFunction(name: "windowLevelKernel")!
            windowLevelComputeShader = try device.makeComputePipelineState(function: kernelFunction)
            print("[DCMImgView] Metal GPU acceleration initialized successfully")
        } catch {
            print("[DCMImgView] Metal shader compilation failed: \(error), using CPU fallback")
        }
    }
    
    /// GPU-accelerated 16-bit to 8-bit window/level conversion
    private func processPixelsGPU(inputPixels: UnsafePointer<UInt16>, 
                                  outputPixels: UnsafeMutablePointer<UInt8>, 
                                  pixelCount: Int,
                                  winMin: Int, 
                                  winMax: Int) -> Bool {
        // Ensure Metal is setup
        _ = DCMImgView.setupMetalOnce
        
        guard let device = DCMImgView.metalDevice,
              let commandQueue = DCMImgView.metalCommandQueue,
              let computeShader = DCMImgView.windowLevelComputeShader else {
            return false
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create Metal buffers
        guard let inputBuffer = device.makeBuffer(bytes: inputPixels, 
                                                  length: pixelCount * 2, 
                                                  options: .storageModeShared),
              let outputBuffer = device.makeBuffer(length: pixelCount, 
                                                   options: .storageModeShared) else {
            return false
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }
        
        // Setup compute shader
        encoder.setComputePipelineState(computeShader)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        
        var parameters = (winMin, winMax, UInt32(pixelCount))
        encoder.setBytes(&parameters.0, length: 4, index: 2)
        encoder.setBytes(&parameters.1, length: 4, index: 3) 
        encoder.setBytes(&parameters.2, length: 4, index: 4)
        
        // Calculate optimal thread group size
        let threadsPerGroup = MTLSize(width: min(computeShader.threadExecutionWidth, pixelCount), height: 1, depth: 1)
        let threadGroups = MTLSize(width: (pixelCount + threadsPerGroup.width - 1) / threadsPerGroup.width, height: 1, depth: 1)
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        // Execute and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Copy results back
        let resultPointer = outputBuffer.contents().assumingMemoryBound(to: UInt8.self)
        memcpy(outputPixels, resultPointer, pixelCount)
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] GPU window/level processing: \(String(format: "%.2f", elapsed))ms | pixels: \(pixelCount)")
        
        return true
    }
}

// MARK: - DCMImgView Performance Extensions

extension DCMImgView {
    
    /// Performance metrics and optimization methods
    public struct PerformanceMetrics {
        let imageCreationTime: Double
        let lutGenerationTime: Double
        let totalProcessingTime: Double
        let pixelCount: Int
        let optimizationsUsed: [String]
    }
    
    /// Get performance information about the last image processing operation
    public func getPerformanceMetrics() -> PerformanceMetrics? {
        // This would be populated during actual processing
        // For now, return nil as metrics aren't fully tracked
        return nil
    }
    
    /// Enable or disable performance logging
    public func setPerformanceLoggingEnabled(_ enabled: Bool) {
        // Implementation would control debug logging
    }
}

// MARK: - DCMImgView Convenience Extensions

extension DCMImgView {
    
    /// Quick setup for common DICOM image types
    public enum ImagePreset {
        case ct
        case mri
        case xray
        case ultrasound
    }
    
    /// Apply optimal settings for common imaging modalities
    public func applyPreset(_ preset: ImagePreset) {
        switch preset {
        case .ct:
            changeValWidth = 25
            changeValCentre = 25
        case .mri:
            changeValWidth = 10
            changeValCentre = 10
        case .xray:
            changeValWidth = 50
            changeValCentre = 50
        case .ultrasound:
            changeValWidth = 2
            changeValCentre = 2
        }
    }
    
    /// Check if the view has valid image data
    public var hasImageData: Bool {
        return pix8 != nil || pix16 != nil || pix24 != nil
    }
    
    /// Get the current image dimensions
    public var imageDimensions: CGSize {
        return CGSize(width: imgWidth, height: imgHeight)
    }
}

// MARK: - DCMImgView Memory Management Extensions

extension DCMImgView {
    
    /// Clear all cached data to free memory
    public func clearCache() {
        cachedImageData = nil
        cachedImageDataValid = false
        lut8 = nil
        lut16 = nil
        resetImage()
    }
    
    /// Estimate memory usage of current image data
    public func estimatedMemoryUsage() -> Int {
        var usage = 0
        
        if let pix8 = pix8 {
            usage += pix8.count
        }
        
        if let pix16 = pix16 {
            usage += pix16.count * 2
        }
        
        if let pix24 = pix24 {
            usage += pix24.count
        }
        
        if let lut16 = lut16 {
            usage += lut16.count
        }
        
        if let lut8 = lut8 {
            usage += lut8.count
        }
        
        if let cachedData = cachedImageData {
            usage += cachedData.count
        }
        
        return usage
    }
}
