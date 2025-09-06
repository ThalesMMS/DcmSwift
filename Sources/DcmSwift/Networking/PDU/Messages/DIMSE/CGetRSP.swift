//
//  CGetRSP.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/**
 The `CGetRSP` class represents a C-GET-RSP message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.3.2.html
 */
public class CGetRSP: DataTF {
    /// Number of remaining sub-operations
    public var numberOfRemainingSuboperations: UInt16?
    /// Number of completed sub-operations
    public var numberOfCompletedSuboperations: UInt16?
    /// Number of failed sub-operations
    public var numberOfFailedSuboperations: UInt16?
    /// Number of warning sub-operations
    public var numberOfWarningSuboperations: UInt16?
    
    public override func messageName() -> String {
        return "C-GET-RSP"
    }
    
    public override func messageInfos() -> String {
        var info = "\(dimseStatus.status)"
        if let remaining = numberOfRemainingSuboperations {
            info += " (Remaining: \(remaining)"
            if let completed = numberOfCompletedSuboperations {
                info += ", Completed: \(completed)"
            }
            if let failed = numberOfFailedSuboperations {
                info += ", Failed: \(failed)"
            }
            if let warning = numberOfWarningSuboperations {
                info += ", Warning: \(warning)"
            }
            info += ")"
        }
        return info
    }
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        // Extract sub-operation counters from command dataset
        if let commandDataset = self.commandDataset {
            // Number of Remaining Sub-operations
            if let element = commandDataset.element(forTagName: "NumberOfRemainingSuboperations") {
                if let data = element.data as? Data, data.count >= 2 {
                    numberOfRemainingSuboperations = UInt16(data.toInt16(byteOrder: .LittleEndian))
                }
            }
            
            // Number of Completed Sub-operations
            if let element = commandDataset.element(forTagName: "NumberOfCompletedSuboperations") {
                if let data = element.data as? Data, data.count >= 2 {
                    numberOfCompletedSuboperations = UInt16(data.toInt16(byteOrder: .LittleEndian))
                }
            }
            
            // Number of Failed Sub-operations
            if let element = commandDataset.element(forTagName: "NumberOfFailedSuboperations") {
                if let data = element.data as? Data, data.count >= 2 {
                    numberOfFailedSuboperations = UInt16(data.toInt16(byteOrder: .LittleEndian))
                }
            }
            
            // Number of Warning Sub-operations
            if let element = commandDataset.element(forTagName: "NumberOfWarningSuboperations") {
                if let data = element.data as? Data, data.count >= 2 {
                    numberOfWarningSuboperations = UInt16(data.toInt16(byteOrder: .LittleEndian))
                }
            }
        }
        
        return status
    }
}