#if canImport(UIKit)
import UIKit
import Foundation

/// Result of DICOM decoding and display operations.
public enum DicomProcessingResult {
    case success
    case failure(DicomToolError)
}

/// Error types produced by ``DicomTool``.
public enum DicomToolError: Error, LocalizedError {
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "Failed to decode DICOM file"
        }
    }
}

/// Lightweight DICOM utility built on DcmSwift primitives (no external service).
public final class DicomTool {

    public static let shared = DicomTool()
    private init() {}

    // MARK: - Decoding

    /// Decode a DICOM file and display it in the provided ``DicomPixelView``.
    @discardableResult
    public func decodeAndDisplay(path: String, view: DicomPixelView) async -> DicomProcessingResult {
        guard let dicomFile = DicomFile(forPath: path), let dataset = dicomFile.dataset else {
            return .failure(.decodingFailed)
        }

        // Dimensions and basic metadata
        let rows = Int(dataset.integer16(forTag: "Rows") ?? 0)
        let cols = Int(dataset.integer16(forTag: "Columns") ?? 0)
        guard rows > 0, cols > 0 else { return .failure(.decodingFailed) }

        // Window/Level: prefer explicit values from dataset; fall back to heuristic defaults
        let slope = Double(dataset.string(forTag: "RescaleSlope") ?? "") ?? 1.0
        let intercept = Double(dataset.string(forTag: "RescaleIntercept") ?? "") ?? 0.0
        let ww = Int(dataset.string(forTag: "WindowWidth")?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
        let wc = Int(dataset.string(forTag: "WindowCenter")?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0

        var windowWidth = ww
        var windowCenter = wc
        if windowWidth <= 0 || windowCenter == 0 {
            let modalityString = dataset.string(forTag: "Modality")?.uppercased() ?? ""
            let modality: DICOMModality
            switch modalityString {
            case "CT": modality = .ct
            case "MR": modality = .mr
            case "CR": modality = .cr
            case "DX": modality = .dx
            case "DR": modality = .dr
            case "RG": modality = .rg
            case "XA": modality = .xa
            case "US": modality = .us
            case "MG": modality = .mg
            case "RF": modality = .rf
            case "XC": modality = .xc
            case "SC": modality = .sc
            case "PT": modality = .pt
            case "NM": modality = .nm
            case "AU": modality = .au
            case "BMD": modality = .bmd
            case "ES": modality = .es
            case "SR": modality = .sr
            case "VL": modality = .vl
            case "PX": modality = .px
            case "OT": modality = .ot
            default: modality = .other
            }
            let calculator = WindowLevelCalculator()
            let defaults = calculator.defaultWindowLevel(for: modality)
            let pixels = calculator.calculateWindowLevel(
                huWidth: Double(defaults.width),
                huLevel: Double(defaults.level),
                rescaleSlope: slope,
                rescaleIntercept: intercept
            )
            windowWidth = pixels.pixelWidth
            windowCenter = pixels.pixelLevel
        }

        // Extract first frame pixel data
        guard let pixelData = Self.firstFramePixelData(from: dataset) else {
            return .failure(.decodingFailed)
        }

        // Bits allocated determines 8-bit vs 16-bit path
        let bitsAllocated = Int(dataset.integer16(forTag: "BitsAllocated") ?? 0)

        await MainActor.run {
            if bitsAllocated > 8 {
                let pixels16 = Self.toUInt16ArrayLE(pixelData)
                view.setPixels16(pixels16,
                                 width: cols,
                                 height: rows,
                                 windowWidth: windowWidth,
                                 windowCenter: windowCenter)
            } else {
                let pixels8 = [UInt8](pixelData)
                view.setPixels8(pixels8,
                                width: cols,
                                height: rows,
                                windowWidth: windowWidth,
                                windowCenter: windowCenter)
            }
        }

        return .success
    }

    /// Synchronous wrapper around ``decodeAndDisplay(path:view:)``.
    @discardableResult
    public func decodeAndDisplay(path: String, view: DicomPixelView) -> DicomProcessingResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: DicomProcessingResult = .failure(.decodingFailed)
        Task {
            result = await decodeAndDisplay(path: path, view: view)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // MARK: - Validation

    public func isValidDICOM(at path: String) async -> Bool {
        guard let file = DicomFile(forPath: path), let dataset = file.dataset else { return false }
        // Attempt to create an image; failure means unsupported/invalid
        return DicomImage(dataset) != nil
    }

    public func isValidDICOM(at path: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        Task { ok = await isValidDICOM(at: path); semaphore.signal() }
        semaphore.wait()
        return ok
    }

    // MARK: - Metadata

    public func extractDICOMUIDs(from filePath: String) async -> (studyUID: String?, seriesUID: String?, sopUID: String?) {
        guard let file = DicomFile(forPath: filePath), let dataset = file.dataset else {
            return (nil, nil, nil)
        }
        return (
            dataset.string(forTag: "StudyInstanceUID"),
            dataset.string(forTag: "SeriesInstanceUID"),
            dataset.string(forTag: "SOPInstanceUID")
        )
    }

    public func extractDICOMUIDs(from path: String) -> (studyUID: String?, seriesUID: String?, sopUID: String?) {
        let semaphore = DispatchSemaphore(value: 0)
        var value: (String?, String?, String?) = (nil, nil, nil)
        Task { value = await extractDICOMUIDs(from: path); semaphore.signal() }
        semaphore.wait()
        return value
    }

    // MARK: - Convenience

    public func quickProcess(path: String, view: DicomPixelView) async -> Bool {
        switch await decodeAndDisplay(path: path, view: view) {
        case .success: return true
        case .failure: return false
        }
    }

    // MARK: - Helpers

    private static func firstFramePixelData(from dataset: DataSet) -> Data? {
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

    private static func toUInt16ArrayLE(_ data: Data) -> [UInt16] {
        var result = [UInt16](repeating: 0, count: data.count / 2)
        _ = result.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst)
        }
        // Ensure little-endian
        for i in 0..<result.count { result[i] = UInt16(littleEndian: result[i]) }
        return result
    }
}
#endif
