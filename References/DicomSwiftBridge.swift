//
//  DicomSwiftBridge.swift
//  DICOMViewer
//
//  Swift bridge for DICOM core functionality
//  Provides type-safe Swift interface to Objective-C++ DICOM decoder
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - DICOM Tag Enumeration

public enum DicomTag: UInt32, CaseIterable {
    // Image Properties
    case pixelRepresentation = 0x00280103
    case transferSyntaxUID = 0x00020010
    case sliceThickness = 0x00180050
    case sliceSpacing = 0x00180088
    case samplesPerPixel = 0x00280002
    case photometricInterpretation = 0x00280004
    case planarConfiguration = 0x00280006
    case numberOfFrames = 0x00280008
    case rows = 0x00280010
    case columns = 0x00280011
    case pixelSpacing = 0x00280030
    case bitsAllocated = 0x00280100
    case windowCenter = 0x00281050
    case windowWidth = 0x00281051
    case rescaleIntercept = 0x00281052
    case rescaleSlope = 0x00281053
    case pixelData = 0x7FE00010
    
    // Patient Information
    case patientID = 0x00100020
    case patientName = 0x00100010
    case patientSex = 0x00100040
    case patientAge = 0x00101010
    
    // Study Information
    case studyInstanceUID = 0x0020000d
    case studyID = 0x00200010
    case studyDate = 0x00080020
    case studyTime = 0x00080030
    case studyDescription = 0x00081030
    case numberOfStudyRelatedSeries = 0x00201206
    case modalitiesInStudy = 0x00080061
    case referringPhysicianName = 0x00080090
    
    // Series Information
    case seriesInstanceUID = 0x0020000e
    case seriesNumber = 0x00200011
    case seriesDate = 0x00080021
    case seriesTime = 0x00080031
    case seriesDescription = 0x0008103E
    case numberOfSeriesRelatedInstances = 0x00201209
    case modality = 0x00080060
    
    // Instance Information
    case sopInstanceUID = 0x00080018
    case acquisitionDate = 0x00080022
    case contentDate = 0x00080023
    case acquisitionTime = 0x00080032
    case contentTime = 0x00080033
    case patientPosition = 0x00185100
    
    // Additional tags for annotations
    case protocolName = 0x00181030
    case instanceNumber = 0x00200013
    case sliceLocation = 0x00201041
    case imageOrientationPatient = 0x00200037
    
    public var description: String {
        switch self {
        case .pixelRepresentation: return "Pixel Representation"
        case .transferSyntaxUID: return "Transfer Syntax UID"
        case .rows: return "Rows"
        case .columns: return "Columns"
        case .windowCenter: return "Window Center"
        case .windowWidth: return "Window Width"
        case .patientName: return "Patient Name"
        case .patientID: return "Patient ID"
        case .studyDate: return "Study Date"
        case .modality: return "Modality"
        default: return "DICOM Tag \(String(format: "0x%08X", rawValue))"
        }
    }
}

// MARK: - DICOM Data Models

public struct DicomImageInfo: Sendable {
    public let width: Int
    public let height: Int
    public let bitDepth: Int
    public let samplesPerPixel: Int
    public let windowCenter: Double
    public let windowWidth: Double
    public let pixelSpacing: (width: Double, height: Double, depth: Double)
    public let numberOfImages: Int
    public let isSignedImage: Bool
    public let isCompressed: Bool
}

public struct DicomPatientInfo: Sendable {
    public let patientID: String?
    public let patientName: String?
    public let patientSex: String?
    public let patientAge: String?
}

public struct DicomStudyInfo: Sendable {
    public let studyInstanceUID: String?
    public let studyID: String?
    public let studyDate: String?
    public let studyTime: String?
    public let studyDescription: String?
    public let modality: String?
    public let acquisitionDate: String?
    public let acquisitionTime: String?
}

public struct DicomSeriesInfo: Sendable {
    public let seriesInstanceUID: String?
    public let seriesNumber: String?
    public let seriesDate: String?
    public let seriesTime: String?
    public let seriesDescription: String?
    public let protocolName: String?
    public let instanceNumber: String?
    public let sliceLocation: String?
    public let imageOrientationPatient: String?
}

// MARK: - Error Handling Types

public enum DicomDecodingError: Error, Sendable {
    case fileNotFound
    case invalidDicomFile
    case decodingFailed
    case unsupportedFormat
    case memoryAllocationFailed
    
    public var localizedDescription: String {
        switch self {
        case .fileNotFound:
            return "DICOM file not found"
        case .invalidDicomFile:
            return "Invalid DICOM file format"
        case .decodingFailed:
            return "Failed to decode DICOM data"
        case .unsupportedFormat:
            return "Unsupported DICOM format"
        case .memoryAllocationFailed:
            return "Memory allocation failed"
        }
    }
}

public struct DicomDecodingResult: Sendable {
    public let imageInfo: DicomImageInfo
    public let patientInfo: DicomPatientInfo
    public let studyInfo: DicomStudyInfo
    public let seriesInfo: DicomSeriesInfo
    public let metadata: [String: String] // Changed from [String: Any] to make it Sendable
}

// MARK: - Main DICOM Bridge Implementation

@objc public class DicomSwiftBridge: NSObject {
    
    private let decoder: DCMDecoder
    
    // Cached pixel arrays to prevent dangling pointers
    private var cachedPixels8: [UInt8]?
    private var cachedPixels16: [UInt16]?
    private var cachedPixels24: [UInt8]?
    
    public override init() {
        self.decoder = DCMDecoder()
        super.init()
    }
    
    // MARK: - Core Decoding Interface
    
    public func decodeDicomFile(at path: String) -> Result<DicomDecodingResult, DicomDecodingError> {
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(.fileNotFound)
        }
        
        decoder.setDicomFilename(path)
        
        guard decoder.dicomFileReadSuccess else {
            return .failure(.decodingFailed)
        }
        
        let result = DicomDecodingResult(
            imageInfo: extractImageInfo(),
            patientInfo: extractPatientInfo(),
            studyInfo: extractStudyInfo(),
            seriesInfo: extractSeriesInfo(),
            metadata: extractMetadata()
        )
        
        return .success(result)
    }
    
    // MARK: - Pixel Data Access Methods
    
    public func getPixels8() -> [UInt8]? {
        // Return arrays directly - safer than raw pointers
        if cachedPixels8 == nil {
            cachedPixels8 = decoder.getPixels8()
        }
        return cachedPixels8
    }
    
    public func getPixels16() -> [UInt16]? {
        // Return arrays directly - safer than raw pointers
        if cachedPixels16 == nil {
            cachedPixels16 = decoder.getPixels16()
        }
        return cachedPixels16
    }
    
    public func getPixels24() -> [UInt8]? {
        // Return arrays directly - safer than raw pointers
        if cachedPixels24 == nil {
            cachedPixels24 = decoder.getPixels24()
        }
        return cachedPixels24
    }
    
    // MARK: - Safe Pixel Data Operations
    
    public func copyPixels8() -> Data? {
        guard let pixels = decoder.getPixels8() else { return nil }
        return Data(pixels)
    }
    
    public func copyPixels16() -> Data? {
        guard let pixels = decoder.getPixels16() else { return nil }
        return pixels.withUnsafeBytes { Data($0) }
    }
    
    public func copyPixels24() -> Data? {
        guard let pixels = decoder.getPixels24() else { return nil }
        let length = Int(decoder.width) * Int(decoder.height) * 3
        return Data(bytes: pixels, count: length)
    }
    
    // MARK: - Image Generation Interface
    
    public func generateUIImage(applyWindowLevel: Bool = true) -> UIImage? {
        guard decoder.dicomFileReadSuccess else { return nil }
        
        let width = Int(decoder.width)
        let height = Int(decoder.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard width > 0 && height > 0 else { return nil }
        
        var imageData: Data?
        var bitsPerComponent: Int = 8
        var bytesPerPixel: Int = 4
        
        // Handle different bit depths
        if decoder.bitDepth == 8 {
            imageData = copyPixels8()
            bitsPerComponent = 8
        } else if decoder.bitDepth == 16 {
            // Convert 16-bit to 8-bit for display
            imageData = convert16BitTo8Bit()
            bitsPerComponent = 8
        } else if decoder.samplesPerPixel == 3 {
            imageData = copyPixels24()
            bytesPerPixel = 3
        }
        
        guard let data = imageData else { return nil }
        
        let bytesPerRow = width * bytesPerPixel
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Convert grayscale to RGB if needed
        if decoder.samplesPerPixel == 1 {
            let rgbaData = convertGrayscaleToRGBA(data)
            context.data?.copyMemory(from: rgbaData.withUnsafeBytes { $0.baseAddress! }, byteCount: rgbaData.count)
        } else {
            context.data?.copyMemory(from: data.withUnsafeBytes { $0.baseAddress! }, byteCount: data.count)
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Data Extraction Implementation
    
    private func extractImageInfo() -> DicomImageInfo {
        return DicomImageInfo(
            width: Int(decoder.width),
            height: Int(decoder.height),
            bitDepth: Int(decoder.bitDepth),
            samplesPerPixel: Int(decoder.samplesPerPixel),
            windowCenter: decoder.windowCenter,
            windowWidth: decoder.windowWidth,
            pixelSpacing: (
                width: decoder.pixelWidth,
                height: decoder.pixelHeight,
                depth: decoder.pixelDepth
            ),
            numberOfImages: Int(decoder.nImages),
            isSignedImage: decoder.signedImage,
            isCompressed: decoder.compressedImage
        )
    }
    
    private func extractPatientInfo() -> DicomPatientInfo {
        return DicomPatientInfo(
            patientID: decoder.info(for: Int(DicomTag.patientID.rawValue)),
            patientName: decoder.info(for: Int(DicomTag.patientName.rawValue)),
            patientSex: decoder.info(for: Int(DicomTag.patientSex.rawValue)),
            patientAge: decoder.info(for: Int(DicomTag.patientAge.rawValue))
        )
    }
    
    private func extractStudyInfo() -> DicomStudyInfo {
        return DicomStudyInfo(
            studyInstanceUID: decoder.info(for: Int(DicomTag.studyInstanceUID.rawValue)),
            studyID: decoder.info(for: Int(DicomTag.studyID.rawValue)),
            studyDate: decoder.info(for: Int(DicomTag.studyDate.rawValue)),
            studyTime: decoder.info(for: Int(DicomTag.studyTime.rawValue)),
            studyDescription: decoder.info(for: Int(DicomTag.studyDescription.rawValue)),
            modality: decoder.info(for: Int(DicomTag.modality.rawValue)),
            acquisitionDate: decoder.info(for: Int(DicomTag.acquisitionDate.rawValue)),
            acquisitionTime: decoder.info(for: Int(DicomTag.acquisitionTime.rawValue))
        )
    }
    
    private func extractSeriesInfo() -> DicomSeriesInfo {
        return DicomSeriesInfo(
            seriesInstanceUID: decoder.info(for: Int(DicomTag.seriesInstanceUID.rawValue)),
            seriesNumber: decoder.info(for: Int(DicomTag.seriesNumber.rawValue)),
            seriesDate: decoder.info(for: Int(DicomTag.seriesDate.rawValue)),
            seriesTime: decoder.info(for: Int(DicomTag.seriesTime.rawValue)),
            seriesDescription: decoder.info(for: Int(DicomTag.seriesDescription.rawValue)),
            protocolName: decoder.info(for: Int(DicomTag.protocolName.rawValue)),
            instanceNumber: decoder.info(for: Int(DicomTag.instanceNumber.rawValue)),
            sliceLocation: decoder.info(for: Int(DicomTag.sliceLocation.rawValue)),
            imageOrientationPatient: decoder.info(for: Int(DicomTag.imageOrientationPatient.rawValue))
        )
    }
    
    private func extractMetadata() -> [String: String] {
        var metadata: [String: String] = [:]
        
        // Extract all available DICOM tags
        for tag in DicomTag.allCases {
            let value = decoder.info(for: Int(tag.rawValue))
            if !value.isEmpty {
                metadata[tag.description] = value
            }
        }
        
        return metadata
    }
    
    private func convert16BitTo8Bit() -> Data? {
        guard let pixels16 = decoder.getPixels16() else { return nil }
        
        let width = Int(decoder.width)
        let height = Int(decoder.height)
        let totalPixels = width * height
        
        var pixels8 = Data(capacity: totalPixels)
        
        // Apply window/level transformation
        let windowCenter = decoder.windowCenter
        let windowWidth = decoder.windowWidth
        let minLevel = windowCenter - windowWidth / 2
        let maxLevel = windowCenter + windowWidth / 2
        
        for i in 0..<totalPixels {
            let pixelValue = Double(pixels16[i])
            let normalizedValue = (pixelValue - minLevel) / (maxLevel - minLevel)
            let clampedValue = max(0, min(1, normalizedValue))
            let byteValue = UInt8(clampedValue * 255)
            pixels8.append(byteValue)
        }
        
        return pixels8
    }
    
    private func convertGrayscaleToRGBA(_ grayscaleData: Data) -> Data {
        var rgbaData = Data(capacity: grayscaleData.count * 4)
        
        for byte in grayscaleData {
            rgbaData.append(byte) // R
            rgbaData.append(byte) // G
            rgbaData.append(byte) // B
            rgbaData.append(255)  // A
        }
        
        return rgbaData
    }
    
    // MARK: - Advanced Thumbnail Generation
    
    /// Decodes DICOM pixel data and generates a UIImage applying window/level,
    /// without requiring a UIKit view. Safe to call on a background thread.
    /// - Parameters:
    ///   - path: The file path of the DICOM file.
    ///   - windowCenter: The window center value to apply.
    ///   - windowWidth: The window width value to apply.
    /// - Returns: A UIImage representing the DICOM image, or nil on failure.
    public func generateThumbnailImage(from path: String, windowCenter: Double? = nil, windowWidth: Double? = nil) -> UIImage? {
        decoder.setDicomFilename(path)
        
        guard decoder.dicomFileReadSuccess else {
            print("❌ generateThumbnailImage: Failed to read DICOM file: \(path)")
            return nil
        }
        
        let width = Int(decoder.width)
        let height = Int(decoder.height)
        let bitDepth = Int(decoder.bitDepth)
        let samplesPerPixel = Int(decoder.samplesPerPixel)
        _ = decoder.signedImage  // Currently unused but kept for future use
        
        guard width > 0 && height > 0 else {
            print("❌ generateThumbnailImage: Invalid image dimensions.")
            return nil
        }
        
        // Read Rescale values for HU conversion - critical for CT images
        var rescaleSlope: Double = 1.0
        var rescaleIntercept: Double = 0.0
        
        let slopeStr = decoder.info(for: 0x00281053)  // Rescale Slope
        if !slopeStr.isEmpty {
            if let value = Double(slopeStr.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? slopeStr) {
                rescaleSlope = value
            }
        }
        
        let interceptStr = decoder.info(for: 0x00281052)  // Rescale Intercept
        if !interceptStr.isEmpty {
            if let value = Double(interceptStr.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? interceptStr) {
                rescaleIntercept = value
            }
        }
        
        // NOVO E CORRIGIDO: Lógica de seleção inteligente de janelamento
        let modalityStr = decoder.info(for: 0x00080060)
        let modality = modalityStr.isEmpty ? "UNKNOWN" : modalityStr.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let bodyPartStr = decoder.info(for: 0x00180015)
        let bodyPart = bodyPartStr.isEmpty ? "UNKNOWN" : bodyPartStr.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        var wc: Double = 0
        var ww: Double = 0
        
        // 1. Prioridade máxima: Usar valores fornecidos explicitamente
        if let providedCenter = windowCenter, let providedWidth = windowWidth {
            wc = providedCenter
            ww = providedWidth
            print("🔍 generateThumbnailImage: Usando janelamento fornecido: W=\(ww), L=\(wc)")
        } 
        // 2. Nova Prioridade: Aplicar presets baseados em Modalidade e Body Part
        else {
            print("📊 generateThumbnailImage: Tentando aplicar presets por anatomia...")
            print("📋 Modalidade: \(modality), Body Part: \(bodyPart)")
            
            switch (modality, bodyPart) {
            case ("CT", let part) where part.contains("LUNG") || part.contains("CHEST"):
                wc = -500.0
                ww = 1400.0
                print("✅ Aplicando preset: PULMÃO (W=\(ww), L=\(wc))")
            case ("CT", let part) where part.contains("BONE"):
                wc = 300.0
                ww = 1500.0
                print("✅ Aplicando preset: OSSO (W=\(ww), L=\(wc))")
            case ("CT", let part) where part.contains("BRAIN") || part.contains("HEAD"):
                wc = 40.0
                ww = 80.0
                print("✅ Aplicando preset: CÉREBRO (W=\(ww), L=\(wc))")
            case ("CT", let part) where part.contains("ABDOMEN") || part.contains("PELVIS"):
                wc = 50.0
                ww = 400.0
                print("✅ Aplicando preset: ABDÔMEN (W=\(ww), L=\(wc))")
            case ("CT", _):
                wc = 40.0
                ww = 350.0
                print("✅ Aplicando preset: TECIDOS MOLES (CT genérico) (W=\(ww), L=\(wc))")
            case ("MR", _), ("MRI", _):
                // Para MR, primeiro tentar usar valores do DICOM, depois fallback
                wc = decoder.windowCenter
                ww = decoder.windowWidth
                
                if ww <= 0 {
                    // Tentar ler dos tags DICOM
                    let wcStr = decoder.info(for: 0x00281050)  // Window Center
                    let wwStr = decoder.info(for: 0x00281051)  // Window Width
                    if !wcStr.isEmpty && !wwStr.isEmpty {
                        if let wcValue = Double(wcStr.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? wcStr),
                           let wwValue = Double(wwStr.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? wwStr),
                           wwValue > 0 {
                            wc = wcValue
                            ww = wwValue
                        }
                    }
                }
                
                // Se ainda não tem valores válidos, usar fallback para MR
                if ww <= 0 {
                    wc = 128.0
                    ww = 256.0
                    print("✅ Aplicando janelamento padrão para MRI (sem valores DICOM) (W=\(ww), L=\(wc))")
                } else {
                    print("✅ Usando janelamento MRI do DICOM (W=\(ww), L=\(wc))")
                }
            case ("US", _):
                wc = 128.0
                ww = 256.0
                print("✅ Aplicando janelamento padrão para ULTRASSOM (W=\(ww), L=\(wc))")
            default:
                // 3. Prioridade mínima: Usar janelamento padrão do DICOM como fallback
                print("🔍 generateThumbnailImage: Nenhuma regra de preset se aplicou. Tentando janelamento DICOM padrão.")
                wc = decoder.windowCenter
                ww = decoder.windowWidth
                
                // Se ainda não tem valores, tentar ler dos tags DICOM
                if ww <= 0 {
                    let wcStr = decoder.info(for: 0x00281050)  // Window Center
                    let wwStr = decoder.info(for: 0x00281051)  // Window Width
                    if !wcStr.isEmpty && !wwStr.isEmpty {
                        // Parse the values (they might be in format "value" or "label: value")
                        if let wcValue = Double(wcStr.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? wcStr),
                           let wwValue = Double(wwStr.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? wwStr),
                           wwValue > 0 {
                            wc = wcValue
                            ww = wwValue
                            print("✅ Lido dos tags DICOM: W=\(ww), L=\(wc)")
                        }
                    }
                }
                
                // Fallback genérico se o janelamento DICOM for inválido
                if ww <= 0 {
                    wc = 128.0
                    ww = 256.0
                    print("❌ Janelamento DICOM inválido. Aplicando fallback genérico (W=\(ww), L=\(wc))")
                } else {
                    print("✅ Usando janelamento DICOM padrão (W=\(ww), L=\(wc))")
                }
            }
        }
        
        // Convert HU values to pixel values using rescale slope/intercept
        // This is critical for CT images where the values are in Hounsfield Units
        let pixelCenter = (wc - rescaleIntercept) / rescaleSlope
        let pixelWidth = ww / rescaleSlope
        
        // Process 16-bit grayscale images (most common DICOM format)
        if samplesPerPixel == 1 && bitDepth == 16 {
            // OPTIMIZATION: Use downsampled pixels for thumbnails
            // This avoids reading millions of pixels for large X-ray images
            if let (downsampledPixels, thumbWidth, thumbHeight) = decoder.getDownsampledPixels16(maxDimension: 150) {
                let pixelCount = thumbWidth * thumbHeight
                let pixels8 = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
                defer { pixels8.deallocate() }
                
                // Apply window/level transformation using pixel values (not HU)
                let minLevel = pixelCenter - pixelWidth / 2.0
                let maxLevel = pixelCenter + pixelWidth / 2.0
                let range = maxLevel - minLevel
                let factor = (range <= 0) ? 0 : 255.0 / range
                
                for i in 0..<pixelCount {
                    let pixelValue = Double(downsampledPixels[i])
                    let normalizedValue = (pixelValue - minLevel) * factor
                    let clampedValue = max(0.0, min(255.0, normalizedValue))
                    pixels8[i] = UInt8(clampedValue)
                }
                
                return createThumbnailUIImage(from: pixels8, width: thumbWidth, height: thumbHeight, isGrayscale: true)
            }
            
            // Fallback to full resolution if downsampling fails
            if let pixels16 = decoder.getPixels16() {
                let pixelCount = width * height
                let pixels8 = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
                defer { pixels8.deallocate() }
                
                // Apply window/level transformation using pixel values (not HU)
                let minLevel = pixelCenter - pixelWidth / 2.0
                let maxLevel = pixelCenter + pixelWidth / 2.0
                let range = maxLevel - minLevel
                let factor = (range <= 0) ? 0 : 255.0 / range
                
                for i in 0..<pixelCount {
                    let pixelValue = Double(pixels16[i])
                    let normalizedValue = (pixelValue - minLevel) * factor
                    let clampedValue = max(0.0, min(255.0, normalizedValue))
                    pixels8[i] = UInt8(clampedValue)
                }
                
                return createThumbnailUIImage(from: pixels8, width: width, height: height, isGrayscale: true)
            }
        }
        
        // Process 8-bit grayscale images
        if samplesPerPixel == 1 && bitDepth == 8, let pixels8 = decoder.getPixels8() {
            // For 8-bit images, also apply transformation using pixel values
            let pixelCount = width * height
            let transformedPixels = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
            defer { transformedPixels.deallocate() }
            
            let minLevel = pixelCenter - pixelWidth / 2.0
            let maxLevel = pixelCenter + pixelWidth / 2.0
            let range = maxLevel - minLevel
            let factor = (range <= 0) ? 0 : 255.0 / range
            
            for i in 0..<pixelCount {
                let pixelValue = Double(pixels8[i])
                let normalizedValue = (pixelValue - minLevel) * factor
                let clampedValue = max(0.0, min(255.0, normalizedValue))
                transformedPixels[i] = UInt8(clampedValue)
            }
            
            return createThumbnailUIImage(from: transformedPixels, width: width, height: height, isGrayscale: true)
        }
        
        // Process RGB 24-bit images (like ultrasound)
        if samplesPerPixel == 3 && bitDepth == 8, let pixels24 = decoder.getPixels24() {
            // RGB images typically don't need window/level adjustment
            return createThumbnailUIImage(from: pixels24, width: width, height: height, isGrayscale: false, bytesPerPixel: 3)
        }
        
        print("❌ generateThumbnailImage: Unsupported image format for thumbnail.")
        return nil
    }
    
    // Helper method to create UIImage from pixel data
    private func createThumbnailUIImage(from pixels: UnsafePointer<UInt8>, width: Int, height: Int, isGrayscale: Bool, bytesPerPixel: Int = 1) -> UIImage? {
        let colorSpace: CGColorSpace
        let bitmapInfo: CGBitmapInfo
        let actualBytesPerPixel: Int
        
        if isGrayscale {
            colorSpace = CGColorSpaceCreateDeviceGray()
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            actualBytesPerPixel = 1
        } else if bytesPerPixel == 3 {
            // Convert RGB to RGBA for CGImage
            colorSpace = CGColorSpaceCreateDeviceRGB()
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
            actualBytesPerPixel = 4
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            actualBytesPerPixel = 4
        }
        
        let bytesPerRow = width * actualBytesPerPixel
        let totalBytes = bytesPerRow * height
        
        // Create data buffer
        var imageData: Data
        
        if isGrayscale {
            // Direct copy for grayscale
            imageData = Data(bytes: pixels, count: width * height)
        } else if bytesPerPixel == 3 {
            // Convert RGB24 to RGBA32
            var rgbaData = Data(capacity: width * height * 4)
            for i in 0..<(width * height) {
                rgbaData.append(pixels[i * 3])      // R
                rgbaData.append(pixels[i * 3 + 1])  // G
                rgbaData.append(pixels[i * 3 + 2])  // B
                rgbaData.append(255)                 // A
            }
            imageData = rgbaData
        } else {
            imageData = Data(bytes: pixels, count: totalBytes)
        }
        
        guard let provider = CGDataProvider(data: imageData as CFData) else { return nil }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: actualBytesPerPixel * 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        
        let originalImage = UIImage(cgImage: cgImage)
        
        // Resize to thumbnail size (150x150)
        let maxSize = CGSize(width: 150, height: 150)
        return resizeImage(originalImage, to: maxSize)
    }
    
    // Helper method to resize image
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
}

// MARK: - View Integration Bridge

@objc public class DicomViewBridge: NSObject {
    
    private let dicomView: DCMImgView
    
    @MainActor
    public init(frame: CGRect) {
        self.dicomView = DCMImgView(frame: frame)
        super.init()
    }
    
    public func getView() -> UIView {
        return dicomView
    }
    
    public func setDicomDecoder(_ decoder: DCMDecoder) {
        // Bridge method to connect Swift bridge with Swift view
        // The DCMImgView now handles DicomDecoder directly
    }
}

// MARK: - Convenience Extensions

extension Result {
    public var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
