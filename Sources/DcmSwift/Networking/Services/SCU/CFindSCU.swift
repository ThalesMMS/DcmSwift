//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/07/2021.
//

import Foundation
import NIO

public class CFindSCU: ServiceClassUser {
    var queryDataset:DataSet
    var queryLevel:QueryRetrieveLevel = .STUDY
    var instanceUID:String?
    var resultsDataset:[DataSet] = []
    var lastFindRSP:CFindRSP?
    
    public override var commandField:CommandField {
        .C_FIND_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        switch queryLevel {
        case .PATIENT:
            return [DicomConstants.PatientRootQueryRetrieveInformationModelFIND]
            
        case .STUDY:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelFIND]
            
        case .SERIES:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelFIND]
            
        case .IMAGE:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelFIND]
        }
    }
    
    
    public init(_ queryDataset:DataSet? = nil, queryLevel:QueryRetrieveLevel? = nil, instanceUID:String? = nil) {
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
    
    
    public override func request(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CFindRQ {
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()

            _ = queryDataset.set(value: "\(self.queryLevel)", forTagName: "QueryRetrieveLevel")

            if let uid = instanceUID {
                switch queryLevel {
                case .SERIES:
                    _ = queryDataset.set(value: uid, forTagName: "StudyInstanceUID")
                case .IMAGE:
                    _ = queryDataset.set(value: uid, forTagName: "SeriesInstanceUID")
                default:
                    break
                }
            }
            
            message.queryDataset = queryDataset
            
            // Log query details for debugging
            Logger.info("C-FIND Query Details:")
            Logger.info("  - Query Level: \(self.queryLevel)")
            Logger.info("  - Calling AET: \(association.callingAE)")
            Logger.info("  - Called AET: \(association.calledAE)")
            Logger.info("  - Query Fields:")
            for element in queryDataset.allElements {
                let value = element.value as? String ?? ""
                Logger.info("    - \(element.name): '\(value)'")
            }
            
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
    
    
    public override func receive(association:DicomAssociation, dataTF message:DataTF) -> DIMSEStatus.Status {
        var result:DIMSEStatus.Status = .Pending
        
        Logger.debug("CFindSCU: Received message type: \(Swift.type(of: message))")
        
        if let m = message as? CFindRSP {
            // C-FIND-RSP message (with or without DATA fragment)
            result = message.dimseStatus.status
            
            Logger.info("CFindSCU: Received C-FIND-RSP with status: \(result)")
            
            receiveRSP(m)
            
            return result
        }
        else {
            // single DATA-TF fragment
            Logger.debug("CFindSCU: Received DATA-TF fragment")
            
            if let ats = association.acceptedTransferSyntax,
               let transferSyntax = TransferSyntax(ats) {
                receiveData(message, transferSyntax: transferSyntax)
            }
        }
        
        return result
    }
    
    
    
    // MARK: - Privates
    private func receiveRSP(_ message:CFindRSP) {
        if let dataset = message.resultsDataset {
            resultsDataset.append(dataset)
            Logger.info("CFindSCU: Added result dataset to collection. Total results: \(resultsDataset.count)")
            
            // Log key fields for debugging
            if let patientName = dataset.string(forTag: "PatientName") {
                Logger.debug("CFindSCU: Result - PatientName: \(patientName)")
            }
            if let studyUID = dataset.string(forTag: "StudyInstanceUID") {
                Logger.debug("CFindSCU: Result - StudyInstanceUID: \(studyUID)")
            }
        } else {
            lastFindRSP = message
            Logger.debug("CFindSCU: Received response without dataset (final response)")
        }
    }
    
    
    private func receiveData(_ message:DataTF, transferSyntax:TransferSyntax) {
        Logger.debug("CFindSCU: Processing DATA-TF fragment with \(message.receivedData.count) bytes")
        
        if message.receivedData.count > 0 {
            let dis = DicomInputStream(data: message.receivedData)
            
            dis.vrMethod    = transferSyntax.vrMethod
            dis.byteOrder   = transferSyntax.byteOrder
        
            if let resultDataset = try? dis.readDataset(enforceVR: false) {
                resultsDataset.append(resultDataset)
                Logger.info("CFindSCU: Added dataset from fragment. Total results: \(resultsDataset.count)")
            } else {
                Logger.warning("CFindSCU: Failed to parse dataset from DATA-TF fragment")
            }
        }
    }
}
