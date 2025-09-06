//
//  DICOMWebModels.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/**
 Common data models and types used across DICOMWeb services.
 
 This file contains shared structures for representing DICOM data
 in JSON format as specified by the DICOMWeb standard.
 */

// MARK: - DICOM JSON Models

/**
 Represents a DICOM attribute in JSON format
 
 According to PS3.18 Section F.2, DICOM JSON encoding
 */
public struct DICOMJSONAttribute: Codable {
    /// Value Representation (e.g., "PN", "UI", "CS")
    public let vr: String
    
    /// Array of values (even single values are in array)
    public let Value: [Any]?
    
    /// For sequences, contains nested items
    public let Sequence: [[String: DICOMJSONAttribute]]?
    
    /// For bulk data, contains URI reference
    public let BulkDataURI: String?
    
    /// For inline binary, contains base64 encoded data
    public let InlineBinary: String?
    
    // Custom encoding/decoding to handle Any type
    public init(from decoder: Decoder) throws {
        // TODO: Implement custom decoding for flexible Value types
        fatalError("Custom decoding not yet implemented")
    }
    
    public func encode(to encoder: Encoder) throws {
        // TODO: Implement custom encoding
        fatalError("Custom encoding not yet implemented")
    }
}

/**
 Represents a complete DICOM object in JSON format
 */
public typealias DICOMJSONObject = [String: DICOMJSONAttribute]

// MARK: - Study Models

/**
 Represents a DICOM study for DICOMWeb operations
 */
public struct WebStudy {
    public let studyInstanceUID: String
    public let studyDate: Date?
    public let studyTime: String?
    public let studyDescription: String?
    public let accessionNumber: String?
    public let modalitiesInStudy: [String]?
    public let numberOfStudyRelatedSeries: Int?
    public let numberOfStudyRelatedInstances: Int?
    
    // Patient information
    public let patientName: String?
    public let patientID: String?
    public let patientBirthDate: Date?
    public let patientSex: String?
    
    /// Initialize from DICOM JSON response
    public init(from json: DICOMJSONObject) {
        // TODO: Parse JSON attributes
        // Extract values from DICOM tags
        
        self.studyInstanceUID = "" // Parse from "0020000D"
        self.studyDate = nil
        self.studyTime = nil
        self.studyDescription = nil
        self.accessionNumber = nil
        self.modalitiesInStudy = nil
        self.numberOfStudyRelatedSeries = nil
        self.numberOfStudyRelatedInstances = nil
        self.patientName = nil
        self.patientID = nil
        self.patientBirthDate = nil
        self.patientSex = nil
    }
}

// MARK: - Series Models

/**
 Represents a DICOM series for DICOMWeb operations
 */
public struct WebSeries {
    public let seriesInstanceUID: String
    public let seriesNumber: Int?
    public let seriesDescription: String?
    public let modality: String
    public let bodyPartExamined: String?
    public let seriesDate: Date?
    public let seriesTime: String?
    public let numberOfSeriesRelatedInstances: Int?
    
    // Reference to parent study
    public let studyInstanceUID: String
    
    /// Initialize from DICOM JSON response
    public init(from json: DICOMJSONObject) {
        // TODO: Parse JSON attributes
        
        self.seriesInstanceUID = "" // Parse from "0020000E"
        self.seriesNumber = nil
        self.seriesDescription = nil
        self.modality = ""
        self.bodyPartExamined = nil
        self.seriesDate = nil
        self.seriesTime = nil
        self.numberOfSeriesRelatedInstances = nil
        self.studyInstanceUID = ""
    }
}

// MARK: - Instance Models

/**
 Represents a DICOM instance (image) for DICOMWeb operations
 */
public struct WebInstance {
    public let sopInstanceUID: String
    public let sopClassUID: String
    public let instanceNumber: Int?
    public let rows: Int?
    public let columns: Int?
    public let bitsAllocated: Int?
    public let numberOfFrames: Int?
    
    // References to parent series and study
    public let seriesInstanceUID: String
    public let studyInstanceUID: String
    
    // Optional retrieve URL for this instance
    public let retrieveURL: URL?
    
    /// Initialize from DICOM JSON response
    public init(from json: DICOMJSONObject) {
        // TODO: Parse JSON attributes
        
        self.sopInstanceUID = "" // Parse from "00080018"
        self.sopClassUID = "" // Parse from "00080016"
        self.instanceNumber = nil
        self.rows = nil
        self.columns = nil
        self.bitsAllocated = nil
        self.numberOfFrames = nil
        self.seriesInstanceUID = ""
        self.studyInstanceUID = ""
        self.retrieveURL = nil
    }
}

// MARK: - Worklist Models

/**
 Represents a Modality Worklist item
 */
public struct WorklistItem {
    public let accessionNumber: String
    public let patientName: String
    public let patientID: String
    public let patientBirthDate: Date?
    public let patientSex: String?
    
    // Scheduled Procedure Step
    public let scheduledStationAETitle: String
    public let scheduledProcedureStepStartDate: Date
    public let scheduledProcedureStepStartTime: String?
    public let modality: String
    public let scheduledProcedureStepDescription: String?
    public let scheduledProcedureStepLocation: String?
    public let scheduledPerformingPhysicianName: String?
    
    // Requested Procedure
    public let requestedProcedureDescription: String?
    public let requestedProcedureID: String?
    public let requestedProcedurePriority: String?
    
    /// Initialize from DICOM JSON response
    public init(from json: DICOMJSONObject) {
        // TODO: Parse worklist attributes
        
        self.accessionNumber = ""
        self.patientName = ""
        self.patientID = ""
        self.patientBirthDate = nil
        self.patientSex = nil
        self.scheduledStationAETitle = ""
        self.scheduledProcedureStepStartDate = Date()
        self.scheduledProcedureStepStartTime = nil
        self.modality = ""
        self.scheduledProcedureStepDescription = nil
        self.scheduledProcedureStepLocation = nil
        self.scheduledPerformingPhysicianName = nil
        self.requestedProcedureDescription = nil
        self.requestedProcedureID = nil
        self.requestedProcedurePriority = nil
    }
}

// MARK: - UPS Models (Unified Procedure Step)

/**
 Represents a UPS (Unified Procedure Step) workitem
 
 For future UPS-RS implementation
 */
public struct UPSWorkitem {
    public let workitemUID: String
    public let procedureStepState: String // SCHEDULED, IN PROGRESS, COMPLETED, CANCELED
    public let scheduledDateTime: Date?
    public let worklistLabel: String?
    public let procedureStepLabel: String?
    public let priority: String? // HIGH, MEDIUM, LOW
    
    // Input information
    public let inputInformationSequence: [DICOMJSONObject]?
    
    // Output information
    public let outputInformationSequence: [DICOMJSONObject]?
    
    /// Initialize from DICOM JSON response
    public init(from json: DICOMJSONObject) {
        // TODO: Parse UPS attributes
        
        self.workitemUID = ""
        self.procedureStepState = "SCHEDULED"
        self.scheduledDateTime = nil
        self.worklistLabel = nil
        self.procedureStepLabel = nil
        self.priority = nil
        self.inputInformationSequence = nil
        self.outputInformationSequence = nil
    }
}

// MARK: - Capabilities Models

/**
 Represents server capabilities document
 
 Used for capability negotiation and discovery
 */
public struct ServerCapabilities {
    public let wadoRSSupported: Bool
    public let wadoURISupported: Bool
    public let qidoRSSupported: Bool
    public let stowRSSupported: Bool
    public let upsRSSupported: Bool
    
    public let supportedTransferSyntaxes: [String]
    public let supportedMediaTypes: [String]
    public let supportedCharacterSets: [String]
    
    public let maxLimit: Int?
    public let defaultLimit: Int?
    
    /// Initialize from capabilities document
    public init(from json: [String: Any]) {
        // TODO: Parse capabilities
        
        self.wadoRSSupported = true
        self.wadoURISupported = false
        self.qidoRSSupported = true
        self.stowRSSupported = true
        self.upsRSSupported = false
        self.supportedTransferSyntaxes = []
        self.supportedMediaTypes = []
        self.supportedCharacterSets = []
        self.maxLimit = nil
        self.defaultLimit = nil
    }
}

// MARK: - Helper Extensions

extension DICOMJSONObject {
    /**
     Helper to extract string value from a DICOM tag
     */
    public func stringValue(for tag: String) -> String? {
        // TODO: Implement value extraction
        // Handle different VR types appropriately
        
        return nil
    }
    
    /**
     Helper to extract date value from a DICOM tag
     */
    public func dateValue(for tag: String) -> Date? {
        // TODO: Parse DICOM date format (YYYYMMDD)
        
        return nil
    }
    
    /**
     Helper to extract integer value from a DICOM tag
     */
    public func intValue(for tag: String) -> Int? {
        // TODO: Extract and convert integer values
        
        return nil
    }
}