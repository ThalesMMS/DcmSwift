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
     This implementation of `data()` encodes PDU and Command part of the `C-MOVE-RQ` message.
     */
    public override func data() -> Data? {
        // fetch accepted PC
        guard let pcID = association.acceptedPresentationContexts.keys.first,
              let spc = association.presentationContexts[pcID],
              let transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian),
              let abstractSyntax = spc.abstractSyntax else {
            return nil
        }
        
        // build command dataset
        let commandDataset = DataSet()
        _ = commandDataset.set(value: abstractSyntax as Any, forTagName: "AffectedSOPClassUID")
        _ = commandDataset.set(value: CommandField.C_MOVE_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(0).bigEndian, forTagName: "Priority")
        _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "CommandDataSetType")
        _ = commandDataset.set(value: moveDestinationAET as Any, forTagName: "MoveDestination")
        
        let pduData = PDUData(
            pduType: self.pduType,
            commandDataset: commandDataset,
            abstractSyntax: abstractSyntax,
            transferSyntax: transferSyntax,
            pcID: pcID, flags: 0x03)
        
        return pduData.data()
    }
    
    /**
     This implementation of `messagesData()` encodes the query dataset into a valid `DataTF` message.
     */
    public override func messagesData() -> [Data] {
        // fetch accepted TS from association
        guard let pcID = association.acceptedPresentationContexts.keys.first,
              let spc = association.presentationContexts[pcID],
              let ats = self.association.acceptedTransferSyntax,
              let transferSyntax = TransferSyntax(ats),
              let abstractSyntax = spc.abstractSyntax else {
            return []
        }
                
        // encode query dataset elements
        if let qrDataset = self.queryDataset, qrDataset.allElements.count > 0 {
            let pduData = PDUData(
                pduType: self.pduType,
                commandDataset: qrDataset,
                abstractSyntax: abstractSyntax,
                transferSyntax: transferSyntax,
                pcID: pcID, flags: 0x02)
            
            return [pduData.data()]
        }
        
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