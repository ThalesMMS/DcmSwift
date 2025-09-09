//
//  CStoreRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CStoreRSP` class represents a C-STORE-RSP message of the DICOM standard.

 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part07/sect_9.3.html
 */
public class CStoreRSP: DataTF {
    public override func messageName() -> String {
        return "C-STORE-RSP"
    }
    
    
    public override func messageInfos() -> String {
        return "\(dimseStatus.status)"
    }
    
    public override func data() -> Data? {
        // Prefer replying on the same Presentation Context as the incoming C-STORE-RQ
        var pcToUse: PresentationContext?
        if let reqDataTF = requestMessage as? DataTF, let ctx = reqDataTF.contextID {
            pcToUse = self.association.acceptedPresentationContexts[ctx]
        }
        if pcToUse == nil { pcToUse = self.association.acceptedPresentationContexts.values.first }
        
        // Fallbacks to ensure we always encode a response
        guard let pc = pcToUse ?? self.association.acceptedPresentationContexts.values.first else {
            Logger.error("C-STORE-RSP: No presentation context available to reply")
            return nil
        }
        guard let transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian) else {
            Logger.error("C-STORE-RSP: Could not resolve command transfer syntax")
            return nil
        }
            let commandDataset = DataSet()
            _ = commandDataset.set(value: CommandField.C_STORE_RSP.rawValue, forTagName: "CommandField")
            // Prefer SOP Class UID from the request; AC presentation contexts may have nil abstractSyntax
            var affectedSOPClass = pc.abstractSyntax
            
            if let request = self.requestMessage {
                _ = commandDataset.set(value: request.messageID, forTagName: "MessageIDBeingRespondedTo")
                if let reqCmd = request.commandDataset {
                    if affectedSOPClass == nil {
                        affectedSOPClass = reqCmd.string(forTag: "AffectedSOPClassUID") ?? reqCmd.string(forTag: "SOPClassUID")
                    }
                    if let iuid = reqCmd.string(forTag: "AffectedSOPInstanceUID") ?? reqCmd.string(forTag: "SOPInstanceUID") {
                        _ = commandDataset.set(value: iuid, forTagName: "AffectedSOPInstanceUID")
                    }
                }
            }
            if let asuid = affectedSOPClass { _ = commandDataset.set(value: asuid, forTagName: "AffectedSOPClassUID") }
            _ = commandDataset.set(value: UInt16(257), forTagName: "CommandDataSetType")
            _ = commandDataset.set(value: UInt16(0), forTagName: "Status")
            
            let pduData = PDUData(
                pduType: self.pduType,
                commandDataset: commandDataset,
                abstractSyntax: affectedSOPClass ?? "1.2.840.10008.1.1", // Verification SOP as last resort
                transferSyntax: transferSyntax,
                pcID: pc.contextID, flags: 0x03)
            
            return pduData.data()
    }
    
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        //print(data.toHex())
        
        return status
    }
    
    
    public override func handleResponse(data: Data) -> PDUMessage? {
        return nil
    }
}
