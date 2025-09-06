//
//  DicomServer.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO
import Dispatch


public struct ServerConfig {
    public var enableCEchoSCP:Bool?     = true
    public var enableCFindSCP:Bool?     = true
    public var enableCStoreSCP:Bool?    = true
    
    public init(enableCEchoSCP:Bool, enableCFindSCP:Bool, enableCStoreSCP:Bool) {
        self.enableCEchoSCP     = enableCEchoSCP
        self.enableCFindSCP     = enableCFindSCP
        self.enableCStoreSCP    = enableCStoreSCP
    }
}

public class DicomServer: CEchoSCPDelegate, CFindSCPDelegate, CStoreSCPDelegate {
    var calledAE:DicomEntity!
    var port: Int = 11112
    
    var config:ServerConfig
    
    var channel: Channel!
    var group:MultiThreadedEventLoopGroup!
    var bootstrap:ServerBootstrap!
    
    /// Optional custom delegate for C-STORE operations
    public var storeSCPDelegate: ((DataSet) -> DIMSEStatus.Status)?

    
    
    public convenience init(port: Int, localAET: String) {
        let defaultConfig = ServerConfig(enableCEchoSCP: true, enableCFindSCP: false, enableCStoreSCP: true)
        self.init(port: port, localAET: localAET, config: defaultConfig)
    }
    
    public init(port: Int, localAET:String, config:ServerConfig) {
        self.calledAE   = DicomEntity(title: localAET, hostname: "localhost", port: port)
        self.port       = port
        self.config     = config
        
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // we create a new DicomAssociation for each new activating channel
                let assoc = DicomAssociation(group: self.group, calledAE: self.calledAE)
                
                // this assoc implements to the following SCPs:
                // C-ECHO-SCP
                if config.enableCEchoSCP ?? false {
                    assoc.addServiceClassProvider(CEchoSCP(self))
                }
                // C-FIND-SCP
                if config.enableCEchoSCP ?? false {
                    assoc.addServiceClassProvider(CFindSCP(self))
                }
                // C-STORE-SCP
                if config.enableCEchoSCP ?? false {
                    assoc.addServiceClassProvider(CStoreSCP(self))
                }
                
                return channel.pipeline.addHandlers([ByteToMessageHandler(PDUBytesDecoder(withAssociation: assoc)), assoc])
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }
    
    
    deinit {
//        channel.close(mode: .all, promise: nil)
//
//        try? group.syncShutdownGracefully()
    }
    
    /**
     Starts the server
     */
    public func start() throws {
        channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
        
        Logger.info("Server listening on port \(port)...")
        
        // Don't wait here, let the server run in background
        // try channel.closeFuture.wait()
    }
    
    /**
     Stops the server
     */
    public func stop() {
        if let channel = channel {
            channel.close(mode: .all, promise: nil)
        }
        
        try? group.syncShutdownGracefully()
    }
    
    
    
    // MARK: - CEchoSCPDelegate
    /// - Returns: returns success
    public func validateEcho(callingAE: DicomEntity) -> DIMSEStatus.Status {
        return .Success
    }
    
    
    
    // MARK: - CFindSCPDelegate
    /// - Returns: returns an empty array
    public func query(level: QueryRetrieveLevel, dataset: DataSet) -> [DataSet] {
        print("query \(level) \(dataset)")
        return []
    }
    
    
    // MARK: - CStoreSCPDelegate
    /// - Returns: `true` if storage succeeded, `false` otherwise
    public func store(fileMetaInfo:DataSet, dataset: DataSet, tempFile:String) -> Bool {
        // Use custom delegate if available
        if let delegate = storeSCPDelegate {
            let status = delegate(dataset)
            return status == .Success
        }
        
        // Default implementation: save to temp file
        if let sopInstanceUID = dataset.string(forTag: "SOPInstanceUID") {
            let outputPath = "/tmp/\(sopInstanceUID).dcm"
            
            // Create a complete DICOM file
            let dicomFile = DicomFile()
            dicomFile.dataset = dataset
            
            // Write to file
            if dicomFile.write(atPath: outputPath) {
                Logger.info("Stored file to: \(outputPath)")
                return true
            } else {
                Logger.error("Failed to store file to: \(outputPath)")
            }
        }
        
        return false
    }
}
