//
//  main.swift
//  DcmGet
//
//  Created by Thales on 2025/01/05.
//

import Foundation
import DcmSwift
import ArgumentParser

/**
 DcmGet - DICOM C-GET SCU command line tool
 
 This tool performs C-GET operations to retrieve DICOM objects directly
 from a remote DICOM node through the same association.
 */
struct DcmGet: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "DICOM C-GET SCU - Retrieve DICOM objects from a remote node",
        discussion: """
            Performs a C-GET operation to retrieve DICOM objects.
            The remote node sends the data through C-STORE sub-operations
            on the same connection.
            
            Examples:
                # Get all studies for a patient
                DcmGet -l PATIENT -p "12345" PACS pacs.hospital.com 104
                
                # Get a specific study
                DcmGet -l STUDY -u "1.2.840.113619.2.55.3.604688119" PACS localhost 11112
                
                # Get a specific series
                DcmGet -l SERIES -u "1.2.840.113619.2.55.3.604688120" PACS localhost 11112
            """
    )
    
    @Option(name: .shortAndLong, help: "Local AET (Application Entity Title)")
    var callingAET: String = "DCMGET"
    
    @Option(name: [.short, .customLong("level")], help: "Query/Retrieve level: PATIENT, STUDY, SERIES, or IMAGE")
    var queryLevel: String = "STUDY"
    
    @Option(name: [.short, .customLong("uid")], help: "Instance UID for the specified level")
    var instanceUID: String?
    
    @Option(name: [.short, .customLong("patient")], help: "Patient ID for PATIENT level query")
    var patientID: String?
    
    @Option(name: [.short, .customLong("output")], help: "Output directory for retrieved files")
    var outputDir: String = "./received"
    
    @Option(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    @Argument(help: "Remote AE title")
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
        
        // Create output directory if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDir) {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
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
        
        // Perform C-GET operation
        do {
            let startTime = Date()
            
            let files = try client.get(
                queryDataset: queryDataset,
                queryLevel: level,
                instanceUID: instanceUID,
                temporaryStoragePath: outputDir
            )
            
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            if files.count > 0 {
                print("\n✅ C-GET SUCCEEDED")
                print("Retrieved \(files.count) file(s) in \(String(format: "%.2f", elapsedTime)) seconds")
                print("Files saved to: \(outputDir)")
                
                if verbose {
                    print("\nRetrieved files:")
                    for (index, file) in files.enumerated() {
                        if let sopInstanceUID = file.dataset.string(forTag: "SOPInstanceUID"),
                           let modality = file.dataset.string(forTag: "Modality") {
                            print("  \(index + 1). \(sopInstanceUID) [\(modality)]")
                        }
                    }
                }
            } else {
                print("\n⚠️ C-GET completed but no files were retrieved")
                print("This may mean no matching objects were found for the specified criteria")
            }
            
        } catch {
            print("\n❌ C-GET FAILED")
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

DcmGet.main()