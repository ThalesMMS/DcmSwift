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
    /// Pending C-STORE data
    private var pendingStoreData = Data()
    
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
            let sopInstanceUID = storeRQ.dicomFile?.dataset.string(forTag: "SOPInstanceUID") ?? "unknown"
            Logger.info("C-GET: Receiving C-STORE-RQ for \(sopInstanceUID)")
            
            // Process the incoming image data
            if let imageData = processStoreRequest(storeRQ, association: association) {
                // Save the file
                let sopInstanceUID = storeRQ.dicomFile?.dataset.string(forTag: "SOPInstanceUID")
                if let file = saveReceivedData(imageData, sopInstanceUID: sopInstanceUID) {
                    receivedFiles.append(file)
                    
                    // Send C-STORE-RSP back
                    sendStoreResponse(for: storeRQ, association: association)
                }
            }
            
            return .Pending // Continue waiting for more data or final C-GET-RSP
        }
        // Handle fragmented DATA-TF messages
        else {
            if let ats = association.acceptedTransferSyntax,
               let transferSyntax = TransferSyntax(ats) {
                receiveData(message, transferSyntax: transferSyntax)
            }
        }
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func processStoreRequest(_ storeRQ: CStoreRQ, association: DicomAssociation) -> Data? {
        // Check if we have a complete dataset
        if let dataset = storeRQ.dicomFile?.dataset {
            // Create a DicomFile from the dataset
            let dicomFile = DicomFile()
            dicomFile.dataset = dataset
            
            // Write to temporary file and read back as data
            let tempPath = NSTemporaryDirectory() + UUID().uuidString + ".dcm"
            if dicomFile.write(atPath: tempPath) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)) {
                    // Clean up temp file
                    try? FileManager.default.removeItem(atPath: tempPath)
                    return data
                }
            }
        } else if storeRQ.receivedData.count > 0 {
            // Handle fragmented data
            pendingStoreData.append(storeRQ.receivedData)
            
            // Check if this is the last fragment (flags indicate completion)
            if storeRQ.commandDataSetType == nil || storeRQ.commandDataSetType == 0x0101 {
                let completeData = pendingStoreData
                pendingStoreData = Data() // Reset for next file
                return completeData
            }
        }
        
        return nil
    }
    
    private func saveReceivedData(_ data: Data, sopInstanceUID: String?) -> DicomFile? {
        let fileName = sopInstanceUID ?? UUID().uuidString
        let filePath = (temporaryStoragePath as NSString).appendingPathComponent("\(fileName).dcm")
        
        do {
            try data.write(to: URL(fileURLWithPath: filePath))
            
            // Create DicomFile object for the saved file
            if let file = DicomFile(forPath: filePath) {
                Logger.info("C-GET: Saved file to \(filePath)")
                return file
            }
        } catch {
            Logger.error("C-GET: Failed to save file: \(error)")
        }
        
        return nil
    }
    
    private func sendStoreResponse(for storeRQ: CStoreRQ, association: DicomAssociation) {
        // Create and send C-STORE-RSP
        if let storeRSP = PDUEncoder.createDIMSEMessage(
            pduType: .dataTF,
            commandField: .C_STORE_RSP,
            association: association
        ) as? CStoreRSP {
            storeRSP.requestMessage = storeRQ
            storeRSP.dimseStatus = DIMSEStatus(status: .Success, command: .C_STORE_RSP)
            
            // Send response (fire and forget for now)
            // Create a promise for the write operation
            if let channel = association.getChannel() {
                let promise = channel.eventLoop.makePromise(of: Void.self)
                _ = association.write(message: storeRSP, promise: promise)
            }
            
            Logger.info("C-GET: Sent C-STORE-RSP with Success status")
        }
    }
    
    private func receiveData(_ message: DataTF, transferSyntax: TransferSyntax) {
        if message.receivedData.count > 0 {
            // Accumulate fragmented data
            pendingStoreData.append(message.receivedData)
        }
    }
}