//
//  CMoveSCU.swift
//  DcmSwift
//
//  Created by Thales on 2025/01/05.
//

import Foundation
import NIO

/**
 C-MOVE Service Class User implementation.
 
 This class handles C-MOVE operations which instruct a remote DICOM node
 to send DICOM objects to a specified destination AE. The actual data
 transfer happens through a separate C-STORE association initiated by
 the remote node to the destination.
 */
public class CMoveSCU: ServiceClassUser {
    /// Query dataset containing the UIDs to move
    var queryDataset: DataSet
    /// Query/Retrieve level (PATIENT, STUDY, SERIES, IMAGE)
    var queryLevel: QueryRetrieveLevel = .STUDY
    /// Instance UID for specific level queries
    var instanceUID: String?
    /// Destination AE title for the move operation
    public var moveDestinationAET: String
    /// Last C-MOVE-RSP message received
    var lastMoveRSP: CMoveRSP?
    
    public override var commandField: CommandField {
        .C_MOVE_RQ
    }
    
    public override var abstractSyntaxes: [String] {
        switch queryLevel {
        case .PATIENT:
            return [DicomConstants.PatientRootQueryRetrieveInformationModelMOVE]
            
        case .STUDY:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelMOVE]
            
        case .SERIES:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelMOVE]
            
        case .IMAGE:
            return [DicomConstants.StudyRootQueryRetrieveInformationModelMOVE]
        }
    }
    
    public init(_ queryDataset: DataSet? = nil, 
                queryLevel: QueryRetrieveLevel? = nil,
                instanceUID: String? = nil,
                moveDestinationAET: String) {
        
        self.moveDestinationAET = moveDestinationAET
        
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
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CMoveRQ {
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
            message.moveDestinationAET = moveDestinationAET
            
            Logger.info("C-MOVE-RQ: Moving to destination AET: \(moveDestinationAET)")
            
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
    
    public override func receive(association: DicomAssociation, dataTF message: DataTF) -> DIMSEStatus.Status {
        var result: DIMSEStatus.Status = .Pending
        
        // Handle C-MOVE-RSP messages
        if let m = message as? CMoveRSP {
            result = m.dimseStatus.status
            lastMoveRSP = m
            
            Logger.info("C-MOVE-RSP: \(m.messageInfos())")
            
            // Log progress if available
            if let remaining = m.numberOfRemainingSuboperations {
                Logger.info("C-MOVE Progress - Remaining: \(remaining)")
                
                if let completed = m.numberOfCompletedSuboperations {
                    Logger.info("  Completed: \(completed)")
                }
                if let failed = m.numberOfFailedSuboperations, failed > 0 {
                    Logger.warning("  Failed: \(failed)")
                }
                if let warning = m.numberOfWarningSuboperations, warning > 0 {
                    Logger.warning("  Warning: \(warning)")
                }
            }
            
            return result
        }
        
        // C-MOVE should not receive other message types on this association
        Logger.warning("C-MOVE-SCU: Unexpected message type received: \(message.messageName())")
        
        return result
    }
    
    // MARK: - Public Methods
    
    /**
     Check if the move operation completed successfully
     */
    public var isSuccessful: Bool {
        guard let lastRSP = lastMoveRSP else { return false }
        
        // Check if status is Success and no failed operations
        return lastRSP.dimseStatus.status == .Success &&
               (lastRSP.numberOfFailedSuboperations ?? 0) == 0
    }
    
    /**
     Get the number of successfully moved instances
     */
    public var completedCount: Int {
        return Int(lastMoveRSP?.numberOfCompletedSuboperations ?? 0)
    }
    
    /**
     Get the number of failed move operations
     */
    public var failedCount: Int {
        return Int(lastMoveRSP?.numberOfFailedSuboperations ?? 0)
    }
}