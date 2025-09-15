//
//  CompressionTests.swift
//  DcmSwiftTests
//
//  Created by Thales on 2025/01/14.
//
//  Tests for DICOM compression support (JPEG 2000, RLE, JPEG-LS)
//

import XCTest
@testable import DcmSwift

final class CompressionTests: XCTestCase {
    
    // MARK: - Transfer Syntax Tests
    
    func testTransferSyntaxDetection() {
        // Test JPEG 2000 Part 1 detection
        let j2kLossless = TransferSyntax("1.2.840.10008.1.2.4.90")
        XCTAssertNotNil(j2kLossless)
        XCTAssertTrue(j2kLossless!.isJPEG2000Part1)
        XCTAssertFalse(j2kLossless!.isUncompressed)
        
        let j2kLossy = TransferSyntax("1.2.840.10008.1.2.4.91")
        XCTAssertNotNil(j2kLossy)
        XCTAssertTrue(j2kLossy!.isJPEG2000Part1)
        XCTAssertFalse(j2kLossy!.isUncompressed)
        
        // Test HTJ2K detection
        let htj2k = TransferSyntax("1.2.840.10008.1.2.4.201")
        XCTAssertNotNil(htj2k)
        XCTAssertTrue(htj2k!.isHTJ2K)
        XCTAssertFalse(htj2k!.isUncompressed)
        
        // Test RLE detection
        let rle = TransferSyntax("1.2.840.10008.1.2.5")
        XCTAssertNotNil(rle)
        XCTAssertTrue(rle!.isRLE)
        XCTAssertFalse(rle!.isUncompressed)
        
        // Test JPEG-LS detection
        let jlsLossless = TransferSyntax("1.2.840.10008.1.2.4.80")
        XCTAssertNotNil(jlsLossless)
        XCTAssertTrue(jlsLossless!.isJPEGLS)
        XCTAssertFalse(jlsLossless!.isUncompressed)
        
        let jlsLossy = TransferSyntax("1.2.840.10008.1.2.4.81")
        XCTAssertNotNil(jlsLossy)
        XCTAssertTrue(jlsLossy!.isJPEGLS)
        XCTAssertFalse(jlsLossy!.isUncompressed)
        
        // Test JPEG Baseline detection
        let jpegBaseline = TransferSyntax("1.2.840.10008.1.2.4.50")
        XCTAssertNotNil(jpegBaseline)
        XCTAssertTrue(jpegBaseline!.isJPEGBaselineOrExtended)
        XCTAssertFalse(jpegBaseline!.isUncompressed)
        
        // Test uncompressed detection
        let uncompressed = TransferSyntax("1.2.840.10008.1.2.1")
        XCTAssertNotNil(uncompressed)
        XCTAssertTrue(uncompressed!.isUncompressed)
        XCTAssertFalse(uncompressed!.isJPEG2000Part1)
        XCTAssertFalse(uncompressed!.isRLE)
        XCTAssertFalse(uncompressed!.isJPEGLS)
    }
    
    // MARK: - JPEG 2000 Tests
    
    func testJP2Builder() {
        // Create a minimal J2K codestream for testing
        let testCodestream = createTestJ2KCodestream()
        let info = J2KCodestreamInfo(width: 256, height: 256, components: 1, bitsPerComponent: 8, isSigned: false)
        
        do {
            let jp2Data = try JP2Builder.makeJP2(from: testCodestream, info: info)
            XCTAssertGreaterThan(jp2Data.count, testCodestream.count)
            
            // Verify JP2 signature
            let signature = jp2Data.prefix(12)
            let expectedSignature: [UInt8] = [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A]
            XCTAssertEqual(Array(signature), expectedSignature)
        } catch {
            XCTFail("JP2Builder failed: \(error)")
        }
    }
    
    func testJ2KCodestreamParser() {
        let testCodestream = createTestJ2KCodestream()
        
        do {
            let info = try J2KCodestreamParser.parseSIZ(testCodestream)
            XCTAssertEqual(info.width, 256)
            XCTAssertEqual(info.height, 256)
            XCTAssertEqual(info.components, 1)
            XCTAssertEqual(info.bitsPerComponent, 8)
            XCTAssertFalse(info.isSigned)
        } catch {
            XCTFail("J2K parser failed: \(error)")
        }
    }
    
    // MARK: - RLE Tests
    
    func testRLEDecoder() {
        // Create test RLE data for 8-bit grayscale
        let testRLEData = createTestRLEData()
        
        do {
            let result = try RLEDecoder.decode(frameData: testRLEData, rows: 64, cols: 64, bitsAllocated: 8, samplesPerPixel: 1)
            XCTAssertNotNil(result.pixels8)
            XCTAssertNil(result.pixels16)
            XCTAssertEqual(result.pixels8?.count, 64 * 64)
        } catch {
            XCTFail("RLE decoder failed: \(error)")
        }
    }
    
    func testRLEDecoder16Bit() {
        // Create test RLE data for 16-bit grayscale
        let testRLEData = createTestRLEData16Bit()
        
        do {
            let result = try RLEDecoder.decode(frameData: testRLEData, rows: 32, cols: 32, bitsAllocated: 16, samplesPerPixel: 1)
            XCTAssertNotNil(result.pixels16)
            XCTAssertNil(result.pixels8)
            XCTAssertEqual(result.pixels16?.count, 32 * 32)
        } catch {
            XCTFail("RLE 16-bit decoder failed: \(error)")
        }
    }
    
    // MARK: - JPEG-LS Tests
    
    func testJPEGLSDecoderDisabled() {
        // Test that JPEG-LS is disabled by default
        let testData = Data([0xFF, 0xD8, 0xFF, 0xD9]) // Minimal JPEG-LS
        
        do {
            _ = try JPEGLSDecoder.decode(testData, expectedWidth: 64, expectedHeight: 64, expectedComponents: 1, bitsPerSample: 8)
            XCTFail("JPEG-LS should be disabled by default")
        } catch JPEGLSError.disabled {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Compression Router Tests
    
    func testCompressedPixelRouter() {
        // Test that the router correctly identifies compressed vs uncompressed
        let dataset = createTestDataset()
        
        // Test with uncompressed data
        dataset.transferSyntax = TransferSyntax("1.2.840.10008.1.2.1") // Explicit VR Little Endian
        XCTAssertTrue(dataset.transferSyntax?.isUncompressed ?? false)
        
        // Test with compressed data
        dataset.transferSyntax = TransferSyntax("1.2.840.10008.1.2.4.90") // JPEG 2000 Lossless
        XCTAssertFalse(dataset.transferSyntax?.isUncompressed ?? true)
    }
    
    // MARK: - Helper Methods
    
    private func createTestJ2KCodestream() -> Data {
        // Create a minimal J2K codestream with SOC and SIZ markers
        var data = Data()
        
        // SOC marker (Start of Codestream)
        data.append(contentsOf: [0xFF, 0x4F])
        
        // SIZ marker (Image and tile size)
        data.append(contentsOf: [0xFF, 0x51])
        
        // SIZ length (38 bytes)
        data.append(contentsOf: [0x00, 0x26])
        
        // SIZ parameters
        data.append(contentsOf: [0x00, 0x00]) // Rsiz (capabilities)
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x00]) // Xsiz (image width)
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x00]) // Ysiz (image height)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XOsiz (image offset X)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YOsiz (image offset Y)
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x00]) // XTsiz (tile width)
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x00]) // YTsiz (tile height)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XTOsiz (tile offset X)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YTOsiz (tile offset Y)
        data.append(contentsOf: [0x00, 0x01]) // Csiz (number of components)
        data.append(contentsOf: [0x07]) // Ssiz (bits per component - 1)
        data.append(contentsOf: [0x01, 0x01]) // XRsiz, YRsiz (component subsampling)
        
        return data
    }
    
    private func createTestRLEData() -> Data {
        // Create minimal RLE data for 8-bit grayscale 64x64
        var data = Data()
        
        // RLE header (64 bytes)
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // Number of segments (1)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Offset 0
        // Fill remaining offsets with zeros
        for _ in 0..<14 {
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }
        
        // RLE segment data (simple pattern)
        let pixelCount = 64 * 64
        for i in 0..<pixelCount {
            data.append(UInt8(i % 256))
        }
        
        return data
    }
    
    private func createTestRLEData16Bit() -> Data {
        // Create minimal RLE data for 16-bit grayscale 32x32
        var data = Data()
        
        // RLE header (64 bytes)
        data.append(contentsOf: [0x02, 0x00, 0x00, 0x00]) // Number of segments (2)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Offset 0
        data.append(contentsOf: [0x00, 0x04, 0x00, 0x00]) // Offset 1 (1024 bytes)
        // Fill remaining offsets with zeros
        for _ in 0..<13 {
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }
        
        // RLE segment 0 (LSB plane)
        let pixelCount = 32 * 32
        for i in 0..<pixelCount {
            data.append(UInt8(i % 256))
        }
        
        // RLE segment 1 (MSB plane)
        for i in 0..<pixelCount {
            data.append(UInt8((i / 256) % 256))
        }
        
        return data
    }
    
    private func createTestDataset() -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax("1.2.840.10008.1.2.1")
        _ = dataset.set(value: 256, forTagName: "Rows")
        _ = dataset.set(value: 256, forTagName: "Columns")
        _ = dataset.set(value: 8, forTagName: "BitsAllocated")
        _ = dataset.set(value: 1, forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        return dataset
    }
}
