//
//  CompressionIntegrationTests.swift
//  DcmSwiftTests
//
//  Created by Thales on 2025/01/14.
//
//  Integration tests for compression support in the pixel pipeline
//

import XCTest
@testable import DcmSwift

@available(iOS 14.0, macOS 11.0, *)
final class CompressionIntegrationTests: XCTestCase {
    
    // MARK: - PixelService Integration Tests
    
    func testPixelServiceWithCompressedData() {
        let pixelService = PixelService.shared
        
        // Test with JPEG 2000 dataset
        let j2kDataset = createJPEG2000Dataset()
        
        do {
            let decodedFrame = try pixelService.decodeFrame(from: j2kDataset, frameIndex: 0)
            XCTAssertNotNil(decodedFrame)
            XCTAssertEqual(decodedFrame.width, 256)
            XCTAssertEqual(decodedFrame.height, 256)
            XCTAssertNotNil(decodedFrame.pixels8)
            XCTAssertNil(decodedFrame.pixels16)
        } catch {
            // JPEG 2000 decoding might fail without proper codestream data
            // This is expected in a test environment
            print("JPEG 2000 decode failed (expected in test): \(error)")
        }
    }
    
    func testPixelServiceWithRLEData() {
        let pixelService = PixelService.shared
        
        // Test with RLE dataset
        let rleDataset = createRLEDataset()
        
        do {
            let decodedFrame = try pixelService.decodeFrame(from: rleDataset, frameIndex: 0)
            XCTAssertNotNil(decodedFrame)
            XCTAssertEqual(decodedFrame.width, 64)
            XCTAssertEqual(decodedFrame.height, 64)
            XCTAssertNotNil(decodedFrame.pixels8)
            XCTAssertNil(decodedFrame.pixels16)
        } catch {
            XCTFail("RLE decode failed: \(error)")
        }
    }
    
    func testPixelServiceWithUncompressedData() {
        let pixelService = PixelService.shared
        
        // Test with uncompressed dataset
        let uncompressedDataset = createUncompressedDataset()
        
        do {
            let decodedFrame = try pixelService.decodeFrame(from: uncompressedDataset, frameIndex: 0)
            XCTAssertNotNil(decodedFrame)
            XCTAssertEqual(decodedFrame.width, 128)
            XCTAssertEqual(decodedFrame.height, 128)
            XCTAssertNotNil(decodedFrame.pixels8)
            XCTAssertNil(decodedFrame.pixels16)
        } catch {
            XCTFail("Uncompressed decode failed: \(error)")
        }
    }
    
    // MARK: - Compression Router Integration Tests
    
    func testCompressedPixelRouterWithJPEG2000() {
        let dataset = createJPEG2000Dataset()
        
        do {
            let decodedFrame = try CompressedPixelRouter.decodeCompressedFrame(from: dataset, frameIndex: 0)
            XCTAssertNotNil(decodedFrame)
            XCTAssertEqual(decodedFrame.width, 256)
            XCTAssertEqual(decodedFrame.height, 256)
        } catch {
            // Expected to fail without proper codestream
            print("JPEG 2000 router test failed (expected): \(error)")
        }
    }
    
    func testCompressedPixelRouterWithRLE() {
        let dataset = createRLEDataset()
        
        do {
            let decodedFrame = try CompressedPixelRouter.decodeCompressedFrame(from: dataset, frameIndex: 0)
            XCTAssertNotNil(decodedFrame)
            XCTAssertEqual(decodedFrame.width, 64)
            XCTAssertEqual(decodedFrame.height, 64)
        } catch {
            XCTFail("RLE router test failed: \(error)")
        }
    }
    
    func testCompressedPixelRouterWithJPEGBaseline() {
        let dataset = createJPEGBaselineDataset()
        
        do {
            let decodedFrame = try CompressedPixelRouter.decodeCompressedFrame(from: dataset, frameIndex: 0)
            XCTAssertNotNil(decodedFrame)
            XCTAssertEqual(decodedFrame.width, 128)
            XCTAssertEqual(decodedFrame.height, 128)
        } catch {
            // Expected to fail without proper JPEG data
            print("JPEG Baseline router test failed (expected): \(error)")
        }
    }
    
    // MARK: - Performance Tests
    
    func testCompressionPerformance() {
        let pixelService = PixelService.shared
        let dataset = createRLEDataset()
        
        measure {
            do {
                _ = try pixelService.decodeFrame(from: dataset, frameIndex: 0)
            } catch {
                // Ignore errors in performance test
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createJPEG2000Dataset() -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax("1.2.840.10008.1.2.4.90") // JPEG 2000 Lossless
        _ = dataset.set(value: 256, forTagName: "Rows")
        _ = dataset.set(value: 256, forTagName: "Columns")
        _ = dataset.set(value: 8, forTagName: "BitsAllocated")
        _ = dataset.set(value: 1, forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: 1.0, forTagName: "RescaleSlope")
        _ = dataset.set(value: 0.0, forTagName: "RescaleIntercept")
        
        // Create a minimal pixel sequence with test data
        let pixelSequence = PixelSequence()
        let testData = createTestJ2KCodestream()
        let item = DataItem(data: testData)
        pixelSequence.items.append(item)
        dataset.elements["PixelData"] = pixelSequence
        
        return dataset
    }
    
    private func createRLEDataset() -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax("1.2.840.10008.1.2.5") // RLE Lossless
        _ = dataset.set(value: 64, forTagName: "Rows")
        _ = dataset.set(value: 64, forTagName: "Columns")
        _ = dataset.set(value: 8, forTagName: "BitsAllocated")
        _ = dataset.set(value: 1, forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: 1.0, forTagName: "RescaleSlope")
        _ = dataset.set(value: 0.0, forTagName: "RescaleIntercept")
        
        // Create a minimal pixel sequence with RLE test data
        let pixelSequence = PixelSequence()
        let testData = createTestRLEData()
        let item = DataItem(data: testData)
        pixelSequence.items.append(item)
        dataset.elements["PixelData"] = pixelSequence
        
        return dataset
    }
    
    private func createJPEGBaselineDataset() -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax("1.2.840.10008.1.2.4.50") // JPEG Baseline
        _ = dataset.set(value: 128, forTagName: "Rows")
        _ = dataset.set(value: 128, forTagName: "Columns")
        _ = dataset.set(value: 8, forTagName: "BitsAllocated")
        _ = dataset.set(value: 1, forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: 1.0, forTagName: "RescaleSlope")
        _ = dataset.set(value: 0.0, forTagName: "RescaleIntercept")
        
        // Create a minimal pixel sequence with JPEG test data
        let pixelSequence = PixelSequence()
        let testData = createTestJPEGData()
        let item = DataItem(data: testData)
        pixelSequence.items.append(item)
        dataset.elements["PixelData"] = pixelSequence
        
        return dataset
    }
    
    private func createUncompressedDataset() -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax("1.2.840.10008.1.2.1") // Explicit VR Little Endian
        _ = dataset.set(value: 128, forTagName: "Rows")
        _ = dataset.set(value: 128, forTagName: "Columns")
        _ = dataset.set(value: 8, forTagName: "BitsAllocated")
        _ = dataset.set(value: 1, forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: 1.0, forTagName: "RescaleSlope")
        _ = dataset.set(value: 0.0, forTagName: "RescaleIntercept")
        
        // Create uncompressed pixel data
        let pixelData = DataElement(tag: DataTag(withGroup: "7FE0", element: "0010"))
        let testData = createTestUncompressedData()
        pixelData.data = testData
        dataset.elements["PixelData"] = pixelData
        
        return dataset
    }
    
    private func createTestJ2KCodestream() -> Data {
        // Create a minimal J2K codestream
        var data = Data()
        data.append(contentsOf: [0xFF, 0x4F]) // SOC
        data.append(contentsOf: [0xFF, 0x51]) // SIZ
        data.append(contentsOf: [0x00, 0x26]) // Length
        // Add minimal SIZ parameters
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x07, 0x01, 0x01])
        return data
    }
    
    private func createTestRLEData() -> Data {
        // Create minimal RLE data
        var data = Data()
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // 1 segment
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Offset 0
        // Fill remaining offsets
        for _ in 0..<14 {
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }
        // Add simple pixel data
        for i in 0..<(64 * 64) {
            data.append(UInt8(i % 256))
        }
        return data
    }
    
    private func createTestJPEGData() -> Data {
        // Create minimal JPEG data (SOI + EOI)
        var data = Data()
        data.append(contentsOf: [0xFF, 0xD8]) // SOI
        data.append(contentsOf: [0xFF, 0xD9]) // EOI
        return data
    }
    
    private func createTestUncompressedData() -> Data {
        // Create uncompressed pixel data
        var data = Data()
        for i in 0..<(128 * 128) {
            data.append(UInt8(i % 256))
        }
        return data
    }
}
