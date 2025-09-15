//
//  DcmDecompress - DICOM Decompression Test Tool
//  DcmSwift
//
//  Tests and demonstrates DICOM image decompression capabilities.
//

import Foundation
import DcmSwift

@main
struct DcmDecompress {
    static func main() {
        let args = CommandLine.arguments

        if args.count < 2 {
            printUsage()
            exit(1)
        }

        let command = args[1]

        switch command {
        case "test":
            if args.count < 3 {
                print("Error: Please specify a DICOM file to test")
                exit(1)
            }
            testDecompression(file: args[2])

        case "batch":
            if args.count < 3 {
                print("Error: Please specify a directory to test")
                exit(1)
            }
            batchTest(directory: args[2])

        case "info":
            if args.count < 3 {
                print("Error: Please specify a DICOM file")
                exit(1)
            }
            showInfo(file: args[2])

        default:
            printUsage()
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        DcmDecompress - DICOM Decompression Test Tool

        Usage:
            DcmDecompress test <file>    Test decompression of a single DICOM file
            DcmDecompress batch <dir>     Test all DICOM files in a directory
            DcmDecompress info <file>     Show compression info for a DICOM file

        Supported Transfer Syntaxes:
            - JPEG Baseline (1.2.840.10008.1.2.4.50)
            - JPEG Extended (1.2.840.10008.1.2.4.51)
            - JPEG Lossless Process 14 (1.2.840.10008.1.2.4.57)
            - JPEG Lossless Process 14 SV1 (1.2.840.10008.1.2.4.70)
            - JPEG-LS Lossless (1.2.840.10008.1.2.4.80)
            - JPEG-LS Near-Lossless (1.2.840.10008.1.2.4.81)
            - JPEG 2000 Lossless (1.2.840.10008.1.2.4.90)
            - JPEG 2000 Lossy (1.2.840.10008.1.2.4.91)
            - RLE Lossless (1.2.840.10008.1.2.5)
        """)
    }

    static func testDecompression(file: String) {
        print("Testing decompression for: \(file)")
        print("-" * 60)

        guard let dicomFile = DicomFile(forPath: file),
              let dataset = dicomFile.dataset else {
            print("❌ Failed to load DICOM file")
            exit(1)
        }

        // Get transfer syntax
        let tsUID = dataset.transferSyntax.tsUID
        let tsName = transferSyntaxName(for: tsUID)
        print("Transfer Syntax: \(tsUID) (\(tsName))")

        // Get image info
        let rows = dataset.integer16(forTag: "Rows") ?? 0
        let cols = dataset.integer16(forTag: "Columns") ?? 0
        let frames = Int(dataset.string(forTag: "NumberOfFrames") ?? "1") ?? 1
        let bitsAllocated = dataset.integer16(forTag: "BitsAllocated") ?? 0
        let photometric = dataset.string(forTag: "PhotometricInterpretation") ?? "UNKNOWN"

        print("Image: \(cols)x\(rows), \(frames) frame(s), \(bitsAllocated) bits")
        print("Photometric: \(photometric)")
        print("-" * 60)

        // Test decompression using PixelService
        let startTime = CFAbsoluteTimeGetCurrent()
        var successCount = 0
        var failureCount = 0

        for frameIndex in 0..<min(frames, 5) { // Test first 5 frames max
            print("Frame \(frameIndex + 1)/\(frames): ", terminator: "")

            do {
                let frameStart = CFAbsoluteTimeGetCurrent()
                if #available(iOS 14.0, macOS 11.0, *) {
                    let decoded = try PixelService.shared.decodeFrame(from: dataset, frameIndex: frameIndex)
                    let frameTime = (CFAbsoluteTimeGetCurrent() - frameStart) * 1000

                    // Verify decoded data
                    let hasPixelData = (decoded.pixels8 != nil) || (decoded.pixels16 != nil)
                    if hasPixelData {
                        let pixelType = decoded.pixels16 != nil ? "16-bit" : "8-bit"
                        print("✅ Decoded (\(pixelType), \(String(format: "%.1f", frameTime))ms)")
                        successCount += 1
                    } else {
                        print("⚠️  Decoded but no pixel data")
                        failureCount += 1
                    }
                } else {
                    print("❌ Requires iOS 14.0 or macOS 11.0")
                    failureCount += 1
                }
            } catch {
                print("❌ Failed: \(error)")
                failureCount += 1
            }
        }

        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("-" * 60)
        print("Results: \(successCount) succeeded, \(failureCount) failed")
        print("Total time: \(String(format: "%.1f", totalTime))ms")

        // Try alternative method with DicomImage
        print("\nTesting with DicomImage:")
        if let dicomImage = DicomImage(dataset) {
            if let uiImage = dicomImage.image(forFrame: 0) {
                print("✅ DicomImage decode successful")
                print("   Size: \(Int(uiImage.size.width))x\(Int(uiImage.size.height))")
            } else {
                print("❌ DicomImage failed to create UIImage")
            }
        } else {
            print("❌ DicomImage initialization failed")
        }
    }

    static func batchTest(directory: String) {
        print("Batch testing directory: \(directory)")
        print("=" * 60)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else {
            print("❌ Cannot access directory")
            exit(1)
        }

        var results: [(file: String, syntax: String, success: Bool, time: Double)] = []

        for case let file as String in enumerator {
            let fullPath = (directory as NSString).appendingPathComponent(file)
            let ext = (file as NSString).pathExtension.lowercased()

            // Check if it's likely a DICOM file
            if ext == "dcm" || ext == "dicom" || ext == "" {
                if let dicomFile = DicomFile(forPath: fullPath),
                   let dataset = dicomFile.dataset {

                    let tsUID = dataset.transferSyntax.tsUID

                    // Skip uncompressed files
                    if tsUID == "1.2.840.10008.1.2" || tsUID == "1.2.840.10008.1.2.1" || tsUID == "1.2.840.10008.1.2.2" {
                        continue
                    }

                    print("\nTesting: \(file)")
                    let startTime = CFAbsoluteTimeGetCurrent()
                    var success = false

                    do {
                        if #available(iOS 14.0, macOS 11.0, *) {
                            _ = try PixelService.shared.decodeFirstFrame(from: dataset)
                            success = true
                            print("  ✅ Success")
                        } else {
                            print("  ❌ Requires iOS 14.0 or macOS 11.0")
                        }
                    } catch {
                        print("  ❌ Failed: \(error)")
                    }

                    let time = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    results.append((file: file, syntax: tsUID, success: success, time: time))
                }
            }
        }

        // Print summary
        print("\n" + "=" * 60)
        print("SUMMARY")
        print("=" * 60)

        let grouped = Dictionary(grouping: results) { transferSyntaxName(for: $0.syntax) }
        for (syntax, items) in grouped.sorted(by: { $0.key < $1.key }) {
            let successful = items.filter { $0.success }.count
            let total = items.count
            let avgTime = items.map { $0.time }.reduce(0, +) / Double(items.count)

            print("\n\(syntax):")
            print("  Files: \(total)")
            print("  Success: \(successful)/\(total) (\(successful * 100 / max(total, 1))%)")
            print("  Avg time: \(String(format: "%.1f", avgTime))ms")
        }
    }

    static func showInfo(file: String) {
        guard let dicomFile = DicomFile(forPath: file),
              let dataset = dicomFile.dataset else {
            print("❌ Failed to load DICOM file")
            exit(1)
        }

        print("DICOM File Information")
        print("=" * 60)
        print("File: \(file)")

        // Transfer syntax
        let tsUID = dataset.transferSyntax.tsUID
        let tsName = transferSyntaxName(for: tsUID)
        let isCompressed = !TransferSyntax.transfersSyntaxes.contains(tsUID)
        print("\nTransfer Syntax:")
        print("  UID: \(tsUID)")
        print("  Name: \(tsName)")
        print("  Compressed: \(isCompressed ? "Yes" : "No")")

        // Image properties
        print("\nImage Properties:")
        print("  Rows: \(dataset.integer16(forTag: "Rows") ?? 0)")
        print("  Columns: \(dataset.integer16(forTag: "Columns") ?? 0)")
        print("  Frames: \(dataset.string(forTag: "NumberOfFrames") ?? "1")")
        print("  Bits Allocated: \(dataset.integer16(forTag: "BitsAllocated") ?? 0)")
        print("  Bits Stored: \(dataset.integer16(forTag: "BitsStored") ?? 0)")
        print("  High Bit: \(dataset.integer16(forTag: "HighBit") ?? 0)")
        print("  Pixel Representation: \(dataset.integer16(forTag: "PixelRepresentation") ?? 0)")
        print("  Samples Per Pixel: \(dataset.integer16(forTag: "SamplesPerPixel") ?? 1)")
        print("  Photometric: \(dataset.string(forTag: "PhotometricInterpretation") ?? "UNKNOWN")")

        // Pixel data info
        if let pixelData = dataset.element(forTagName: "PixelData") {
            print("\nPixel Data:")
            // Check if it's compressed based on transfer syntax
            let isCompressed = !TransferSyntax.transfersSyntaxes.contains(dataset.transferSyntax.tsUID)
            print("  Type: \(isCompressed ? "Encapsulated (compressed)" : "Native (uncompressed)")")
            print("  Length: \(pixelData.length) bytes")
        }

        // Modality specific
        let modality = dataset.string(forTag: "Modality") ?? "UNKNOWN"
        print("\nModality: \(modality)")

        if modality == "CT" {
            print("  Rescale Intercept: \(dataset.string(forTag: "RescaleIntercept") ?? "N/A")")
            print("  Rescale Slope: \(dataset.string(forTag: "RescaleSlope") ?? "N/A")")
        }

        if let windowCenter = dataset.string(forTag: "WindowCenter"),
           let windowWidth = dataset.string(forTag: "WindowWidth") {
            print("  Window Center: \(windowCenter)")
            print("  Window Width: \(windowWidth)")
        }
    }

    static func transferSyntaxName(for uid: String) -> String {
        switch uid {
        case "1.2.840.10008.1.2": return "Implicit VR Little Endian"
        case "1.2.840.10008.1.2.1": return "Explicit VR Little Endian"
        case "1.2.840.10008.1.2.2": return "Explicit VR Big Endian"
        case "1.2.840.10008.1.2.4.50": return "JPEG Baseline"
        case "1.2.840.10008.1.2.4.51": return "JPEG Extended"
        case "1.2.840.10008.1.2.4.57": return "JPEG Lossless Process 14"
        case "1.2.840.10008.1.2.4.70": return "JPEG Lossless Process 14 SV1"
        case "1.2.840.10008.1.2.4.80": return "JPEG-LS Lossless"
        case "1.2.840.10008.1.2.4.81": return "JPEG-LS Near-Lossless"
        case "1.2.840.10008.1.2.4.90": return "JPEG 2000 Lossless"
        case "1.2.840.10008.1.2.4.91": return "JPEG 2000 Lossy"
        case "1.2.840.10008.1.2.5": return "RLE Lossless"
        default: return "Unknown"
        }
    }
}

// Helper to repeat strings
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}