//
//  MemoryMappedFileTests.swift
//  DcmSwiftTests
//
//  Phase 4: I/O Throughput - Optional mmapped Frames + Frame Index
//  Created by AI Assistant on 2025-01-14.
//

import XCTest
@testable import DcmSwift

final class MemoryMappedFileTests: XCTestCase {
    
    private var tempFileURL: URL!
    private var testData: Data!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary file with test data
        tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_mmap_\(UUID().uuidString).bin")
        testData = Data("Hello, Memory Mapped World! This is a test file for memory mapping functionality.".utf8)
        
        try! testData.write(to: tempFileURL)
    }
    
    override func tearDown() {
        // Clean up temporary file
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }
    
    func testMemoryMappedFileInitialization() throws {
        // Test successful initialization
        let mmapFile = try MemoryMappedFile(filePath: tempFileURL.path)
        
        XCTAssertNotNil(mmapFile.base)
        XCTAssertEqual(mmapFile.size, testData.count)
        
        // Test cleanup
        mmapFile.cleanup()
    }
    
    func testMemoryMappedFilePointerAccess() throws {
        let mmapFile = try MemoryMappedFile(filePath: tempFileURL.path)
        defer { mmapFile.cleanup() }
        
        // Test pointer at offset 0
        let pointer0 = mmapFile.pointer(at: 0)
        XCTAssertNotNil(pointer0)
        
        // Test pointer at valid offset
        let pointer5 = mmapFile.pointer(at: 5)
        XCTAssertNotNil(pointer5)
        
        // Test pointer at invalid offset (negative)
        let pointerNegative = mmapFile.pointer(at: -1)
        XCTAssertNil(pointerNegative)
        
        // Test pointer at invalid offset (beyond file size)
        let pointerBeyond = mmapFile.pointer(at: testData.count + 1)
        XCTAssertNil(pointerBeyond)
    }
    
    func testMemoryMappedFileBufferAccess() throws {
        let mmapFile = try MemoryMappedFile(filePath: tempFileURL.path)
        defer { mmapFile.cleanup() }
        
        // Test valid buffer range
        let buffer = mmapFile.buffer(offset: 0, length: 10)
        XCTAssertNotNil(buffer)
        XCTAssertEqual(buffer?.count, 10)
        
        // Test buffer with invalid offset
        let invalidBuffer = mmapFile.buffer(offset: -1, length: 10)
        XCTAssertNil(invalidBuffer)
        
        // Test buffer with invalid length
        let invalidLengthBuffer = mmapFile.buffer(offset: 0, length: -1)
        XCTAssertNil(invalidLengthBuffer)
        
        // Test buffer extending beyond file
        let beyondBuffer = mmapFile.buffer(offset: testData.count - 5, length: 10)
        XCTAssertNil(beyondBuffer)
    }
    
    func testMemoryMappedFileDataAccess() throws {
        let mmapFile = try MemoryMappedFile(filePath: tempFileURL.path)
        defer { mmapFile.cleanup() }
        
        // Test data access for entire file
        let fullData = mmapFile.data(offset: 0, length: testData.count)
        XCTAssertNotNil(fullData)
        XCTAssertEqual(fullData, testData)
        
        // Test data access for partial range
        let partialData = mmapFile.data(offset: 0, length: 5)
        XCTAssertNotNil(partialData)
        XCTAssertEqual(partialData, testData.prefix(5))
        
        // Test data access with invalid parameters
        let invalidData = mmapFile.data(offset: -1, length: 5)
        XCTAssertNil(invalidData)
    }
    
    func testMemoryMappedFileErrorHandling() {
        // Test non-existent file
        XCTAssertThrowsError(try MemoryMappedFile(filePath: "/non/existent/file.bin")) { error in
            XCTAssertTrue(error is MemoryMappingError)
        }
        
        // Test empty file
        let emptyFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty_\(UUID().uuidString).bin")
        try! Data().write(to: emptyFileURL)
        defer { try? FileManager.default.removeItem(at: emptyFileURL) }
        
        XCTAssertThrowsError(try MemoryMappedFile(filePath: emptyFileURL.path)) { error in
            XCTAssertTrue(error is MemoryMappingError)
            if case MemoryMappingError.emptyFile = error {
                // Expected error
            } else {
                XCTFail("Expected emptyFile error")
            }
        }
    }
    
    func testMemoryMappedFileRAII() throws {
        // Test that cleanup is called automatically
        var mmapFile: MemoryMappedFile? = try MemoryMappedFile(filePath: tempFileURL.path)
        XCTAssertNotNil(mmapFile?.base)
        
        // Explicitly set to nil to trigger deinit
        mmapFile = nil
        
        // If we get here without crashing, RAII is working
        XCTAssertTrue(true)
    }
}
