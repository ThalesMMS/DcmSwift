//
//  CGetSCU.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation
import NIO

/**
 C-GET Service Class User implementation.
 
 This class handles C-GET operations which retrieve DICOM objects directly
 through the same association used for the request. Unlike C-MOVE, C-GET
 receives the data through C-STORE sub-operations on the same connection.
 */
public class CGetSCU: ServiceClassUser {
    /// Query dataset containing the UIDs to retrieve
    var queryDataset: DataSet
    /// Query/Retrieve level (PATIENT, STUDY, SERIES, IMAGE)
    var queryLevel: QueryRetrieveLevel = .STUDY
    /// Instance UID for specific level queries
    var instanceUID: String?
    /// Collection of received DICOM files
    public var receivedFiles: [DicomFile] = []
    /// Path for temporary storage of received files
    public var temporaryStoragePath: String = NSTemporaryDirectory()
    /// Last C-GET-RSP message received
    var lastGetRSP: CGetRSP?
    
    public override var commandField: CommandField {
        .C_GET_RQ
    }
    
    public override var abstractSyntaxes: [String] {
        switch queryLevel {
        case .PATIENT:
            return [DicomConstants.PatientRootQueryRetrieveInformationModelGET]
            
        case .STUDY:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelGET]
            
        case .SERIES:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelGET]
            
        case .IMAGE:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelGET]
        }
    }
    
    public init(_ queryDataset: DataSet? = nil, queryLevel: QueryRetrieveLevel? = nil, instanceUID: String? = nil) {
        if let queryLevel = queryLevel {
            self.queryLevel = queryLevel
        }
        
        self.instanceUID = instanceUID
        
        if let queryDataset = queryDataset {
            self.queryDataset = queryDataset
        } else {
            self.queryDataset = QueryRetrieveLevel.defaultQueryDataset(level: self.queryLevel)
        }
        
        super.init()
    }
    
    public override func request(association: DicomAssociation, channel: Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CGetRQ {
            let p: EventLoopPromise<Void> = channel.eventLoop.makePromise()
            
            _ = queryDataset.set(value: "\(self.queryLevel)", forTagName: "QueryRetrieveLevel")
            
            if let uid = instanceUID {
                switch queryLevel {
                case .STUDY:
                    _ = queryDataset.set(value: uid, forTagName: "StudyInstanceUID")
                case .SERIES:
                    _ = queryDataset.set(value: uid, forTagName: "SeriesInstanceUID")
                case .IMAGE:
                    _ = queryDataset.set(value: uid, forTagName: "SOPInstanceUID")
                default:
                    break
                }
            }
            
            message.queryDataset = queryDataset
            message.temporaryStoragePath = temporaryStoragePath
            
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
    
    public override func receive(association: DicomAssociation, dataTF message: DataTF) -> DIMSEStatus.Status {
        var result: DIMSEStatus.Status = .Pending
        
        // Handle C-GET-RSP messages (status updates)
        if let m = message as? CGetRSP {
            result = m.dimseStatus.status
            lastGetRSP = m
            
            Logger.info("C-GET-RSP: \(m.messageInfos())")
            
            return result
        }
        // Handle C-STORE-RQ messages (actual data transfer)
        else if let storeRQ = message as? CStoreRQ {
            if let dicomFile = storeRQ.dicomFile {
                let sopInstanceUID = dicomFile.dataset.string(forTag: "SOPInstanceUID")
                if let file = saveReceivedFile(dicomFile, sopInstanceUID: sopInstanceUID) {
                    receivedFiles.append(file)
                    sendStoreResponse(for: storeRQ, association: association, status: .Success)
                } else {
                    sendStoreResponse(for: storeRQ, association: association, status: .UnableToProcess)
                    Logger.error("C-GET: \(DicomNetworkError.saveFailed(path: temporaryStoragePath, underlying: nil))")
                }
            }
            
            return .Pending // Continue waiting for more data or final C-GET-RSP
        }
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func saveReceivedFile(_ dicomFile: DicomFile, sopInstanceUID: String?) -> DicomFile? {
        let fileName = sopInstanceUID ?? UUID().uuidString
        let filePath = (temporaryStoragePath as NSString).appendingPathComponent("\(fileName).dcm")
        
        if dicomFile.write(atPath: filePath) {
            Logger.info("C-GET: Saved file to \(filePath)")
            return DicomFile(forPath: filePath)
        }
        
        return nil
    }
    
    private func sendStoreResponse(for storeRQ: CStoreRQ, association: DicomAssociation, status: DIMSEStatus.Status = .Success) {
        // Create and send C-STORE-RSP
        if let storeRSP = PDUEncoder.createDIMSEMessage(
            pduType: .dataTF,
            commandField: .C_STORE_RSP,
            association: association
        ) as? CStoreRSP {
            storeRSP.requestMessage = storeRQ
            storeRSP.dimseStatus = DIMSEStatus(status: status, command: .C_STORE_RSP)
            
            // Send response (fire and forget for now)
            if let channel = association.getChannel() {
                let promise = channel.eventLoop.makePromise(of: Void.self)
                _ = association.write(message: storeRSP, promise: promise)
            }
            
            Logger.info("C-GET: Sent C-STORE-RSP with \(status) status")
        }
    }
}