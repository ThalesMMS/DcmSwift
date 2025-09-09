# DcmSwift fork with C-GET, C-MOVE and DICOMWeb

DcmSwift is a DICOM implementation in Swift that's still under development. The library started with basic DICOM file format support and has been extended with networking features including C-GET, C-MOVE and DICOMWeb. Additional features from the DICOM standard will be added over time. 

## Recent Updates

### DICOMWeb, C-MOVE and C-GET Services Implementation (2025)

This fork adds complete DICOM Query/Retrieve services:

#### DICOMWeb
- **WADO-RS**: Retrieves studies, series, instances, metadata, and rendered images
- **QIDO-RS**: Searches for studies, series, and instances with various query parameters
- **STOW-RS**: Stores DICOM instances, metadata, and bulk data
- **DICOMweb Client**: Single client for all DICOMweb services

#### Message Structures
- Created `CMoveRQ`/`CMoveRSP` and `CGetRQ`/`CGetRSP` message classes
- Updated PDU encoder/decoder for new message types
- Full support for sub-operation progress tracking

#### Service Classes
- **CGetSCU**: Handles C-GET operations with C-STORE sub-operations on the same association
- **CMoveSCU**: Manages C-MOVE operations with destination AE specification
- Updated `DicomAssociation` to support multiple message types in a single association

#### Client Integration  
- Added `get()` and `move()` methods to `DicomClient`
- Optional temporary C-STORE SCP server for C-MOVE local reception
- Async support through SwiftNIO

#### Command-Line Tools
- **DcmGet**: C-GET SCU tool with query levels and filtering
- **DcmMove**: C-MOVE SCU tool with optional local receiver mode
- Both tools include help documentation, examples, and verbose logging options

## Requirements

* macOS 10.15+ / iOS 13.0+
* Xcode 12.4+
* Swift 5.3+

## Dependencies

* `IBM-Swift/BlueSocket` (networking)
* `Apple/swift-nio` (async networking layer)
* `pointfreeco/swift-html` (HTML rendering of DICOM SR)
* `Apple/swift-argument-parser` (CLI tools)

*Dependencies are managed by SPM.*

## Disclaimer

DcmSwift is not intended for medical imaging or diagnosis. It's a developer tool focused on the technical aspects of the DICOM standard, providing low-level access to DICOM file structures. The authors are not responsible for any misuse or malfunction of this software, as stated in the license.

## Overview

DcmSwift is written in Swift 5.3 and relies primarily on Foundation for compatibility across Swift toolchains.

The `DicomSpec` class contains a minimal DICOM specification and provides tools for working with UIDs, SOP Classes, VRs, Tags and other DICOM identifiers.

The `DicomFile` class handles reading and writing of DICOM files (including some non-standard ones). It uses the `DataSet` class as an abstraction layer and can export to various formats (raw data, XML, JSON) and transfer syntaxes.

The library includes helpers for DICOM-specific data types like dates, times, and endianness. The API aims to be minimal while providing the necessary features to work with DICOM files safely.

DcmSwift is used in the **DicomiX** macOS application, which demonstrates the library's capabilities.

## ROI Measurement Service

`ROIMeasurementService` offers tools for ROI measurements on DICOM images.  Through `ROIMeasurementServiceProtocol`, UI layers can start a measurement, add points and complete it to obtain values in millimetres.  The service currently supports **distance** and **ellipse** modes and includes helpers for converting view coordinates to image pixel coordinates.

## Use DcmSwift in your project

DcmSwift uses Swift Package Manager. Add it as a dependency in your `Package.swift`:

    dependencies: [
        .package(name: "DcmSwift", url: "http://gitlab.dev.opale.pro/rw/DcmSwift.git", from:"0.0.1"),
    ]
    
    ...
    
    .target(
        name: "YourTarget",
        dependencies: [
            "DcmSwift"
        ]
        
In Xcode, you can add this package using the repository URL.

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

## Using binaries

The DcmSwift package includes several command-line tools. To build them:

    swift build
    
To build release binaries:
    
    swift build -c release
    
Binaries can be found in `.build/release` directory. Available tools:

* **DcmPrint** - Display DICOM file contents
* **DcmAnonymize** - Anonymize DICOM files  
* **DcmEcho** - Test DICOM connectivity (C-ECHO)
* **DcmFind** - Query DICOM servers (C-FIND)
* **DcmStore** - Send DICOM files (C-STORE)
* **DcmGet** - Retrieve DICOM objects (C-GET)
* **DcmMove** - Move DICOM objects between nodes (C-MOVE)
* **DcmServer** - DICOM server implementation
* **DcmSR** - Structured Report handling

Examples:

    # Display DICOM file
    .build/release/DcmPrint /my/dicom/file.dcm
    
    # Test connectivity
    .build/release/DcmEcho PACS 192.168.1.100 104
    
    # Retrieve a study
    .build/release/DcmGet -l STUDY -u "1.2.840..." PACS localhost 11112
    
    # Move studies with local receiver
    .build/release/DcmMove -l STUDY -u "1.2.840..." -d LOCAL_AE --receive PACS localhost 11112

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
      --build-tool-arguments -Xswiftc,-swift-version,-Xswiftc,5
      
Or with swift doc:

    swift doc generate \
        --module-name DcmSwift Sources/DcmSwift/Data \
        --minimum-access-level private \
        --output docs --format html
    
## Side notes

### For testing/debuging networking

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

MIT License

Copyright (c) 2019 - OPALE, https://www.opale.fr

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
