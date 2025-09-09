//
//  CFindRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 04/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CFindRSP` class represents a C-FIND-RSP message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.2.2.html
 */
public class CFindRSP: DataTF {
    public var resultsDataset:DataSet?
    
    
    public override func messageName() -> String {
        return "C-FIND-RSP"
    }
    
    
    public override func messageInfos() -> String {
        return "\(dimseStatus.status)"
    }
    
    public override func data() -> Data? {
        if let pc = self.association.acceptedPresentationContexts.values.first,
           let transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian) {
            let commandDataset = DataSet()
            _ = commandDataset.set(value: CommandField.C_FIND_RSP.rawValue, forTagName: "CommandField")
            _ = commandDataset.set(value: pc.abstractSyntax as Any, forTagName: "AffectedSOPClassUID")
            
            if let request = self.requestMessage {
                _ = commandDataset.set(value: request.messageID, forTagName: "MessageIDBeingRespondedTo")
            }
            _ = commandDataset.set(value: UInt16(257), forTagName: "CommandDataSetType")
            _ = commandDataset.set(value: UInt16(0), forTagName: "Status")
            
            let pduData = PDUData(
                pduType: self.pduType,
                commandDataset: commandDataset,
                abstractSyntax: pc.abstractSyntax,
                transferSyntax: transferSyntax,
                pcID: pc.contextID, flags: 0x03)
            
            return pduData.data()
        }
        
        return nil
    }
    
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        Logger.debug("C-FIND-RSP: Input data size: \(data.count) bytes")
        let status = super.decodeData(data: data)
        
        Logger.debug("C-FIND-RSP: Parent decodeData returned status: \(status)")
        Logger.debug("C-FIND-RSP: CommandDataSetType: \(String(describing: commandDataSetType))")
        Logger.debug("C-FIND-RSP: CommandField: \(String(describing: commandField))")
        Logger.debug("C-FIND-RSP: Flags: \(String(format: "0x%02X", flags ?? 0))")
        Logger.debug("C-FIND-RSP: ReceivedData size: \(receivedData.count) bytes")
        Logger.debug("C-FIND-RSP: Stream readable bytes: \(stream.readableBytes)")
        
        // Handle different fragment types based on flags
        // 0x00: Data fragment, more fragments follow
        // 0x01: Command fragment, more fragments follow (not fully supported yet)
        // 0x02: Data fragment, last fragment
        // 0x03: Command fragment, last fragment
        
        if flags == 0x01 {
            Logger.warning("C-FIND-RSP: Received fragmented command (flags=0x01) - not fully supported, waiting for more fragments")
            return .Pending
        }
        
        // For data fragments (flags 0x00 or 0x02), commandDataSetType will be nil and that's OK
        // Only refuse if it's a command fragment (0x03) that failed
        if flags == 0x03 && (status == .Refused || status == .Cancel || status == .Unknow) {
            Logger.error("C-FIND-RSP: Command fragment failed to decode, returning status: \(status)")
            return status
        }
        
        let pc = association.acceptedPresentationContexts[association.acceptedPresentationContexts.keys.first!]
        let ts = pc?.transferSyntaxes.first
        
        if ts == nil {
            Logger.error("No transfer syntax found, refused")
            return .Refused
        }
        
        let transferSyntax = TransferSyntax(ts!)
                     
        // Check if this is a data fragment (flags == 0x00 or 0x02) that parent already processed
        if (flags == 0x00 || flags == 0x02) && commandDataSetType == nil {
            Logger.debug("C-FIND-RSP: Data fragment (flags=\(String(format: "0x%02X", flags ?? 0))) - parent class already consumed PDV header")
            
            // Parent class already read PDV length and context+flags, data is in receivedData
            if receivedData.count > 0 {
                Logger.debug("C-FIND-RSP: Processing \(receivedData.count) bytes of received data")
                
                let dis = DicomInputStream(data: receivedData)
                dis.vrMethod    = transferSyntax!.vrMethod
                dis.byteOrder   = transferSyntax!.byteOrder
                
                if let resultDataset = try? dis.readDataset(enforceVR: false) {
                    resultsDataset = resultDataset
                    Logger.info("C-FIND-RSP: Successfully parsed result dataset with \(resultDataset.allElements.count) elements")
                    
                    // Log key fields if present
                    if let patientName = resultDataset.string(forTag: "PatientName") {
                        Logger.debug("C-FIND-RSP: PatientName: \(patientName)")
                    }
                    if let studyUID = resultDataset.string(forTag: "StudyInstanceUID") {
                        Logger.debug("C-FIND-RSP: StudyInstanceUID: \(studyUID)")
                    }
                } else {
                    Logger.warning("C-FIND-RSP: Failed to parse result dataset from receivedData")
                }
            } else {
                Logger.debug("C-FIND-RSP: No received data to process")
            }
            
            return status
        }
        
        // if the PDU message is complete, and commandDataSetType indicates presence of dataset
        if commandDataSetType == 0 {
            Logger.debug("C-FIND-RSP: Processing complete message with dataset")
            Logger.debug("C-FIND-RSP: Stream has \(stream.readableBytes) readable bytes")
            
            var datasetData: Data?
            
            // Check if there's enough data for another PDV
            if stream.readableBytes >= 6 { // Minimum: 4 bytes length + 1 byte context + 1 byte flags
                // read data PDV length
                guard let dataPDVLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
                    Logger.error("Cannot read data PDV Length for fragmented message (CFindRSP)")
                    return .Refused
                }
                
                Logger.debug("C-FIND-RSP: Data PDV length: \(dataPDVLength)")
                
                // Validate PDV length
                guard dataPDVLength > 2 && dataPDVLength < 1024 * 1024 * 10 else { // Max 10MB PDV
                    Logger.error("Invalid PDV length: \(dataPDVLength)")
                    return .Refused
                }
                            
                // jump context + flags
                stream.forward(by: 2)
                
                // read dataset data
                datasetData = stream.read(length: Int(dataPDVLength - 2))
                if datasetData == nil {
                    Logger.error("Cannot read dataset data")
                    return .Refused
                }
            } else {
                // No more PDVs in this P-DATA-TF, dataset might come in next message
                Logger.debug("C-FIND-RSP: No data PDV in this message, waiting for next P-DATA-TF")
                return status
            }
            
            if let datasetData = datasetData {
                Logger.debug("C-FIND-RSP: Read \(datasetData.count) bytes of dataset data")
                
                let dis = DicomInputStream(data: datasetData)
                
                dis.vrMethod    = transferSyntax!.vrMethod
                dis.byteOrder   = transferSyntax!.byteOrder
                
                if commandField == .C_FIND_RSP {
                    if let resultDataset = try? dis.readDataset() {
                        resultsDataset = resultDataset
                        Logger.info("C-FIND-RSP: Successfully parsed result dataset with \(resultDataset.allElements.count) elements")
                        
                        // Log key fields if present
                        if let patientName = resultDataset.string(forTag: "PatientName") {
                            Logger.debug("C-FIND-RSP: PatientName: \(patientName)")
                        }
                        if let studyUID = resultDataset.string(forTag: "StudyInstanceUID") {
                            Logger.debug("C-FIND-RSP: StudyInstanceUID: \(studyUID)")
                        }
                        if let modality = resultDataset.string(forTag: "Modality") {
                            Logger.debug("C-FIND-RSP: Modality: \(modality)")
                        }
                    } else {
                        Logger.warning("C-FIND-RSP: Failed to parse result dataset")
                    }
                }
            }
        } else {
            Logger.debug("C-FIND-RSP: No dataset present (commandDataSetType: \(commandDataSetType ?? -1))")
        }
        
        return status
    }
}
