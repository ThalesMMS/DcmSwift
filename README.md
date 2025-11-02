# DcmSwift

DcmSwift is a Swift package that implements the DICOM standard with an emphasis on predictable performance and practical tooling. It combines GPU accelerated image processing, complete DIMSE and DICOMweb networking stacks, and utilities for integrating with PACS systems.

## Highlights

- GPU-accelerated window and level operations through Metal compute shaders, with a CPU path fallback.
- Vectorised CPU pipelines using vDSP for LUT generation and pixel mapping.
- Complete DIMSE services (C-ECHO, C-FIND, C-STORE, C-GET, C-MOVE) and DICOMweb clients (WADO-RS, QIDO-RS, STOW-RS).
- Command-line tools for inspecting, anonymising, retrieving, and serving DICOM data.
- Production-oriented design with streaming decode, persistent buffers, and configurable caching.

## Key Features

### Complete DICOM Query/Retrieve Services

#### DICOMWeb
- **WADO-RS**: Retrieves studies, series, instances, metadata, and rendered images
- **QIDO-RS**: Searches for studies, series, and instances with various query parameters
- **STOW-RS**: Stores DICOM instances, metadata, and bulk data
- **DICOMweb Client**: Single client for all DICOMweb services

#### DIMSE Protocol Implementation
- **C-ECHO**: Connection testing and keepalive
- **C-FIND**: Query with fixed PDU packing (command and dataset in single P-DATA-TF)
- **C-STORE**: Send and receive DICOM objects
- **C-GET**: Direct retrieval with C-STORE sub-operations on same association
- **C-MOVE**: Remote-initiated transfers with optional local receiver
- **Robust PDU handling**: Multi-fragment support, proper dataset flags and group lengths

### High-Performance Image Processing

#### GPU Acceleration
- **Metal Compute Pipeline**: Hardware-accelerated window/level adjustments
- **Buffer Caching**: Reusable Metal buffers minimize allocations
- **Automatic Fallback**: Seamless CPU processing when Metal unavailable
- **RGB Support**: Direct RGB pixel processing in Metal shaders

#### Optimized CPU Path
- **vDSP Vectorization**: SIMD-accelerated LUT generation and pixel mapping
- **Streaming Pixel Data**: Progressive loading from `DicomInputStream`
- **Persistent Buffers**: `DicomPixelView` maintains raw pixels across W/L changes
- **Fast 16->8 Mapping**: Vectorized conversion for display

#### Concurrency & Memory
- **Concurrency**: Async/await in DICOMweb and utilities; DIMSE uses NIO with sync wrappers
- **Threading**: Select types adopt `Sendable` where applicable
- **Caching**: Buffer reuse and LUT caching in rendering paths
- **Memory-Mapped I/O**: Optional, enable via `DCMSWIFT_MAP_IF_SAFE=1`

## Requirements

* macOS 10.15+ / iOS 13.0+
* Xcode 14+
* Swift 5.7+

## Quick Start

```bash
# Build library and tools
swift build

# Build with release optimizations
swift build -c release

# Run tests (requires test resources)
./test.sh  # Downloads test DICOM files
swift test

# Build specific tool
swift build --product DcmPrint
```

## Dependencies

* `IBM-Swift/BlueSocket` (networking)
* `Apple/swift-nio` (async networking layer)
* `pointfreeco/swift-html` (HTML rendering of DICOM SR)
* `Apple/swift-argument-parser` (CLI tools)

*Dependencies are managed by SPM.*

## Production Readiness

### Supported Features

- Transfer syntaxes (recognition and/or decoding)
  - Uncompressed: Implicit VR Little Endian; Explicit VR Little/Big Endian.
  - JPEG (baseline) and JPEG 2000 via platform codecs where available.
  - JPEG-LS (lossless/near-lossless): Experimental NEAR=0 grayscale decoder (enabled by default; set `DCMSWIFT_DISABLE_JPEGLS=1` to opt out).
  - RLE Lossless: Implemented for Mono8, Mono16, RGB8.
  - Not yet available: Deflate (custom codec required).

- Image types
  - Grayscale (8/12/16-bit), MONOCHROME1/MONOCHROME2.
  - RGB/ARGB.
  - Multi-frame.

- Network protocols
  - Core DIMSE services: C-ECHO, C-FIND, C-STORE, C-GET, C-MOVE.
  - DICOMweb: WADO-RS, QIDO-RS, STOW-RS.

### Known Limitations

- SR rendering limited to basic text extraction
- 3D reconstruction not included (MPR/MIP)
- DICOM Print Management not implemented
- Compressed transfer syntaxes beyond platform decoders require external codecs

## Disclaimer

DcmSwift is not intended for medical imaging or diagnosis. It's a developer tool focused on the technical aspects of the DICOM standard, providing low-level access to DICOM file structures. The authors are not responsible for any misuse or malfunction of this software, as stated in the license.

## Overview

DcmSwift is a DICOM library that focuses on practical performance and a minimal, predictable API surface. DIMSE services use SwiftNIO under the hood with synchronous convenience methods; DICOMweb and some utilities expose async/await APIs. 

- `DicomSpec` provides a compact DICOM dictionary covering common tags, VRs, UIDs and SOP classes.
- `DicomFile` reads/writes datasets and exposes a `DataSet` abstraction. Decoding is supported for uncompressed images and for compressed images supported by the platform decoders (e.g., JPEG, JPEG 2000).
- Image rendering supports both Metal (optional) and vectorized CPU paths with automatic fallback.

DcmSwift is used within this repository and downstream apps.

## Main DcmSwift APIs

The primary APIs are grouped by area. Each snippet shows the typical entry points.

### Files and Datasets

- DicomFile
  - Load: `let file = DicomFile(forPath: "/path/image.dcm")` - Opens and parses a DICOM file into a `DataSet`.
  - Write: `_ = file?.write(atPath: "/tmp/out.dcm")` - Writes the current dataset back to disk.
  - Validate: `let issues = file?.validate()` - Runs basic checks and returns validation issues.
  - SR/PDF: `file?.structuredReportDocument`, `file?.pdfData()` - Access SR document or extract an encapsulated PDF.

- DataSet
  - Read: `dataset.string(forTag: "PatientName")` - Gets a string value for a tag.
  - Write: `_ = dataset.set(value: "John^Doe", forTagName: "PatientName")` - Sets or creates an element value.
  - Sequences: `dataset.add(element: DataSequence(withTag: tag, parent: nil))` - Adds a sequence element.

- Streams
  - Input: `DicomInputStream(filePath:)` -> `readDataset(headerOnly:withoutPixelData:)` - Reads a dataset from a stream with options.
  - Output: `DicomOutputStream(filePath:)` -> `write(dataset:vrMethod:byteOrder:)` - Writes a dataset to an output stream.
  - Optional memory mapping: `export DCMSWIFT_MAP_IF_SAFE=1` - Enables mapped file reads when safe.

- DICOMDIR
  - `DicomDir(forPath:)` -> `patients`, `index`, `index(forPatientID:)` - Lists indexed patients and files.

### Graphics and Window/Level

- DicomImage
  - From dataset: `let img = file?.dicomImage` - Creates an image helper from a dataset.
  - Stream frames: `img?.streamFrames { data in ... }` - Iterates frames without retaining them.

- DicomPixelView (UIKit platforms)
  - 8-bit: `setPixels8(_:width:height:windowWidth:windowCenter:)` - Sets 8-bit pixels and applies window/level.
  - 16-bit: `setPixels16(_:width:height:windowWidth:windowCenter:)` - Sets 16-bit pixels with W/L mapping.
  - RGB: `setPixelsRGB(_:width:height:bgr:)` - Sets RGB data (optionally BGR) for color images.
  - Adjust W/L: `setWindow(center:width:)` - Updates window/level and redraws using cached pixels.
  - Disable Metal: `export DCMSWIFT_DISABLE_METAL=1` - Forces CPU rendering path.

- WindowLevelCalculator
  - Defaults by modality: `defaultWindowLevel(for:)` - Returns recommended W/L for a modality.
  - Conversions: `convertPixelToHU`, `convertHUToPixel` - Converts between stored pixel and HU.
  - Compute pixel W/L: `calculateWindowLevel(context:)` - Computes W/L in pixel space given context.

### DIMSE Networking

- DicomClient
  - Echo: `try client.echo()` - Tests connectivity with a C-ECHO.
  - Find: `try client.find(queryDataset:queryLevel:instanceUID:)` - Queries a remote SCP (C-FIND).
  - Store: `try client.store(filePaths:)` - Sends files to a remote SCP (C-STORE).
  - Get: `try client.get(queryDataset:queryLevel:instanceUID:)` - Retrieves objects via same association (C-GET).
  - Move: `try client.move(queryDataset:queryLevel:instanceUID:destinationAET:startTemporaryServer:)` - Requests remote send to an AE (C-MOVE).

- Notes
  - C-FIND packs command + dataset in a single P-DATA-TF when possible
  - C-GET reassembles multi-fragment PDUs; returns `[DicomFile]`
  - C-MOVE supports an optional temporary C-STORE SCP for local reception

- Advanced services
  - SCUs: `CFindSCU`, `CGetSCU`, `CMoveSCU`
  - PDU: `PDUEncoder`, `PDUBytesDecoder`

### DICOMweb

- Facade: `let web = try DICOMweb(urlString: "https://server/dicom-web")` - Creates a DICOMweb client facade.
  - WADO-RS: `try await web.wado.retrieveStudy(...)` - Downloads all instances in a study.
  - QIDO-RS: `try await web.qido.searchForStudies(...)` - Searches studies with DICOM JSON results.
  - STOW-RS: `try await web.stow.storeFiles([...])` - Uploads DICOM instances to a study.

### Tools and Utilities

- DicomTool (UIKit platforms)
  - Display: `await DicomTool.shared.decodeAndDisplay(path:view:)` - Decodes and shows an image in `DicomPixelView`.
  - Validate: `await DicomTool.shared.isValidDICOM(at:)` - Quickly checks if a file is parseable DICOM.
  - UIDs: `await DicomTool.shared.extractDICOMUIDs(from:)` - Returns study/series/instance UIDs.

## Architecture

### Module Organization

- **Foundation** - Core DICOM types, tags, VRs, transfer syntax handling
- **IO** - Stream-based reading/writing with `DicomInputStream`/`DicomOutputStream`
- **Data** - `DataSet`, element types, sequences, DICOMDIR, structured reports
- **Graphics** - GPU-accelerated rendering with `DicomImage`, `DicomPixelView`, window/level
- **Networking** - DIMSE protocol implementation with all service classes
- **Web** - Async DICOMweb client (WADO-RS, QIDO-RS, STOW-RS)
- **Tools** - ROI measurements, anonymization, utilities
- **Executables** - Command-line tools for all DICOM operations

### Performance Architecture

The library employs multiple optimization strategies:

**GPU Path (Metal)**
- Hardware-accelerated window/level compute shaders
- Persistent Metal buffer cache
- RGB and grayscale pixel processing
- Automatic CPU fallback when unavailable

**CPU Path (Vectorized)**
- vDSP-accelerated LUT generation
- SIMD pixel mapping operations
- Streaming decode for large files
- Optional memory-mapped file I/O (enable with `DCMSWIFT_MAP_IF_SAFE=1`)

**Configuration**
- Disable Metal: `export DCMSWIFT_DISABLE_METAL=1`
- Force CPU path for testing/debugging

## Performance Characteristics

### Benchmarks

The library achieves excellent performance through its multi-tier optimization strategy:

| Operation | Performance | Notes |
|-----------|------------|-------|
| **Window/Level (Metal)** | ~2ms for 512x512 | GPU-accelerated with VOI LUT support |
| **Window/Level (CPU)** | ~8ms for 512x512 | vDSP vectorized with fallback |
| **JPEG Decode** | ~15ms for 512x512 | Native decompression |
| **C-FIND Query** | ~50ms | With PDU optimization and packing fixes |
| **C-GET Transfer** | ~1.2s/MB | Network dependent with improved reassembly |
| **Pixel Buffer Cache** | <1ms | Direct memory access with byte-based limits |
| **Memory-Mapped I/O** | ~1-3ms savings | Zero-copy frame access for large series |
| **Adaptive Prefetch** | +/-2 to +/-16 frames | Dynamic based on scroll velocity |

### Memory Usage

- **Streaming Mode**: Constant memory regardless of file size
- **Cached Mode**: ~4MB per 512x512 16-bit image with configurable limits
- **Metal Buffers**: Reused across frames to minimize allocation
- **Automatic Eviction**: NSCache-based management with byte-based cost calculation
- **Memory-Mapped I/O**: Optional zero-copy access for large multiframe files
- **Adaptive Prefetch**: Ring buffer with velocity-based distance (+/-2 to +/-16 frames)

## ROI Measurement Service

`ROIMeasurementService` offers tools for ROI measurements on DICOM images.  Through `ROIMeasurementServiceProtocol`, UI layers can start a measurement, add points and complete it to obtain values in millimetres.  The service currently supports **distance** and **ellipse** modes and includes helpers for converting view coordinates to image pixel coordinates.

## Integration

### Import in Code

```swift
import DcmSwift
```

## DICOM files

### Read a DICOM file

Read a file:

    let dicomFile = DicomFile(forPath: filepath)

Get a DICOM dataset attribute:

    let patientName = dicomFile.dataset.string(forTag: "PatientName")

### Write a DICOM file

Set a DICOM dataset attribute:

    dicomFile.dataset.set(value:"John^Doe", forTagName: "PatientName")
    
Once modified, write the dataset to a file again:

    dicomFile.write(atPath: newPath)

### Quick DICOM utilities

`DicomTool` offers high level helpers for working with images:

```swift
let view = DicomPixelView()
// Decode and show the image
let result = await DicomTool.shared.decodeAndDisplay(path: "/path/to/image.dcm", view: view)

// Validate a file
let isValid = await DicomTool.shared.isValidDICOM(at: "/path/to/image.dcm")

// Extract common instance identifiers
let uids = await DicomTool.shared.extractDICOMUIDs(from: "/path/to/image.dcm")
```

Synchronous wrappers for these methods are also provided for existing callers.

## DataSet

### Read dataset 

You can load a `DataSet` object manually using `DicomInputStream`:

    let inputStream = DicomInputStream(filePath: filepath)

    do {
        if let dataset = try inputStream.readDataset() {
            // ...
        }
    } catch {
        Logger.error("Error")
    }
    
`DicomInputStream` can also be initialized with `URL` or `Data` object.

### Create DataSet from scratch

Or you can create a totally genuine `DataSet` instance and start adding some element to it:

    let dataset = DataSet()
    
    dataset.set(value:"John^Doe", forTagName: "PatientName")
    dataset.set(value:"12345678", forTagName: "PatientID")
    
    print(dataset.toData().toHex())
    
Add an element, here a sequence, to a dataset:

    dataset.add(element: DataSequence(withTag: tag, parent: nil))
    
## DICOMDIR

Get all files indexed by a DICOMDIR file:

    if let dicomDir = DicomDir(forPath: dicomDirPath) {
        print(dicomDir.index)
    }
    
List patients indexed in the DICOMDIR:

    if let dicomDir = DicomDir(forPath: dicomDirPath) {
        print(dicomDir.patients)
    }

Get files indexed by a DICOMDIR file for a specific `PatientID`:

    if let dicomDir = DicomDir(forPath: dicomDirPath) {
        if let files = dicomDir.index(forPatientID: "198726783") {
            print(files)
        }
    }

## DICOM SR

Load and print SR Tree:

    if let dicomFile = DicomFile(forPath: dicomSRPath) {
        if let doc = dicomFile.structuredReportDocument {
            print(doc)
        }
    }

Load and print SR as HTML:

    if let dicomFile = DicomFile(forPath: dicomSRPath) {
        if let doc = dicomFile.structuredReportDocument {
            print(doc.html)
        }
    }
    
## Networking

### DICOM ECHO

Create a calling AE, aka your local client (port is totally random and unused):
    
    let callingAE = DicomEntity(
        title: callingAET,
        hostname: "127.0.0.1",
        port: 11112)

Create a called AE, aka the remote AE you want to connect to:
   
    let calledAE = DicomEntity(
        title: calledAET,
        hostname: calledHostname,
        port: calledPort)

Create a DICOM client:
    
    let client = DicomClient(
        callingAE: callingAE,
        calledAE: calledAE)

Run C-ECHO SCU service:
    
    if client.echo() {
        print("ECHO \(calledAE) SUCCEEDED")
    } else {
        print("ECHO \(callingAE) FAILED")
    }
    
See source code of embedded binaries for more network related examples (`DcmFind`, `DcmStore`, `DcmGet`, `DcmMove`).

### Network Protocol Notes

- C-FIND: command and dataset are packed into a single P-DATA-TF PDU where possible
- C-GET/C-MOVE: improved handling of multi-fragment PDUs and correct dataset flags/group lengths
- Association timeout configurable via `DicomAssociation.dicomTimeout`

### DICOM C-GET

C-GET retrieves DICOM objects directly through the same association:

```swift
let client = DicomClient(
    callingAE: callingAE,
    calledAE: calledAE)

// Get a specific study
let files = try client.get(
    queryLevel: .STUDY,
    instanceUID: "1.2.840.113619.2.55.3.604688119"
)

print("Retrieved \(files.count) files")
```

### DICOM C-MOVE

C-MOVE instructs a remote node to send objects to a destination AE:

```swift
let client = DicomClient(
    callingAE: callingAE,
    calledAE: calledAE)

// Move a study to another AE
let result = try client.move(
    queryLevel: .STUDY,
    instanceUID: "1.2.840.113619.2.55.3.604688119",
    destinationAET: "DESTINATION_AE"
)

if result.success {
    print("C-MOVE succeeded")
}

// Move with local receiver (starts temporary C-STORE SCP)
let result = try client.move(
    queryLevel: .STUDY,
    instanceUID: "1.2.840.113619.2.55.3.604688119",
    destinationAET: "LOCAL_AE",
    startTemporaryServer: true
)

if let files = result.files {
    print("Received \(files.count) files locally")
}
```

## DICOMWeb

The `DICOMweb` class provides an interface for all DICOMweb services (WADO-RS, QIDO-RS, STOW-RS).

### WADO-RS

Retrieve studies, series, instances, metadata, and rendered images.

```swift
let dicomweb = try DICOMweb(urlString: "https://my-pacs.com/dicom-web")

// Retrieve a study
let files = try await dicomweb.wado.retrieveStudy(studyUID: "1.2.3.4.5")

// Retrieve a rendered instance
let jpegData = try await dicomweb.wado.retrieveRenderedInstance(
    studyUID: "1.2.3.4.5",
    seriesUID: "1.2.3.4.5.6",
    instanceUID: "1.2.3.4.5.6.7",
    format: .jpeg
)
```

### QIDO-RS

Search for studies, series, and instances using query parameters.

```swift
// Search for studies
let studies = try await dicomweb.qido.searchForStudies(patientID: "12345")
```

### STOW-RS

Store DICOM instances, metadata, and bulk data.

```swift
// Store a DICOM file
let response = try await dicomweb.stow.storeFiles([myDicomFile])
```

## Command-Line Tools

DcmSwift includes comprehensive CLI tools for all DICOM operations:

### Available Tools

| Tool | Description | Use Case |
|------|-------------|----------|
| **DcmPrint** | Display DICOM file contents | Inspect headers and metadata |
| **DcmAnonymize** | Remove patient information | De-identify datasets |
| **DcmEcho** | Test connectivity (C-ECHO) | Verify PACS connection |
| **DcmFind** | Query servers (C-FIND) | Search for studies/series |
| **DcmStore** | Send files (C-STORE) | Upload to PACS |
| **DcmGet** | Retrieve objects (C-GET) | Download from PACS |
| **DcmMove** | Transfer between nodes (C-MOVE) | Remote-initiated transfers |
| **DcmServer** | DICOM SCP implementation | Receive DICOM objects |
| **DcmSR** | Structured Report tools | Process SR documents |

### Examples

```bash
# Display DICOM file with specific tags
.build/release/DcmPrint /path/to/file.dcm --tags PatientName,StudyDate

# Test PACS connectivity
.build/release/DcmEcho PACS_AE 192.168.1.100 104

# Query for today's studies
.build/release/DcmFind -l STUDY -d TODAY PACS localhost 11112

# Retrieve entire study
.build/release/DcmGet -l STUDY -u "1.2.840..." PACS localhost 11112

# Move with local receiver
.build/release/DcmMove -l STUDY -u "1.2.840..." -d LOCAL_AE --receive PACS localhost 11112
```

## Unit Tests

Before running tests, download test resources:

    ./test.sh

Then run:
    
    swift test
    
## Documentation

Documentation can be generated using `jazzy`:

    jazzy \
      --module DcmSwift \
      --swift-build-tool spm \
      --build-tool-arguments -Xswiftc,-swift-version,-Xswiftc,5.7
      
Or with swift doc:

    swift doc generate \
        --module-name DcmSwift Sources/DcmSwift/Data \
        --minimum-access-level private \
        --output docs --format html
    
## Side notes

### For testing/debugging networking

Useful DCMTK command for debugging with verbose logs: 

    storescp 11112 --log-level trace

Alternative using dcm4chee (5.x) `storescp`:

    storescp -b STORESCP@127.0.0.1:11112
    
DCMTK also includes a server for testing `cfind`:

    dcmqrscp 11112 --log-level trace -c /path/to/config/dcmqrscp.cfg

Both `DCMTK` and `dcm4chee` tools are useful references for testing DICOM features.

## Contributors

* Rafaël Warnault <rw@opale.pro>
* Paul Repain <pr@opale.pro>
* Colombe Blachère
* Thales Matheus <thalesmmsradio@gmail.com>

## License

DcmSwift is distributed under the MIT License. See the `LICENSE` file for the full text.
