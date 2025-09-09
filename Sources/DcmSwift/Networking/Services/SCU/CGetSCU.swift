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
    
    // Incoming C-STORE state
    private var incomingStoreBuffer = Data()
    private var incomingStoreTS: TransferSyntax? = nil
    private var incomingSOPInstanceUID: String? = nil
    private var incomingStoreRequest: CStoreRQ? = nil
    private var savedCount: Int = 0
    
    public override var commandField: CommandField {
        .C_GET_RQ
    }
    
    public override var abstractSyntaxes: [String] {
        // Always include the appropriate GET model, plus all Storage SOP Classes
        // so the peer can send C-STORE sub-operations back on this association.
        let getAS: String = {
            switch queryLevel {
            case .PATIENT: return DicomConstants.PatientRootQueryRetrieveInformationModelGET
            default:       return DicomConstants.StudyRootQueryRetrieveInformationModelGET
            }
        }()
        return [getAS] + DicomConstants.storageSOPClasses
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
            // Post status progress for UI: remaining/completed/failed/warning
            let rem = Int(m.numberOfRemainingSuboperations ?? 0)
            let com = Int(m.numberOfCompletedSuboperations ?? 0)
            let fail = Int(m.numberOfFailedSuboperations ?? 0)
            let warn = Int(m.numberOfWarningSuboperations ?? 0)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("CGetStatus"), object: nil, userInfo: [
                    "remaining": rem,
                    "completed": com,
                    "failed": fail,
                    "warning": warn
                ])
            }
            
            return result
        }
        // Handle C-STORE-RQ messages (actual data transfer)
        else if let storeRQ = message as? CStoreRQ {
            // Handle incoming C-STORE sub-operations. DataTF flags indicate phase.
            let flags = storeRQ.flags ?? 0
            Logger.debug("C-STORE handling: flags=\(String(format: "0x%02X", flags)) ctx=\(storeRQ.contextID ?? 0) data=\(storeRQ.receivedData.count) bytes")
            if flags == 0x03 {
                // Command fragment: initialize state and capture context/UID
                incomingStoreBuffer.removeAll(keepingCapacity: true)
                incomingStoreTS = nil
                incomingSOPInstanceUID = nil
                incomingStoreRequest = storeRQ
                if let ctxID = storeRQ.contextID,
                   let tsUID = association.acceptedPresentationContexts[ctxID]?.transferSyntaxes.first,
                   let ts = TransferSyntax(tsUID) {
                    incomingStoreTS = ts
                }
                // Prefer AffectedSOPInstanceUID from command dataset
                if let cmd = storeRQ.commandDataset {
                    incomingSOPInstanceUID = cmd.string(forTag: "AffectedSOPInstanceUID") ?? cmd.string(forTag: "SOPInstanceUID")
                }
                return .Pending
            } else if flags == 0x00 || flags == 0x02 {
                // Data fragment: append; on last (0x02), assemble and save
                if storeRQ.receivedData.count > 0 { incomingStoreBuffer.append(storeRQ.receivedData) }
                if flags == 0x02 {
                    // Attempt to parse dataset and save as Part-10 with File Meta
                    let netTS = incomingStoreTS ?? TransferSyntax(TransferSyntax.implicitVRLittleEndian)
                    let dis = DicomInputStream(data: incomingStoreBuffer)
                    dis.vrMethod = netTS!.vrMethod
                    dis.byteOrder = netTS!.byteOrder
                    if let dataset = try? dis.readDataset(enforceVR: false) {
                        // Build Part-10 meta header
                        let chosenTS = TransferSyntax(TransferSyntax.explicitVRLittleEndian)!
                        let sopClass = dataset.string(forTag: "SOPClassUID") ?? (incomingStoreRequest?.commandDataset?.string(forTag: "AffectedSOPClassUID") ?? "1.2.840.10008.1.1")
                        let sopInst = dataset.string(forTag: "SOPInstanceUID") ?? (incomingSOPInstanceUID ?? UUID().uuidString)

                        // Minimal meta tags
                        dataset.hasPreamble = true
                        dataset.transferSyntax = chosenTS
                        _ = dataset.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
                        _ = dataset.set(value: sopClass, forTagName: "MediaStorageSOPClassUID")
                        _ = dataset.set(value: sopInst, forTagName: "MediaStorageSOPInstanceUID")
                        _ = dataset.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
                        _ = dataset.set(value: "2.25.123456789012345678901234567890", forTagName: "ImplementationClassUID")
                        _ = dataset.set(value: "DcmSwift", forTagName: "ImplementationVersionName")
                        if let ae = association.callingAE?.title { _ = dataset.set(value: ae, forTagName: "SourceApplicationEntityTitle") }

                        // Compute proper FileMetaInformationGroupLength
                        let metaOnly = DataSet()
                        _ = metaOnly.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
                        _ = metaOnly.set(value: sopClass, forTagName: "MediaStorageSOPClassUID")
                        _ = metaOnly.set(value: sopInst, forTagName: "MediaStorageSOPInstanceUID")
                        _ = metaOnly.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
                        _ = metaOnly.set(value: "2.25.123456789012345678901234567890", forTagName: "ImplementationClassUID")
                        _ = metaOnly.set(value: "DcmSwift", forTagName: "ImplementationVersionName")
                        if let ae = association.callingAE?.title { _ = metaOnly.set(value: ae, forTagName: "SourceApplicationEntityTitle") }
                        let metaData = metaOnly.toData(transferSyntax: chosenTS)
                        _ = dataset.set(value: UInt32(metaData.count), forTagName: "FileMetaInformationGroupLength")

                        // Write Part-10
                        let df = DicomFile()
                        df.dataset = dataset
                        let savedName = sopInst + ".dcm"
                        let outPath = (temporaryStoragePath as NSString).appendingPathComponent(savedName)
                        if df.write(atPath: outPath, vrMethod: .Explicit, byteOrder: .LittleEndian) {
                            Logger.info("C-GET: Saved file to \(outPath)")
                            self.savedCount += 1
                            if let saved = DicomFile(forPath: outPath) { self.receivedFiles.append(saved) }
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: NSNotification.Name("CGetProgress"), object: nil, userInfo: [
                                    "saved": self.savedCount,
                                    "path": outPath,
                                    "sopInstanceUID": sopInst
                                ])
                            }
                            Logger.info("C-GET: Sending C-STORE-RSP Success for \(sopInst)")
                            sendStoreResponse(for: storeRQ, association: association, status: .Success)
                        } else {
                            sendStoreResponse(for: storeRQ, association: association, status: .UnableToProcess)
                        }
                    } else {
                        sendStoreResponse(for: storeRQ, association: association, status: .UnableToProcess)
                    }
                    // reset state per sub‑operation
                    incomingStoreBuffer.removeAll(keepingCapacity: true)
                    incomingStoreTS = nil
                    incomingSOPInstanceUID = nil
                    incomingStoreRequest = nil
                }
                return .Pending
            }
        }
        // Generic DATA-TF fragment belonging to an ongoing C-STORE (no subclass)
        else if message.commandField == nil {
            let flags = message.flags ?? 0
            Logger.debug("DATA-TF (generic) flags=\(String(format: "0x%02X", flags)) len=\(message.receivedData.count)")
            if flags == 0x00 || flags == 0x02, incomingStoreRequest != nil {
                if message.receivedData.count > 0 { incomingStoreBuffer.append(message.receivedData) }
                if flags == 0x02 {
                    let ts = incomingStoreTS ?? TransferSyntax(TransferSyntax.implicitVRLittleEndian)
                    let dis = DicomInputStream(data: incomingStoreBuffer)
                    dis.vrMethod = ts!.vrMethod
                    dis.byteOrder = ts!.byteOrder
                    if let dataset = try? dis.readDataset(enforceVR: false) {
                        // Build Part-10 meta header as above
                        let chosenTS = TransferSyntax(TransferSyntax.explicitVRLittleEndian)!
                        let sopClass = dataset.string(forTag: "SOPClassUID") ?? (incomingStoreRequest?.commandDataset?.string(forTag: "AffectedSOPClassUID") ?? "1.2.840.10008.1.1")
                        let sopInst = dataset.string(forTag: "SOPInstanceUID") ?? (incomingSOPInstanceUID ?? UUID().uuidString)

                        dataset.hasPreamble = true
                        dataset.transferSyntax = chosenTS
                        _ = dataset.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
                        _ = dataset.set(value: sopClass, forTagName: "MediaStorageSOPClassUID")
                        _ = dataset.set(value: sopInst, forTagName: "MediaStorageSOPInstanceUID")
                        _ = dataset.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
                        _ = dataset.set(value: "2.25.123456789012345678901234567890", forTagName: "ImplementationClassUID")
                        _ = dataset.set(value: "DcmSwift", forTagName: "ImplementationVersionName")
                        if let ae = association.callingAE?.title { _ = dataset.set(value: ae, forTagName: "SourceApplicationEntityTitle") }

                        let metaOnly = DataSet()
                        _ = metaOnly.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
                        _ = metaOnly.set(value: sopClass, forTagName: "MediaStorageSOPClassUID")
                        _ = metaOnly.set(value: sopInst, forTagName: "MediaStorageSOPInstanceUID")
                        _ = metaOnly.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
                        _ = metaOnly.set(value: "2.25.123456789012345678901234567890", forTagName: "ImplementationClassUID")
                        _ = metaOnly.set(value: "DcmSwift", forTagName: "ImplementationVersionName")
                        if let ae = association.callingAE?.title { _ = metaOnly.set(value: ae, forTagName: "SourceApplicationEntityTitle") }
                        let metaData = metaOnly.toData(transferSyntax: chosenTS)
                        _ = dataset.set(value: UInt32(metaData.count), forTagName: "FileMetaInformationGroupLength")

                        let df = DicomFile()
                        df.dataset = dataset
                        let savedName = sopInst + ".dcm"
                        let outPath = (temporaryStoragePath as NSString).appendingPathComponent(savedName)
                        if df.write(atPath: outPath, vrMethod: .Explicit, byteOrder: .LittleEndian) {
                            Logger.info("C-GET: Saved file to \(outPath)")
                            self.savedCount += 1
                            if let saved = DicomFile(forPath: outPath) { self.receivedFiles.append(saved) }
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: NSNotification.Name("CGetProgress"), object: nil, userInfo: [
                                    "saved": self.savedCount,
                                    "path": outPath,
                                    "sopInstanceUID": sopInst
                                ])
                            }
                            if let req = incomingStoreRequest {
                                Logger.info("C-GET: Sending C-STORE-RSP Success for \(sopInst)")
                                sendStoreResponse(for: req, association: association, status: .Success)
                            }
                        } else {
                            if let req = incomingStoreRequest { sendStoreResponse(for: req, association: association, status: .UnableToProcess) }
                        }
                    } else {
                        if let req = incomingStoreRequest { sendStoreResponse(for: req, association: association, status: .UnableToProcess) }
                    }
                    // reset state per sub‑operation
                    incomingStoreBuffer.removeAll(keepingCapacity: true)
                    incomingStoreTS = nil
                    incomingSOPInstanceUID = nil
                    incomingStoreRequest = nil
                }
                return .Pending
            }
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
