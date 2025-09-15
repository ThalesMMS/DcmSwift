//
//  FrameIndex.swift
//  DcmSwift
//
//  Phase 4: I/O Throughput - Optional mmapped Frames + Frame Index
//  Created by AI Assistant on 2025-01-14.
//

import Foundation

/// Information about a single frame in a DICOM file
public struct FrameInfo {
    /// Byte offset from the beginning of the file where this frame starts
    public let offset: Int
    
    /// Length of this frame in bytes
    public let length: Int
    
    /// Whether this frame is encapsulated (compressed) or native (uncompressed)
    public let isEncapsulated: Bool
    
    public init(offset: Int, length: Int, isEncapsulated: Bool = false) {
        self.offset = offset
        self.length = length
        self.isEncapsulated = isEncapsulated
    }
}

/// Index of frames in a DICOM file for efficient zero-copy access
public final class FrameIndex {
    private let frames: [FrameInfo]
    private let totalFrames: Int

    /// Maximum supported frame size (512MB) to protect against resource exhaustion.
    private static let maxFrameSize = 512 * 1024 * 1024
    
    /// Initialize frame index from a dataset
    /// - Parameter dataset: The parsed DICOM dataset
    /// - Throws: FrameIndexError if indexing fails
    public init(dataset: DataSet) throws {
        guard let pixelDataElement = dataset.element(forTagName: "PixelData") else {
            throw FrameIndexError.noPixelData
        }
        
        var frameInfos: [FrameInfo] = []
        
        if let pixelSequence = pixelDataElement as? PixelSequence {
            // Encapsulated (compressed) frames
            frameInfos = try Self.buildEncapsulatedFrameIndex(pixelSequence: pixelSequence, 
                                                             baseOffset: pixelDataElement.dataOffset)
        } else {
            // Native (uncompressed) frames
            frameInfos = try Self.buildNativeFrameIndex(pixelDataElement: pixelDataElement, 
                                                       dataset: dataset)
        }
        
        self.frames = frameInfos
        self.totalFrames = frameInfos.count
    }
    
    /// Get the number of frames in this index
    public var count: Int {
        return totalFrames
    }
    
    /// Get frame information for a specific index
    /// - Parameter index: Frame index (0-based)
    /// - Returns: FrameInfo for the frame, or nil if index is out of bounds
    public func frameInfo(at index: Int) -> FrameInfo? {
        guard index >= 0 && index < totalFrames else {
            return nil
        }
        return frames[index]
    }
    
    /// Get all frame information
    public var allFrames: [FrameInfo] {
        return frames
    }
    
    /// Check if a frame index is valid
    /// - Parameter index: Frame index to check
    /// - Returns: True if the index is valid
    public func isValidFrameIndex(_ index: Int) -> Bool {
        return index >= 0 && index < totalFrames
    }
}

// MARK: - Private Frame Index Building Methods

private extension FrameIndex {
    
    /// Build frame index for encapsulated (compressed) pixel data
    static func buildEncapsulatedFrameIndex(pixelSequence: PixelSequence, baseOffset: Int) throws -> [FrameInfo] {
        var frameInfos: [FrameInfo] = []
        
        let fragments = pixelSequence.items.dropFirst() // Skip BOT item
        let totalFragmentLength = fragments.reduce(0) { $0 + ($1.data?.count ?? 0) }

        // Get BOT (Basic Offset Table) offsets from first item
        if let offsets = pixelSequence.basicOffsetTable(), !offsets.isEmpty {
            guard totalFragmentLength > 0 else {
                throw FrameIndexError.noFramesFound
            }

            try validateBasicOffsetTable(offsets, totalFragmentLength: totalFragmentLength)

            for (index, startOffset) in offsets.enumerated() {
                let endOffset = (index + 1 < offsets.count) ? offsets[index + 1] : totalFragmentLength

                let length = endOffset - startOffset
                guard length > 0 else {
                    throw FrameIndexError.invalidBOTOffsets
                }
                guard length <= maxFrameSize else {
                    throw FrameIndexError.frameTooLarge
                }

                let (absoluteOffset, overflow) = baseOffset.addingReportingOverflow(startOffset)
                guard !overflow else {
                    throw FrameIndexError.invalidBOTOffsets
                }

                frameInfos.append(FrameInfo(offset: absoluteOffset,
                                          length: length,
                                          isEncapsulated: true))
            }
        } else {
            // No BOT - treat as single frame (fallback)
            if totalFragmentLength > 0 {
                guard totalFragmentLength <= maxFrameSize else {
                    throw FrameIndexError.frameTooLarge
                }
                frameInfos.append(FrameInfo(offset: baseOffset,
                                          length: totalFragmentLength,
                                          isEncapsulated: true))
            }
        }
        
        guard !frameInfos.isEmpty else {
            throw FrameIndexError.noFramesFound
        }
        
        return frameInfos
    }
    
    /// Build frame index for native (uncompressed) pixel data
    static func buildNativeFrameIndex(pixelDataElement: DataElement, dataset: DataSet) throws -> [FrameInfo] {
        var frameInfos: [FrameInfo] = []
        
        // Get frame dimensions
        guard let rows = dataset.integer32(forTag: "Rows"),
              let cols = dataset.integer32(forTag: "Columns"),
              let samplesPerPixel = dataset.integer32(forTag: "SamplesPerPixel"),
              let bitsAllocated = dataset.integer32(forTag: "BitsAllocated") else {
            throw FrameIndexError.missingRequiredTags
        }
        
        let bytesPerSample = Int((bitsAllocated + 7) / 8)

        let rowsValue = Int(rows)
        let colsValue = Int(cols)
        let samplesValue = Int(samplesPerPixel)

        guard rowsValue > 0, colsValue > 0, samplesValue > 0, bytesPerSample > 0 else {
            throw FrameIndexError.invalidFrameSize
        }

        let frameSize64 = Int64(rowsValue) * Int64(colsValue) * Int64(samplesValue) * Int64(bytesPerSample)
        guard frameSize64 > 0 else {
            throw FrameIndexError.invalidFrameSize
        }
        guard frameSize64 <= Int64(maxFrameSize) else {
            throw FrameIndexError.frameTooLarge
        }

        let frameSize = Int(frameSize64)

        // Check if this is a multiframe
        if let numberOfFramesString = dataset.string(forTag: "NumberOfFrames"),
           let numberOfFrames = Int(numberOfFramesString), numberOfFrames > 1 {

            // Multiframe: calculate offsets for each frame
            let totalPixelDataLength = pixelDataElement.length
            let actualFrameSize = totalPixelDataLength / numberOfFrames

            // Validate that frames fit exactly
            guard actualFrameSize == frameSize else {
                throw FrameIndexError.frameSizeMismatch(expected: Int(frameSize), actual: actualFrameSize)
            }

            for i in 0..<numberOfFrames {
                let offset = pixelDataElement.dataOffset + (i * Int(frameSize))
                frameInfos.append(FrameInfo(offset: offset,
                                          length: Int(frameSize),
                                          isEncapsulated: false))
            }
        } else {
            // Single frame: use entire pixel data
            guard pixelDataElement.length <= maxFrameSize else {
                throw FrameIndexError.frameTooLarge
            }
            frameInfos.append(FrameInfo(offset: pixelDataElement.dataOffset,
                                      length: pixelDataElement.length,
                                      isEncapsulated: false))
        }

        return frameInfos
    }

    static func validateBasicOffsetTable(_ offsets: [Int], totalFragmentLength: Int) throws {
        guard totalFragmentLength > 0 else {
            throw FrameIndexError.invalidBOTOffsets
        }

        var previousOffset = -1
        for offset in offsets {
            guard offset >= 0 else {
                throw FrameIndexError.invalidBOTOffsets
            }
            guard offset < totalFragmentLength else {
                throw FrameIndexError.invalidBOTOffsets
            }
            if previousOffset >= 0 {
                guard offset > previousOffset else {
                    throw FrameIndexError.invalidBOTOffsets
                }
            }
            previousOffset = offset
        }
    }
}

// MARK: - Frame Index Errors

public enum FrameIndexError: Error, LocalizedError {
    case noPixelData
    case noFramesFound
    case missingRequiredTags
    case invalidFrameSize
    case frameSizeMismatch(expected: Int, actual: Int)
    case invalidBOTOffsets
    case frameTooLarge

    public var errorDescription: String? {
        switch self {
        case .noPixelData:
            return "No PixelData element found in dataset"
        case .noFramesFound:
            return "No frames found in pixel data"
        case .missingRequiredTags:
            return "Missing required tags for frame indexing (Rows, Columns, SamplesPerPixel, BitsAllocated)"
        case .invalidFrameSize:
            return "Invalid frame size calculated from pixel data dimensions"
        case .frameSizeMismatch(let expected, let actual):
            return "Frame size mismatch: expected \(expected) bytes, got \(actual) bytes"
        case .invalidBOTOffsets:
            return "Basic Offset Table contains invalid or non-monotonic offsets"
        case .frameTooLarge:
            return "Frame size exceeds maximum supported size"
        }
    }
}
