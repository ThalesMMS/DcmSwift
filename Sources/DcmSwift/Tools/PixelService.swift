//
//  PixelService.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import Foundation
#if canImport(os)
import os
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
    private let oslog = os.Logger(subsystem: "com.isis.dicomviewer", category: "PixelService")

    /// Decode the first available frame in the dataset into a display-ready buffer.
    /// - Note: For color images this returns raw 8-bit data; consumers may convert as needed.
    @available(iOS 14.0, macOS 11.0, *)
    public func decodeFirstFrame(from dataset: DataSet) throws -> DecodedFrame {
        let debug = UserDefaults.standard.bool(forKey: "settings.debugLogsEnabled")
        let t0 = CFAbsoluteTimeGetCurrent()
        let rows = Int(dataset.integer16(forTag: "Rows") ?? 0)
        let cols = Int(dataset.integer16(forTag: "Columns") ?? 0)
        guard rows > 0, cols > 0 else { throw PixelServiceError.invalidDimensions }

        let bitsAllocated = Int(dataset.integer16(forTag: "BitsAllocated") ?? 0)
        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let pi = dataset.string(forTag: "PhotometricInterpretation")
        let sop = dataset.string(forTag: "SOPInstanceUID")

        guard let data = firstFramePixelData(from: dataset) else { throw PixelServiceError.missingPixelData }

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
            return out
        }
    }

    // MARK: - Internals (mirrors common helpers consolidated here)

    private func firstFramePixelData(from dataset: DataSet) -> Data? {
        guard let element = dataset.element(forTagName: "PixelData") else { return nil }
        if let seq = element as? DataSequence {
            for item in seq.items {
                if item.length > 128, let data = item.data { return data }
            }
            return nil
        } else {
            if let framesString = dataset.string(forTag: "NumberOfFrames"), let frames = Int(framesString), frames > 1 {
                let frameSize = element.length / frames
                let chunks = element.data.toUnsigned8Array().chunked(into: frameSize)
                if let first = chunks.first { return Data(first) }
                return nil
            } else {
                return element.data
            }
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
