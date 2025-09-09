//
//  CFindRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


/**
 The `CFindRQ` class represents a C-FIND-RQ message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.2.html
 */
public class CFindRQ: DataTF {
    /// the query dataset given by the user
    public var queryDataset:DataSet?
    /// the query results of the C-FIND
    public var queryResults:[Any] = []
    public var resultsDataset:DataSet?
    
    public override func messageName() -> String {
        return "C-FIND-RQ"
    }
    
    
    /**
     Encodes the C-FIND request as a P-DATA-TF with 1 or 2 PDVs:
     - PDV #1: Command Set (Command flag set, Last fragment set)
     - PDV #2: Dataset (if present) (Command flag clear, Last fragment set)

     Notes:
     - Command Set always uses Implicit VR Little Endian.
     - Dataset uses the accepted transfer syntax for the chosen Presentation Context.
     - Presentation Context is selected to match the requested abstract syntax (FIND model).
     */
    public override func data() -> Data? {
        Logger.debug("!!!! CFindRQ.data() CALLED !!!!")
        
        // 1. Find accepted Presentation Context for C-FIND (Study Root preferred, then Patient Root)
        let studyAS = DicomConstants.StudyRootQueryRetrieveInformationModelFIND
        let patientAS = DicomConstants.PatientRootQueryRetrieveInformationModelFIND

        func findAcceptedPC(for asuid: String) -> UInt8? {
            for (ctxID, _) in association.acceptedPresentationContexts {
                if let proposed = association.presentationContexts[ctxID], proposed.abstractSyntax == asuid {
                    return ctxID
                }
            }
            return nil
        }

        guard let pcID = findAcceptedPC(for: studyAS) ?? findAcceptedPC(for: patientAS),
              let spc = association.presentationContexts[pcID],
              let abstractSyntax = spc.abstractSyntax,
              let commandTransferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian) else {
            Logger.error("C-FIND: No accepted Presentation Context for Study/Patient Root FIND")
            return nil
        }
        // 2. Prepare Command Dataset (always Implicit VR Little Endian)
        let commandDataset = DataSet()
        _ = commandDataset.set(value: CommandField.C_FIND_RQ.rawValue, forTagName: "CommandField")
        _ = commandDataset.set(value: abstractSyntax, forTagName: "AffectedSOPClassUID")
        _ = commandDataset.set(value: self.messageID, forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(0), forTagName: "Priority") // MEDIUM

        // 3. Prepare Data Dataset (if any)
        var datasetData: Data? = nil
        if let qrDataset = self.queryDataset, qrDataset.allElements.count > 0 {
            // Per DICOM PS 3.7, CommandDataSetType = 0x0101 means NO Data Set present.
            // Any other value (typically 0x0000) indicates a Data Set follows.
            _ = commandDataset.set(value: UInt16(0x0000), forTagName: "CommandDataSetType") // DataSet follows
            guard let dataTS_UID = association.acceptedPresentationContexts[pcID]?.transferSyntaxes.first,
                  let dataTransferSyntax = TransferSyntax(dataTS_UID) else {
                Logger.error("C-FIND: Could not find an accepted transfer syntax for PC ID \(pcID)")
                return nil
            }
            
            // Log the query dataset before serialization
            Logger.debug("--- BEGIN C-FIND QUERY DATASET DUMP ---")
            for element in qrDataset.allElements {
                let valueStr = element.value != nil ? "\(element.value)" : "<empty>"
                Logger.debug("(\(element.tag)) \(element.name.padding(toLength: 25, withPad: " ", startingAt: 0)) \(element.vr): \(valueStr)")
                
                // WARN if any tag name is "Unknow" - indicates missing dictionary entry
                if element.name == "Unknow" {
                    Logger.error("WARNING: Tag \(element.tag) has no dictionary entry! This may cause PACS to reject the query.")
                    Logger.error("Consider removing this field from the query or fixing the dictionary.")
                }
            }
            Logger.debug("--- END C-FIND QUERY DATASET DUMP ---")
            
            datasetData = qrDataset.toData(transferSyntax: dataTransferSyntax)
        } else {
            _ = commandDataset.set(value: UInt16(0x0101), forTagName: "CommandDataSetType") // No DataSet
        }

        // Log the command dataset before serialization
        Logger.debug("--- BEGIN C-FIND COMMAND DATASET DUMP ---")
        for element in commandDataset.allElements {
            let valueStr: String
            if element.name == "CommandField", let cmdValue = element.value as? UInt16 {
                valueStr = "\(cmdValue) [C_FIND_RQ]"
            } else if element.name == "Priority", let prio = element.value as? UInt16 {
                valueStr = "\(prio) [\(prio == 0 ? "MEDIUM" : prio == 1 ? "HIGH" : "LOW")]"
            } else if element.name == "CommandDataSetType", let dsType = element.value as? UInt16 {
                // 0x0101 => No DataSet present; anything else (e.g., 0x0000) => DataSet follows
                valueStr = "\(dsType) [\(dsType == 0x0101 ? "NO_DATASET" : "HAS_DATASET")]"
            } else {
                valueStr = element.value != nil ? "\(element.value)" : "<empty>"
            }
            Logger.debug("(\(element.tag)) \(element.name.padding(toLength: 25, withPad: " ", startingAt: 0)) \(element.vr): \(valueStr)")
        }
        Logger.debug("--- END C-FIND COMMAND DATASET DUMP ---")

        // 4. Compute CommandGroupLength and serialize command
        // IMPORTANT: First create CommandGroupLength with placeholder value
        _ = commandDataset.set(value: UInt32(0), forTagName: "CommandGroupLength")
        
        // Now serialize the complete dataset to get correct size
        var commandData = commandDataset.toData(transferSyntax: commandTransferSyntax)
        
        // The CommandGroupLength should be the total size minus the CommandGroupLength element itself (12 bytes)
        // CommandGroupLength in Implicit VR = 4 bytes (tag) + 4 bytes (length) + 4 bytes (value) = 12 bytes
        let commandLength = commandData.count - 12
        
        Logger.debug("C-FIND: Total command size: \(commandData.count), Setting CommandGroupLength to \(commandLength)")
        
        // Update CommandGroupLength with correct value
        _ = commandDataset.set(value: UInt32(commandLength), forTagName: "CommandGroupLength")
        
        // Re-serialize with correct CommandGroupLength value
        commandData = commandDataset.toData(transferSyntax: commandTransferSyntax)
        
        // Verify CommandGroupLength is first in the dataset
        if let firstElement = commandDataset.allElements.first {
            Logger.debug("C-FIND: First element in dataset: tag=\(firstElement.tag), name=\(firstElement.name)")
            if firstElement.name != "CommandGroupLength" {
                Logger.error("C-FIND: WARNING - CommandGroupLength is not the first element!")
            }
        }
        
        // Log serialization results
        Logger.info("C-FIND: Final Command Dataset (\(commandData.count) bytes), Query Dataset (\(datasetData?.count ?? 0) bytes)")
        if commandData.count >= 20 {
            let preview = commandData.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
            Logger.debug("C-FIND: Command first 20 bytes: \(preview)")
            
            // Also log the expected bytes for CommandGroupLength
            Logger.debug("C-FIND: Expected CommandGroupLength bytes: 00 00 00 00 04 00 00 00 \(String(format: "%02X", commandLength & 0xFF)) \(String(format: "%02X", (commandLength >> 8) & 0xFF)) \(String(format: "%02X", (commandLength >> 16) & 0xFF)) \(String(format: "%02X", (commandLength >> 24) & 0xFF))")
        }
        if let dsData = datasetData, dsData.count >= 8 {
            let preview = dsData.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            Logger.debug("C-FIND: Query first bytes: \(preview)")
        }

        // 5. Build a single P-DATA-TF PDU containing both Command PDV and (if present) Data PDV
        var pduPayload = Data()
        // Command PDV
        var cmdPDV = Data()
        let cmdHeader: UInt8 = 0x03 // Command + Last fragment
        cmdPDV.append(uint8: pcID, bigEndian: true)
        cmdPDV.append(cmdHeader)
        cmdPDV.append(commandData)
        pduPayload.append(uint32: UInt32(cmdPDV.count), bigEndian: true)
        pduPayload.append(cmdPDV)

        // Data PDV (if any)
        if let data = datasetData {
            var dataPDV = Data()
            let dataHeader: UInt8 = 0x02 // Last fragment only
            dataPDV.append(uint8: pcID, bigEndian: true)
            dataPDV.append(dataHeader)
            dataPDV.append(data)
            pduPayload.append(uint32: UInt32(dataPDV.count), bigEndian: true)
            pduPayload.append(dataPDV)
        }

        Logger.info("C-FIND using PCID=\(pcID) AS=\(abstractSyntax) cmdLen=\(commandData.count) dsLen=\(datasetData?.count ?? 0)")

        var pdu = Data()
        pdu.append(uint8: PDUType.dataTF.rawValue, bigEndian: true)
        pdu.append(byte: 0x00)
        pdu.append(uint32: UInt32(pduPayload.count), bigEndian: true)
        pdu.append(pduPayload)

        return pdu
    }
    
    public override func messagesData() -> [Data] {
        // Command and Query Dataset are now sent together in a single PDU
        return []
    }
    
    
    /**
     Not implemeted yet
     
     TODO: we actually don't read C-FIND-RQ message, yet! (server side)
     */
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
                
        if stream.readableBytes > 0 {
            let pc = association.acceptedPresentationContexts[association.acceptedPresentationContexts.keys.first!]
            let ts = pc?.transferSyntaxes.first
            
            if ts == nil {
                Logger.error("No transfer syntax found, refused")
                return .Refused
            }
            
            let transferSyntax = TransferSyntax(ts!)
            
            guard let pdvLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
                Logger.error("Cannot read dataset data")
                return .Refused
            }
            
            self.pdvLength = Int(pdvLength)
            
            // jump context + flags
            stream.forward(by: 2)
            
            // read dataset data
            guard let datasetData = stream.read(length: Int(pdvLength - 2)) else {
                Logger.error("Cannot read dataset data")
                return .Refused
            }
            
            let dis = DicomInputStream(data: datasetData)
            
            dis.vrMethod    = transferSyntax!.vrMethod
            dis.byteOrder   = transferSyntax!.byteOrder
            
            if commandField == .C_FIND_RQ {
                if let resultDataset = try? dis.readDataset() {
                    resultsDataset = resultDataset
                }
            }
        }
        
        return status
    }
    
    
    /**
     This implementation of `handleResponse()` decodes the received data as `CFindRSP` using `PDUDecoder`.
     
     This method is called by NIO channelRead() method to decode DIMSE messages.
     The method is directly fired from the originator message of type `CFindRQ`.

     It benefits from the proximity between the originator (`CFindRQ`) message and it response (`CFindRSP`)
     to fill the `queryResults` property with freshly received dataset (`CFindRSP.studiesDataset`).
     */
    override public func handleResponse(data: Data) -> PDUMessage? {
        if let command:UInt8 = data.first {
            if command == self.pduType.rawValue {
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: data,
                    pduType: PDUType.dataTF,
                    commandField: .C_FIND_RSP,
                    association: self.association
                ) as? CFindRSP {
                    // fill result with dataset from each DATA-TF message
                    if let studiesDataset = message.resultsDataset {
                        self.queryResults.append(studiesDataset.toJSONArray())
                    }
                    
                    return message
                }
            }
        }
        return nil
    }
}
