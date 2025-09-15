//
//  FrameIndexTests.swift
//  DcmSwiftTests
//
//  Phase 4: I/O Throughput - Optional mmapped Frames + Frame Index
//  Created by AI Assistant on 2025-01-14.
//

import XCTest
@testable import DcmSwift

final class FrameIndexTests: XCTestCase {
    
    func testFrameIndexNativeSingleFrame() throws {
        // Create a mock dataset for single frame
        let dataset = DataSet()
        
        // Add required tags
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0010"), dataset: dataset)) // Rows
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0011"), dataset: dataset)) // Columns
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0002"), dataset: dataset)) // SamplesPerPixel
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0100"), dataset: dataset)) // BitsAllocated
        
        // Set values
        dataset.element(forTagName: "Rows")?.setValue(Int32(512))
        dataset.element(forTagName: "Columns")?.setValue(Int32(512))
        dataset.element(forTagName: "SamplesPerPixel")?.setValue(Int32(1))
        dataset.element(forTagName: "BitsAllocated")?.setValue(Int32(16))
        
        // Add PixelData element
        let pixelDataElement = DataElement(withTag: DataTag(withGroup: "7FE0", element: "0010"), dataset: dataset)
        pixelDataElement.dataOffset = 1000 // Mock offset
        pixelDataElement.length = 512 * 512 * 2 // 512x512 16-bit
        dataset.add(element: pixelDataElement)
        
        // Create frame index
        let frameIndex = try FrameIndex(dataset: dataset)
        
        // Verify single frame
        XCTAssertEqual(frameIndex.count, 1)
        
        let frameInfo = frameIndex.frameInfo(at: 0)
        XCTAssertNotNil(frameInfo)
        XCTAssertEqual(frameInfo?.offset, 1000)
        XCTAssertEqual(frameInfo?.length, 512 * 512 * 2)
        XCTAssertFalse(frameInfo?.isEncapsulated ?? true)
        
        // Test invalid frame index
        XCTAssertNil(frameIndex.frameInfo(at: 1))
        XCTAssertFalse(frameIndex.isValidFrameIndex(1))
        XCTAssertTrue(frameIndex.isValidFrameIndex(0))
    }
    
    func testFrameIndexNativeMultiFrame() throws {
        // Create a mock dataset for multiframe
        let dataset = DataSet()
        
        // Add required tags
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0010"), dataset: dataset)) // Rows
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0011"), dataset: dataset)) // Columns
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0002"), dataset: dataset)) // SamplesPerPixel
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0100"), dataset: dataset)) // BitsAllocated
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0008"), dataset: dataset)) // NumberOfFrames
        
        // Set values
        _ = dataset.element(forTagName: "Rows")?.setValue(Int32(256))
        _ = dataset.element(forTagName: "Columns")?.setValue(Int32(256))
        _ = dataset.element(forTagName: "SamplesPerPixel")?.setValue(Int32(1))
        _ = dataset.element(forTagName: "BitsAllocated")?.setValue(Int32(8))
        dataset.element(forTagName: "NumberOfFrames")?.setValue("3")
        
        // Add PixelData element
        let pixelDataElement = DataElement(withTag: DataTag(withGroup: "7FE0", element: "0010"), dataset: dataset)
        pixelDataElement.dataOffset = 2000 // Mock offset
        pixelDataElement.length = 256 * 256 * 3 // 3 frames of 256x256 8-bit
        dataset.add(element: pixelDataElement)
        
        // Create frame index
        let frameIndex = try FrameIndex(dataset: dataset)
        
        // Verify multiframe
        XCTAssertEqual(frameIndex.count, 3)
        
        let frameSize = 256 * 256 // 8-bit frame size
        
        for i in 0..<3 {
            let frameInfo = frameIndex.frameInfo(at: i)
            XCTAssertNotNil(frameInfo)
            XCTAssertEqual(frameInfo?.offset, 2000 + (i * frameSize))
            XCTAssertEqual(frameInfo?.length, frameSize)
            XCTAssertFalse(frameInfo?.isEncapsulated ?? true)
            XCTAssertTrue(frameIndex.isValidFrameIndex(i))
        }
        
        // Test invalid frame index
        XCTAssertNil(frameIndex.frameInfo(at: 3))
        XCTAssertFalse(frameIndex.isValidFrameIndex(3))
    }
    
    func testFrameIndexEncapsulatedWithBOT() throws {
        // Create a mock dataset for encapsulated frames with BOT
        let dataset = DataSet()
        
        // Add required tags
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0010"), dataset: dataset)) // Rows
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0011"), dataset: dataset)) // Columns
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0002"), dataset: dataset)) // SamplesPerPixel
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0100"), dataset: dataset)) // BitsAllocated
        
        // Set values
        _ = dataset.element(forTagName: "Rows")?.setValue(Int32(128))
        _ = dataset.element(forTagName: "Columns")?.setValue(Int32(128))
        _ = dataset.element(forTagName: "SamplesPerPixel")?.setValue(Int32(1))
        _ = dataset.element(forTagName: "BitsAllocated")?.setValue(Int32(16))
        
        // Create PixelSequence with BOT
        let pixelSequence = PixelSequence(withTag: DataTag(withGroup: "7FE0", element: "0010"))
        pixelSequence.dataOffset = 3000 // Mock offset
        
        // Create BOT item (Item 0)
        let botItem = DataItem(withTag: DataTag(withGroup: "FFFE", element: "E000"))
        // BOT contains 2 offsets: [0, 1000, 2000] for 2 frames
        var botData = Data()
        botData.append(contentsOf: [0, 0, 0, 0]) // First offset: 0
        botData.append(contentsOf: [232, 3, 0, 0]) // Second offset: 1000 (little endian)
        botData.append(contentsOf: [208, 7, 0, 0]) // Third offset: 2000 (little endian)
        botItem.data = botData
        pixelSequence.items.append(botItem)
        
        // Create fragment items (Item 1, 2, 3)
        for _ in 1...3 {
            let fragmentItem = DataItem(withTag: DataTag(withGroup: "FFFE", element: "E000"))
            fragmentItem.data = Data(count: 1000) // Mock fragment data
            pixelSequence.items.append(fragmentItem)
        }
        
        dataset.add(element: pixelSequence)
        
        // Create frame index
        let frameIndex = try FrameIndex(dataset: dataset)
        
        // Verify encapsulated frames
        XCTAssertEqual(frameIndex.count, 2)
        
        let frameInfo0 = frameIndex.frameInfo(at: 0)
        XCTAssertNotNil(frameInfo0)
        XCTAssertEqual(frameInfo0?.offset, 3000) // Base offset + BOT offset 0
        XCTAssertEqual(frameInfo0?.length, 1000) // 1000 - 0
        XCTAssertTrue(frameInfo0?.isEncapsulated ?? false)
        
        let frameInfo1 = frameIndex.frameInfo(at: 1)
        XCTAssertNotNil(frameInfo1)
        XCTAssertEqual(frameInfo1?.offset, 4000) // Base offset + BOT offset 1000
        XCTAssertEqual(frameInfo1?.length, 1000) // 2000 - 1000
        XCTAssertTrue(frameInfo1?.isEncapsulated ?? false)
    }

    func testFrameIndexEncapsulatedWithInvalidBOTOffsets() {
        let dataset = DataSet()

        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0010"), dataset: dataset))
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0011"), dataset: dataset))
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0002"), dataset: dataset))
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0100"), dataset: dataset))

        _ = dataset.element(forTagName: "Rows")?.setValue(Int32(64))
        _ = dataset.element(forTagName: "Columns")?.setValue(Int32(64))
        _ = dataset.element(forTagName: "SamplesPerPixel")?.setValue(Int32(1))
        _ = dataset.element(forTagName: "BitsAllocated")?.setValue(Int32(8))

        let pixelSequence = PixelSequence(withTag: DataTag(withGroup: "7FE0", element: "0010"))
        pixelSequence.dataOffset = 5000

        let botItem = DataItem(withTag: DataTag(withGroup: "FFFE", element: "E000"))
        // Offsets are not strictly increasing (100 followed by 80) and should trigger a validation error
        var botData = Data()
        botData.append(contentsOf: [100, 0, 0, 0])
        botData.append(contentsOf: [80, 0, 0, 0])
        botItem.data = botData
        pixelSequence.items.append(botItem)

        for _ in 0..<2 {
            let fragmentItem = DataItem(withTag: DataTag(withGroup: "FFFE", element: "E000"))
            fragmentItem.data = Data(count: 200)
            pixelSequence.items.append(fragmentItem)
        }

        dataset.add(element: pixelSequence)

        XCTAssertThrowsError(try FrameIndex(dataset: dataset)) { error in
            guard case FrameIndexError.invalidBOTOffsets = error else {
                return XCTFail("Expected invalidBOTOffsets error")
            }
        }
    }

    func testFrameIndexEncapsulatedWithoutBOT() throws {
        // Create a mock dataset for encapsulated frames without BOT
        let dataset = DataSet()
        
        // Add required tags
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0010"), dataset: dataset)) // Rows
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0011"), dataset: dataset)) // Columns
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0002"), dataset: dataset)) // SamplesPerPixel
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0100"), dataset: dataset)) // BitsAllocated
        
        // Set values
        _ = dataset.element(forTagName: "Rows")?.setValue(Int32(64))
        _ = dataset.element(forTagName: "Columns")?.setValue(Int32(64))
        _ = dataset.element(forTagName: "SamplesPerPixel")?.setValue(Int32(1))
        _ = dataset.element(forTagName: "BitsAllocated")?.setValue(Int32(8))
        
        // Create PixelSequence without BOT
        let pixelSequence = PixelSequence(withTag: DataTag(withGroup: "7FE0", element: "0010"))
        pixelSequence.dataOffset = 4000 // Mock offset
        
        // Create empty BOT item (Item 0)
        let botItem = DataItem(withTag: DataTag(withGroup: "FFFE", element: "E000"))
        botItem.data = Data() // Empty BOT
        pixelSequence.items.append(botItem)
        
        // Create single fragment item (Item 1)
        let fragmentItem = DataItem(withTag: DataTag(withGroup: "FFFE", element: "E000"))
        fragmentItem.data = Data(count: 500) // Mock fragment data
        pixelSequence.items.append(fragmentItem)
        
        dataset.add(element: pixelSequence)
        
        // Create frame index
        let frameIndex = try FrameIndex(dataset: dataset)
        
        // Verify single frame fallback
        XCTAssertEqual(frameIndex.count, 1)
        
        let frameInfo = frameIndex.frameInfo(at: 0)
        XCTAssertNotNil(frameInfo)
        XCTAssertEqual(frameInfo?.offset, 4000) // Base offset
        XCTAssertEqual(frameInfo?.length, 500) // Total fragment length
        XCTAssertTrue(frameInfo?.isEncapsulated ?? false)
    }
    
    func testFrameIndexErrorHandling() {
        // Test dataset without PixelData
        let dataset = DataSet()
        XCTAssertThrowsError(try FrameIndex(dataset: dataset)) { error in
            XCTAssertTrue(error is FrameIndexError)
            if case FrameIndexError.noPixelData = error {
                // Expected error
            } else {
                XCTFail("Expected noPixelData error")
            }
        }
        
        // Test dataset with missing required tags
        let incompleteDataset = DataSet()
        let pixelDataElement = DataElement(withTag: DataTag(withGroup: "7FE0", element: "0010"), dataset: incompleteDataset)
        incompleteDataset.add(element: pixelDataElement)
        
        XCTAssertThrowsError(try FrameIndex(dataset: incompleteDataset)) { error in
            XCTAssertTrue(error is FrameIndexError)
            if case FrameIndexError.missingRequiredTags = error {
                // Expected error
            } else {
                XCTFail("Expected missingRequiredTags error")
            }
        }
    }

    func testFrameIndexFrameTooLarge() {
        let dataset = DataSet()

        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0010"), dataset: dataset))
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0011"), dataset: dataset))
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0002"), dataset: dataset))
        dataset.add(element: DataElement(withTag: DataTag(withGroup: "0028", element: "0100"), dataset: dataset))

        _ = dataset.element(forTagName: "Rows")?.setValue(Int32(8192))
        _ = dataset.element(forTagName: "Columns")?.setValue(Int32(8192))
        _ = dataset.element(forTagName: "SamplesPerPixel")?.setValue(Int32(3))
        _ = dataset.element(forTagName: "BitsAllocated")?.setValue(Int32(24))

        let pixelDataElement = DataElement(withTag: DataTag(withGroup: "7FE0", element: "0010"), dataset: dataset)
        pixelDataElement.dataOffset = 1234
        pixelDataElement.length = 603_979_776 // 8192 * 8192 * 3 samples * 3 bytes per sample
        dataset.add(element: pixelDataElement)

        XCTAssertThrowsError(try FrameIndex(dataset: dataset)) { error in
            guard case FrameIndexError.frameTooLarge = error else {
                return XCTFail("Expected frameTooLarge error")
            }
        }
    }
}
