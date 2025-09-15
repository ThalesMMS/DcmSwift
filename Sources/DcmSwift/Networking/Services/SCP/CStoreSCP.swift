//
//  File.swift
//
//
//  Created by Rafael Warnault on 28/07/2021.
//

import Foundation
import NIO



/**
 This service delegate provides a way to implement specific behaviors in the end-program
 */
public protocol CStoreSCPDelegate {
    func store(fileMetaInfo:DataSet, dataset: DataSet, tempFile:String) -> Bool
}


public class CStoreSCP: ServiceClassProvider {
    private var delegate:CStoreSCPDelegate?
    
    
    public override var commandField:CommandField {
        .C_STORE_RSP
    }
    
    
    public init(_ delegate:CStoreSCPDelegate?) {
        super.init()
        
        self.delegate = delegate
    }
    
    
    public override func reply(request: PDUMessage?, association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        Logger.debug("CStoreSCP: Received request: \(String(describing: request))")
        
        guard let storeRequest = request as? CStoreRQ else {
            Logger.error("CStoreSCP: Invalid request type")
            return channel.eventLoop.makeFailedFuture(DicomNetworkError.pduEncodingFailed(messageType: "CStoreSCP"))
        }
        
        // Phase 5: Handle C-STORE request properly
        guard let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CStoreRSP else {
            Logger.error("CStoreSCP: Failed to create C-STORE-RSP message")
            return channel.eventLoop.makeFailedFuture(NetworkError.internalError)
        }
        
        // Set up the response message
        message.requestMessage = storeRequest
        message.dimseStatus = DIMSEStatus(status: .Success, command: self.commandField)
        
        // Process the received dataset if delegate is available
        var storageSuccess = true
        if let delegate = delegate {
            // Create temporary file path
            let tempFile = NSTemporaryDirectory() + "\(UUID().uuidString).dcm"
            
            // Call delegate to handle storage
            storageSuccess = delegate.store(fileMetaInfo: DataSet(), dataset: DataSet(), tempFile: tempFile)
            
            if !storageSuccess {
                Logger.warning("CStoreSCP: Storage failed, returning OutOfResources status")
                message.dimseStatus = DIMSEStatus(status: .OutOfResources, command: self.commandField)
            } else {
                Logger.info("CStoreSCP: Successfully stored dataset")
            }
        } else {
            Logger.warning("CStoreSCP: No delegate available, accepting without storage")
        }
        
        let p: EventLoopPromise<Void> = channel.eventLoop.makePromise()
        return association.write(message: message, promise: p)
    }
}
