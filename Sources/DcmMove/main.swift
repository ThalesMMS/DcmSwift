//
//  main.swift
//  DcmMove
//
//  Created by Thales on 2025/01/05.
//

import Foundation
import DcmSwift
import ArgumentParser

/**
 DcmMove - DICOM C-MOVE SCU command line tool
 
 This tool performs C-MOVE operations to instruct a remote DICOM node
 to send DICOM objects to a specified destination AE.
 */
struct DcmMove: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "DICOM C-MOVE SCU - Move DICOM objects between remote nodes",
        discussion: """
            Performs a C-MOVE operation to instruct a remote DICOM node
            to send objects to a destination AE. The actual data transfer
            happens through a separate C-STORE association.
            
            Examples:
                # Move all studies for a patient to another AE
                DcmMove -l PATIENT -p "12345" -d DEST_AE PACS pacs.hospital.com 104
                
                # Move a specific study
                DcmMove -l STUDY -u "1.2.840.113619.2.55.3.604688119" -d WORKSTATION PACS localhost 11112
                
                # Move with local receiver (starts temporary C-STORE SCP)
                DcmMove -l STUDY -u "1.2.840.113619.2.55.3.604688119" -d DCMMOVE --receive PACS localhost 11112
            """
    )
    
    @Option(name: .shortAndLong, help: "Local AET (Application Entity Title)")
    var callingAET: String = "DCMMOVE"
    
    @Option(name: [.short, .customLong("destination")], help: "Destination AET for the move operation")
    var destinationAET: String = "DCMMOVE_DEST"
    
    @Option(name: [.short, .customLong("level")], help: "Query/Retrieve level: PATIENT, STUDY, SERIES, or IMAGE")
    var queryLevel: String = "STUDY"
    
    @Option(name: [.short, .customLong("uid")], help: "Instance UID for the specified level")
    var instanceUID: String?
    
    @Option(name: [.short, .customLong("patient")], help: "Patient ID for PATIENT level query")
    var patientID: String?
    
    @Option(name: .shortAndLong, help: "Start a temporary C-STORE SCP to receive files locally")
    var receive: Bool = false
    
    @Option(name: [.short, .customLong("output")], help: "Output directory for received files (when using --receive)")
    var outputDir: String = "./received"
    
    @Option(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    @Argument(help: "Remote AE title (PACS)")
    var calledAET: String
    
    @Argument(help: "Remote hostname or IP address")
    var calledHostname: String
    
    @Argument(help: "Remote port number")
    var calledPort: Int
    
    mutating func run() throws {
        // Configure logging
        if verbose {
            Logger.setMaxLevel(.VERBOSE)
        } else {
            Logger.setMaxLevel(.WARNING)
        }
        
        // Parse query level
        let level: QueryRetrieveLevel
        switch queryLevel.uppercased() {
        case "PATIENT":
            level = .PATIENT
        case "STUDY":
            level = .STUDY
        case "SERIES":
            level = .SERIES
        case "IMAGE":
            level = .IMAGE
        default:
            print("Invalid query level: \(queryLevel). Use PATIENT, STUDY, SERIES, or IMAGE")
            throw ExitCode.failure
        }
        
        // Create output directory if receiving files locally
        if receive {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: outputDir) {
                try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
            }
        }
        
        // Create calling AE (local client)
        let callingAE = DicomEntity(
            title: callingAET,
            hostname: "127.0.0.1",
            port: 0)  // Port 0 means any available port
        
        // Create called AE (remote server)
        let calledAE = DicomEntity(
            title: calledAET,
            hostname: calledHostname,
            port: calledPort)
        
        print("Connecting to \(calledAET)@\(calledHostname):\(calledPort)...")
        print("Move destination AET: \(destinationAET)")
        
        if receive {
            print("Starting local C-STORE SCP server on port 11113...")
        }
        
        // Create DICOM client
        let client = DicomClient(
            callingAE: callingAE,
            calledAE: calledAE)
        
        // Prepare query dataset if needed
        var queryDataset: DataSet? = nil
        if let patientID = patientID, level == .PATIENT {
            queryDataset = DataSet()
            _ = queryDataset?.set(value: patientID, forTagName: "PatientID")
        }
        
        // Perform C-MOVE operation
        do {
            let startTime = Date()
            
            let result = try client.move(
                queryDataset: queryDataset,
                queryLevel: level,
                instanceUID: instanceUID,
                destinationAET: destinationAET,
                startTemporaryServer: receive
            )
            
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            if result.success {
                print("\n✅ C-MOVE SUCCEEDED")
                print("Operation completed in \(String(format: "%.2f", elapsedTime)) seconds")
                
                if receive, let files = result.files {
                    print("Received \(files.count) file(s)")
                    print("Files saved to: \(outputDir)")
                    
                    if verbose && files.count > 0 {
                        print("\nReceived files:")
                        for (index, file) in files.enumerated() {
                            if let sopInstanceUID = file.dataset.string(forTag: "SOPInstanceUID"),
                               let modality = file.dataset.string(forTag: "Modality") {
                                print("  \(index + 1). \(sopInstanceUID) [\(modality)]")
                            }
                        }
                    }
                } else if !receive {
                    print("Files were sent to destination AET: \(destinationAET)")
                    print("Check the destination system for received files")
                }
            } else {
                print("\n⚠️ C-MOVE completed with issues")
                print("The operation may have partially succeeded. Check the destination system.")
            }
            
        } catch {
            print("\n❌ C-MOVE FAILED")
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

DcmMove.main()