//
//  DicomImage.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

#if canImport(Accelerate)
import Accelerate
#endif

#if os(macOS)
import Quartz
import AppKit
public typealias UIImage = NSImage
extension NSImage {
    var png: Data? { tiffRepresentation?.bitmap?.png }
}
extension NSBitmapImageRep {
    var png: Data? { representation(using: .png, properties: [:]) }
}
extension Data {
    var bitmap: NSBitmapImageRep? { NSBitmapImageRep(data: self) }
}
#elseif os(iOS)
import UIKit
#endif
/**
 DicomImage is a wrapper that provides images related features for the DICOM standard.
 Please refer to dicomiseasy : http://dicomiseasy.blogspot.com/2012/08/chapter-12-pixel-data.html
 */
public class DicomImage {
    
    /// Color space of the image
    public enum PhotometricInterpretation: String {
        case MONOCHROME1
        case MONOCHROME2
        case PALETTE_COLOR
        case RGB
        case HSV
        case ARGB
        case CMYK
        case YBR_FULL
        case YBR_FULL_422
        case YBR_PARTIAL_422
        case YBR_PARTIAL_420
        case YBR_ICT
        case YBR_RCT
    }
    
    
    /// Indicates if a pixel is signed or unsigned
    public enum PixelRepresentation:Int {
        case Unsigned  = 0
        case Signed    = 1
    }
    
    
    private var dataset:DataSet!
    private var frames:[Data] = []
    
    public var photoInter           = PhotometricInterpretation.RGB
    public var pixelRepresentation  = PixelRepresentation.Unsigned
    public var colorSpace           = CGColorSpaceCreateDeviceRGB()
    
    public var isMultiframe     = false
    public var isMonochrome     = false
    
    public var numberOfFrames   = 0
    public var rows             = 0
    public var columns          = 0
    
    public var windowWidth      = -1
    public var windowCenter     = -1
    public var rescaleSlope     = 1
    public var rescaleIntercept = 0
    
    public var samplesPerPixel  = 0
    public var bitsAllocated    = 0
    public var bitsStored       = 0
    public var bitsPerPixel     = 0
    public var bytesPerRow      = 0
    
    
    
    public init?(_ dataset:DataSet) {
        self.dataset = dataset
        configureMetadata()
        self.loadPixelData()
    }

    /// Initialize a DicomImage by streaming pixel data directly from a DicomInputStream.
    /// - Parameters:
    ///   - stream: The input stream to read from.
    ///   - pixelHandler: Optional handler invoked for each pixel fragment as it is read.
    public init?(stream: DicomInputStream, pixelHandler: ((Data) -> Bool)? = nil) {
        var collected:[Data] = []
        let handler = pixelHandler ?? { fragment in collected.append(fragment); return true }

        guard let ds = try? stream.readDataset(pixelDataHandler: handler) else {
            return nil
        }

        self.dataset = ds
        self.frames = collected
        configureMetadata()

        if frames.isEmpty && self.dataset.hasElement(forTagName: "PixelData") {
            loadPixelData()
        }

        if pixelHandler == nil && numberOfFrames == 0 {
            numberOfFrames = frames.count
        }
    }

    /// Extract important metadata from the dataset and populate image properties.
    private func configureMetadata() {
        if let pi = self.dataset.string(forTag: "PhotometricInterpretation") {
            if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "MONOCHROME1" {
                self.photoInter = .MONOCHROME1
                self.isMonochrome = true

            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "MONOCHROME2" {
                self.photoInter = .MONOCHROME2
                self.isMonochrome = true

            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "ARGB" {
                self.photoInter = .ARGB

            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "RGB" {
                self.photoInter = .RGB
            }
        }

        if let v = self.dataset.integer16(forTag: "Rows") {
            self.rows = Int(v)
        }

        if let v = self.dataset.integer16(forTag: "Columns") {
            self.columns = Int(v)
        }

        if let v = self.dataset.string(forTag: "WindowWidth") {
            self.windowWidth = Int(v) ?? self.windowWidth
        }

        if let v = self.dataset.string(forTag: "WindowCenter") {
            self.windowCenter = Int(v) ?? self.windowCenter
        }

        if let v = self.dataset.string(forTag: "RescaleSlope") {
            self.rescaleSlope = Int(v) ?? self.rescaleSlope
        }

        if let v = self.dataset.string(forTag: "RescaleIntercept") {
            self.rescaleIntercept = Int(v) ?? self.rescaleIntercept
        }

        if let v = self.dataset.integer16(forTag: "BitsAllocated") {
            self.bitsAllocated = Int(v)
        }

        if let v = self.dataset.integer16(forTag: "BitsStored") {
            self.bitsStored = Int(v)
        }

        if let v = self.dataset.integer16(forTag: "SamplesPerPixel") {
            self.samplesPerPixel = Int(v)
        }

        if let v = self.dataset.integer16(forTag: "PixelRepresentation") {
            if v == 0 {
                self.pixelRepresentation = .Unsigned
            } else if v == 1 {
                self.pixelRepresentation = .Signed
            }
        }

        if self.dataset.hasElement(forTagName: "PixelData") {
            self.numberOfFrames = 1
        }

        if let nofString = self.dataset.string(forTag: "NumberOfFrames") {
            if let nof = Int(nofString) {
                self.isMultiframe   = true
                self.numberOfFrames = nof
            }
        }

        Logger.verbose("  -> rows : \(self.rows)")
        Logger.verbose("  -> columns : \(self.columns)")
        Logger.verbose("  -> photoInter : \(photoInter)")
        Logger.verbose("  -> isMultiframe : \(isMultiframe)")
        Logger.verbose("  -> numberOfFrames : \(numberOfFrames)")
        Logger.verbose("  -> samplesPerPixel : \(samplesPerPixel)")
        Logger.verbose("  -> bitsAllocated : \(bitsAllocated)")
        Logger.verbose("  -> bitsStored : \(bitsStored)")
    }

#if os(macOS)
    /**
     Creates an `NSImage` for a given frame
     - Important: only for `macOS`
     */
    // Replace the existing image(forFrame:) method(s) with this single, powerful one.
    public func image(forFrame frame: Int = 0, wwl: (width: Int, center: Int)? = nil, inverted: Bool = false) -> UIImage? {
        if !frames.indices.contains(frame) {
            Logger.error("   -> No such frame (\(frame))")
            return nil
        }
        
        let data = self.frames[frame]
        
        // For uncompressed monochrome images, use our new rendering pipeline
        if isMonochrome, TransferSyntax.transfersSyntaxes.contains(self.dataset.transferSyntax.tsUID) {
            let effectiveWidth = wwl?.width ?? self.windowWidth
            let effectiveCenter = wwl?.center ?? self.windowCenter
            
            return renderFrame(
                pixelData: data,
                windowWidth: effectiveWidth,
                windowCenter: effectiveCenter,
                rescaleSlope: self.rescaleSlope,
                rescaleIntercept: self.rescaleIntercept,
                photometricInterpretation: self.photoInter.rawValue,
                inverted: inverted
            )
        }
        // For compressed images (like JPEG), create the image directly from the data
        else if !TransferSyntax.transfersSyntaxes.contains(self.dataset.transferSyntax.tsUID) {
            #if os(macOS)
            return NSImage(data: data)
            #elseif os(iOS)
            return UIImage(data: data)
            #endif
        }
        
        // Fallback for other formats (e.g., RGB color)
        let size = CGSize(width: self.columns, height: self.rows)
        if let cgim = self.imageFromPixels(size: size, pixels: data.toUnsigned8Array(), width: self.columns, height: self.rows) {
            #if os(macOS)
            return NSImage(cgImage: cgim, size: size)
            #elseif os(iOS)
            return UIImage(cgImage: cgim)
            #endif
        }

        return nil
    }
    
#elseif os(iOS)
    /**
     Creates an `UIImage` for a given frame
     - Important: only for `iOS`
     */
    public func image(forFrame frame: Int = 0, wwl: (width: Int, center: Int)? = nil, inverted: Bool = false) -> UIImage? {
        if !frames.indices.contains(frame) {
            Logger.error("   -> No such frame (\(frame))")
            return nil
        }
        
        let data = self.frames[frame]
        
        // For uncompressed monochrome images, use our new rendering pipeline
        if isMonochrome, TransferSyntax.transfersSyntaxes.contains(self.dataset.transferSyntax.tsUID) {
            let effectiveWidth = wwl?.width ?? self.windowWidth
            let effectiveCenter = wwl?.center ?? self.windowCenter
            
            return renderFrame(
                pixelData: data,
                windowWidth: effectiveWidth,
                windowCenter: effectiveCenter,
                rescaleSlope: self.rescaleSlope,
                rescaleIntercept: self.rescaleIntercept,
                photometricInterpretation: self.photoInter.rawValue,
                inverted: inverted
            )
        }
        // For compressed images (like JPEG), create the image directly from the data
        else if !TransferSyntax.transfersSyntaxes.contains(self.dataset.transferSyntax.tsUID) {
            #if os(macOS)
            return NSImage(data: data)
            #elseif os(iOS)
            return UIImage(data: data)
            #endif
        }
        
        // Fallback for other formats (e.g., RGB color)
        let size = CGSize(width: self.columns, height: self.rows)
        if let cgim = self.imageFromPixels(size: size, pixels: data.toUnsigned8Array(), width: self.columns, height: self.rows) {
            #if os(macOS)
            return NSImage(cgImage: cgim, size: size)
            #elseif os(iOS)
            return UIImage(cgImage: cgim)
            #endif
        }

        return nil
    }
#endif
    
    
    
    
    
    // MARK: - Private

    private func renderFrame(
        pixelData: Data,
        windowWidth: Int,
        windowCenter: Int,
        rescaleSlope: Int,
        rescaleIntercept: Int,
        photometricInterpretation: String,
        inverted: Bool
    ) -> UIImage? {

        let pixelCount = self.rows * self.columns
        var buffer8bit = [UInt8](repeating: 0, count: pixelCount)

        let ww = Float(windowWidth > 0 ? windowWidth : 1)
        let wc = Float(windowCenter)
        let slope = Float(rescaleSlope)
        let intercept = Float(rescaleIntercept)

        let lowerBound = wc - ww / 2.0
        let upperBound = wc + ww / 2.0

        let shouldInvert = (photometricInterpretation == "MONOCHROME1" && !inverted) ||
                           (photometricInterpretation == "MONOCHROME2" && inverted)

#if canImport(Accelerate)
        var floatPixels = [Float](repeating: 0, count: pixelCount)
        pixelData.withUnsafeBytes { rawBufferPointer in
            if self.bitsAllocated > 8 {
                if self.pixelRepresentation == .Signed {
                    let src = rawBufferPointer.bindMemory(to: Int16.self)
                    vDSP.integerToFloatingPoint(src, result: &floatPixels)
                } else {
                    let src = rawBufferPointer.bindMemory(to: UInt16.self)
                    vDSP.integerToFloatingPoint(src, result: &floatPixels)
                }
            } else {
                let src = rawBufferPointer.bindMemory(to: UInt8.self)
                vDSP.integerToFloatingPoint(src, result: &floatPixels)
            }
        }

        var m = slope
        var b = intercept
        vDSP_vsmsa(floatPixels, 1, &m, &b, &floatPixels, 1, vDSP_Length(pixelCount))

        var lo = lowerBound
        var hi = upperBound
        vDSP_vclip(floatPixels, 1, &lo, &hi, &floatPixels, 1, vDSP_Length(pixelCount))

        var negLo = -lo
        vDSP_vsadd(floatPixels, 1, &negLo, &floatPixels, 1, vDSP_Length(pixelCount))

        var scale = Float(255) / ww
        vDSP_vsmul(floatPixels, 1, &scale, &floatPixels, 1, vDSP_Length(pixelCount))

        if shouldInvert {
            var minusOne: Float = -1
            var maxVal: Float = 255
            vDSP_vsmsa(floatPixels, 1, &minusOne, &maxVal, &floatPixels, 1, vDSP_Length(pixelCount))
        }

        vDSP_vfixu8(floatPixels, 1, &buffer8bit, 1, vDSP_Length(pixelCount))
#else
        let wwD = Double(ww)
        let slopeD = Double(slope)
        let interceptD = Double(intercept)
        let lowerBoundD = Double(lowerBound)
        let upperBoundD = Double(upperBound)

        pixelData.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            if self.bitsAllocated > 8 {
                if self.pixelRepresentation == .Signed {
                    let pixelPtr = rawBufferPointer.bindMemory(to: Int16.self).baseAddress!
                    for i in 0..<pixelCount {
                        let rawValue = Double(pixelPtr[i].littleEndian)
                        let modalityValue = rawValue * slopeD + interceptD

                        if modalityValue <= lowerBoundD { buffer8bit[i] = 0 }
                        else if modalityValue >= upperBoundD { buffer8bit[i] = 255 }
                        else { buffer8bit[i] = UInt8(((modalityValue - lowerBoundD) / wwD) * 255.0) }
                    }
                } else { // Unsigned
                    let pixelPtr = rawBufferPointer.bindMemory(to: UInt16.self).baseAddress!
                    for i in 0..<pixelCount {
                        let rawValue = Double(pixelPtr[i].littleEndian)
                        let modalityValue = rawValue * slopeD + interceptD

                        if modalityValue <= lowerBoundD { buffer8bit[i] = 0 }
                        else if modalityValue >= upperBoundD { buffer8bit[i] = 255 }
                        else { buffer8bit[i] = UInt8(((modalityValue - lowerBoundD) / wwD) * 255.0) }
                    }
                }
            } else { // 8-bit
                let pixelPtr = rawBufferPointer.bindMemory(to: UInt8.self).baseAddress!
                for i in 0..<pixelCount {
                    let rawValue = Double(pixelPtr[i])
                    let modalityValue = rawValue * slopeD + interceptD

                    if modalityValue <= lowerBoundD { buffer8bit[i] = 0 }
                    else if modalityValue >= upperBoundD { buffer8bit[i] = 255 }
                    else { buffer8bit[i] = UInt8(((modalityValue - lowerBoundD) / wwD) * 255.0) }
                }
            }
        }

        if shouldInvert {
            for i in 0..<pixelCount {
                buffer8bit[i] = 255 - buffer8bit[i]
            }
        }
#endif
        
        guard let provider = CGDataProvider(data: Data(buffer8bit) as CFData) else { return nil }
        
        let cgImage = CGImage(
            width: self.columns,
            height: self.rows,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: self.columns,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
        
        guard let finalCGImage = cgImage else { return nil }
        
        #if os(macOS)
        return NSImage(cgImage: finalCGImage, size: NSSize(width: self.columns, height: self.rows))
        #elseif os(iOS)
        return UIImage(cgImage: finalCGImage)
        #endif
    }

    private func imageFromPixels(size: CGSize, pixels: UnsafeRawPointer, width: Int, height: Int) -> CGImage? {
        var bitmapInfo:CGBitmapInfo = []
        
        if self.isMonochrome {
            self.colorSpace = CGColorSpaceCreateDeviceGray()
        } else {
            if self.photoInter != .ARGB {
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            }
        }
        
        self.bitsPerPixel = self.samplesPerPixel * self.bitsAllocated
        self.bytesPerRow  = width * (self.bitsAllocated / 8) * samplesPerPixel
        let dataLength = height * bytesPerRow
        
        let imageData = NSData(bytes: pixels, length: dataLength)
        let providerRef = CGDataProvider(data: imageData)
        
        if providerRef == nil {
            Logger.error("  -> FATAL: cannot allocate bitmap properly")
            return nil
        }
        
        if let cgim = CGImage(
            width: width,
            height: height,
            bitsPerComponent: self.bitsAllocated,
            bitsPerPixel: self.bitsPerPixel,
            bytesPerRow: self.bytesPerRow,
            space: self.colorSpace,
            bitmapInfo: bitmapInfo,
            provider: providerRef!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) {
            return cgim
        }
        
        Logger.error("  -> FATAL: invalid bitmap for CGImage")
        return nil
    }
    
    
    
    
    private func processPresentationValues(pixels: [UInt8]) -> [UInt8] {
        var output:[UInt8] = pixels
        
        Logger.verbose("  -> rescaleIntercept : \(self.rescaleIntercept)")
        Logger.verbose("  -> rescaleSlope : \(self.rescaleSlope)")
        Logger.verbose("  -> windowCenter : \(self.windowCenter)")
        Logger.verbose("  -> windowWidth : \(self.windowWidth)")
        
        // sanity checks
        if rescaleIntercept != 0 || rescaleSlope != 1 {
            // pixel_data.collect!{|x| (slope * x) + intercept}
            output = pixels.map { (b) -> UInt8 in
                (UInt8(rescaleSlope) * b) + UInt8(rescaleIntercept)
            }
        }
        
        if self.windowWidth != -1 && self.windowCenter != -1 {
            let low = windowCenter - windowWidth / 2
            let high = windowCenter + windowWidth / 2
            
            Logger.verbose("  -> low  : \(low)")
            Logger.verbose("  -> high : \(high)")

            for i in 0..<output.count {
                if output[i] < low {
                    output[i] = UInt8(low)
                } else if output[i] > high {
                    output[i] = UInt8(high)
                }
            }
        }
        
        return output
    }
    
    /**
     Writes a dicom image to a png file, given a path, and a basename for the file
     There might be multiple frames, hence the base in basename
     files will be named like this: `<baseName>_0.png`, `<baseName>_1.png`, etc
     
     If the basename is nil, an uid is generated
     
     - Parameters:
        - path: where to save the PNG
        - baseName: the (root) name of the PNG file
     */
    public func toPNG(path: String, baseName: String?) {
        
        let baseFilename: String
        if baseName == nil {
            baseFilename = UID.generate() + "_"
        } else {
            baseFilename = baseName! + "_"
        }
        
        for frame in 0..<numberOfFrames {
            if let image = image(forFrame: frame) {
                
                var url = URL(fileURLWithPath: path)
                url.appendPathComponent(baseFilename + String(frame) + ".png")
                Logger.debug(url.absoluteString)
                
                // image() gives different class following the OS
                #if os(macOS)
                image.setName(url.absoluteString)
                if let data = image.png {
                    try? data.write(to: url)
                }
                #elseif os(iOS)
                if let data = image.pngData() {
                    do {
                        try? data.write(to: url)
                    } catch let error as NSError {
                        print(error)
                    }
                }
                #endif
            }
        }
    }
    
    /// Load all pixel data into memory. For large multi-frame images this may be expensive.
    /// Consider using ``streamFrames(_:)`` to iterate frames without retaining them all.
    public func loadPixelData() {
        self.frames.removeAll(keepingCapacity: true)
        streamFrames { data in
            self.frames.append(data)
            return true
        }
    }

    /// Incrementally iterate over pixel data frames without storing them.
    /// - Parameter handler: Called once per frame. Return `false` to stop iteration early.
    /// - Note: For single-frame images the handler is still invoked once.
    public func streamFrames(_ handler: (Data) -> Bool) {
        guard let pixelDataElement = self.dataset.element(forTagName: "PixelData") else { return }

        if let seq = pixelDataElement as? DataSequence {
            for item in seq.items {
                if let data = item.data, item.length > 128 {
                    if !handler(data) { break }
                }
            }
            return
        }

        if self.numberOfFrames > 1 {
            let frameSize = pixelDataElement.length / self.numberOfFrames
            let bytes = pixelDataElement.data.toUnsigned8Array()
            var offset = 0
            for _ in 0..<self.numberOfFrames {
                let end = min(offset + frameSize, bytes.count)
                let chunk = Data(bytes[offset..<end])
                offset += frameSize
                if !handler(chunk) { break }
            }
        } else if let data = pixelDataElement.data {
            _ = handler(data)
        }
    }
}
