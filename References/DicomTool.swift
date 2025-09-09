//
//  DicomTool.swift
//  DICOMViewer
//
//  Swift Migration - Replacing Tool.h/m
//  Modern Swift DICOM utility class with improved error handling and type safety
//

import UIKit
import Foundation
import Accelerate

// MARK: - Protocols

/// Protocol for receiving window/level updates during image manipulation
/// Migration from: ToolDelegate protocol in Tool.h
protocol DicomToolDelegate: AnyObject {
    /// Called when window width and center values are updated
    /// - Parameters:
    ///   - windowWidth: Updated window width value
    ///   - windowCenter: Updated window center value
    func updateWindowLevel(width: String, center: String)
}

// MARK: - Error Types

enum DicomToolError: Error, LocalizedError {
    case invalidDecoder
    case decoderNotReady
    case unsupportedImageFormat
    case invalidPixelData
    case geometryCalculationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidDecoder:
            return "DICOM decoder is invalid"
        case .decoderNotReady:
            return "DICOM decoder is not ready or failed to read file"
        case .unsupportedImageFormat:
            return "Unsupported DICOM image format"
        case .invalidPixelData:
            return "Invalid or missing pixel data"
        case .geometryCalculationFailed:
            return "Failed to calculate geometric measurements"
        }
    }
}

// MARK: - Data Structures

struct DicomImageParameters {
    let width: Int
    let height: Int
    let bitDepth: Int
    let samplesPerPixel: Int
    let isSignedImage: Bool
    let windowWidth: Int
    let windowCenter: Int
    let pixelData: DicomPixelData
}

enum DicomPixelData {
    case pixels8(UnsafePointer<UInt8>)
    case pixels16(UnsafePointer<UInt16>)
    case pixels24(UnsafePointer<UInt8>)
}

// MARK: - Modern Swift DICOM Tool Class

/// Modern Swift DICOM utility class with improved safety and functionality
/// Migration from: Tool.h/m class
@MainActor
class DicomTool {
    
    // MARK: - Constants
    
    private static let pi: CGFloat = .pi
    
    // MARK: - Singleton Instance
    
    /// Shared singleton instance
    /// Migration from: shareInstance method
    static let shared = DicomTool()
    
    // MARK: - Properties
    
    /// Delegate for window/level updates
    weak var delegate: DicomToolDelegate?
    
    // MARK: - Private Initializer
    
    private init() {}
    
    // MARK: - Angle Calculation Methods
    
    /// Calculates the angle between two lines from a common start point
    /// Migration from: angleForStartPoint:firstEndPoint:secEndPoint:
    /// - Parameters:
    ///   - startPoint: Common start point of both lines
    ///   - firstEndPoint: End point of the first line
    ///   - secondEndPoint: End point of the second line
    /// - Returns: Angle in degrees, or nil if calculation fails
    func angle(from startPoint: CGPoint,
               to firstEndPoint: CGPoint,
               and secondEndPoint: CGPoint) -> Result<CGFloat, DicomToolError> {
        
        let a = firstEndPoint.x - startPoint.x
        let b = firstEndPoint.y - startPoint.y
        let c = secondEndPoint.x - startPoint.x
        let d = secondEndPoint.y - startPoint.y
        
        let denominator = sqrt(a * a + b * b) * sqrt(c * c + d * d)
        
        guard denominator != 0 else {
            return .failure(.geometryCalculationFailed)
        }
        
        let cosValue = ((a * c) + (b * d)) / denominator
        
        // Clamp to valid range for acos
        let clampedCos = max(-1.0, min(1.0, cosValue))
        var radians = acos(clampedCos)
        
        // Adjust for quadrant
        if startPoint.y > firstEndPoint.y {
            radians = -radians
        }
        
        let degrees = radians * 180.0 / Self.pi
        return .success(degrees)
    }
    
    /// Convenience method for angle calculation with error handling
    func calculateAngle(from startPoint: CGPoint,
                        to firstEndPoint: CGPoint,
                        and secondEndPoint: CGPoint) -> CGFloat? {
        switch angle(from: startPoint, to: firstEndPoint, and: secondEndPoint) {
        case .success(let angle):
            return angle
        case .failure(let error):
            print("Angle calculation failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Window/Level Application Methods
    
    /// Applies window/level values directly to the current image display
    /// - Parameters:
    ///   - windowWidth: New window width value
    ///   - windowCenter: New window center value
    ///   - view: The DICOM 2D view to update
    /// - Returns: Result indicating success or failure
    func applyWindowLevel(windowWidth: Int, windowCenter: Int, view: DCMImgView) -> Result<Void, DicomToolError> {
        // Aplica os novos valores diretamente na view
        view.winWidth = windowWidth
        view.winCenter = windowCenter
        
        // CORREÇÃO CRÍTICA: Use os métodos públicos para recalcular a imagem
        view.resetValues() // Recalcula os valores internos de min/max
        
        // Verifica a profundidade de bits e samples per pixel para chamar o método correto
        if view.signed16Image {
            // Recalcula a LUT e recria o bitmap para 16-bit
            view.computeLookUpTable16()
            view.createImage16()
        } else {
            // Recalcula a LUT para 8-bit/24-bit
            view.computeLookUpTable8()
            
            // Verifica samples per pixel para determinar se é 8-bit ou 24-bit
            if view.samplesPerPixel == 3 {
                view.createImage24()
            } else {
                view.createImage8()
            }
        }
        
        // Força o redesenho da view com a nova imagem
        view.setNeedsDisplay()
        
        print("✅ Applied W/L and regenerated image: WW=\(windowWidth), WL=\(windowCenter), SPP=\(view.samplesPerPixel)")
        
        // Update delegate with new values
        let widthString = "Window Width: \(view.winWidth)"
        let centerString = "Window Level: \(view.winCenter)"
        delegate?.updateWindowLevel(width: widthString, center: centerString)
        
        return .success(())
    }
    
    // MARK: - DICOM Processing Methods
    
    /// Decodes and displays DICOM file with automatic window/level calculation
    /// Migration from: decodeAndDisplay:dicomDecoder:dicom2DView:
    /// - Parameters:
    ///   - path: Path to DICOM file
    ///   - decoder: DICOM decoder instance
    ///   - view: 2D view for display
    /// - Returns: Result indicating success or failure
    func decodeAndDisplay(path: String,
                          decoder: DCMDecoder,
                          view: DCMImgView) -> Result<Void, DicomToolError> {
        let startTime = CFAbsoluteTimeGetCurrent()
        // CORREÇÃO: Carrega o arquivo no decodificador antes de tentar usá-lo.
        decoder.setDicomFilename(path)
        let result = display(windowWidth: 0, windowCenter: 0, decoder: decoder, view: view)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] DicomTool.decodeAndDisplay: \(String(format: "%.2f", elapsed))ms")
        return result
    }
    
    /// Displays DICOM image with specified window/level settings
    /// Migration from: displayWith:windowCenter:dicomDecoder:dicom2DView:
    /// - Parameters:
    ///   - windowWidth: Window width value (0 for auto-calculation)
    ///   - windowCenter: Window center value (0 for auto-calculation)
    ///   - decoder: DICOM decoder instance
    ///   - view: 2D view for display
    /// - Returns: Result indicating success or failure
    func display(windowWidth: Int,
                 windowCenter: Int,
                 decoder: DCMDecoder,
                 view: DCMImgView) -> Result<Void, DicomToolError> {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Validate decoder state
        guard decoder.dicomFound && decoder.dicomFileReadSuccess else {
            return .failure(.decoderNotReady)
        }
        
        // Extract image parameters
        let imageWidth = Int(decoder.width)
        let imageHeight = Int(decoder.height)
        let bitDepth = Int(decoder.bitDepth)
        let samplesPerPixel = Int(decoder.samplesPerPixel)
        let isSignedImage = decoder.signedImage
        
        var winWidth = windowWidth
        var winCenter = windowCenter
        var needsDisplay = false
        
        // Process different image formats
        switch (samplesPerPixel, bitDepth) {
        case (1, 8):
            let result = process8BitImage(decoder: decoder,
                                        imageWidth: imageWidth,
                                        imageHeight: imageHeight,
                                        windowWidth: &winWidth,
                                        windowCenter: &winCenter,
                                        view: view)
            if case .failure(let error) = result {
                return .failure(error)
            }
            needsDisplay = true
            
        case (1, 16):
            let result = process16BitImage(decoder: decoder,
                                         imageWidth: imageWidth,
                                         imageHeight: imageHeight,
                                         windowWidth: &winWidth,
                                         windowCenter: &winCenter,
                                         isSignedImage: isSignedImage,
                                         view: view)
            if case .failure(let error) = result {
                return .failure(error)
            }
            needsDisplay = true
            
        case (3, 8):
            let result = process24BitImage(decoder: decoder,
                                         imageWidth: imageWidth,
                                         imageHeight: imageHeight,
                                         windowWidth: &winWidth,
                                         windowCenter: &winCenter,
                                         view: view)
            if case .failure(let error) = result {
                return .failure(error)
            }
            needsDisplay = true
            
        default:
            return .failure(.unsupportedImageFormat)
        }
        
        // Update display if needed
        if needsDisplay {
            updateViewDisplay(view: view, imageWidth: imageWidth, imageHeight: imageHeight)
            notifyDelegate(windowWidth: winWidth, windowCenter: winCenter, view: view)
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] DicomTool.display: \(String(format: "%.2f", elapsed))ms | size: \(imageWidth)x\(imageHeight) | depth: \(bitDepth)-bit")
        return .success(())
    }
    
    // MARK: - Image Format Processing
    
    private func process8BitImage(decoder: DCMDecoder,
                                  imageWidth: Int,
                                  imageHeight: Int,
                                  windowWidth: inout Int,
                                  windowCenter: inout Int,
                                  view: DCMImgView) -> Result<Void, DicomToolError> {
        
        guard let pixels8 = decoder.getPixels8() else {
            return .failure(.invalidPixelData)
        }
        
        // Auto-calculate window/level if needed
        if windowWidth == 0 && windowCenter == 0 {
            let (min, max) = calculateMinMax8Bit(pixels: pixels8, count: imageWidth * imageHeight)
            windowCenter = Int((Double(max) + Double(min)) / 2.0)  // Center is midpoint
            windowWidth = Int(Double(max) - Double(min))           // Width is range
        }
        
        view.setPixels8(pixels8,
                        width: imageWidth,
                        height: imageHeight,
                        windowWidth: Double(windowWidth),
                        windowCenter: Double(windowCenter),
                        samplesPerPixel: 1,
                        resetScroll: true)
        
        return .success(())
    }
    
    private func process16BitImage(decoder: DCMDecoder,
                                   imageWidth: Int,
                                   imageHeight: Int,
                                   windowWidth: inout Int,
                                   windowCenter: inout Int,
                                   isSignedImage: Bool,
                                   view: DCMImgView) -> Result<Void, DicomToolError> {
        
        guard let pixels16 = decoder.getPixels16() else {
            return .failure(.invalidPixelData)
        }
        
        // Auto-calculate window/level if needed
        if windowWidth == 0 || windowCenter == 0 {
            let (min, max) = calculateMinMax16Bit(pixels: pixels16, count: imageWidth * imageHeight)
            windowCenter = Int((Double(max) + Double(min)) / 2.0)  // Center is midpoint
            windowWidth = Int(Double(max) - Double(min))           // Width is range
        }
        
        view.signed16Image = isSignedImage
        view.setPixels16(pixels16,
                         width: imageWidth,
                         height: imageHeight,
                         windowWidth: Double(windowWidth),
                         windowCenter: Double(windowCenter),
                         samplesPerPixel: 1,
                         resetScroll: true)
        
        return .success(())
    }
    
    private func process24BitImage(decoder: DCMDecoder,
                                   imageWidth: Int,
                                   imageHeight: Int,
                                   windowWidth: inout Int,
                                   windowCenter: inout Int,
                                   view: DCMImgView) -> Result<Void, DicomToolError> {
        
        guard let pixels24 = decoder.getPixels24() else {
            return .failure(.invalidPixelData)
        }
        
        // For RGB images (like US), use full dynamic range
        // RGB images are already processed and don't need window/level adjustment
        if windowWidth == 0 || windowCenter == 0 {
            // Use full 8-bit range for RGB images
            windowCenter = 128  // Middle of 8-bit range
            windowWidth = 256   // Full 8-bit range
        }
        
        view.setPixels8(pixels24,
                        width: imageWidth,
                        height: imageHeight,
                        windowWidth: Double(windowWidth),
                        windowCenter: Double(windowCenter),
                        samplesPerPixel: 3,
                        resetScroll: true)
        
        return .success(())
    }
    
    // MARK: - Pixel Analysis Utilities
    
    private func calculateMinMax8Bit(pixels: UnsafePointer<UInt8>, count: Int) -> (min: UInt8, max: UInt8) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use Accelerate framework for vectorized min/max operations
        var minValue: UInt8 = 0
        var maxValue: UInt8 = 0
        
        // Convert UInt8 to Float for vDSP processing
        var floatBuffer = [Float](repeating: 0, count: count)
        vDSP_vfltu8(pixels, 1, &floatBuffer, 1, vDSP_Length(count))
        
        // Find min/max using vectorized operations
        var minFloat: Float = 0
        var maxFloat: Float = 0
        vDSP_minv(&floatBuffer, 1, &minFloat, vDSP_Length(count))
        vDSP_maxv(&floatBuffer, 1, &maxFloat, vDSP_Length(count))
        
        minValue = UInt8(minFloat)
        maxValue = UInt8(maxFloat)
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] calculateMinMax8Bit (vectorized): \(String(format: "%.2f", elapsed))ms | pixels: \(count)")
        
        return (minValue, maxValue)
    }
    
    private func calculateMinMax16Bit(pixels: UnsafePointer<UInt16>, count: Int) -> (min: UInt16, max: UInt16) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use Accelerate framework for ultra-fast vectorized min/max operations
        var minValue: UInt16 = 0
        var maxValue: UInt16 = 0
        
        // For large datasets, use chunked processing to avoid memory pressure
        if count > 1000000 { // >1M pixels
            let chunkSize = 500000 // Process 500K pixels at a time
            var globalMin: UInt16 = 65535
            var globalMax: UInt16 = 0
            
            var offset = 0
            while offset < count {
                let currentChunkSize = min(chunkSize, count - offset)
                let chunkPtr = pixels.advanced(by: offset)
                
                // Convert UInt16 chunk to Float for vDSP processing
                var floatBuffer = [Float](repeating: 0, count: currentChunkSize)
                vDSP_vfltu16(chunkPtr, 1, &floatBuffer, 1, vDSP_Length(currentChunkSize))
                
                // Find min/max using vectorized operations
                var chunkMinFloat: Float = 0
                var chunkMaxFloat: Float = 0
                vDSP_minv(&floatBuffer, 1, &chunkMinFloat, vDSP_Length(currentChunkSize))
                vDSP_maxv(&floatBuffer, 1, &chunkMaxFloat, vDSP_Length(currentChunkSize))
                
                let chunkMin = UInt16(chunkMinFloat)
                let chunkMax = UInt16(chunkMaxFloat)
                
                if chunkMin < globalMin { globalMin = chunkMin }
                if chunkMax > globalMax { globalMax = chunkMax }
                
                offset += currentChunkSize
            }
            
            minValue = globalMin
            maxValue = globalMax
        } else {
            // For smaller datasets, process all at once
            // Convert UInt16 to Float for vDSP processing
            var floatBuffer = [Float](repeating: 0, count: count)
            vDSP_vfltu16(pixels, 1, &floatBuffer, 1, vDSP_Length(count))
            
            // Find min/max using vectorized operations
            var minFloat: Float = 0
            var maxFloat: Float = 0
            vDSP_minv(&floatBuffer, 1, &minFloat, vDSP_Length(count))
            vDSP_maxv(&floatBuffer, 1, &maxFloat, vDSP_Length(count))
            
            minValue = UInt16(minFloat)
            maxValue = UInt16(maxFloat)
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] calculateMinMax16Bit (vectorized): \(String(format: "%.2f", elapsed))ms | pixels: \(count) | result: \(minValue)-\(maxValue)")
        
        return (minValue, maxValue)
    }
    
    // MARK: - Display Management
    
    private func updateViewDisplay(view: DCMImgView, imageWidth: Int, imageHeight: Int) {
        // Update view frame and bounds (using constants that should be defined elsewhere)
        let screenWidth: CGFloat = UIScreen.main.bounds.width // Fallback for MedFilm_WIDTH
        let screenHeight: CGFloat = UIScreen.main.bounds.height // Fallback for MedFilm_HEIGHT
        let margin: CGFloat = 40
        
        view.center = CGPoint(x: screenWidth / 2, y: screenHeight / 2)
        view.bounds = CGRect(x: 0, y: 0, width: screenWidth - margin * 2, height: screenWidth - margin * 2)
        view.setNeedsDisplay()
    }
    
    private func notifyDelegate(windowWidth: Int, windowCenter: Int, view: DCMImgView) {
        let widthString = "Window Width: \(view.winWidth)"
        let centerString = "Window Level: \(view.winCenter)"
        delegate?.updateWindowLevel(width: widthString, center: centerString)
    }
}

// MARK: - DicomTool Extensions

// MARK: - Async/Await Interface

extension DicomTool {
    
    /// Async version of DICOM processing
    /// - Parameters:
    ///   - path: DICOM file path
    ///   - decoder: DICOM decoder
    ///   - view: Display view
    /// - Returns: Processing result
    func processAsync(path: String,
                      decoder: DCMDecoder,
                      view: DCMImgView) async -> Result<Void, DicomToolError> {
        return await withCheckedContinuation { continuation in
            let result = decodeAndDisplay(path: path, decoder: decoder, view: view)
            continuation.resume(returning: result)
        }
    }
    
    /// Async processing with progress tracking
    /// - Parameters:
    ///   - path: DICOM file path
    ///   - decoder: DICOM decoder
    ///   - view: Display view
    ///   - progressCallback: Progress callback
    /// - Returns: Processing result
    func processWithProgress(path: String,
                             decoder: DCMDecoder,
                             view: DCMImgView,
                             progressCallback: @escaping (Float) -> Void) async -> Result<Void, DicomToolError> {
        
        progressCallback(0.0) // Start
        
        // Simulate processing steps
        progressCallback(0.3) // Validation complete
        
        let result = await processAsync(path: path, decoder: decoder, view: view)
        
        progressCallback(1.0) // Complete
        
        return result
    }
}

// MARK: - Convenience Methods

extension DicomTool {
    
    /// Quick DICOM processing with default parameters
    /// - Parameters:
    ///   - decoder: DICOM decoder
    ///   - view: Display view
    /// - Returns: Success flag
    @discardableResult
    func quickProcess(decoder: DCMDecoder, view: DCMImgView) -> Bool {
        let result = decodeAndDisplay(path: "", decoder: decoder, view: view)
        switch result {
        case .success:
            return true
        case .failure(let error):
            print("DICOM processing failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Legacy Objective-C Bridge

extension DicomTool {
    
    /// Legacy angle calculation method for compatibility
    /// Migration from: angleForStartPoint:firstEndPoint:secEndPoint:
    @objc func angleForStartPoint(_ startPoint: CGPoint,
                                  firstEndPoint endPoint: CGPoint,
                                  secEndPoint: CGPoint) -> CGFloat {
        return calculateAngle(from: startPoint, to: endPoint, and: secEndPoint) ?? 0.0
    }
}

