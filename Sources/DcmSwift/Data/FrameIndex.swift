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

            for (index, startOffset) in offsets.enumerated() {
                let nextOffset = (index + 1 < offsets.count) ? offsets[index + 1] : totalFragmentLength
                let clampedNextOffset = min(max(nextOffset, startOffset), totalFragmentLength)
                let length = clampedNextOffset - startOffset

                guard length > 0 else { continue }

                // Add base offset to get absolute file position
                let absoluteOffset = baseOffset + startOffset

                frameInfos.append(FrameInfo(offset: absoluteOffset,
                                          length: length,
                                          isEncapsulated: true))
            }
        } else {
            // No BOT - treat as single frame (fallback)
            if totalFragmentLength > 0 {
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
        
        let bytesPerSample = (bitsAllocated + 7) / 8
        let frameSize = rows * cols * samplesPerPixel * bytesPerSample
        
        guard frameSize > 0 else {
            throw FrameIndexError.invalidFrameSize
        }
        
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
            frameInfos.append(FrameInfo(offset: pixelDataElement.dataOffset, 
                                      length: pixelDataElement.length, 
                                      isEncapsulated: false))
        }
        
        return frameInfos
    }
}

// MARK: - Frame Index Errors

public enum FrameIndexError: Error, LocalizedError {
    case noPixelData
    case noFramesFound
    case missingRequiredTags
    case invalidFrameSize
    case frameSizeMismatch(expected: Int, actual: Int)
    
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
        }
    }
}
