//
//  CompressedPixelRouter.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/14.
//
//  Centralized router for DICOM compressed pixel data decoding.
//  Routes different Transfer Syntaxes to appropriate decoders.
//

import Foundation
import CoreGraphics
#if canImport(os)
import os
import os.signpost
#endif

/// Centralized router for compressed pixel data decoding
public enum CompressedPixelRouter {
    
    /// Decode compressed pixel data based on Transfer Syntax
    /// - Parameters:
    ///   - dataset: DICOM dataset containing pixel data
    ///   - frameIndex: Frame index to decode (0-based)
    /// - Returns: Decoded frame with pixel data
    /// - Throws: PixelServiceError if decoding fails
    public static func decodeCompressedFrame(from dataset: DataSet, frameIndex: Int) throws -> DecodedFrame {
        guard let transferSyntax = dataset.transferSyntax else {
            throw PixelServiceError.invalidDataset
        }
        
        let debug = UserDefaults.standard.bool(forKey: "settings.debugLogsEnabled")
        let t0 = CFAbsoluteTimeGetCurrent()
        
#if canImport(os)
        let perf = UserDefaults.standard.bool(forKey: "settings.perfMetricsEnabled")
        let spLog = OSLog(subsystem: "com.isis.dicomviewer", category: .pointsOfInterest)
        let spid = OSSignpostID(log: spLog)
        if perf, #available(iOS 14.0, macOS 11.0, *) {
            os_signpost(.begin, log: spLog, name: "CompressedPixelRouter.decode", signpostID: spid, 
                       "transferSyntax=%{public}s frameIndex=%d", transferSyntax.tsUID, frameIndex)
            defer { os_signpost(.end, log: spLog, name: "CompressedPixelRouter.decode", signpostID: spid) }
        }
#endif
        
        // Route based on Transfer Syntax
        switch transferSyntax.tsUID {
        case let uid where transferSyntax.isJPEG2000Part1:
            return try decodeJPEG2000Part1(dataset: dataset, frameIndex: frameIndex, debug: debug, t0: t0)
            
        case let uid where transferSyntax.isHTJ2K:
            return try decodeHTJ2K(dataset: dataset, frameIndex: frameIndex, debug: debug, t0: t0)
            
        case let uid where transferSyntax.isJPEGBaselineOrExtended:
            return try decodeJPEGBaseline(dataset: dataset, frameIndex: frameIndex, debug: debug, t0: t0)
            
        case let uid where transferSyntax.isRLE:
            return try decodeRLE(dataset: dataset, frameIndex: frameIndex, debug: debug, t0: t0)
            
        case let uid where transferSyntax.isJPEGLS:
            return try decodeJPEGLS(dataset: dataset, frameIndex: frameIndex, debug: debug, t0: t0)
            
        default:
            throw PixelServiceError.invalidDataset
        }
    }
}

// MARK: - Individual Decoder Methods

private extension CompressedPixelRouter {
    
    /// Decode JPEG 2000 Part 1 (UIDs 1.2.840.10008.1.2.4.90 and 1.2.840.10008.1.2.4.91)
    static func decodeJPEG2000Part1(dataset: DataSet, frameIndex: Int, debug: Bool, t0: CFAbsoluteTime) throws -> DecodedFrame {
        guard let element = dataset.element(forTagName: "PixelData") as? PixelSequence else {
            throw PixelServiceError.missingPixelData
        }
        
#if canImport(os)
        let perf = UserDefaults.standard.bool(forKey: "settings.perfMetricsEnabled")
        let spLog = OSLog(subsystem: "com.isis.dicomviewer", category: .pointsOfInterest)
        let spid = OSSignpostID(log: spLog)
        if perf, #available(iOS 14.0, macOS 11.0, *) {
            os_signpost(.begin, log: spLog, name: "CompressedPixelRouter.JPEG2000", signpostID: spid)
            defer { os_signpost(.end, log: spLog, name: "CompressedPixelRouter.JPEG2000", signpostID: spid) }
        }
#endif
        
        guard let codestream = try? element.frameData(at: frameIndex) else {
            throw PixelServiceError.missingPixelData
        }
        
        // Extract metadata
        let rows = Int(dataset.integer16(forTag: "Rows") ?? 0)
        let cols = Int(dataset.integer16(forTag: "Columns") ?? 0)
        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let bitsAllocatedTag = Int(dataset.integer16(forTag: "BitsAllocated") ?? 0)
        let pi = dataset.string(forTag: "PhotometricInterpretation")
        let sop = dataset.string(forTag: "SOPInstanceUID")
        
        // Prefer native decoder (OpenJPH) when requested for high bit-depth streams.
        let preferNativeDecode = (UserDefaults.standard.object(forKey: "settings.decoderPrefer16Bit") as? Bool) ?? true
        if preferNativeDecode,
           let native = J2KNativeDecoder.decode(codestream) {
            if native.components == 1, let p16 = native.pixels16, native.bitsPerSample > 8 {
                let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
                let p16Out: [UInt16] = mono1 ? p16.map { 0xFFFF &- $0 } : p16
                let bits = bitsAllocatedTag > 0 ? bitsAllocatedTag : native.bitsPerSample
                let out = DecodedFrame(id: sop, width: native.width, height: native.height, bitsAllocated: bits,
                                       pixels8: nil, pixels16: p16Out,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[CompressedPixelRouter] J2K native decode dt=\(String(format: "%.1f", dt)) ms size=\(native.width)x\(native.height)")
                }
                return out
            } else if native.components == 3, let rgb = native.pixels8 {
                let out = DecodedFrame(id: sop, width: native.width, height: native.height, bitsAllocated: 8,
                                       pixels8: rgb, pixels16: nil,
                                       rescaleSlope: 1.0, rescaleIntercept: 0.0,
                                       photometricInterpretation: "RGB")
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[CompressedPixelRouter] J2K native RGB decode dt=\(String(format: "%.1f", dt)) ms size=\(native.width)x\(native.height)")
                }
                return out
            }
        }
        
        // Use ImageIO decoder
        let j2k = try JPEG2000Decoder.decodeCodestream(codestream)
        
        if j2k.bitsPerComponent > 8 && j2k.components == 1 {
            // 16-bit grayscale - reconstruct from 8-bit
            guard let px8raw = extract8(j2k.cgImage) else { throw PixelServiceError.missingPixelData }
            let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
            let p8Out: [UInt8] = mono1 ? px8raw.map { 255 &- $0 } : px8raw
            let p16Out = reconstruct16From8(p8Out, slope: slope, intercept: intercept)
            
            let out = DecodedFrame(id: sop, width: j2k.width, height: j2k.height, bitsAllocated: 16,
                                   pixels8: nil, pixels16: p16Out,
                                   rescaleSlope: slope, rescaleIntercept: intercept,
                                   photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                print("[CompressedPixelRouter] J2K 16-bit reconstructed dt=\(String(format: "%.1f", dt)) ms size=\(j2k.width)x\(j2k.height)")
            }
            return out
        } else if j2k.components == 1 {
            // 8-bit grayscale
            guard let px8raw = extract8(j2k.cgImage) else { throw PixelServiceError.missingPixelData }
            let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
            let p8Out: [UInt8] = mono1 ? px8raw.map { 255 &- $0 } : px8raw
            
            let out = DecodedFrame(id: sop, width: j2k.width, height: j2k.height, bitsAllocated: 8,
                                   pixels8: p8Out, pixels16: nil,
                                   rescaleSlope: slope, rescaleIntercept: intercept,
                                   photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                print("[CompressedPixelRouter] J2K 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(j2k.width)x\(j2k.height)")
            }
            return out
        } else {
            // Color: return interleaved RGB8
            guard let rgb = extractRGB8(j2k.cgImage) else { throw PixelServiceError.missingPixelData }
            let out = DecodedFrame(id: sop, width: j2k.width, height: j2k.height, bitsAllocated: 8,
                                   pixels8: rgb, pixels16: nil,
                                   rescaleSlope: 1.0, rescaleIntercept: 0.0,
                                   photometricInterpretation: "RGB")
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                print("[CompressedPixelRouter] J2K RGB decode dt=\(String(format: "%.1f", dt)) ms size=\(j2k.width)x\(j2k.height)")
            }
            return out
        }
    }
    
    /// Decode HTJ2K (High-Throughput JPEG 2000) - currently unsupported
    static func decodeHTJ2K(dataset: DataSet, frameIndex: Int, debug: Bool, t0: CFAbsoluteTime) throws -> DecodedFrame {
        guard let element = dataset.element(forTagName: "PixelData") as? PixelSequence else {
            throw PixelServiceError.missingPixelData
        }
        guard let codestream = try? element.frameData(at: frameIndex) else {
            throw PixelServiceError.missingPixelData
        }

        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let bitsAllocatedTag = Int(dataset.integer16(forTag: "BitsAllocated") ?? 0)
        let pi = dataset.string(forTag: "PhotometricInterpretation")
        let sop = dataset.string(forTag: "SOPInstanceUID")
        let preferNativeDecode = (UserDefaults.standard.object(forKey: "settings.decoderPrefer16Bit") as? Bool) ?? true

        guard preferNativeDecode, let native = J2KNativeDecoder.decode(codestream) else {
            if debug { print("[CompressedPixelRouter] HTJ2K native decoder unavailable") }
            throw PixelServiceError.missingPixelData
        }

        if native.components == 1, let pixels16 = native.pixels16 {
            let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
            let p16Out: [UInt16] = mono1 ? pixels16.map { 0xFFFF &- $0 } : pixels16
            let bits = bitsAllocatedTag > 0 ? bitsAllocatedTag : max(16, native.bitsPerSample)
            let out = DecodedFrame(id: sop, width: native.width, height: native.height, bitsAllocated: bits,
                                   pixels8: nil, pixels16: p16Out,
                                   rescaleSlope: slope, rescaleIntercept: intercept,
                                   photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                print("[CompressedPixelRouter] HTJ2K native decode dt=\(String(format: "%.1f", dt)) ms size=\(native.width)x\(native.height)")
            }
            return out
        }

        if native.components == 1, let pixels8 = native.pixels8 {
            let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
            let p8Out: [UInt8] = mono1 ? pixels8.map { 255 &- $0 } : pixels8
            let out = DecodedFrame(id: sop, width: native.width, height: native.height, bitsAllocated: 8,
                                   pixels8: p8Out, pixels16: nil,
                                   rescaleSlope: slope, rescaleIntercept: intercept,
                                   photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                print("[CompressedPixelRouter] HTJ2K native 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(native.width)x\(native.height)")
            }
            return out
        }

        if native.components == 3, let rgb = native.pixels8 {
            let out = DecodedFrame(id: sop, width: native.width, height: native.height, bitsAllocated: 8,
                                   pixels8: rgb, pixels16: nil,
                                   rescaleSlope: 1.0, rescaleIntercept: 0.0,
                                   photometricInterpretation: "RGB")
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                print("[CompressedPixelRouter] HTJ2K native RGB decode dt=\(String(format: "%.1f", dt)) ms size=\(native.width)x\(native.height)")
            }
            return out
        }

        if debug {
            print("[CompressedPixelRouter] HTJ2K native decoder returned unsupported format")
        }
        throw PixelServiceError.missingPixelData
    }
    
    /// Decode JPEG Baseline/Extended
    static func decodeJPEGBaseline(dataset: DataSet, frameIndex: Int, debug: Bool, t0: CFAbsoluteTime) throws -> DecodedFrame {
        guard let element = dataset.element(forTagName: "PixelData") as? PixelSequence else {
            throw PixelServiceError.missingPixelData
        }
        
        guard let jpegData = try? element.frameData(at: frameIndex) else {
            throw PixelServiceError.missingPixelData
        }
        
        // Extract metadata
        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let pi = dataset.string(forTag: "PhotometricInterpretation")
        let sop = dataset.string(forTag: "SOPInstanceUID")
        
        do {
            let cg = try JPEGBaselineDecoder.decode(jpegData)
            if cg.bitsPerComponent > 8 {
                if debug { print("[CompressedPixelRouter] JPEG 12-bit unsupported on this platform") }
                throw PixelServiceError.missingPixelData
            }
            guard let px8 = extract8(cg) else { throw PixelServiceError.missingPixelData }
            let out = DecodedFrame(id: sop, width: cg.width, height: cg.height, bitsAllocated: 8,
                                   pixels8: px8, pixels16: nil,
                                   rescaleSlope: slope, rescaleIntercept: intercept,
                                   photometricInterpretation: pi)
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                print("[CompressedPixelRouter] JPEG 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cg.width)x\(cg.height)")
            }
            return out
        } catch {
            if debug { print("[CompressedPixelRouter] JPEG decode failed: \(error)") }
            throw PixelServiceError.missingPixelData
        }
    }
    
    /// Decode RLE Lossless
    static func decodeRLE(dataset: DataSet, frameIndex: Int, debug: Bool, t0: CFAbsoluteTime) throws -> DecodedFrame {
        guard let element = dataset.element(forTagName: "PixelData") as? PixelSequence else {
            throw PixelServiceError.missingPixelData
        }
        
        guard let rleData = try? element.frameData(at: frameIndex) else {
            throw PixelServiceError.missingPixelData
        }
        
        // Extract metadata
        let rows = Int(dataset.integer16(forTag: "Rows") ?? 0)
        let cols = Int(dataset.integer16(forTag: "Columns") ?? 0)
        let bitsAllocated = Int(dataset.integer16(forTag: "BitsAllocated") ?? 0)
        let spp = Int(dataset.integer16(forTag: "SamplesPerPixel") ?? 1)
        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let pi = dataset.string(forTag: "PhotometricInterpretation")
        let sop = dataset.string(forTag: "SOPInstanceUID")
        
        do {
            let decoded = try RLEDecoder.decode(frameData: rleData, rows: rows, cols: cols, bitsAllocated: bitsAllocated, samplesPerPixel: spp)
            if let p16 = decoded.pixels16 {
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 16,
                                       pixels8: nil, pixels16: p16,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[CompressedPixelRouter] RLE mono16 decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            } else if let p8 = decoded.pixels8 {
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 8,
                                       pixels8: p8, pixels16: nil,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[CompressedPixelRouter] RLE 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            }
            throw PixelServiceError.missingPixelData
        } catch {
            if debug { print("[CompressedPixelRouter] RLE decode failed: \(error)") }
            throw PixelServiceError.missingPixelData
        }
    }
    
    /// Decode JPEG-LS (feature-flagged)
    static func decodeJPEGLS(dataset: DataSet, frameIndex: Int, debug: Bool, t0: CFAbsoluteTime) throws -> DecodedFrame {
        guard let element = dataset.element(forTagName: "PixelData") as? PixelSequence else {
            throw PixelServiceError.missingPixelData
        }
        
        guard let jlsData = try? element.frameData(at: frameIndex) else {
            throw PixelServiceError.missingPixelData
        }
        
        // Extract metadata
        let rows = Int(dataset.integer16(forTag: "Rows") ?? 0)
        let cols = Int(dataset.integer16(forTag: "Columns") ?? 0)
        let bitsAllocated = Int(dataset.integer16(forTag: "BitsAllocated") ?? 0)
        let spp = Int(dataset.integer16(forTag: "SamplesPerPixel") ?? 1)
        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let pi = dataset.string(forTag: "PhotometricInterpretation")
        let sop = dataset.string(forTag: "SOPInstanceUID")
        
        do {
            let result = try JPEGLSDecoder.decode(jlsData, expectedWidth: cols, expectedHeight: rows, expectedComponents: spp, bitsPerSample: bitsAllocated)
            
            if let p16 = result.gray16 {
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 16,
                                       pixels8: nil, pixels16: p16,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[CompressedPixelRouter] JPEG-LS 16-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            } else if let p8 = result.gray8 {
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 8,
                                       pixels8: p8, pixels16: nil,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[CompressedPixelRouter] JPEG-LS 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            } else if let rgb8 = result.rgb8 {
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 8,
                                       pixels8: rgb8, pixels16: nil,
                                       rescaleSlope: 1.0, rescaleIntercept: 0.0,
                                       photometricInterpretation: "RGB")
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[CompressedPixelRouter] JPEG-LS RGB decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            }
            throw PixelServiceError.missingPixelData
        } catch {
            if debug { print("[CompressedPixelRouter] JPEG-LS decode failed: \(error)") }
            throw PixelServiceError.missingPixelData
        }
    }
}

// MARK: - Helper Functions

private extension CompressedPixelRouter {
    
    /// Extract 8-bit grayscale pixels from CGImage
    static func extract8(_ cg: CGImage) -> [UInt8]? {
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
    
    /// Extract RGB8 pixels from CGImage
    static func extractRGB8(_ cg: CGImage) -> [UInt8]? {
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 3
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
    
    /// Reconstruct 16-bit pixels from 8-bit using slope/intercept
    static func reconstruct16From8(_ pixels8: [UInt8], slope: Double, intercept: Double) -> [UInt16] {
        return pixels8.map { p8 in
            let reconstructed = (Double(p8) * slope) + intercept
            return UInt16(max(0, min(65535, reconstructed)))
        }
    }
}
