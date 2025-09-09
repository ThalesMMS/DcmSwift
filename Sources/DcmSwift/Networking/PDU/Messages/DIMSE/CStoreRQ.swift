//
//  CStoreRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public protocol CStoreRQDelegate {
    func receive(message: CStoreRQ)
}

/**
 The `CStoreRQ` class represents a C-STORE-RQ message of the DICOM standard.
 
 Its main property is a `DicomFile` object, the one that will be transfered over the DIMSE service.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part07/sect_9.3.html
 */
public class CStoreRQ: DataTF {
    public var dicomFile:DicomFile?
    
    
    public override func messageName() -> String {
        return "C-STORE-RQ"
    }
    
    
    public override func data() -> Data? {
        // get file SOPClassUID and accepted PC
        guard let sopClassUID = dicomFile?.dataset.string(forTag: "SOPClassUID"),
              let sopInstanceUID = dicomFile?.dataset.string(forTag: "SOPInstanceUID"),
              let commandTransferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian),
              let pc = self.association.acceptedPresentationContexts(forSOPClassUID: sopClassUID).first else {
            Logger.error("File cannot be sent because no SOP Class UID was found.")
            return nil
        }

        // 1) Build Command Set
        let commandDataset = DataSet()
        _ = commandDataset.set(value: CommandField.C_STORE_RQ.rawValue, forTagName: "CommandField")
        _ = commandDataset.set(value: sopClassUID, forTagName: "AffectedSOPClassUID")
        _ = commandDataset.set(value: UInt16(1), forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(0), forTagName: "Priority")
        _ = commandDataset.set(value: UInt16(1), forTagName: "CommandDataSetType")
        _ = commandDataset.set(value: sopInstanceUID, forTagName: "AffectedSOPInstanceUID")

        var commandData = commandDataset.toData(transferSyntax: commandTransferSyntax)
        let commandLength = commandData.count
        _ = commandDataset.set(value: UInt32(commandLength), forTagName: "CommandGroupLength")
        commandData = commandDataset.toData(transferSyntax: commandTransferSyntax)

        // 2) Data Set bytes with negotiated TS for this PC
        var datasetData: Data? = nil
        if let dicomFile = self.dicomFile,
           let tsUID = self.association.acceptedPresentationContexts[pc.contextID]?.transferSyntaxes.first,
           let dataTransferSyntax = TransferSyntax(tsUID) {
            datasetData = dicomFile.dataset.toData(transferSyntax: dataTransferSyntax)
        }

        // 3) Build PDU with two PDVs
        var pduPayload = Data()

        // Command PDV
        var cmdPDV = Data()
        let cmdHeader: UInt8 = 0b00000011 // Command, and always Last fragment for command part
        cmdPDV.append(uint8: pc.contextID, bigEndian: true)
        cmdPDV.append(cmdHeader)
        cmdPDV.append(commandData)
        pduPayload.append(uint32: UInt32(cmdPDV.count), bigEndian: true)
        pduPayload.append(cmdPDV)

        // Data PDV (if any)
        if let ds = datasetData {
            var dataPDV = Data()
            dataPDV.append(uint8: pc.contextID, bigEndian: true)
            dataPDV.append(UInt8(0b00000010)) // Last only
            dataPDV.append(ds)
            pduPayload.append(uint32: UInt32(dataPDV.count), bigEndian: true)
            pduPayload.append(dataPDV)
        }

        var pdu = Data()
        pdu.append(uint8: PDUType.dataTF.rawValue, bigEndian: true)
        pdu.append(byte: 0x00)
        pdu.append(uint32: UInt32(pduPayload.count), bigEndian: true)
        pdu.append(pduPayload)
        return pdu
    }
    
    
    public override func messagesData() -> [Data] {
        return []
    }
    
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        return status
    }
    
    
    public override func handleResponse(data: Data) -> PDUMessage? {
        if let command:UInt8 = data.first {
            if command == self.pduType.rawValue {
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: data,
                    pduType: PDUType.dataTF,
                    commandField: CommandField.C_STORE_RSP,
                    association: self.association
                ) as? PDUMessage {
                    return message
                }
            }
        }
        return nil
    }
    
    
    public override func handleRequest() -> PDUMessage? {
        if let response = PDUEncoder.createDIMSEMessage(
            pduType: .dataTF,
            commandField: .C_STORE_RSP,
            association: self.association
        ) as? PDUMessage {
            response.dimseStatus = DIMSEStatus(status: .Success, command: .C_STORE_RSP)
            response.requestMessage = self
            return response
        }
        return nil
    }
}
