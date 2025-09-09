//
//  Abort.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `Abort` class represents a A-ABORT message of the DICOM standard.

 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.8
 */
public class Abort: PDUMessage {
    
    /// Full name of ABORT PDU
    public override func messageName() -> String {
        return "A-ABORT"
    }
    
    /**
     Builds the A-ABORT PDU message
     
     A-ABORT consists of:
     - pdu type
     - 1 reserved byte
     - pdu length
     - 4 reserved bytes
     - 2 reserved bytes
     - the source (0 : user initiated abort, 1 : reserved, 2 : provider initiated abort)
     
     - Returns: A-ABORT bytes
     */
    public override func data() -> Data {
        var data = Data()
        let length = UInt32(4)
        
        data.append(uint8: ItemType.applicationContext.rawValue, bigEndian: true)
        data.append(byte: 0x00)
        data.append(uint32: length, bigEndian: true)
        data.append(byte: 0x00, count: 4)
        
        return data
    }
    
    /// - Returns: Success
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        _ = super.decodeData(data: data)
        
        // Skip PDU header (already processed)
        // PDU structure: Type(1) + Reserved(1) + Length(4) = 6 bytes header
        // Then: Reserved(2) + Source(1) + Reason(1)
        
        if stream.readableBytes >= 4 {
            // Skip 2 reserved bytes
            stream.forward(by: 2)
            
            // Read abort source
            var source: UInt8 = 0
            var reason: UInt8 = 0
            
            if let sourceData = stream.read(length: 1) {
                source = sourceData[0]
            }
            
            // Read abort reason
            if let reasonData = stream.read(length: 1) {
                reason = reasonData[0]
            }
            
            // Interpret source and reason
            let sourceDesc = source == 0 ? "DICOM UL service-user (Remote application)" : 
                            source == 2 ? "DICOM UL service-provider (Remote DICOM stack)" : "Unknown"
            
            let reasonDesc: String
            if source == 0 {
                // Service-user (application level) reasons
                reasonDesc = reason == 0 ? "Reason not specified (possibly unauthorized AET or unsupported operation)" : "Unknown reason: \(reason)"
            } else if source == 2 {
                // Service-provider (DICOM protocol level) reasons
                switch reason {
                case 0: reasonDesc = "Reason not specified"
                case 1: reasonDesc = "Unrecognized PDU"
                case 2: reasonDesc = "Unexpected PDU"
                case 3: reasonDesc = "Reserved"
                case 4: reasonDesc = "Unrecognized PDU parameter"
                case 5: reasonDesc = "Unexpected PDU parameter"
                case 6: reasonDesc = "Invalid PDU parameter value"
                default: reasonDesc = "Unknown reason: \(reason)"
                }
            } else {
                reasonDesc = "Unknown reason: \(reason)"
            }
            
            Logger.error("========== A-ABORT RECEIVED ==========")
            Logger.error("Source: \(source) (\(sourceDesc))")
            Logger.error("Reason: \(reason) (\(reasonDesc))")
            Logger.error("")
            Logger.error("Common causes:")
            Logger.error("- AET '\(association.callingAE)' not authorized on PACS")
            Logger.error("- Query/Retrieve operations not enabled for this AET")
            Logger.error("- Required query fields missing")
            Logger.error("- Incompatible DICOM implementation")
            Logger.error("=======================================")
        }
        
        return .Success
    }
}
