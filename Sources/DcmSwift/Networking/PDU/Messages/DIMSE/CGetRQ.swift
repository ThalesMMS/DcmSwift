//
//  CGetRQ.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/**
 The `CGetRQ` class represents a C-GET-RQ message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.3.html
 */
public class CGetRQ: DataTF {
    /// The query dataset containing the UIDs to get
    public var queryDataset: DataSet?
    /// Collection of received files
    public var receivedFiles: [DicomFile] = []
    /// Path for temporary storage of received files
    public var temporaryStoragePath: String = NSTemporaryDirectory()
    
    public override func messageName() -> String {
        return "C-GET-RQ"
    }
    
    /**
     This implementation of `data()` encodes PDU, Command and Query Dataset parts of the `C-GET-RQ` message.
     FIXED: Now sends command and query dataset in the same PDU to ensure proper operation.
     */
    public override func data() -> Data? {
        // 1. Get presentation context for Study/Patient Root GET, abstract syntax, and command transfer syntax
        let studyAS = DicomConstants.StudyRootQueryRetrieveInformationModelGET
        let patientAS = DicomConstants.PatientRootQueryRetrieveInformationModelGET
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
            Logger.error("C-GET: No accepted Presentation Context for Study/Patient Root GET")
            return nil
        }

        // 2. Check if a query dataset is present
        let hasDataset = self.queryDataset != nil && self.queryDataset!.allElements.count > 0

        // 3. Build the command dataset
        let commandDataset = DataSet()
        _ = commandDataset.set(value: CommandField.C_GET_RQ.rawValue, forTagName: "CommandField")
        _ = commandDataset.set(value: abstractSyntax, forTagName: "AffectedSOPClassUID")
        _ = commandDataset.set(value: self.messageID, forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(0), forTagName: "Priority") // MEDIUM

        if hasDataset {
            // Per PS 3.7, 0x0101 means no dataset; anything else (e.g., 0x0000) means dataset follows
            _ = commandDataset.set(value: UInt16(0x0000), forTagName: "CommandDataSetType")
        } else {
            _ = commandDataset.set(value: UInt16(0x0101), forTagName: "CommandDataSetType")
        }

        // Insert placeholder for CommandGroupLength at the beginning
        _ = commandDataset.set(value: UInt32(0), forTagName: "CommandGroupLength")

        // Compute actual group length excluding the CommandGroupLength element itself (12 bytes)
        var commandData = commandDataset.toData(transferSyntax: commandTransferSyntax)
        let commandLength = commandData.count - 12
        _ = commandDataset.set(value: UInt32(commandLength), forTagName: "CommandGroupLength")
        commandData = commandDataset.toData(transferSyntax: commandTransferSyntax)
        
        // 5. Build the PDU payload (two PDVs when dataset exists)
        var pduPayload = Data()

        // Command PDV
        var cmdPDV = Data()
        let cmdHeader: UInt8 = 0b00000011 // Command, and always Last fragment for command part
        cmdPDV.append(uint8: pcID, bigEndian: true)
        cmdPDV.append(cmdHeader)
        cmdPDV.append(commandData)
        pduPayload.append(uint32: UInt32(cmdPDV.count), bigEndian: true)
        pduPayload.append(cmdPDV)

        // Data PDV (if any)
        if hasDataset, let qrDataset = self.queryDataset {
            guard let tsUID = self.association.acceptedPresentationContexts[pcID]?.transferSyntaxes.first,
                  let dataTransferSyntax = TransferSyntax(tsUID) else {
                return nil
            }
            let datasetData = qrDataset.toData(transferSyntax: dataTransferSyntax)
            var dataPDV = Data()
            dataPDV.append(uint8: pcID, bigEndian: true)
            dataPDV.append(UInt8(0b00000010)) // Last only
            dataPDV.append(datasetData)
            pduPayload.append(uint32: UInt32(dataPDV.count), bigEndian: true)
            pduPayload.append(dataPDV)
        }
        
        // 6. Build the final P-DATA-TF PDU
        var pdu = Data()
        pdu.append(uint8: PDUType.dataTF.rawValue, bigEndian: true)
        pdu.append(byte: 0x00) // reserved
        pdu.append(uint32: UInt32(pduPayload.count), bigEndian: true)
        pdu.append(pduPayload)
        
        return pdu
    }
    
    /**
     This implementation of `messagesData()` is now empty since query dataset is included in main data() method.
     */
    public override func messagesData() -> [Data] {
        // Query dataset is now sent together with command in data() method
        return []
    }
    
    /**
     This implementation of `handleResponse()` decodes the received data.
     
     C-GET is special: it can receive both C-GET-RSP messages (status updates)
     and C-STORE-RQ messages (actual image data) on the same association.
     */
    override public func handleResponse(data: Data) -> PDUMessage? {
        if let command: UInt8 = data.first {
            if command == self.pduType.rawValue {
                // Try to decode as C-GET-RSP first
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: data,
                    pduType: PDUType.dataTF,
                    commandField: .C_GET_RSP,
                    association: self.association
                ) as? CGetRSP {
                    return message
                }
                
                // Also handle incoming C-STORE-RQ messages on the same association
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: data,
                    pduType: PDUType.dataTF,
                    commandField: .C_STORE_RQ,
                    association: self.association
                ) as? CStoreRQ {
                    // Process the incoming image data
                    // This will be handled by the CGetSCU service class
                    return message
                }
            }
        }
        return nil
    }
}
