//
//  DicomFile.swift
//  DICOM Test
//
//  Created by Rafael Warnault, OPALE on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

/**
 Class representing a DICOM file and all associated methods.
 With this class you can load a DICOM file from a given path to access its dataset of attributes.
 You can also write the dataset back to a file, process some validation, and get access to image or PDF data.
 
 Example:
 
        let dicomFile = DicomFile(forPath: filepath)
 
        print(dicomFile.dataset)
 
 */
public class DicomFile {
    // MARK: - Attributes
    /// The path of the loaded DICOM file
    public var filepath:String!
    /// The parsed dataset containing all the DICOM attributes
    public var dataset:DataSet!
    /// Define if the file has a standard DICOM prefix header. If yes, parsing witll start at 132 bytes offset, else at 0.
    public var hasPreamble:Bool = true
    /// A flag that informs if the file is a DICOM encapsulated PDF
    public var isEncapsulatedPDF = false
    
    // MARK: - Phase 4: Memory Mapping and Frame Index
    /// Optional memory-mapped file for zero-copy access
    private var memoryMappedFile: MemoryMappedFile?
    /// Frame index for efficient frame access
    private var frameIndex: FrameIndex?
    /// Whether memory mapping is enabled for this file
    public private(set) var isMemoryMapped: Bool = false
    
    
    // MARK: - Public methods
    /**
    Load a DICOM file
     
    - Parameter filepath: the path of the DICOM file to load
    */
    public init?(forPath filepath: String) {
        if !FileManager.default.fileExists(atPath: filepath) {
            Logger.error("No such file at \(filepath)")
            return nil
        }
        
        self.filepath = filepath
        
        if !self.read() { return nil }
    }
    
    /**
        Create a void dicomFile
     */
    internal init() { }
    
    /**
     Initialize a DICOM file with memory mapping enabled
     
     - Parameter filepath: the path of the DICOM file to load
     - Parameter enableMemoryMapping: whether to enable memory mapping for zero-copy access
     */
    public init?(forPath filepath: String, enableMemoryMapping: Bool = false) {
        if !FileManager.default.fileExists(atPath: filepath) {
            Logger.error("No such file at \(filepath)")
            return nil
        }
        
        self.filepath = filepath
        
        if !self.read() { return nil }
        
        // Initialize memory mapping and frame index if requested
        if enableMemoryMapping {
            do {
                try self.enableMemoryMapping()
            } catch {
                Logger.warning("Failed to enable memory mapping: \(error.localizedDescription)")
                // Continue without memory mapping
            }
        }
    }
    
    /**
    Get the formatted size of the current file path
     
    - Returns: a formatted string of the size in bytes of the current file path
    */
    public func fileSizeWithUnit() -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(self.fileSize()), countStyle: .file)
    }
    
    
    /**
    Get the size of the current file path
     
    - Returns: the size in bytes of the current file path
    */
    public func fileSize() -> UInt64 {
        return DicomFile.fileSize(path: self.filepath)
    }
    
    public class func fileSize(path:String) -> UInt64 {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: path)
            return attr[FileAttributeKey.size] as! UInt64
        } catch {
            Logger.error("Error: \(error)")
            return 0
        }
    }
    
    /**
    Get the filename of the current file path
     
    - Returns: the filename (with extension) of the current file path
    */
    public func fileName() -> String {
        return (self.filepath as NSString).lastPathComponent
    }
    
    /**
     Write the DICOM file at given path.
     
     - Parameter path: Path where to write the file
     - Parameter inVrMethod: the VR method used to write the file (explicit vs. implicit)
     - Parameter byteOrder: the endianess used to write the file (big vs. little endian)
     
     - Returns: true if the file was successfully written
     */
    public func write(
        atPath path:String,
        vrMethod inVrMethod:VRMethod? = nil,
        byteOrder inByteOrder:ByteOrder? = nil
    ) -> Bool {
        let outputStream = DicomOutputStream(filePath: path)
                
        do {
            return try outputStream.write(
                dataset: dataset,
                vrMethod: inVrMethod ?? nil,
                byteOrder: inByteOrder ?? nil)
            
        } catch StreamError.cannotOpenStream(let message) {
            Logger.error("\(message): \(String(describing: path))")
        } catch StreamError.cannotWriteStream(let message) {
            Logger.error("\(message): \(String(describing: path))")
        } catch StreamError.datasetIsCorrupted(let message) {
            Logger.error("\(message): \(String(describing: path))")
        } catch {
            Logger.error("Unknow error while writing: \(String(describing: path))")
        }

        return false
        
    }
    
    /**
     Write the DICOM file at given path.
     
     - Parameter path: Path where to write the file
     - Parameter transferSyntax: The transfer syntax used to write the file (EXPERIMENTAL)
     
     - Returns: true if the file was successfully written
     */
    public func write(atPath path:String, transferSyntax:String) -> Bool {        
        if transferSyntax == TransferSyntax.explicitVRLittleEndian {
            return write(atPath: path, vrMethod: .Explicit, byteOrder: .LittleEndian)
        }
        else if transferSyntax == TransferSyntax.implicitVRLittleEndian {
            return write(atPath: path, vrMethod: .Implicit, byteOrder: .LittleEndian)
        }
        else if transferSyntax == TransferSyntax.explicitVRBigEndian {
            return write(atPath: path, vrMethod: .Explicit, byteOrder: .BigEndian)
        }

        return false
    }
    
    
    /**
    - Returns: true if the file was found corrupted while parsing.
    */
    public func isCorrupted() -> Bool {
        return self.dataset.isCorrupted
    }
    
    
    /**
    Validate the file against DICM embedded specification (DcmSpec)
     
     - Returns: A ValidationResult array containing errors and warning issued from the validation process
    */
    public func validate() -> [ValidationResult] {
        return DicomSpec.shared.validate(file: self)
    }
    
    
    /**
     Instance of DicomImage if available.
     */
    public var dicomImage: DicomImage? {
        get {
            return DicomImage(self.dataset)
        }
    }
    
    
    /**
     Instance of SRDocument if available.
     */
    public var structuredReportDocument: SRDocument? {
        get {
            return SRDocument(withDataset: dataset)
        }
    }
    
    
    /**
     Tries to take out a PDF encapsulated in a DICOM file
     
     Takes out the PDF data from the `DataElement`, which tag is (0042,0011) EncapsulatedDocument.
     
     - Returns: the data of the PDF, or nil if not found
     */
    public func pdfData() -> Data? {
        if self.isEncapsulatedPDF {
            if let e = self.dataset.element(forTagName: "EncapsulatedDocument") {
                if e.length > 0 && e.data != nil {
                    return e.data
                }
            }
        }
        return nil
    }

    
    // MARK: - Static methods
    
    /**
     A static helper to check if the given file is a DICOM file
     
     Obsolete: It first looks at `DICM` magic world, and if not found (for old ACR-NEMA type of files) it
     checks the first group,element pair (0008,0004) before accepting the file as DICOM or not
     
     - Returns: A boolean value that indicates if the file is readable by DcmSwift
     */
    public static func isDicomFile(_ filepath: String) -> Bool {
        let inputStream = DicomInputStream(filePath: filepath)
        
        do {
            _ = try inputStream.readDataset(withoutPixelData: true)
            
            return true
        } catch _ {
            return false
        }
    }

    // MARK: - Private methods
    internal func read() -> Bool {
        let inputStream = DicomInputStream(filePath: filepath)
        
        do {
            if let dataset = try inputStream.readDataset(headerOnly: false, withoutPixelData: false) {
                hasPreamble     = inputStream.hasPreamble
                self.dataset    = dataset
                
                if let s = self.dataset.string(forTag: "MIMETypeOfEncapsulatedDocument") {
                    if s.trimmingCharacters(in: .whitespaces) == "application/pdf " {
                        Logger.debug("  -> MIMETypeOfEncapsulatedDocument : application/pdf")
                        isEncapsulatedPDF = true
                    }
                }
                
                inputStream.close()
                return true
            }
        } catch StreamError.cannotOpenStream(let message) {
            Logger.error("\(message): \(String(describing: filepath))")
        } catch StreamError.cannotReadStream(let message) {
            Logger.error("\(message): \(String(describing: filepath))")
        } catch StreamError.notDicomFile(let message) {
            Logger.error("\(message): \(String(describing: filepath))")
        } catch StreamError.datasetIsCorrupted(let message) {
            Logger.error("\(message): \(String(describing: filepath))")
        } catch {
            Logger.error("Unknow error while reading: \(String(describing: filepath))")
        }
                
        inputStream.close()
        return false
    }
    
    // MARK: - Phase 4: Memory Mapping and Frame Index Methods
    
    /**
     Enable memory mapping for zero-copy frame access
     
     - Throws: MemoryMappingError or FrameIndexError if initialization fails
     */
    public func enableMemoryMapping() throws {
        guard !isMemoryMapped else {
            return // Already enabled
        }
        
        // Create memory-mapped file
        memoryMappedFile = try MemoryMappedFile(filePath: filepath)
        
        // Build frame index
        frameIndex = try FrameIndex(dataset: dataset)
        
        isMemoryMapped = true
        Logger.debug("Memory mapping enabled for \(fileName()) with \(frameIndex?.count ?? 0) frames")
    }
    
    /**
     Disable memory mapping and cleanup resources
     */
    public func disableMemoryMapping() {
        memoryMappedFile?.cleanup()
        memoryMappedFile = nil
        frameIndex = nil
        isMemoryMapped = false
    }
    
    /**
     Get the number of frames in this DICOM file
     
     - Returns: Number of frames, or nil if frame index is not available
     */
    public func frameCount() -> Int? {
        return frameIndex?.count
    }
    
    /**
     Get frame data using zero-copy access (if memory mapping is enabled)
     
     - Parameter frameIndex: Index of the frame to retrieve (0-based)
     - Returns: Data containing the frame, or nil if not available
     */
    public func frameData(at frameIndex: Int) -> Data? {
        guard isMemoryMapped,
              let memoryMappedFile = memoryMappedFile,
              let frameInfo = self.frameIndex?.frameInfo(at: frameIndex) else {
            // Fallback to traditional method
            return traditionalFrameData(at: frameIndex)
        }
        
        // Use zero-copy access
        return memoryMappedFile.data(offset: frameInfo.offset, length: frameInfo.length)
    }
    
    /**
     Get frame data using traditional method (fallback)
     
     - Parameter frameIndex: Index of the frame to retrieve (0-based)
     - Returns: Data containing the frame, or nil if not available
     */
    private func traditionalFrameData(at frameIndex: Int) -> Data? {
        guard let pixelDataElement = dataset.element(forTagName: "PixelData") else {
            return nil
        }
        
        if let pixelSequence = pixelDataElement as? PixelSequence {
            // Encapsulated frames
            return try? pixelSequence.frameData(at: frameIndex)
        } else {
            // Native frames
            guard let numberOfFramesString = dataset.string(forTag: "NumberOfFrames"),
                  let numberOfFrames = Int(numberOfFramesString), numberOfFrames > 1 else {
                // Single frame
                return frameIndex == 0 ? pixelDataElement.data : nil
            }
            
            guard frameIndex >= 0 && frameIndex < numberOfFrames else {
                return nil
            }
            
            let frameSize = pixelDataElement.length / numberOfFrames
            let startOffset = frameIndex * frameSize
            let endOffset = min(startOffset + frameSize, pixelDataElement.data.count)
            
            guard startOffset < pixelDataElement.data.count else {
                return nil
            }
            
            return pixelDataElement.data.subdata(in: startOffset..<endOffset)
        }
    }
    
    /**
     Get frame information for a specific frame
     
     - Parameter frameIndex: Index of the frame (0-based)
     - Returns: FrameInfo containing offset and length, or nil if not available
     */
    public func frameInfo(at frameIndex: Int) -> FrameInfo? {
        return self.frameIndex?.frameInfo(at: frameIndex)
    }
    
    deinit {
        disableMemoryMapping()
    }
}
