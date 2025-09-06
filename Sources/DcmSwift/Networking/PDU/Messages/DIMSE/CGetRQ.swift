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
     This implementation of `data()` encodes PDU and Command part of the `C-GET-RQ` message.
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
        _ = commandDataset.set(value: CommandField.C_GET_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(0).bigEndian, forTagName: "Priority")
        _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "CommandDataSetType")
        
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