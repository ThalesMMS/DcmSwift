//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 12/07/2021.
//

import Foundation

public class OffsetInputStream {
    var stream:InputStream!
    
    /// A copy of the original stream used if we need to reset the read offset
    var backstream:InputStream!
    
    /// The current position of the cursor in the stream
    internal var offset = 0
    
    /// The total number of bytes in the stream
    internal var total  = 0
    
    public var hasReadableBytes:Bool {
        get {
            return offset < total
        }
    }
    
    public var readableBytes:Int {
        get {
            return total - offset
        }
    }
    
    /**
     Init a DicomInputStream with a file path
     */
    public init(filePath:String) {
        let url = URL(fileURLWithPath: filePath)
        // Make memory mapping opt-in via env var to avoid Anonymous VM spikes on batch import
        let shouldMap = ProcessInfo.processInfo.environment["DCMSWIFT_MAP_IF_SAFE"] == "1"
        if shouldMap, let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            stream     = InputStream(data: data)
            backstream = InputStream(data: data)
            total      = data.count
        } else {
            stream      = InputStream(fileAtPath: filePath)
            backstream  = InputStream(fileAtPath: filePath)
            total       = Int(DicomFile.fileSize(path: filePath))
        }
    }

    /**
    Init a DicomInputStream with a file URL
    */
    public init(url:URL) {
        let shouldMap = ProcessInfo.processInfo.environment["DCMSWIFT_MAP_IF_SAFE"] == "1"
        if shouldMap, let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            stream     = InputStream(data: data)
            backstream = InputStream(data: data)
            total      = data.count
        } else {
            stream      = InputStream(url: url)
            backstream  = InputStream(url: url)
            total       = Int(DicomFile.fileSize(path: url.path))
        }
    }
    
    /**
    Init a DicomInputStream with a Data object
    */
    public init(data:Data) {
        stream      = InputStream(data: data)
        backstream  = InputStream(data: data)
        total       = data.count
    }
    
    
    deinit {
        close()
    }
    
    /**
     Opens the stream
     */
    public func open() {
        stream.open()
        backstream.open()
    }
    
    /**
     Closes the stream
     */
    public func close() {
        stream?.close(); backstream?.close()
        stream = nil; backstream = nil
    }

    
    /**
     Reads `length` bytes and returns the data read from the stream
     
     - Parameter length: the number of bytes to read
     - Returns: the data read in the stream, or nil
     */
    public func read(length:Int) -> Data? {
        // Validate length to prevent crashes and out-of-bounds reads
        guard length > 0 && length <= readableBytes else {
            Logger.warning("Invalid read length: \(length)")
            return nil
        }
        
        // Avoid extra allocations by reading directly into a Data buffer
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { ptr -> Int in
            guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else {
                return -1
            }
            return stream.read(base, maxLength: length)
        }

        // Bail out if the stream didn't deliver the requested bytes
        if read < length {
            return nil
        }

        // maintain local offset
        offset += read

        return data
    }

    
    /**
     Jumps of `bytes` bytes  in the stream
     
     - Parameter bytes: the number of bytes to jump in the stream
     */
    internal func forward(by bytes: Int) {
        // Consume bytes in fixed-size chunks to avoid allocating huge Data buffers.
        guard bytes > 0 else { return }
        var remaining = bytes
        let chunkSize = min(remaining, 1 << 20) // up to 1 MiB
        var scratch = Data(count: chunkSize)
        while remaining > 0 {
            let n = min(remaining, scratch.count)
            let readCount = scratch.withUnsafeMutableBytes { ptr -> Int in
                guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return stream.read(base, maxLength: n)
            }
            if readCount <= 0 { break }
            remaining -= readCount
            offset += readCount
        }
    }
}
