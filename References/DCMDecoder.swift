//
//  DCMDecoder.swift
//
//  This class parses DICOM files
//  encoded with little or big endian explicit or implicit VR and
//  extracts metadata and uncompressed pixel data.  The decoder
//  handles 8‑bit and 16‑bit grayscale images as well as 24‑bit
//  RGB images (common for ultrasound).  Compressed transfer
//  syntaxes are detected and rejected gracefully.  See the
//  original Objective‑C code for a one‑to‑one algorithmic
//  reference; this port emphasises clarity, safety and Swift
//  idioms while maintaining the same public API.
//
//  Usage:
//
//    let decoder = DCMDecoder()
//    decoder.setDicomFilename(url.path)
//    if decoder.dicomFileReadSuccess {
//        let pixels = decoder.getPixels16()
//        // process pixels
//    }
//

import Foundation
import CoreGraphics
import ImageIO

/// Various DICOM tag constants used by the decoder.  The values
/// mirror the hexadecimal definitions found in the original
/// Objective‑C header.  Group and element numbers are
/// concatenated into a single 32‑bit value.
private enum Tag: Int {
    // Image information
    case pixelRepresentation   = 0x00280103
    case transferSyntaxUID     = 0x00020010
    case sliceThickness        = 0x00180050
    case sliceSpacing          = 0x00180088
    case samplesPerPixel       = 0x00280002
    case photometricInterpretation = 0x00280004
    case planarConfiguration   = 0x00280006
    case numberOfFrames        = 0x00280008
    case rows                  = 0x00280010
    case columns               = 0x00280011
    case pixelSpacing          = 0x00280030
    case bitsAllocated         = 0x00280100
    case windowCenter          = 0x00281050
    case windowWidth           = 0x00281051
    case rescaleIntercept      = 0x00281052
    case rescaleSlope          = 0x00281053
    case redPalette            = 0x00281201
    case greenPalette          = 0x00281202
    case bluePalette           = 0x00281203
    case iconImageSequence     = 0x00880200
    case pixelData             = 0x7FE00010
    // Patient information (a small subset for demonstration)
    case patientID             = 0x00100020
    case patientName           = 0x00100010
    case patientSex            = 0x00100040
    case patientAge            = 0x00101010
    // Study information
    case studyInstanceUID      = 0x0020000d
    case studyID               = 0x00200010
    case studyDate             = 0x00080020
    case studyTime             = 0x00080030
    case studyDescription      = 0x00081030
    case numberOfStudyRelatedSeries = 0x00201206
    case modalitiesInStudy     = 0x00080061
    case referringPhysicianName = 0x00080090
    // Series information
    case seriesInstanceUID     = 0x0020000e
    case seriesNumber          = 0x00200011
    case seriesDate            = 0x00080021
    case seriesTime            = 0x00080031
    case seriesDescription     = 0x0008103E
    case numberOfSeriesRelatedInstances = 0x00201209
    case modality              = 0x00080060
    // SOP instance
    case sopInstanceUID        = 0x00080018
    case acquisitionDate       = 0x00080022
    case contentDate           = 0x00080023
    case acquisitionTime       = 0x00080032
    case contentTime           = 0x00080033
    case patientPosition       = 0x00185100
}

/// Value Representation codes expressed as their 16‑bit ASCII
/// representation.  These values correspond to the constants in
/// the original decoder (e.g. ``AE``, ``AS``, etc.).  Implicit
/// VR is represented by ``implicitRaw`` which is the value of
/// two hyphens (0x2D2D).  Unknown VR is represented by ``unknown``.
private enum VR: Int {
    case AE = 0x4145, AS = 0x4153, AT = 0x4154
    case CS = 0x4353, DA = 0x4441, DS = 0x4453
    case DT = 0x4454, FD = 0x4644, FL = 0x464C
    case IS = 0x4953, LO = 0x4C4F, LT = 0x4C54
    case PN = 0x504E, SH = 0x5348, SL = 0x534C
    case SS = 0x5353, ST = 0x5354, TM = 0x544D
    case UI = 0x5549, UL = 0x554C, US = 0x5553
    case UT = 0x5554, OB = 0x4F42, OW = 0x4F57
    case SQ = 0x5351, UN = 0x554E, QQ = 0x3F3F
    case RT = 0x5254
    case implicitRaw = 0x2D2D
    case unknown = 0

    /// Returns true if this VR expects a 32‑bit length when explicit.
    var uses32BitLength: Bool {
        switch self {
        case .OB, .OW, .SQ, .UN, .UT:
            return true
        default:
            return false
        }
    }
}

// MARK: - Main Decoder Class

/// Decoder for DICOM files.  Designed to work on uncompressed
/// transfer syntaxes with both little and big endian byte order and
/// explicit or implicit VR.  The public API mirrors the original
/// Objective‑C class but uses Swift properties and throws away
/// manual memory management.  Pixel buffers are returned as
/// optional arrays; they will be ``nil`` until ``setDicomFilename``
/// is invoked and decoding succeeds.
public final class DCMDecoder {
    
    // MARK: - Properties

    /// Dictionary used to translate tags to human readable names.  The
    /// original code stored a strong pointer to ``DCMDictionary``.
    private let dict = DCMDictionary.shared

    /// Raw filename used to open the file.  Kept for reference but
    /// never exposed directly.
    private var dicomFileName: String = ""

    /// Raw DICOM file contents.  The Data type is used instead of
    /// NSData to take advantage of value semantics and Swift
    /// performance characteristics.  All reads into this data
    /// respect the current ``location`` cursor.
    private var dicomData: Data = Data()
    
    /// OPTIMIZATION: Memory-mapped file for ultra-fast large file access
    private var mappedData: Data?
    private var fileSize: Int = 0

    /// Cursor into ``dicomData`` used for sequential reading.
    private var location: Int = 0

    /// Pixel representation: 0 for unsigned, 1 for two's complement
    /// signed data.  This affects how 16‑bit pixel data are
    /// normalised.
    private var pixelRepresentation: Int = 0

    /// The length of the current element value.  Computed by
    /// ``getLength()`` during tag parsing.
    private var elementLength: Int = 0

    /// The current Value Representation.  Represented as the raw
    /// 16‑bit ASCII code stored in the DICOM header.  A value of
    /// ``VR.implicitRaw`` indicates implicit VR.
    private var vr: VR = .unknown

    /// Minimum values used for mapping signed pixel data into
    /// unsigned representation.  ``min8`` is unused in this port
    /// but retained to mirror the original design.  ``min16`` is
    /// used when converting 16‑bit two's complement data into
    /// unsigned ranges.
    private var min8: Int = 0
    private var min16: Int = Int(Int16.min)

    /// Flags controlling how the decoder behaves when encountering
    /// certain structures in the file.
    private var oddLocations: Bool = false
    private var inSequence: Bool = false
    private var bigEndianTransferSyntax: Bool = false
    private var littleEndian: Bool = true

    /// Rescale intercept and slope.  These values are stored in
    /// DICOM headers and may be used to map pixel intensities to
    /// physical values.  This implementation does not apply them
    /// automatically but exposes them for clients to use as
    /// appropriate.
    private var rescaleIntercept: Double = 0.0
    private var rescaleSlope: Double = 1.0

    /// Colour lookup tables for palette‑based images.  These are
    /// rarely used in modern imaging but are included for
    /// completeness.  When present the decoder will populate them
    /// with one byte per entry, representing the high eight bits of
    /// the 16‑bit LUT values.  Clients may combine these into
    /// colour images as desired.
    private var reds: [UInt8]? = nil
    private var greens: [UInt8]? = nil
    private var blues: [UInt8]? = nil

    /// Buffers for pixel data.  Only one of these will be non‑nil
    /// depending on ``samplesPerPixel`` and ``bitDepth``.  Grayscale
    /// 8‑bit data uses ``pixels8``, grayscale 16‑bit data uses
    /// ``pixels16`` and colour (3 samples per pixel) uses
    /// ``pixels24``.
    private var pixels8: [UInt8]? = nil
    private var pixels16: [UInt16]? = nil
    private var pixels24: [UInt8]? = nil

    /// Dictionary of parsed metadata keyed by raw tag integer.
    /// Values consist of the VR description followed by a colon and
    /// the value.  For unknown tags the description may be
    /// ``"---"`` indicating a private tag.  Clients should use
    /// ``info(for:)`` to extract the value portion cleanly.
    private var dicomInfoDict: [Int: String] = [:]
    
    /// OPTIMIZATION: Cache for frequently accessed parsed values to avoid string processing
    private var cachedInfo: [Int: String] = [:]
    
    /// Frequently accessed DICOM tags that benefit from caching
    private static let frequentTags: Set<Int> = [
        0x00281053, // Rescale Slope
        0x00281052, // Rescale Intercept
        0x00281030, // Protocol Name
        0x0008103E, // Series Description
        0x00181030, // Protocol Name
        0x00280010, // Rows
        0x00280011, // Columns
        0x00280100, // Bits Allocated
        0x00280101, // Bits Stored
        0x00280102, // High Bit
        0x00280103  // Pixel Representation
    ]

    /// Transfer Syntax UID detected in the header.  Used to
    /// determine whether the image data is compressed and which
    /// decoder to use.  Stored when the `TRANSFER_SYNTAX_UID` tag
    /// is encountered in ``readFileInfo``.
    private var transferSyntaxUID: String = ""

    // MARK: - Public properties

    /// Bit depth of the decoded pixels (8 or 16).  Defaults to
    /// 16 until parsed from the header.  Read‑only outside the
    /// class.
    public private(set) var bitDepth: Int = 16

    /// Image dimensions in pixels.  Defaults to 1×1 until parsed.
    public private(set) var width: Int = 1
    public private(set) var height: Int = 1

    /// Byte offset from the start of ``dicomData`` to the
    /// beginning of ``pixelData``.  Useful for debugging.  Not
    /// currently used elsewhere in this class.
    private(set) var offset: Int = 1

    /// Number of frames in a multi‑frame image.  Defaults to 1.
    public private(set) var nImages: Int = 1

    /// Number of samples per pixel.  1 for grayscale, 3 for RGB.  If
    /// other values are encountered the decoder will still parse the
    /// metadata but the pixel data may not be interpretable by
    /// ``Dicom2DView``.  Defaults to 1.
    public private(set) var samplesPerPixel: Int = 1
    
    /// Photometric interpretation (MONOCHROME1 or MONOCHROME2).
    /// MONOCHROME1 means white is zero (common for X-rays)
    /// MONOCHROME2 means black is zero (standard grayscale)
    public private(set) var photometricInterpretation: String = ""

    /// Physical dimensions of the pixel spacing.  These values are
    /// derived from the ``PIXEL_SPACING`` and ``SLICE_THICKNESS``
    /// tags and may be used by clients to compute aspect ratios or
    /// volumetric measurements.
    public private(set) var pixelDepth: Double = 1.0
    public private(set) var pixelWidth: Double = 1.0
    public private(set) var pixelHeight: Double = 1.0

    /// Default window centre and width for display.  These come
    /// from the ``WINDOW_CENTER`` and ``WINDOW_WIDTH`` tags when
    /// present.  If absent they default to zero, leaving it to
    /// the viewer to choose appropriate values based on the image
    /// histogram.
    public private(set) var windowCenter: Double = 0.0
    public private(set) var windowWidth: Double = 0.0

    /// Flags indicating the status of the decoder.  `dicomFound`
    /// becomes true if the file begins with ``"DICM"`` at offset
    /// 128.  `dicomFileReadSuccess` indicates whether the header
    /// parsed successfully and pixels were read.  `compressedImage`
    /// becomes true if an unsupported transfer syntax is detected.
    /// `dicomDir` is reserved for future use to distinguish
    /// directory records.  `signedImage` indicates whether the
    /// pixel data originally used two's complement representation.
    private(set) var dicomFound: Bool = false
    public private(set) var dicomFileReadSuccess: Bool = false
    public private(set) var compressedImage: Bool = false
    private(set) var dicomDir: Bool = false
    public private(set) var signedImage: Bool = false

    // MARK: - Public API

    /// Assigns a file to decode.  The file is read into memory and
    /// parsed immediately.  Errors are logged to the console in
    /// DEBUG builds; on failure ``dicomFileReadSuccess`` will be
    /// false.  Calling this method resets any previous state.
    ///
    /// - Parameter filename: Path to the DICOM file on disk.
    public func setDicomFilename(_ filename: String) {
        guard !filename.isEmpty else {
            return
        }
        // Avoid re‑reading the same file
        if dicomFileName == filename {
            return
        }
        dicomFileName = filename
        do {
            let fileURL = URL(fileURLWithPath: filename)
            
            // OPTIMIZATION: Use memory-mapped reading for large files (>10MB)
            let attributes = try FileManager.default.attributesOfItem(atPath: filename)
            fileSize = attributes[.size] as? Int ?? 0
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            if fileSize > 10_000_000 { // >10MB - use memory mapping
                // Memory-mapped access for large files - dramatically faster
                dicomData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                mappedData = dicomData
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("[PERF] Memory-mapped DICOM load: \(String(format: "%.2f", elapsed))ms | size: \(fileSize/1024/1024)MB")
            } else {
                // Regular loading for smaller files
                dicomData = try Data(contentsOf: fileURL)
                mappedData = nil
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("[PERF] Regular DICOM load: \(String(format: "%.2f", elapsed))ms | size: \(fileSize/1024)KB")
            }
        } catch {
            print("[DCMDecoder] Error: Failed to load file at \(filename): \(error)")
            return
        }
        // Reset state
        dicomFileReadSuccess = false
        signedImage = false
        dicomDir = false
        location = 0
        windowCenter = 0
        windowWidth = 0
        dicomInfoDict.removeAll()
        // Parse the header
        if readFileInfo() {
            // If compressed transfer syntax, attempt to decode compressed pixel data.
            if !compressedImage {
                readPixels()
            } else {
                decodeCompressedPixelData()
            }
            dicomFileReadSuccess = true
        } else {
            dicomFileReadSuccess = false
        }
    }

    /// Returns the 8‑bit pixel buffer if the image is grayscale and
    /// encoded with eight bits per sample.  Returns ``nil`` if the
    /// buffer is not present.  The array length is ``width × height``.
    public func getPixels8() -> [UInt8]? {
        let startTime = CFAbsoluteTimeGetCurrent()
        if pixels8 == nil { readPixels() }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 1 { print("[PERF] getPixels8: \(String(format: "%.2f", elapsed))ms") }
        return pixels8
    }

    /// Returns the 16‑bit pixel buffer if the image is grayscale and
    /// encoded with sixteen bits per sample.  Returns ``nil`` if the
    /// buffer is not present.  The array length is ``width × height``.
    public func getPixels16() -> [UInt16]? {
        let startTime = CFAbsoluteTimeGetCurrent()
        if pixels16 == nil { readPixels() }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 1 { print("[PERF] getPixels16: \(String(format: "%.2f", elapsed))ms") }
        return pixels16
    }

    /// Returns the 8‑bit interleaved RGB pixel buffer if the image
    /// has three samples per pixel.  Returns ``nil`` if the buffer
    /// is not present.  The array length is ``width × height × 3``.
    public func getPixels24() -> [UInt8]? {
        let startTime = CFAbsoluteTimeGetCurrent()
        if pixels24 == nil { readPixels() }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 1 { print("[PERF] getPixels24: \(String(format: "%.2f", elapsed))ms") }
        return pixels24
    }
    
    /// Returns a downsampled 16-bit pixel buffer for thumbnail generation.
    /// This method reads only every Nth pixel to dramatically speed up thumbnail creation.
    /// - Parameter maxDimension: Maximum dimension for the thumbnail (default 150)
    /// - Returns: Tuple with downsampled pixels and dimensions, or nil if not available
    public func getDownsampledPixels16(maxDimension: Int = 150) -> (pixels: [UInt16], width: Int, height: Int)? {
        guard samplesPerPixel == 1 && bitDepth == 16 else { return nil }
        guard offset > 0 else { return nil }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Calculate proper aspect-preserving thumbnail dimensions
        let aspectRatio = Double(width) / Double(height)
        let thumbWidth: Int
        let thumbHeight: Int
        
        if width > height {
            thumbWidth = min(width, maxDimension)
            thumbHeight = Int(Double(thumbWidth) / aspectRatio)
        } else {
            thumbHeight = min(height, maxDimension)
            thumbWidth = Int(Double(thumbHeight) * aspectRatio)
        }
        
        // Calculate actual sampling step (can be fractional)
        let xStep = Double(width) / Double(thumbWidth)
        let yStep = Double(height) / Double(thumbHeight)
        
        print("[DCMDecoder] Downsampling \(width)x\(height) -> \(thumbWidth)x\(thumbHeight) (step: \(String(format: "%.2f", xStep))x\(String(format: "%.2f", yStep)))")
        
        var downsampledPixels = [UInt16](repeating: 0, count: thumbWidth * thumbHeight)
        
        dicomData.withUnsafeBytes { dataBytes in
            let basePtr = dataBytes.baseAddress!.advanced(by: offset)
            
            for thumbY in 0..<thumbHeight {
                for thumbX in 0..<thumbWidth {
                    // Calculate source pixel position
                    let sourceX = Int(Double(thumbX) * xStep)
                    let sourceY = Int(Double(thumbY) * yStep)
                    
                    // Ensure we don't go out of bounds
                    let clampedX = min(sourceX, width - 1)
                    let clampedY = min(sourceY, height - 1)
                    
                    let sourceIndex = (clampedY * width + clampedX) * 2
                    let thumbIndex = thumbY * thumbWidth + thumbX
                    
                    let b0 = basePtr.advanced(by: sourceIndex).assumingMemoryBound(to: UInt8.self).pointee
                    let b1 = basePtr.advanced(by: sourceIndex + 1).assumingMemoryBound(to: UInt8.self).pointee
                    
                    var value = littleEndian ? UInt16(b1) << 8 | UInt16(b0)
                                            : UInt16(b0) << 8 | UInt16(b1)
                    
                    // Handle MONOCHROME1 inversion
                    if photometricInterpretation == "MONOCHROME1" {
                        value = 65535 - value
                    }
                    
                    downsampledPixels[thumbIndex] = value
                }
            }
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[PERF] getDownsampledPixels16: \(String(format: "%.2f", elapsed))ms | thumbSize: \(thumbWidth)x\(thumbHeight)")
        
        return (downsampledPixels, thumbWidth, thumbHeight)
    }

    /// Retrieves the value of a parsed header as a string, trimming
    /// any leading description up to the colon.  Returns an empty
    /// string if the tag was not found.
    public func info(for tag: Int) -> String {
        // OPTIMIZATION: Check cache first for frequently accessed tags
        if DCMDecoder.frequentTags.contains(tag), let cached = cachedInfo[tag] {
            return cached
        }
        
        guard let info = dicomInfoDict[tag] else {
            return ""
        }
        
        // Split on the first colon to remove the VR description
        let result: String
        if let range = info.range(of: ":") {
            result = String(info[range.upperBound...].trimmingCharacters(in: .whitespaces))
        } else {
            result = info
        }
        
        // Cache frequently accessed tags
        if DCMDecoder.frequentTags.contains(tag) {
            cachedInfo[tag] = result
        }
        
        return result
    }

    // MARK: - Private helper methods

    /// Reads a string of the specified length from the current
    /// location, advancing the cursor.  The data is interpreted as
    /// UTF‑8.  If the bytes do not form valid UTF‑8 the result
    /// may contain replacement characters.  In the original
    /// implementation a zero‑terminated C string was created; here
    /// we simply decode a slice of the Data.
    /// DICOM strings may contain NUL padding which is removed.
    private func readString(length: Int) -> String {
        guard length > 0, location + length <= dicomData.count else {
            location += length
            return ""
        }
        let slice = dicomData[location..<location + length]
        location += length
        
        // Convert to string
        var str = String(data: slice, encoding: .utf8) ?? ""
        
        // Remove NUL characters and trim whitespace
        // DICOM strings are often padded with NUL (0x00) or spaces
        if let nullIndex = str.firstIndex(of: "\0") {
            str = String(str[..<nullIndex])
        }
        
        // Trim trailing spaces (common in DICOM)
        str = str.trimmingCharacters(in: .whitespaces)
        
        return str
    }

    /// Reads a single byte from the current location and advances
    /// the cursor.
    private func readByte() -> UInt8 {
        guard location < dicomData.count else { return 0 }
        let b = dicomData[location]
        location += 1
        return b
    }

    /// Reads a 16‑bit unsigned integer respecting the current
    /// endianness and advances the cursor.
    private func readShort() -> UInt16 {
        guard location + 1 < dicomData.count else { return 0 }
        let b0 = dicomData[location]
        let b1 = dicomData[location + 1]
        location += 2
        if littleEndian {
            return UInt16(b1) << 8 | UInt16(b0)
        } else {
            return UInt16(b0) << 8 | UInt16(b1)
        }
    }

    /// Reads a 32‑bit signed integer respecting the current
    /// endianness and advances the cursor.
    private func readInt() -> Int {
        guard location + 3 < dicomData.count else { return 0 }
        let b0 = dicomData[location]
        let b1 = dicomData[location + 1]
        let b2 = dicomData[location + 2]
        let b3 = dicomData[location + 3]
        location += 4
        let value: Int
        if littleEndian {
            value = Int(b3) << 24 | Int(b2) << 16 | Int(b1) << 8 | Int(b0)
        } else {
            value = Int(b0) << 24 | Int(b1) << 16 | Int(b2) << 8 | Int(b3)
        }
        return value
    }

    /// Reads a 64‑bit double precision floating point number.  The
    /// DICOM standard stores doubles as IEEE 754 values.  This
    /// implementation reconstructs the bit pattern into a UInt64
    /// then converts it to Double using Swift's bitPattern
    /// initializer.
    private func readDouble() -> Double {
        guard location + 7 < dicomData.count else { return 0.0 }
        var high: UInt32 = 0
        var low: UInt32 = 0
        if littleEndian {
            // bytes 4..7 become the high word
            high = UInt32(dicomData[location + 7]) << 24 |
                   UInt32(dicomData[location + 6]) << 16 |
                   UInt32(dicomData[location + 5]) << 8  |
                   UInt32(dicomData[location + 4])
            low  = UInt32(dicomData[location + 3]) << 24 |
                   UInt32(dicomData[location + 2]) << 16 |
                   UInt32(dicomData[location + 1]) << 8  |
                   UInt32(dicomData[location])
        } else {
            high = UInt32(dicomData[location]) << 24 |
                   UInt32(dicomData[location + 1]) << 16 |
                   UInt32(dicomData[location + 2]) << 8  |
                   UInt32(dicomData[location + 3])
            low  = UInt32(dicomData[location + 4]) << 24 |
                   UInt32(dicomData[location + 5]) << 16 |
                   UInt32(dicomData[location + 6]) << 8  |
                   UInt32(dicomData[location + 7])
        }
        location += 8
        let bits = UInt64(high) << 32 | UInt64(low)
        return Double(bitPattern: bits)
    }

    /// Reads a 32‑bit floating point number.  Similar to
    /// ``readDouble`` but producing a Float.  Because Swift's
    /// bitPattern initialisers require UInt32, we assemble the
    /// bytes accordingly then reinterpret the bits.
    private func readFloat() -> Float {
        guard location + 3 < dicomData.count else { return 0.0 }
        let value: UInt32
        if littleEndian {
            value = UInt32(dicomData[location + 3]) << 24 |
                    UInt32(dicomData[location + 2]) << 16 |
                    UInt32(dicomData[location + 1]) << 8  |
                    UInt32(dicomData[location])
        } else {
            value = UInt32(dicomData[location]) << 24 |
                    UInt32(dicomData[location + 1]) << 16 |
                    UInt32(dicomData[location + 2]) << 8  |
                    UInt32(dicomData[location + 3])
        }
        location += 4
        return Float(bitPattern: value)
    }

    /// Reads a lookup table stored as a sequence of 16‑bit values
    /// and converts them to 8‑bit entries by discarding the low
    /// eight bits.  Returns false if the length is odd, in which
    /// case the cursor is advanced and the table is skipped.
    private func readLUT(length: Int) -> [UInt8]? {
        guard length % 2 == 0 else {
            // Skip odd length sequences
            location += length
            return nil
        }
        let count = length / 2
        var table: [UInt8] = Array(repeating: 0, count: count)
        for i in 0..<count {
            let value = readShort()
            table[i] = UInt8(value >> 8)
        }
        return table
    }

    /// Determines the length of the next element.  Updates the
    /// current ``vr`` based on the data read.  This logic mirrors
    /// ``getLength()`` from the original code.  The return value is
    /// the element length in bytes.  Implicit VR is detected by
    /// noting cases where the two reserved bytes are non‑zero for
    /// certain VRs.
    private func getLength() -> Int {
        // Read four bytes without advancing the cursor prematurely
        guard location + 3 < dicomData.count else { return 0 }
        let b0 = dicomData[location]
        let b1 = dicomData[location + 1]
        let b2 = dicomData[location + 2]
        let b3 = dicomData[location + 3]
        location += 4
        // Combine the first two bytes into a VR code; this will be
        // overwritten later if we detect an implicit VR
        let rawVR = Int(UInt16(b0) << 8 | UInt16(b1))
        vr = VR(rawValue: rawVR) ?? .unknown
        var retValue: Int = 0
        switch vr {
        case .OB, .OW, .SQ, .UN, .UT:
            // Explicit VRs with 32‑bit lengths have two reserved
            // bytes (b2 and b3).  If those bytes are zero we
            // interpret the following 4 bytes as the length.
            if b2 == 0 || b3 == 0 {
                retValue = readInt()
            } else {
                // This is actually an implicit VR; the four bytes
                // read constitute the length.
                vr = .implicitRaw
                if littleEndian {
                    retValue = Int(b3) << 24 | Int(b2) << 16 | Int(b1) << 8 | Int(b0)
                } else {
                    retValue = Int(b0) << 24 | Int(b1) << 16 | Int(b2) << 8 | Int(b3)
                }
            }
        case .AE, .AS, .AT, .CS, .DA, .DS, .DT, .FD, .FL, .IS, .LO,
             .LT, .PN, .SH, .SL, .SS, .ST, .TM, .UI, .UL, .US, .QQ, .RT:
            // Explicit VRs with 16‑bit lengths
            if littleEndian {
                retValue = Int(b3) << 8 | Int(b2)
            } else {
                retValue = Int(b2) << 8 | Int(b3)
            }
        default:
            // Implicit VR with 32‑bit length
            vr = .implicitRaw
            if littleEndian {
                retValue = Int(b3) << 24 | Int(b2) << 16 | Int(b1) << 8 | Int(b0)
            } else {
                retValue = Int(b0) << 24 | Int(b1) << 16 | Int(b2) << 8 | Int(b3)
            }
        }
        return retValue
    }

    /// Reads the next tag from the stream.  Returns the tag value
    /// (group << 16 | element).  Updates ``elementLength`` and
    /// ``vr`` internally.  Implicit sequences update the
    /// ``inSequence`` flag.
    private func getNextTag() -> Int {
        // Check if we have enough data to read a tag
        guard location + 4 <= dicomData.count else {
            return 0  // Return 0 to signal end of data
        }
        
        let group = Int(readShort())
        // Endianness detection: if the group appears as 0x0800 in a
        // big endian transfer syntax we flip endianness.  This
        // mirrors the hack in the original implementation.
        var actualGroup = group
        if group == 0x0800 && bigEndianTransferSyntax {
            littleEndian = false
            actualGroup = 0x0008
        }
        let element = Int(readShort())
        let tag = actualGroup << 16 | element
        elementLength = getLength()
        
        // Handle undefined lengths indicating the start of a sequence
        if elementLength == -1 || elementLength == 0xFFFFFFFF {
            elementLength = 0
            inSequence = true
        }
        
        // Sanity check: element length should not exceed remaining data
        let remainingBytes = dicomData.count - location
        if elementLength > remainingBytes {
            elementLength = min(elementLength, remainingBytes)
        }
        
        // Correct for odd location hack
        if elementLength == 13 && !oddLocations {
            elementLength = 10
        }
        return tag
    }

    /// Constructs a human readable header string for the given tag
    /// and optional value.  This replicates the behaviour of
    /// ``getHeaderInfo(withValue:)`` in the original code.  If
    /// ``inSequence`` is true the description is prefixed with
    /// ``">"``.  Private tags (those with odd group numbers)
    /// receive the description ``"Private Tag"``.  Unknown tags
    /// produce nil.
    private func headerInfo(for tag: Int, value inValue: String?) -> String? {
        let key = String(format: "%08X", tag)
        // Handle sequence delimiters
        if key == "FFFEE000" || key == "FFFEE00D" || key == "FFFEE0DD" {
            inSequence = false
            return nil
        }
        var description: String? = dict.value(forKey: key)
        // Determine VR if implicit
        if let desc = description, vr == .implicitRaw {
            let rawVRCode = desc.prefix(2)
            if let ascii = rawVRCode.data(using: .utf8), ascii.count == 2 {
                let code = Int(UInt16(ascii[0]) << 8 | UInt16(ascii[1]))
                vr = VR(rawValue: code) ?? .unknown
            }
            description = String(desc.dropFirst(2))
        }
        // ITEM tags do not have a value
        if key == "FFFEE000" {
            description = description ?? ":null"
            return description
        }
        if let provided = inValue {
            let prefix = description ?? "---"
            return "\(prefix): \(provided)"
        }
        // Determine how to read the value based on VR
        var value: String? = nil
        var privateTag = false
        switch vr {
        case .FD:
            // Skip elementLength bytes (8 bytes per double)
            location += elementLength
        case .FL:
            // Skip elementLength bytes (4 bytes per float)
            location += elementLength
        case .AE, .AS, .AT, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UI:
            value = readString(length: elementLength)
        case .US:
            if elementLength == 2 {
                let s = readShort()
                value = String(s)
            } else {
                // Multiple unsigned shorts separated by spaces
                var vals = [String]()
                let count = elementLength / 2
                for _ in 0..<count {
                    vals.append(String(readShort()))
                }
                value = vals.joined(separator: " ")
            }
        case .implicitRaw:
            // Interpret as a string unless extremely long
            let s = readString(length: elementLength)
            if elementLength <= 44 {
                value = s
            } else {
                value = nil
            }
        case .SQ:
            // Sequences are read elsewhere; here we just skip
            value = ""
            privateTag = ((tag >> 16) & 1) != 0
            if tag != Tag.iconImageSequence.rawValue && !privateTag {
                break
            }
            location += elementLength
        default:
            // Unknown VR: skip the bytes
            location += elementLength
            value = ""
        }
        // Build the return string
        if value?.isEmpty == false {
            // If we have no description look up the tag again
            let desc = description ?? "---"
            return "\(desc): \(value ?? "")"
        } else if description == nil {
            return nil
        } else {
            let desc = description ?? "---"
            return "\(desc): \(value ?? "")"
        }
    }

    /// Adds the provided value to ``dicomInfoDict`` keyed by the raw
    /// tag.  If ``inSequence`` is true the stored string is
    /// prefixed with ``">"`` to indicate nesting.  Private tag
    /// markers ``"---"`` are replaced with the literal string
    /// ``"Private Tag"`` for clarity.
    private func addInfo(tag: Int, stringValue: String?) {
        guard let info = headerInfo(for: tag, value: stringValue) else { return }
        var stored = info
        if inSequence {
            stored = ">" + stored
        }
        // Replace unknown description marker with "Private Tag"
        if let range = stored.range(of: "---") {
            stored.replaceSubrange(range, with: "Private Tag")
        }
        dicomInfoDict[tag] = stored
    }

    /// Convenience overload for adding integer values as strings.
    private func addInfo(tag: Int, intValue: Int) {
        addInfo(tag: tag, stringValue: String(intValue))
    }

    /// Parses the ``PIXEL_SPACING`` string into separate x and y
    /// scales and stores them in ``pixelWidth`` and ``pixelHeight``.
    /// The expected format is ``"row\column"`` (note the use of
    /// backslash).  If the parsing fails the existing pixel
    /// dimensions are left unchanged.
    private func applySpatialScale(_ scale: String) {
        let components = scale.split(separator: "\\")
        guard components.count == 2,
              let y = Double(components[0]),
              let x = Double(components[1]) else {
            return
        }
        pixelHeight = y
        pixelWidth = x
    }

    /// Main header parsing loop.  This corresponds to
    /// ``readFileInfo()`` in the original code.  Returns false if
    /// the file is not a valid DICOM file or if an unsupported
    /// transfer syntax is encountered.  On success all metadata is
    /// recorded and available via properties or ``info(for:)``.
    private func readFileInfo() -> Bool {
        // Reset some state to sane defaults
        bitDepth = 16
        compressedImage = false
        // Move to offset 128 where "DICM" marker resides
        location = 128
        // Read the four magic bytes
        let fileMark = readString(length: 4)
        guard fileMark == "DICM" else {
            dicomFound = false
            return false
        }
        dicomFound = true
        samplesPerPixel = 1
        // Temporary variables for planar configuration and modality
        var planarConfiguration = 0
        var modality: String? = nil
        var decodingTags = true
        var tagCount = 0
        let maxTags = 10000  // Safety limit to prevent infinite loops
        
        while decodingTags && location < dicomData.count {
            tagCount += 1
            if tagCount > maxTags {
                print("[DCMDecoder] Warning: Exceeded max tags at location \(location)")
                // Don't set offset here - we're not at pixel data
                // Let the end of function handle finding pixel data
                break
            }
            
            let tag = getNextTag()
            
            // Check for end of data or invalid tag
            if tag == 0 || location >= dicomData.count {
                if offset == 0 {
                    offset = location
                }
                break
            }
            // Track odd byte offsets
            if (location & 1) != 0 {
                oddLocations = true
            }
            if inSequence {
                // Sequence content is handled inside headerInfo
                addInfo(tag: tag, stringValue: nil)
                continue
            }
            switch tag {
            case Tag.transferSyntaxUID.rawValue:
                // Read and store the transfer syntax UID
                let s = readString(length: elementLength)
                transferSyntaxUID = s
                addInfo(tag: tag, stringValue: s)
                // Detect compressed syntaxes.  JPEG Baseline (1.2.840.10008.1.2.4.50),
                // JPEG Extended (1.2.840.10008.1.2.4.51), JPEG‑LS (1.2.840.10008.1.2.4.80 and .81),
                // JPEG2000 Lossless (1.2.840.10008.1.2.4.90) and JPEG2000 Lossy (.91).
                let compressedPrefixes = ["1.2.840.10008.1.2.4.5",  // JPEG baseline & extended
                                          "1.2.840.10008.1.2.4.50", // JPEG baseline
                                          "1.2.840.10008.1.2.4.51", // JPEG extended
                                          "1.2.840.10008.1.2.4.57", // JPEG lossless
                                          "1.2.840.10008.1.2.4.70", // JPEG lossless, nonhierarchical, first‑order prediction
                                          "1.2.840.10008.1.2.4.80", // JPEG‑LS lossless
                                          "1.2.840.10008.1.2.4.81", // JPEG‑LS near‑lossless
                                          "1.2.840.10008.1.2.4.90", // JPEG2000 lossless
                                          "1.2.840.10008.1.2.4.91", // JPEG2000 lossy
                                          "1.2.840.10008.1.2.5"]   // RLE
                compressedImage = compressedPrefixes.contains { s.hasPrefix($0) }
                // Detect big endian explicit transfer syntax
                if s.contains("1.2.840.10008.1.2.2") {
                    bigEndianTransferSyntax = true
                }
            case Tag.modality.rawValue:
                modality = readString(length: elementLength)
                addInfo(tag: tag, stringValue: modality)
            case Tag.numberOfFrames.rawValue:
                let s = readString(length: elementLength)
                addInfo(tag: tag, stringValue: s)
                if let frames = Double(s), frames > 1.0 {
                    nImages = Int(frames)
                }
            case Tag.samplesPerPixel.rawValue:
                let spp = Int(readShort())
                samplesPerPixel = spp
                addInfo(tag: tag, intValue: spp)
            case Tag.photometricInterpretation.rawValue:
                let s = readString(length: elementLength)
                photometricInterpretation = s
                addInfo(tag: tag, stringValue: s)
            case Tag.planarConfiguration.rawValue:
                planarConfiguration = Int(readShort())
                addInfo(tag: tag, intValue: planarConfiguration)
            case Tag.rows.rawValue:
                let h = Int(readShort())
                height = h
                addInfo(tag: tag, intValue: h)
            case Tag.columns.rawValue:
                let w = Int(readShort())
                width = w
                addInfo(tag: tag, intValue: w)
            case Tag.pixelSpacing.rawValue:
                let scale = readString(length: elementLength)
                applySpatialScale(scale)
                addInfo(tag: tag, stringValue: scale)
            case Tag.sliceThickness.rawValue, Tag.sliceSpacing.rawValue:
                let spacing = readString(length: elementLength)
                pixelDepth = Double(spacing) ?? pixelDepth
                addInfo(tag: tag, stringValue: spacing)
            case Tag.bitsAllocated.rawValue:
                let depth = Int(readShort())
                bitDepth = depth
                addInfo(tag: tag, intValue: depth)
            case Tag.pixelRepresentation.rawValue:
                pixelRepresentation = Int(readShort())
                addInfo(tag: tag, intValue: pixelRepresentation)
            case Tag.windowCenter.rawValue:
                var center = readString(length: elementLength)
                if let index = center.firstIndex(of: "\\") {
                    center = String(center[center.index(after: index)...])
                }
                windowCenter = Double(center) ?? 0.0
                addInfo(tag: tag, stringValue: center)
            case Tag.windowWidth.rawValue:
                var widthS = readString(length: elementLength)
                if let index = widthS.firstIndex(of: "\\") {
                    widthS = String(widthS[widthS.index(after: index)...])
                }
                windowWidth = Double(widthS) ?? 0.0
                addInfo(tag: tag, stringValue: widthS)
            case Tag.rescaleIntercept.rawValue:
                let intercept = readString(length: elementLength)
                rescaleIntercept = Double(intercept) ?? 0.0
                addInfo(tag: tag, stringValue: intercept)
            case Tag.rescaleSlope.rawValue:
                let slope = readString(length: elementLength)
                rescaleSlope = Double(slope) ?? 1.0
                addInfo(tag: tag, stringValue: slope)
            case Tag.redPalette.rawValue:
                if let table = readLUT(length: elementLength) {
                    reds = table
                    addInfo(tag: tag, intValue: table.count)
                }
            case Tag.greenPalette.rawValue:
                if let table = readLUT(length: elementLength) {
                    greens = table
                    addInfo(tag: tag, intValue: table.count)
                }
            case Tag.bluePalette.rawValue:
                if let table = readLUT(length: elementLength) {
                    blues = table
                    addInfo(tag: tag, intValue: table.count)
                }
            case Tag.pixelData.rawValue:
                offset = location
                addInfo(tag: tag, intValue: location)
                print("[DCMDecoder] Found pixel data tag at offset \(offset), elementLength=\(elementLength)")
                decodingTags = false  // Stop processing after pixel data
            default:
                // Unhandled tag; defer to headerInfo which will read
                // the appropriate number of bytes based on VR
                addInfo(tag: tag, stringValue: nil)
            }
        }
        
        // Ensure we have a valid pixel data offset
        if offset == 0 {
            // If we couldn't find the pixel data tag, try to locate it
            // Pixel data is usually at the end of the file
            // Calculate expected size
            let expectedPixelBytes = width * height * samplesPerPixel * (bitDepth / 8)
            if expectedPixelBytes > 0 && dicomData.count > expectedPixelBytes {
                // Assume pixel data is at the end
                offset = dicomData.count - expectedPixelBytes
                print("[DCMDecoder] No pixel data tag found, assuming pixels at offset \(offset)")
            } else {
                print("[DCMDecoder] Error: Could not determine pixel data location")
                return false
            }
        }
        
        return true
    }

    /// Converts a two's complement encoded 16‑bit value into an
    /// unsigned 16‑bit representation.  This is used when
    /// ``pixelRepresentation`` equals one to map signed pixel values
    /// into the positive range expected by rendering code.  The
    /// algorithm subtracts the minimum short value to shift the
    /// range appropriately.
    private func normaliseSigned16(bytes b0: UInt8, b1: UInt8) -> UInt16 {
        let combined = Int16(bitPattern: UInt16(b1) << 8 | UInt16(b0))
        // Shift negative values up by min16 to make them positive
        let shifted = Int(combined) - min16
        return UInt16(shifted)
    }

    /// Reads the pixel data from the DICOM file.  This method
    /// allocates new buffers for each invocation and clears any
    /// previous buffers.  It supports 8‑bit grayscale, 16‑bit
    /// grayscale and 8‑bit 3‑channel RGB images.  Other values of
    /// ``samplesPerPixel`` or ``bitDepth`` result in empty buffers.
    private func readPixels() {
        let startTime = CFAbsoluteTimeGetCurrent()
        // Clear any previously stored buffers
        pixels8 = nil
        pixels16 = nil
        pixels24 = nil
        // Grayscale 8‑bit
        if samplesPerPixel == 1 && bitDepth == 8 {
            let numPixels = width * height
            guard offset > 0 && offset + numPixels <= dicomData.count else {
                return
            }
            pixels8 = Array(dicomData[offset..<offset + numPixels])
            
            // Handle MONOCHROME1 (white is zero) - common for X-rays
            if photometricInterpretation == "MONOCHROME1" {
                if var p8 = pixels8 {
                    for i in 0..<numPixels {
                        p8[i] = 255 - p8[i]
                    }
                    pixels8 = p8
                }
            }
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[PERF] readPixels (8-bit): \(String(format: "%.2f", elapsed))ms | size: \(width)x\(height)")
            return
        }
        // Grayscale 16‑bit
        if samplesPerPixel == 1 && bitDepth == 16 {
            let numPixels = width * height
            let numBytes = numPixels * 2
            
            // Debug logging
            print("[DCMDecoder] Reading 16-bit pixels: width=\(width), height=\(height), numPixels=\(numPixels), offset=\(offset), dataSize=\(dicomData.count)")
            
            guard offset > 0 && offset + numBytes <= dicomData.count else {
                print("[DCMDecoder] Error: Invalid offset or insufficient data. offset=\(offset), needed=\(numBytes), available=\(dicomData.count - offset)")
                return
            }
            
            // OPTIMIZATION: Use withUnsafeBytes for much faster pixel reading
            pixels16 = Array(repeating: 0, count: numPixels)
            guard var pixels = pixels16 else { return }
            
            dicomData.withUnsafeBytes { dataBytes in
                let basePtr = dataBytes.baseAddress!.advanced(by: offset)
                
                if pixelRepresentation == 0 {
                    // Unsigned pixels - most common for CR/DX
                    if littleEndian {
                        // Little endian (most common)
                        // Check if the pointer is aligned for UInt16 access
                        if offset % 2 == 0 {
                            // Aligned - can use fast path
                            basePtr.withMemoryRebound(to: UInt16.self, capacity: numPixels) { uint16Ptr in
                                if photometricInterpretation == "MONOCHROME1" {
                                    // Invert for MONOCHROME1 (white is zero)
                                    for i in 0..<numPixels {
                                        pixels[i] = 65535 - uint16Ptr[i]
                                    }
                                } else {
                                    // Direct copy for MONOCHROME2
                                    pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                                        _ = memcpy(pixelBuffer.baseAddress!, uint16Ptr, numBytes)
                                    }
                                }
                            }
                        } else {
                            // Unaligned - use byte-by-byte reading
                            let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)
                            for i in 0..<numPixels {
                                let byteIndex = i * 2
                                let b0 = uint8Ptr[byteIndex]
                                let b1 = uint8Ptr[byteIndex + 1]
                                var value = UInt16(b0) | (UInt16(b1) << 8)  // Little endian
                                if photometricInterpretation == "MONOCHROME1" {
                                    value = 65535 - value
                                }
                                pixels[i] = value
                            }
                        }
                    } else {
                        // Big endian (rare)
                        let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)
                        for i in 0..<numPixels {
                            let byteIndex = i * 2
                            let b0 = uint8Ptr[byteIndex]
                            let b1 = uint8Ptr[byteIndex + 1]
                            var value = UInt16(b0) << 8 | UInt16(b1)
                            if photometricInterpretation == "MONOCHROME1" {
                                value = 65535 - value
                            }
                            pixels[i] = value
                        }
                    }
                    signedImage = false
                } else {
                    // Signed pixels (less common)
                    signedImage = true
                    let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<numPixels {
                        let byteIndex = i * 2
                        let b0 = uint8Ptr[byteIndex]
                        let b1 = uint8Ptr[byteIndex + 1]
                        var value = normaliseSigned16(bytes: b0, b1: b1)
                        if photometricInterpretation == "MONOCHROME1" {
                            value = UInt16(32768) - (value - UInt16(32768))
                        }
                        pixels[i] = value
                    }
                }
            }
            
            pixels16 = pixels
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[PERF] readPixels (16-bit): \(String(format: "%.2f", elapsed))ms | size: \(width)x\(height) | pixels: \(numPixels)")
            return
        }
        // Colour 8‑bit RGB
        if samplesPerPixel == 3 && bitDepth == 8 {
            signedImage = false
            let numBytes = width * height * 3
            guard offset + numBytes <= dicomData.count else { return }
            pixels24 = Array(dicomData[offset..<offset + numBytes])
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[PERF] readPixels (24-bit RGB): \(String(format: "%.2f", elapsed))ms | size: \(width)x\(height)")
            return
        }
        // Fallback: leave buffers nil
    }

    /// Attempts to decode compressed pixel data using ImageIO.
    /// This function supports common DICOM transfer syntaxes
    /// including JPEG Baseline, JPEG Extended, JPEG‑LS and
    /// JPEG2000.  The compressed data is assumed to begin at
    /// ``offset`` and extend to the end of ``dicomData``.  On
    /// success the ``pixels8``, ``pixels16`` or ``pixels24``
    /// buffers are populated accordingly.  If decoding fails the
    /// buffers remain nil and ``dicomFileReadSuccess`` is set to
    /// false.
    private func decodeCompressedPixelData() {
        // Extract the encapsulated pixel data from the offset to
        // the end of the file.  Some DICOM files encapsulate each
        // frame into separate items; for simplicity we treat the
        // entire remaining data as one JPEG/JP2 codestream.  For
        // robust handling you would need to parse the Basic Offset
        // Table and items (see PS3.5).  This implementation is
        // designed to handle single–frame images.
        let compressedData = dicomData.subdata(in: offset..<dicomData.count)
        // Create an image source from the compressed data.  ImageIO
        // automatically detects JPEG, JPEG2000 and JPEG‑LS formats.
        guard let source = CGImageSourceCreateWithData(compressedData as CFData, nil) else {
            dicomFileReadSuccess = false
            return
        }
        // Decode the first image in the source.
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            dicomFileReadSuccess = false
            return
        }
        // Retrieve dimensions
        width = cgImage.width
        height = cgImage.height
        bitDepth = cgImage.bitsPerComponent
        // Determine number of colour samples.  bitsPerPixel may
        // include alpha; we compute based on bitsPerPixel and
        // bitsPerComponent.
        let samples = max(1, cgImage.bitsPerPixel / cgImage.bitsPerComponent)
        samplesPerPixel = samples >= 3 ? 3 : 1
        signedImage = false
        // Prepare a context to extract the pixel data.  For colour
        // images we render into a BGRA 32‑bit buffer; for grayscale
        // we render into an 8‑bit buffer.
        if samplesPerPixel == 1 {
            // Grayscale output
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bytesPerRow = width
            guard let ctx = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                dicomFileReadSuccess = false
                return
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let dataPtr = ctx.data else {
                dicomFileReadSuccess = false
                return
            }
            let buffer = dataPtr.assumingMemoryBound(to: UInt8.self)
            let count = width * height
            pixels8 = [UInt8](UnsafeBufferPointer(start: buffer, count: count))
        } else {
            // Colour output.  Render into BGRA and then strip alpha.
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            guard let ctx = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
                dicomFileReadSuccess = false
                return
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let dataPtr = ctx.data else {
                dicomFileReadSuccess = false
                return
            }
            let rawBuffer = dataPtr.assumingMemoryBound(to: UInt8.self)
            let count = width * height
            // Allocate pixel24 and fill with RGB triples (BGR in
            // little endian).  We omit the alpha channel.
            var output = [UInt8](repeating: 0, count: count * 3)
            for i in 0..<count {
                let srcIndex = i * 4
                let dstIndex = i * 3
                // CGImage in little endian stores bytes as BGRA
                let blue  = rawBuffer[srcIndex]
                let green = rawBuffer[srcIndex + 1]
                let red   = rawBuffer[srcIndex + 2]
                output[dstIndex]     = blue
                output[dstIndex + 1] = green
                output[dstIndex + 2] = red
            }
            pixels24 = output
        }
    }
}
