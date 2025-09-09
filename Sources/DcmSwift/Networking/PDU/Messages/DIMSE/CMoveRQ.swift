//
//  CMoveRQ.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation

/**
 The `CMoveRQ` class represents a C-MOVE-RQ message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.4.html
 */
public class CMoveRQ: DataTF {
    /// The query dataset containing the UIDs to move
    public var queryDataset: DataSet?
    /// The destination AE title for the move operation
    public var moveDestinationAET: String = ""
    /// Collection of move results
    public var moveResults: [Any] = []
    
    public override func messageName() -> String {
        return "C-MOVE-RQ"
    }
    
    /**
     This implementation of `data()` encodes PDU, Command and Query Dataset parts of the `C-MOVE-RQ` message.
     FIXED: Now sends command and query dataset in the same PDU to ensure proper operation.
     */
    public override func data() -> Data? {
        // 1. Get presentation context, abstract syntax, and command transfer syntax
        guard let pcID = association.acceptedPresentationContexts.keys.first,
              let spc = association.presentationContexts[pcID],
              let commandTransferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian),
              let abstractSyntax = spc.abstractSyntax else {
            return nil
        }

        // 2. Check if a query dataset is present
        let hasDataset = self.queryDataset != nil && self.queryDataset!.allElements.count > 0

        // 3. Build the command dataset
        let commandDataset = DataSet()
        _ = commandDataset.set(value: CommandField.C_MOVE_RQ.rawValue, forTagName: "CommandField")
        _ = commandDataset.set(value: abstractSyntax, forTagName: "AffectedSOPClassUID")
        _ = commandDataset.set(value: UInt16(1), forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(0), forTagName: "Priority") // MEDIUM
        _ = commandDataset.set(value: moveDestinationAET, forTagName: "MoveDestination")

        if hasDataset {
            _ = commandDataset.set(value: UInt16(0x0001), forTagName: "CommandDataSetType")
        } else {
            _ = commandDataset.set(value: UInt16(0x0102), forTagName: "CommandDataSetType")
        }
        
        // 4. Serialize the command dataset
        var commandData = commandDataset.toData(transferSyntax: commandTransferSyntax)
        let commandLength = commandData.count
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
     This implementation of `handleResponse()` decodes the received data as `CMoveRSP` using `PDUDecoder`.
     
     This method is called by NIO channelRead() method to decode DIMSE messages.
     The method is directly fired from the originator message of type `CMoveRQ`.
     */
    override public func handleResponse(data: Data) -> PDUMessage? {
        if let command: UInt8 = data.first {
            if command == self.pduType.rawValue {
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: data,
                    pduType: PDUType.dataTF,
                    commandField: .C_MOVE_RSP,
                    association: self.association
                ) as? CMoveRSP {
                    return message
                }
            }
        }
        return nil
    }
}
