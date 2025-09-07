//
//  DicomTool.swift
//  DICOMViewer
//
//  Swift Migration - Utility for DICOM operations
//  Refactored to use DcmSwift instead of DCMDecoder
//

import UIKit
import Foundation
import Accelerate

// MARK: - Protocols

/// Protocol for receiving window/level updates during image manipulation
protocol DicomToolDelegate: AnyObject {
    func updateWindowLevel(width: String, center: String)
}

// MARK: - Error Types

enum DicomToolError: Error, LocalizedError {
    case invalidPath
    case decodingFailed
    case unsupportedImageFormat
    case invalidPixelData
    case geometryCalculationFailed
    case dcmSwiftServiceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Invalid DICOM file path"
        case .decodingFailed:
            return "Failed to decode DICOM file"
        case .unsupportedImageFormat:
            return "Unsupported DICOM image format"
        case .invalidPixelData:
            return "Invalid or missing pixel data"
        case .geometryCalculationFailed:
            return "Failed to calculate geometric measurements"
        case .dcmSwiftServiceUnavailable:
            return "DcmSwift service is not available"
        }
    }
}

// MARK: - Data Structures

/// Result of DICOM decoding and display operation
enum DicomProcessingResult {
    case success
    case failure(DicomToolError)
}

// MARK: - Main Class

/// Modern Swift DICOM utility class using DcmSwift
final class DicomTool: @unchecked Sendable {
    
    // MARK: - Properties
    
    static let shared = DicomTool()
    weak var delegate: DicomToolDelegate?
    
    private let dicomService: any DicomServiceProtocol
    
    // MARK: - Initialization
    
    private init() {
        // Use DcmSwift service directly
        self.dicomService = DcmSwiftService.shared
        print("✅ DicomTool initialized with DcmSwift")
    }
    
    // MARK: - Public Methods
    
    /// Main entry point for decoding and displaying DICOM images using DcmSwift
    func decodeAndDisplay(path: String, view: DCMImgView) async -> DicomProcessingResult {
        print("🔄 [DcmSwift] Processing DICOM file: \(path.components(separatedBy: "/").last ?? path)")
        
        let url = URL(fileURLWithPath: path)
        let result = await dicomService.loadDicomImage(from: url)
        
        switch result {
        case .success(let imageModel):
            // Display the image in DCMImgView
            await MainActor.run {
                // Set pixels directly in the view based on pixel data type
                switch imageModel.pixelData {
                case .uint16(let data):
                    view.setPixels16(data, 
                                   width: imageModel.width, 
                                   height: imageModel.height,
                                   windowWidth: imageModel.windowWidth, 
                                   windowCenter: imageModel.windowCenter,
                                   samplesPerPixel: imageModel.samplesPerPixel ?? 1)
                    print("✅ [DcmSwift] Successfully displayed 16-bit image")
                    
                case .uint8(let data):
                    view.setPixels8(data, 
                                  width: imageModel.width, 
                                  height: imageModel.height,
                                  windowWidth: imageModel.windowWidth, 
                                  windowCenter: imageModel.windowCenter,
                                  samplesPerPixel: imageModel.samplesPerPixel ?? 1)
                    print("✅ [DcmSwift] Successfully displayed 8-bit image")
                    
                case .uint24(let data):
                    // For RGB images, convert to UIImage first
                    if let uiImage = self.createRGBImage(from: data, width: imageModel.width, height: imageModel.height) {
                        // DCMImgView doesn't have direct RGB support, so we need to use setPixels8
                        // This is a limitation we'll need to handle differently
                        print("⚠️ [DcmSwift] RGB images need special handling in DCMImgView")
                    }
                }
            }
            return .success
            
        case .failure(let error):
            print("❌ [DcmSwift] Failed to load DICOM: \(error)")
            return .failure(.decodingFailed)
        }
    }
    
    /// Synchronous wrapper for compatibility
    func decodeAndDisplay(path: String, view: DCMImgView) -> DicomProcessingResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: DicomProcessingResult = .failure(.decodingFailed)
        
        Task {
            result = await decodeAndDisplay(path: path, view: view)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    /// Extract DICOM UIDs from file
    func extractDICOMUIDs(from filePath: String) async -> (studyUID: String?, seriesUID: String?, sopUID: String?) {
        let url = URL(fileURLWithPath: filePath)
        
        // Use DcmSwift to extract metadata
        let metadataResult = await dicomService.extractFullMetadata(from: url)
        
        switch metadataResult {
        case .success(let metadata):
            let studyUID = metadata["StudyInstanceUID"] as? String
            let seriesUID = metadata["SeriesInstanceUID"] as? String
            let sopUID = metadata["SOPInstanceUID"] as? String
            return (studyUID, seriesUID, sopUID)
            
        case .failure:
            return (nil, nil, nil)
        }
    }
    
    /// Check if file is a valid DICOM
    func isValidDICOM(at path: String) async -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // Try to load with DcmSwift
        let result = await dicomService.loadDicomImage(from: url)
        
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }
    
    /// Calculate window/level for display
    func calculateWindowLevel(windowWidth: Double, windowLevel: Double, rescaleSlope: Double, rescaleIntercept: Double) -> (pixelWidth: Int, pixelLevel: Int) {
        // Convert HU values to pixel values
        let pixelLevel = Int((windowLevel - rescaleIntercept) / rescaleSlope)
        let pixelWidth = Int(windowWidth / rescaleSlope)
        return (pixelWidth, pixelLevel)
    }
    
    /// Apply window/level to view
    func applyWindowLevel(to view: DCMImgView, width: Double, level: Double) {
        // DCMImgView handles window/level internally
        // Just update the delegate
        delegate?.updateWindowLevel(
            width: String(format: "%.0f", width),
            center: String(format: "%.0f", level)
        )
    }
}

// MARK: - Extensions

extension DicomTool {
    
    /// Quick process for thumbnail generation
    func quickProcess(path: String, view: DCMImgView) async -> Bool {
        let result = await decodeAndDisplay(path: path, view: view)
        
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }
    
    /// Get image dimensions from DICOM file
    func getImageDimensions(from path: String) async -> (width: Int, height: Int)? {
        let url = URL(fileURLWithPath: path)
        let result = await dicomService.loadDicomImage(from: url)
        
        switch result {
        case .success(let imageModel):
            return (imageModel.width, imageModel.height)
        case .failure:
            return nil
        }
    }
    
    /// Extract modality from DICOM file
    func getModality(from path: String) async -> String? {
        let url = URL(fileURLWithPath: path)
        let result = await dicomService.extractFullMetadata(from: url)
        
        switch result {
        case .success(let metadata):
            return metadata["Modality"] as? String
        case .failure:
            return nil
        }
    }
}

// MARK: - Utility Functions

extension DicomTool {
    
    /// Convert pixel value to HU
    func pixelToHU(_ pixelValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double {
        return pixelValue * rescaleSlope + rescaleIntercept
    }
    
    /// Convert HU to pixel value
    func huToPixel(_ huValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double {
        return (huValue - rescaleIntercept) / rescaleSlope
    }
    
    /// Calculate distance between two points
    func calculateDistance(from point1: CGPoint, to point2: CGPoint, pixelSpacing: (x: Double, y: Double)) -> Double {
        let dx = Double(point2.x - point1.x) * pixelSpacing.x
        let dy = Double(point2.y - point1.y) * pixelSpacing.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Helper Methods
    
    private func createUIImage(from model: DicomImageModel) -> UIImage? {
        let width = model.width
        let height = model.height
        
        // Apply window/level to convert to 8-bit grayscale
        let windowWidth = model.windowWidth
        let windowCenter = model.windowCenter
        let rescaleSlope = model.rescaleSlope
        let rescaleIntercept = model.rescaleIntercept
        
        // Calculate pixel value bounds
        let pixelCenter = (windowCenter - rescaleIntercept) / rescaleSlope
        let pixelWidth = windowWidth / rescaleSlope
        let minLevel = pixelCenter - pixelWidth / 2.0
        let maxLevel = pixelCenter + pixelWidth / 2.0
        let range = maxLevel - minLevel
        let factor = (range <= 0) ? 0 : 255.0 / range
        
        // Create 8-bit pixel buffer
        let pixelCount = width * height
        var pixels8 = [UInt8](repeating: 0, count: pixelCount)
        
        switch model.pixelData {
        case .uint16(let data):
            for i in 0..<pixelCount {
                let pixelValue = Double(data[i])
                let normalizedValue = (pixelValue - minLevel) * factor
                let clampedValue = max(0.0, min(255.0, normalizedValue))
                pixels8[i] = UInt8(clampedValue)
            }
            
        case .uint8(let data):
            for i in 0..<pixelCount {
                let pixelValue = Double(data[i])
                let normalizedValue = (pixelValue - minLevel) * factor
                let clampedValue = max(0.0, min(255.0, normalizedValue))
                pixels8[i] = UInt8(clampedValue)
            }
            
        case .uint24(let data):
            // RGB image - handle as RGB
            return createRGBImage(from: data, width: width, height: height)
        }
        
        // Create grayscale CGImage
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let context = CGContext(
            data: &pixels8,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func createRGBImage(from data: [UInt8], width: Int, height: Int) -> UIImage? {
        let pixelCount = width * height
        var rgbaData = [UInt8](repeating: 0, count: pixelCount * 4)
        
        // Convert RGB to RGBA
        for i in 0..<pixelCount {
            let srcIndex = i * 3
            let dstIndex = i * 4
            if srcIndex + 2 < data.count {
                rgbaData[dstIndex] = data[srcIndex]     // R
                rgbaData[dstIndex + 1] = data[srcIndex + 1] // G
                rgbaData[dstIndex + 2] = data[srcIndex + 2] // B
                rgbaData[dstIndex + 3] = 255                // A
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: &rgbaData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}