//
//  DataTF.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


/**
 The `DataTF` class represents a DATA-TF message of the DICOM standard.
 
 This class serves as a base for all the DIMSE messages.
 
 It decodes most of the generic part of the message, like the PDU, the Command dataset and the DIMSE status (see `decodeData()`).
 When inheriting from `DataTF`, `super.decodeData()` must be called in order to primarilly decode this generic attributes.
 
 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#table_9-22
 */
public class DataTF: PDUMessage {
    public var contextID: UInt8?
    
    /// Full name of DataTF PDU
    public override func messageName() -> String {
        return "DATA-TF"
    }
    
    
    /// Decodes the DataTF PDU data : type, 1 reserved byte, length, presentation-data-value items
    /// presentation-data-value contains : item length, presentation context id, presentation-data-value
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        _ = super.decodeData(data: data)
        receivedData.removeAll(keepingCapacity: true)

        func readOnePDV() -> Bool {
            guard let pdvLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
                return false
            }
            self.pdvLength = Int(pdvLength)
            guard let ctx = stream.read(length: 1)?.toInt8(byteOrder: .BigEndian) else { return false }
            self.contextID = UInt8(bitPattern: ctx)
            guard let f = stream.read(length: 1)?.toInt8(byteOrder: .BigEndian) else { return false }
            self.flags = UInt8(f)
            let isCommand = (self.flags & 0x01) == 0x01
            guard let payload = stream.read(length: Int(pdvLength) - 2) else { return false }

            if isCommand {
                let dis = DicomInputStream(data: payload)
                guard let commandDataset = try? dis.readDataset() else { return false }
                self.commandDataset = commandDataset
                if let cmd = commandDataset.element(forTagName: "CommandField") {
                    let c = cmd.data.toUInt16(byteOrder: .LittleEndian)
                    self.commandField = CommandField(rawValue: c)
                }
                // Capture MessageID for proper RSP linking
                if let mid = commandDataset.integer16(forTag: "MessageID") {
                    self.messageID = UInt16(mid)
                }
                if let s = commandDataset.element(forTagName: "Status") {
                    if let ss = DIMSEStatus.Status(rawValue: s.data.toUInt16(byteOrder: .LittleEndian)) {
                        self.dimseStatus = DIMSEStatus(status: ss, command: self.commandField ?? .NONE)
                    }
                }
                if let cdst = commandDataset.integer16(forTag: "CommandDataSetType") {
                    self.commandDataSetType = cdst
                }
            } else {
                // Data PDV; append
                receivedData.append(payload)
                // Keep Pending until a final command provides definitive status
                self.dimseStatus = DIMSEStatus(status: .Pending, command: .NONE)
            }
            return true
        }

        // Read all PDVs present in this P-DATA-TF
        var any = false
        while stream.readableBytes > 0 {
            if !readOnePDV() { break }
            any = true
        }
        if !any { return .Refused }

        // If we already have a status from a command PDV, return it; otherwise Pending
        if let ds = dimseStatus { return ds.status }
        return .Pending
    }
}
