//
//  PixelService.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import Foundation
import CoreGraphics
#if canImport(os)
import os
import os.signpost
#endif

/// A lightweight, reusable pixel decoding surface for applications.
/// Centralizes first-frame extraction and basic pixel buffer preparation.
public struct DecodedFrame: Sendable {
    public let id: String?
    public let width: Int
    public let height: Int
    public let bitsAllocated: Int
    public let pixels8: [UInt8]?
    public let pixels16: [UInt16]?
    public let rescaleSlope: Double
    public let rescaleIntercept: Double
    public let photometricInterpretation: String?

    public init(id: String?, width: Int, height: Int, bitsAllocated: Int,
                pixels8: [UInt8]?, pixels16: [UInt16]?,
                rescaleSlope: Double, rescaleIntercept: Double,
                photometricInterpretation: String?) {
        self.id = id
        self.width = width
        self.height = height
        self.bitsAllocated = bitsAllocated
        self.pixels8 = pixels8
        self.pixels16 = pixels16
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.photometricInterpretation = photometricInterpretation
    }
}

public enum PixelServiceError: Error, LocalizedError {
    case invalidDataset
    case missingPixelData
    case invalidDimensions

    public var errorDescription: String? {
        switch self {
        case .invalidDataset: return "Invalid dataset"
        case .missingPixelData: return "Missing PixelData"
        case .invalidDimensions: return "Invalid Rows/Columns"
        }
    }
}

@available(iOS 14.0, macOS 11.0, *)
public final class PixelService: @unchecked Sendable {
    public static let shared = PixelService()
    private init() {}
#if canImport(os)
    private let oslog = os.Logger(subsystem: "com.isis.dicomviewer", category: "PixelService")
    private let spLog = OSLog(subsystem: "com.isis.dicomviewer", category: .pointsOfInterest)
#else
    private struct DummyLogger { func debug(_ msg: String) {} }
    private let oslog = DummyLogger()
#endif

    /// Decode a specific frame from the dataset into a display-ready buffer.
    /// - Parameters:
    ///   - dataset: DICOM dataset containing pixel data
    ///   - frameIndex: Frame index to decode (0-based)
    /// - Returns: Decoded frame with pixel data
    /// - Note: For color images this returns raw 8-bit data; consumers may convert as needed.
    @available(iOS 14.0, macOS 11.0, *)
    public func decodeFrame(from dataset: DataSet, frameIndex: Int) throws -> DecodedFrame {
        let debug = UserDefaults.standard.bool(forKey: "settings.debugLogsEnabled")
        let t0 = CFAbsoluteTimeGetCurrent()
#if canImport(os)
        let perf = UserDefaults.standard.bool(forKey: "settings.perfMetricsEnabled")
        let spid = OSSignpostID(log: spLog)
        if perf, #available(iOS 14.0, macOS 11.0, *) {
            os_signpost(.begin, log: spLog, name: "PixelService.decodeFrame", signpostID: spid, 
                       "frameIndex=%d", frameIndex)
            defer { os_signpost(.end, log: spLog, name: "PixelService.decodeFrame", signpostID: spid) }
        }
#endif
        var rows = Int(dataset.integer16(forTag: "Rows") ?? 0)
        var cols = Int(dataset.integer16(forTag: "Columns") ?? 0)
        guard rows > 0, cols > 0 else { throw PixelServiceError.invalidDimensions }

        let bitsAllocated = Int(dataset.integer16(forTag: "BitsAllocated") ?? 0)
        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let pi = dataset.string(forTag: "PhotometricInterpretation")
        let sop = dataset.string(forTag: "SOPInstanceUID")

        // JPEG 2000 Part 1 and HTJ2K: decode via JP2+ImageIO, preserve 16 bpc for mono when possible
        if let ts = dataset.transferSyntax, (ts.isJPEG2000Part1 || ts.isHTJ2K),
           let element = dataset.element(forTagName: "PixelData") as? PixelSequence {
            if debug { print("[PixelService] JPEG2000/HTJ2K detected; decoding via ImageIO") }
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.begin, log: spLog, name: "PixelService.frameExtraction", signpostID: spid, 
                           "transferSyntax=%{public}s", ts.tsUID)
            }
#endif
            guard let codestream = try? element.frameData(at: frameIndex) else { 
#if canImport(os)
                if perf, #available(iOS 14.0, macOS 11.0, *) {
                    os_signpost(.end, log: spLog, name: "PixelService.frameExtraction", signpostID: spid)
                }
#endif
                throw PixelServiceError.missingPixelData 
            }
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.end, log: spLog, name: "PixelService.frameExtraction", signpostID: spid)
                os_signpost(.begin, log: spLog, name: "PixelService.imageDecode", signpostID: spid, 
                           "codestreamSize=%d", codestream.count)
            }
#endif
            // Prefer native 16-bit decoder when requested (guarded by compile flag)
            #if DCMSWIFT_ENABLE_NATIVE_J2K
            if UserDefaults.standard.bool(forKey: "settings.decoderPrefer16Bit"),
               let native = J2KNativeDecoder.decodeU16(codestream) {
                rows = native.height
                cols = native.width
                let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
                let p16Out: [UInt16] = mono1 ? native.pixels.map { 0xFFFF &- $0 } : native.pixels
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 16,
                                       pixels8: nil, pixels16: p16Out,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[PixelService] j2k native 16-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            }
            #endif

            let j2k = try JPEG2000Decoder.decodeCodestream(codestream)

            // Use decoded dimensions (authoritative from codestream)
            rows = j2k.height
            cols = j2k.width

            if j2k.bitsPerComponent > 8 && j2k.components == 1 {
                // Prefer raw provider bytes to avoid color management/gamma transforms.
                let px16 = extractGray16Raw(j2k.cgImage) ?? extractGray16Little(j2k.cgImage)
                guard let px16 else { throw PixelServiceError.missingPixelData }
                let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
                let p16Out: [UInt16]
                if mono1 {
                    p16Out = px16.map { 0xFFFF &- $0 }
                } else {
                    p16Out = px16
                }
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 16,
                                       pixels8: nil, pixels16: p16Out,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[PixelService] j2k/htj2k mono16 decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            } else if j2k.components == 1 {
                // 8-bit grayscale
                guard let px8raw = extract8(j2k.cgImage) else { throw PixelServiceError.missingPixelData }
                let mono1 = (pi?.trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1")
                let p8Out: [UInt8] = mono1 ? px8raw.map { 255 &- $0 } : px8raw

                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 8,
                                    pixels8: p8Out, pixels16: nil,
                                    // >>> preserve slope/intercept aqui <<<
                                    rescaleSlope: slope, rescaleIntercept: intercept,
                                    photometricInterpretation: mono1 ? "MONOCHROME2" : pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[PixelService] j2k/htj2k 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
                return out
            } else {
                // Color: return interleaved RGB8
                guard let rgb = extractRGB8(j2k.cgImage) else { throw PixelServiceError.missingPixelData }
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 8,
                                       pixels8: rgb, pixels16: nil,
                                       rescaleSlope: 1.0, rescaleIntercept: 0.0,
                                       photometricInterpretation: "RGB")
#if canImport(os)
                if perf, #available(iOS 14.0, macOS 11.0, *) {
                    os_signpost(.end, log: spLog, name: "PixelService.imageDecode", signpostID: spid)
                }
#endif
                return out
            }
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.end, log: spLog, name: "PixelService.imageDecode", signpostID: spid)
            }
#endif
        }

        // JPEG Baseline/Extended (8-bit baseline, 12-bit likely unsupported on iOS)
        if let ts = dataset.transferSyntax, ts.isJPEGBaselineOrExtended,
           let element = dataset.element(forTagName: "PixelData") as? PixelSequence {
            if debug { print("[PixelService] JPEG Baseline/Extended detected; decoding via ImageIO") }
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.begin, log: spLog, name: "PixelService.frameExtraction", signpostID: spid, 
                           "transferSyntax=%{public}s", ts.tsUID)
            }
#endif
            guard let jpegs = try? element.frameData(at: frameIndex) else { 
#if canImport(os)
                if perf, #available(iOS 14.0, macOS 11.0, *) {
                    os_signpost(.end, log: spLog, name: "PixelService.frameExtraction", signpostID: spid)
                }
#endif
                throw PixelServiceError.missingPixelData 
            }
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.end, log: spLog, name: "PixelService.frameExtraction", signpostID: spid)
                os_signpost(.begin, log: spLog, name: "PixelService.imageDecode", signpostID: spid, 
                           "codestreamSize=%d", jpegs.count)
            }
#endif
            do {
                let cg = try JPEGBaselineDecoder.decode(jpegs)
                // Dimensions from decoded image
                rows = cg.height
                cols = cg.width
                if cg.bitsPerComponent > 8 {
                    // Treat as unsupported for now (12-bit). Let caller surface an error.
                    if debug { print("[PixelService] JPEG 12-bit unsupported on this platform") }
                    throw PixelServiceError.missingPixelData
                }
                guard let px8 = extract8(cg) else { throw PixelServiceError.missingPixelData }
                let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 8,
                                       pixels8: px8, pixels16: nil,
                                       rescaleSlope: slope, rescaleIntercept: intercept,
                                       photometricInterpretation: pi)
                if debug {
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[PixelService] jpeg 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                }
#if canImport(os)
                if perf, #available(iOS 14.0, macOS 11.0, *) {
                    os_signpost(.end, log: spLog, name: "PixelService.imageDecode", signpostID: spid)
                }
#endif
                return out
            } catch {
                if debug { print("[PixelService] JPEG decode failed: \(error)") }
#if canImport(os)
                if perf, #available(iOS 14.0, macOS 11.0, *) {
                    os_signpost(.end, log: spLog, name: "PixelService.imageDecode", signpostID: spid)
                }
#endif
                throw PixelServiceError.missingPixelData
            }
        }

        // JPEG-LS (feature-flagged)
        if let ts = dataset.transferSyntax, ts.isJPEGLS,
           let element = dataset.element(forTagName: "PixelData") as? PixelSequence {
            if debug { print("[PixelService] JPEG-LS detected") }
            guard let jlsData = try? element.frameData(at: frameIndex) else { throw PixelServiceError.missingPixelData }
            do {
                let comps = Int(dataset.integer16(forTag: "SamplesPerPixel") ?? 1)
                let res = try JPEGLSDecoder.decode(jlsData, expectedWidth: cols, expectedHeight: rows, expectedComponents: comps, bitsPerSample: bitsAllocated)
                if let p16 = res.gray16 {
                    let out = DecodedFrame(id: sop, width: res.width, height: res.height, bitsAllocated: 16,
                                           pixels8: nil, pixels16: p16,
                                           rescaleSlope: slope, rescaleIntercept: intercept,
                                           photometricInterpretation: pi)
                    return out
                } else if let p8 = res.gray8 ?? res.rgb8 {
                    let out = DecodedFrame(id: sop, width: res.width, height: res.height, bitsAllocated: 8,
                                           pixels8: p8, pixels16: nil,
                                           rescaleSlope: slope, rescaleIntercept: intercept,
                                           photometricInterpretation: pi)
                    return out
                } else {
                    throw PixelServiceError.missingPixelData
                }
            } catch JPEGLSError.disabled {
                if debug { print("[PixelService] JPEG-LS disabled: set DCMSWIFT_ENABLE_JPEGLS=1 to enable experimental decoder") }
                throw PixelServiceError.missingPixelData
            } catch JPEGLSError.notImplemented {
                if debug { print("[PixelService] JPEG-LS not implemented yet (decoder scaffold in place)") }
                throw PixelServiceError.missingPixelData
            } catch {
                if debug { print("[PixelService] JPEG-LS decode failed: \(error)") }
                throw PixelServiceError.missingPixelData
            }
        }

        // RLE Lossless (Annex G): common cases (mono16, mono8, RGB8)
        if let ts = dataset.transferSyntax, ts.isRLE,
           let element = dataset.element(forTagName: "PixelData") as? PixelSequence {
            if debug { print("[PixelService] RLE detected; decoding") }
            guard let rleData = try? element.frameData(at: frameIndex) else { throw PixelServiceError.missingPixelData }
            let spp = Int(dataset.integer16(forTag: "SamplesPerPixel") ?? 1)
            do {
                let decoded = try RLEDecoder.decode(frameData: rleData, rows: rows, cols: cols, bitsAllocated: bitsAllocated, samplesPerPixel: spp)
                if let p16 = decoded.pixels16 {
                    let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 16,
                                           pixels8: nil, pixels16: p16,
                                           rescaleSlope: slope, rescaleIntercept: intercept,
                                           photometricInterpretation: pi)
                    if debug {
                        let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                        print("[PixelService] rle mono16 decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                    }
                    return out
                } else if let p8 = decoded.pixels8 {
                    let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: 8,
                                           pixels8: p8, pixels16: nil,
                                           rescaleSlope: slope, rescaleIntercept: intercept,
                                           photometricInterpretation: pi)
                    if debug {
                        let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                        print("[PixelService] rle 8-bit decode dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows)")
                    }
                    return out
                }
            } catch {
                if debug { print("[PixelService] RLE decode failed: \(error)") }
                throw PixelServiceError.missingPixelData
            }
        }

#if canImport(os)
        if perf, #available(iOS 14.0, macOS 11.0, *) {
            os_signpost(.begin, log: spLog, name: "PixelService.frameExtraction", signpostID: spid, 
                       "transferSyntax=native")
        }
#endif
        guard let data = pixelDataForFrame(from: dataset, frameIndex: frameIndex) else { 
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.end, log: spLog, name: "PixelService.frameExtraction", signpostID: spid)
            }
#endif
            throw PixelServiceError.missingPixelData 
        }
#if canImport(os)
        if perf, #available(iOS 14.0, macOS 11.0, *) {
            os_signpost(.end, log: spLog, name: "PixelService.frameExtraction", signpostID: spid)
            os_signpost(.begin, log: spLog, name: "PixelService.imageDecode", signpostID: spid, 
                       "dataSize=%d bitsAllocated=%d", data.count, bitsAllocated)
        }
#endif

        if bitsAllocated > 8 {
            let pixels16 = toUInt16ArrayLE(data)
            let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: bitsAllocated,
                                pixels8: nil, pixels16: pixels16,
                                rescaleSlope: slope, rescaleIntercept: intercept,
                                photometricInterpretation: pi)
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                if #available(iOS 14.0, macOS 11.0, *) {
                    oslog.debug("decode16 dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows) bits=\(bitsAllocated)")
                } else {
                    print("[PixelService] decode16 dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows) bits=\(bitsAllocated)")
                }
            }
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.end, log: spLog, name: "PixelService.imageDecode", signpostID: spid)
            }
#endif
            return out
        } else {
            let pixels8 = [UInt8](data)
            let out = DecodedFrame(id: sop, width: cols, height: rows, bitsAllocated: bitsAllocated,
                                pixels8: pixels8, pixels16: nil,
                                rescaleSlope: slope, rescaleIntercept: intercept,
                                photometricInterpretation: pi)
            if debug {
                let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                if #available(iOS 14.0, macOS 11.0, *) {
                    oslog.debug("decode8 dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows) bits=\(bitsAllocated)")
                } else {
                    print("[PixelService] decode8 dt=\(String(format: "%.1f", dt)) ms size=\(cols)x\(rows) bits=\(bitsAllocated)")
                }
            }
#if canImport(os)
            if perf, #available(iOS 14.0, macOS 11.0, *) {
                os_signpost(.end, log: spLog, name: "PixelService.imageDecode", signpostID: spid)
            }
#endif
            return out
        }
    }
    
    /// Decode the first available frame in the dataset into a display-ready buffer.
    /// - Note: For color images this returns raw 8-bit data; consumers may convert as needed.
    @available(iOS 14.0, macOS 11.0, *)
    public func decodeFirstFrame(from dataset: DataSet) throws -> DecodedFrame {
        return try decodeFrame(from: dataset, frameIndex: 0)
    }

    // MARK: - Internals (mirrors common helpers consolidated here)

    private func firstFramePixelData(from dataset: DataSet) -> Data? {
        return pixelDataForFrame(from: dataset, frameIndex: 0)
    }
    
    /// Extract pixel data for a specific frame index from the dataset.
    /// Handles both encapsulated (with BOT) and non-encapsulated multiframe data.
    /// - Parameters:
    ///   - dataset: DICOM dataset containing pixel data
    ///   - frameIndex: Frame index (0-based)
    /// - Returns: Frame pixel data or nil if not available
    public func pixelDataForFrame(from dataset: DataSet, frameIndex: Int) -> Data? {
        guard let element = dataset.element(forTagName: "PixelData") else { return nil }
        
        if let px = element as? PixelSequence {
            // Encapsulated: use BOT-based frame extraction
            if let ts = dataset.transferSyntax, ts.isJPEG2000Part1 || ts.isRLE || ts.isJPEGBaselineOrExtended || ts.isJPEGLS || ts.isHTJ2K {
                // Use precise frame extraction with BOT
                if let data = try? px.frameData(at: frameIndex) { return data }
            }
            // Fallback: first non-empty item data for frame 0
            if frameIndex == 0 {
                for item in px.items { if item.length > 0, let data = item.data, data.count > 0 { return data } }
            }
            return nil
        } else {
            // Native (uncompressed) data: handle single or multi-frame contiguous buffers
            if let framesString = dataset.string(forTag: "NumberOfFrames"), let frames = Int(framesString), frames > 1, element.length > 0, frames > 0 {
                let frameSize = element.length / frames
                guard frameIndex >= 0 && frameIndex < frames && frameSize > 0 else { return nil }
                let startOffset = frameIndex * frameSize
                let endOffset = min(startOffset + frameSize, element.data.count)
                guard startOffset < element.data.count else { return nil }
                return element.data.subdata(in: startOffset..<endOffset)
            } else {
                // Single frame: return all data for frame 0, nil for others
                return frameIndex == 0 ? element.data : nil
            }
        }
    }
    
    /// Phase 4: Get frame pixel data using memory-mapped file for zero-copy access
    /// - Parameters:
    ///   - dicomFile: The DicomFile with memory mapping enabled
    ///   - frameIndex: Index of the frame to retrieve (0-based)
    /// - Returns: Frame pixel data or nil if not available
    public func pixelDataForFrame(from dicomFile: DicomFile, frameIndex: Int) -> Data? {
        // Use the new zero-copy method if memory mapping is enabled
        if dicomFile.isMemoryMapped {
            return dicomFile.frameData(at: frameIndex)
        } else {
            // Fallback to traditional method
            return pixelDataForFrame(from: dicomFile.dataset, frameIndex: frameIndex)
        }
    }
    
    /// Phase 4: Decode a specific frame from raw frame data (for memory-mapped files)
    /// - Parameters:
    ///   - dataset: DICOM dataset containing metadata
    ///   - frameData: Raw frame data bytes
    ///   - frameIndex: Index of the frame (0-based)
    /// - Returns: Decoded frame with pixel data
    /// - Throws: PixelServiceError if decoding fails
    public func decodeFrame(from dataset: DataSet, frameData: Data, frameIndex: Int) throws -> DecodedFrame {
        guard let rows = dataset.integer32(forTag: "Rows"),
              let cols = dataset.integer32(forTag: "Columns"),
              let bitsAllocated = dataset.integer32(forTag: "BitsAllocated"),
              let samplesPerPixel = dataset.integer32(forTag: "SamplesPerPixel") else {
            throw PixelServiceError.invalidDataset
        }
        
        let rescaleSlope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let rescaleIntercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let photometricInterpretation = dataset.string(forTag: "PhotometricInterpretation")
        
        // Decode based on bits allocated
        if bitsAllocated == 8 {
            let pixels8 = Array(frameData)
            return DecodedFrame(
                id: "frame_\(frameIndex)",
                width: Int(cols),
                height: Int(rows),
                bitsAllocated: Int(bitsAllocated),
                pixels8: pixels8,
                pixels16: nil,
                rescaleSlope: rescaleSlope,
                rescaleIntercept: rescaleIntercept,
                photometricInterpretation: photometricInterpretation
            )
        } else if bitsAllocated == 16 {
            let pixels16 = toUInt16ArrayLE(frameData)
            return DecodedFrame(
                id: "frame_\(frameIndex)",
                width: Int(cols),
                height: Int(rows),
                bitsAllocated: Int(bitsAllocated),
                pixels8: nil,
                pixels16: pixels16,
                rescaleSlope: rescaleSlope,
                rescaleIntercept: rescaleIntercept,
                photometricInterpretation: photometricInterpretation
            )
        } else {
            throw PixelServiceError.invalidDimensions
        }
    }

    private func toUInt16ArrayLE(_ data: Data) -> [UInt16] {
        var result = [UInt16](repeating: 0, count: data.count / 2)
        _ = result.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst)
        }
        for i in 0..<result.count { result[i] = UInt16(littleEndian: result[i]) }
        return result
    }
}

// MARK: - CGImage extraction helpers

@available(iOS 14.0, macOS 11.0, *)
private func extractGray16Little(_ image: CGImage) -> [UInt16]? {
    let width = image.width
    let height = image.height
    let count = width * height
    var buffer = [UInt16](repeating: 0, count: count)
    // Use linear grayscale to avoid gamma changes.
    guard let space = CGColorSpace(name: CGColorSpace.linearGray) ?? CGColorSpaceCreateDeviceGray() as CGColorSpace? else { return nil }
    var info = CGBitmapInfo.byteOrder16Little
    info.insert(CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue))
    let bytesPerRow = width * MemoryLayout<UInt16>.size
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        guard let ctx = CGContext(data: base, width: width, height: height,
                                  bitsPerComponent: 16, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: info.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return ok ? buffer : nil
}

@available(iOS 14.0, macOS 11.0, *)
private func extract8(_ image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    // Fast path: native 8-bit gray
    if image.bitsPerComponent == 8, image.bitsPerPixel == 8, (image.colorSpace?.numberOfComponents ?? 1) == 1, image.alphaInfo == .none {
        if let data = image.dataProvider?.data as Data? {
            return [UInt8](data)
        }
    }
    // General path: RGBA8888 little-endian
    let count = width * height * 4
    var buffer = [UInt8](repeating: 0, count: count)
    guard let space = CGColorSpaceCreateDeviceRGB() as CGColorSpace? else { return nil }
    var info = CGBitmapInfo.byteOrder32Little
    info.insert(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
    let bytesPerRow = width * 4
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        guard let ctx = CGContext(data: base, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: info.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return ok ? buffer : nil
}

@available(iOS 14.0, macOS 11.0, *)
private func extractRGB8(_ image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    let count = width * height * 3
    var buffer = [UInt8](repeating: 0, count: count)
    guard let space = CGColorSpaceCreateDeviceRGB() as CGColorSpace? else { return nil }
    // Try 24 bpp RGB (no alpha)
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    let bytesPerRow = width * 3
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        guard let ctx = CGContext(data: base, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: info.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    if ok { return buffer }
    // Fallback: draw as RGBA8888 and strip alpha
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    var info2 = CGBitmapInfo.byteOrder32Little
    info2.insert(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
    let ok2 = rgba.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        guard let ctx = CGContext(data: base, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: info2.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    if !ok2 { return nil }
    var out = [UInt8](repeating: 0, count: count)
    var j = 0
    var i = 0
    while i < rgba.count {
        // RGBA little-endian: BGRA in memory; convert to RGB
        let b = rgba[i+0]
        let g = rgba[i+1]
        let r = rgba[i+2]
        out[j] = r; out[j+1] = g; out[j+2] = b
        j += 3; i += 4
    }
    return out
}

@available(iOS 14.0, macOS 11.0, *)
private func extractGray16Raw(_ image: CGImage) -> [UInt16]? {
    guard image.bitsPerComponent == 16,
          image.bitsPerPixel == 16,
          (image.colorSpace?.numberOfComponents ?? 1) == 1,
          image.alphaInfo == .none else { return nil }
    guard let data = image.dataProvider?.data as Data? else { return nil }
    let width = image.width
    let height = image.height
    let rowBytes = image.bytesPerRow
    if rowBytes < width * 2 { return nil }
    var out = [UInt16](repeating: 0, count: width * height)
    data.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
        var dstIndex = 0
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes)
            var x = 0
            while x < width {
                // Assume big-endian in provider; convert to host little-endian
                let msb = UInt16(row[x*2])
                let lsb = UInt16(row[x*2 + 1])
                let be = (msb << 8) | lsb
                out[dstIndex] = UInt16(bigEndian: be)
                dstIndex += 1
                x += 1
            }
        }
    }
    return out
}
