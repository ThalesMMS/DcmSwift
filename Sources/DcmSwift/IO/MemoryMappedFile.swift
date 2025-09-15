//
//  MemoryMappedFile.swift
//  DcmSwift
//
//  Phase 4: I/O Throughput - Optional mmapped Frames + Frame Index
//  Created by AI Assistant on 2025-01-14.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// RAII wrapper for memory-mapped files with automatic unmapping
public final class MemoryMappedFile {
    private var basePointer: UnsafeMutableRawPointer?
    private var fileSize: Int
    private var fileDescriptor: Int32
    
    /// Initialize a memory-mapped file
    /// - Parameter filePath: Path to the file to map
    /// - Throws: MemoryMappingError if mapping fails
    public init(filePath: String) throws {
        // Open file
        fileDescriptor = open(filePath, O_RDONLY)
        guard fileDescriptor >= 0 else {
            throw MemoryMappingError.cannotOpenFile(errno: errno)
        }
        
        // Get file size
        var statInfo = stat()
        guard fstat(fileDescriptor, &statInfo) == 0 else {
            close(fileDescriptor)
            throw MemoryMappingError.cannotGetFileSize(errno: errno)
        }
        
        fileSize = Int(statInfo.st_size)
        guard fileSize > 0 else {
            close(fileDescriptor)
            throw MemoryMappingError.emptyFile
        }
        
        // Map the file
        basePointer = mmap(nil, fileSize, PROT_READ, MAP_PRIVATE, fileDescriptor, 0)
        guard basePointer != MAP_FAILED else {
            close(fileDescriptor)
            throw MemoryMappingError.mappingFailed(errno: errno)
        }
    }
    
    deinit {
        cleanup()
    }
    
    /// Get a pointer to the mapped memory
    public var base: UnsafeRawPointer? {
        return basePointer.map { UnsafeRawPointer($0) }
    }
    
    /// Get the size of the mapped file
    public var size: Int {
        return fileSize
    }
    
    /// Get a pointer to a specific offset in the mapped file
    /// - Parameter offset: Byte offset from the beginning of the file
    /// - Returns: Pointer to the offset, or nil if offset is out of bounds
    public func pointer(at offset: Int) -> UnsafeRawPointer? {
        guard let base = basePointer, offset >= 0, offset < fileSize else {
            return nil
        }
        return UnsafeRawPointer(base.advanced(by: offset))
    }
    
    /// Get a buffer pointer for a range of bytes
    /// - Parameters:
    ///   - offset: Starting byte offset
    ///   - length: Number of bytes to include
    /// - Returns: UnsafeRawBufferPointer for the range, or nil if invalid
    public func buffer(offset: Int, length: Int) -> UnsafeRawBufferPointer? {
        guard let base = basePointer,
              offset >= 0,
              length > 0,
              offset + length <= fileSize else {
            return nil
        }
        
        let startPointer = base.advanced(by: offset)
        return UnsafeRawBufferPointer(start: startPointer, count: length)
    }
    
    /// Create a Data object from a range without copying (zero-copy)
    /// - Parameters:
    ///   - offset: Starting byte offset
    ///   - length: Number of bytes to include
    /// - Returns: Data object backed by the mapped memory, or nil if invalid
    public func data(offset: Int, length: Int) -> Data? {
        guard let buffer = buffer(offset: offset, length: length) else {
            return nil
        }
        
        // Create Data with no-copy constructor
        return Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: buffer.baseAddress!), count: length, deallocator: .none)
    }
    
    /// Manually cleanup resources (called automatically in deinit)
    public func cleanup() {
        if let base = basePointer {
            munmap(base, fileSize)
            basePointer = nil
        }
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
}

/// Errors that can occur during memory mapping
public enum MemoryMappingError: Error, LocalizedError {
    case cannotOpenFile(errno: Int32)
    case cannotGetFileSize(errno: Int32)
    case emptyFile
    case mappingFailed(errno: Int32)
    
    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let errno):
            return "Cannot open file for memory mapping: \(String(cString: strerror(errno)))"
        case .cannotGetFileSize(let errno):
            return "Cannot get file size: \(String(cString: strerror(errno)))"
        case .emptyFile:
            return "File is empty and cannot be mapped"
        case .mappingFailed(let errno):
            return "Memory mapping failed: \(String(cString: strerror(errno)))"
        }
    }
}

// MARK: - Constants for system calls
#if canImport(Darwin)
private let O_RDONLY = Darwin.O_RDONLY
private let PROT_READ = Darwin.PROT_READ
private let MAP_PRIVATE = Darwin.MAP_PRIVATE
private let MAP_FAILED = Darwin.MAP_FAILED
#elseif canImport(Glibc)
private let O_RDONLY = Glibc.O_RDONLY
private let PROT_READ = Glibc.PROT_READ
private let MAP_PRIVATE = Glibc.MAP_PRIVATE
private let MAP_FAILED = Glibc.MAP_FAILED
#endif
