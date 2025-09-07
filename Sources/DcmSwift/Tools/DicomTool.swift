#if canImport(UIKit)
import UIKit
import Foundation

/// Result of DICOM decoding and display operations.
public enum DicomProcessingResult {
    /// Image was decoded and displayed successfully.
    case success
    /// An error occurred during processing.
    case failure(DicomToolError)
}

/// Error types produced by ``DicomTool``.
public enum DicomToolError: Error, LocalizedError {
    /// The DICOM image could not be decoded.
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "Failed to decode DICOM file"
        }
    }
}

/// Swift DICOM utility based on ``DicomServiceProtocol``.
///
/// The class offers asynchronous helpers for validating and displaying
/// DICOM images while preserving the original synchronous API through
/// blocking wrappers.
public final class DicomTool {

    /// Shared singleton instance.
    public static let shared = DicomTool()

    private let dicomService: any DicomServiceProtocol

    private init(service: any DicomServiceProtocol = DcmSwiftService.shared) {
        self.dicomService = service
    }

    // MARK: - Decoding

    /// Decode a DICOM file and display it in the provided ``DCMImgView``.
    ///
    /// - Parameters:
    ///   - path: Path to a DICOM file on disk.
    ///   - view: Destination view that will display the decoded pixels.
    /// - Returns: ``DicomProcessingResult`` describing the outcome.
    public func decodeAndDisplay(path: String, view: DCMImgView) async -> DicomProcessingResult {
        let url = URL(fileURLWithPath: path)
        let result = await dicomService.loadDicomImage(from: url)

        switch result {
        case .success(let imageModel):
            await MainActor.run {
                switch imageModel.pixelData {
                case .uint16(let data):
                    view.setPixels16(
                        data,
                        width: imageModel.width,
                        height: imageModel.height,
                        windowWidth: imageModel.windowWidth,
                        windowCenter: imageModel.windowCenter,
                        samplesPerPixel: imageModel.samplesPerPixel ?? 1
                    )
                case .uint8(let data):
                    view.setPixels8(
                        data,
                        width: imageModel.width,
                        height: imageModel.height,
                        windowWidth: imageModel.windowWidth,
                        windowCenter: imageModel.windowCenter,
                        samplesPerPixel: imageModel.samplesPerPixel ?? 1
                    )
                case .uint24:
                    break
                }
            }
            return .success
        case .failure:
            return .failure(.decodingFailed)
        }
    }

    /// Synchronous wrapper around ``decodeAndDisplay(path:view:)`` for
    /// backwards compatibility.
    @discardableResult
    public func decodeAndDisplay(path: String, view: DCMImgView) -> DicomProcessingResult {
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

    /// Determine whether the supplied path points to a valid DICOM file.
    /// - Parameter path: File system path to inspect.
    /// - Returns: `true` when the file can be decoded.
    public func isValidDICOM(at path: String) async -> Bool {
        let url = URL(fileURLWithPath: path)
        let result = await dicomService.loadDicomImage(from: url)
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Synchronous wrapper around ``isValidDICOM(at:)``.
    public func isValidDICOM(at path: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var value = false
        Task {
            value = await isValidDICOM(at: path)
            semaphore.signal()
        }
        semaphore.wait()
        return value
    }

    // MARK: - Metadata

    /// Extract common DICOM instance UIDs from a file.
    /// - Parameter filePath: Path to the DICOM file on disk.
    /// - Returns: Study, Series and SOP Instance UIDs when present.
    public func extractDICOMUIDs(from filePath: String) async -> (studyUID: String?, seriesUID: String?, sopUID: String?) {
        let url = URL(fileURLWithPath: filePath)
        let metadataResult = await dicomService.extractFullMetadata(from: url)

        switch metadataResult {
        case .success(let metadata):
            return (
                metadata["StudyInstanceUID"] as? String,
                metadata["SeriesInstanceUID"] as? String,
                metadata["SOPInstanceUID"] as? String
            )
        case .failure:
            return (nil, nil, nil)
        }
    }

    /// Blocking wrapper around ``extractDICOMUIDs(from:)``.
    public func extractDICOMUIDs(from path: String) -> (studyUID: String?, seriesUID: String?, sopUID: String?) {
        let semaphore = DispatchSemaphore(value: 0)
        var value: (studyUID: String?, seriesUID: String?, sopUID: String?) = (nil, nil, nil)
        Task {
            value = await extractDICOMUIDs(from: path)
            semaphore.signal()
        }
        semaphore.wait()
        return value
    }

    // MARK: - Convenience

    /// Quickly decode an image and render it for thumbnail generation.
    /// - Returns: `true` on success.
    public func quickProcess(path: String, view: DCMImgView) async -> Bool {
        switch await decodeAndDisplay(path: path, view: view) {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
#endif

