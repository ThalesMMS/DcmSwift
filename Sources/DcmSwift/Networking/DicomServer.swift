//
//  DicomServer.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO
import NIOSSL
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

/// TLS server options for DICOM listener
public struct TLSServerOptions {
    public var enabled: Bool
    public var certificatePath: String?
    public var privateKeyPath: String?
    public var passphrase: String?

    public init(enabled: Bool = false, certificatePath: String? = nil, privateKeyPath: String? = nil, passphrase: String? = nil) {
        self.enabled = enabled
        self.certificatePath = certificatePath
        self.privateKeyPath = privateKeyPath
        self.passphrase = passphrase
    }
}

public class DicomServer: CEchoSCPDelegate, CFindSCPDelegate, CStoreSCPDelegate {
    var calledAE:DicomEntity!
    var port: Int = 4096
    
    var config:ServerConfig
    
    var channel: Channel!
    var group:MultiThreadedEventLoopGroup!
    var bootstrap:ServerBootstrap!
    var tlsOptions: TLSServerOptions? = nil
    var tlsContext: NIOSSLContext? = nil
    
    /// Optional custom delegate for C-STORE operations
    public var storeSCPDelegate: ((DataSet) -> DIMSEStatus.Status)?

    
    
    public convenience init(port: Int, localAET: String) {
        let defaultConfig = ServerConfig(enableCEchoSCP: true, enableCFindSCP: false, enableCStoreSCP: true)
        self.init(port: port, localAET: localAET, config: defaultConfig)
    }
    
    public init(port: Int, localAET:String, config:ServerConfig, tls: TLSServerOptions? = nil) {
        self.calledAE   = DicomEntity(title: localAET, hostname: DicomEntity.getLocalIPAddress(), port: port)
        self.port       = port
        self.config     = config
        self.tlsOptions = tls
        
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // Optionally add TLS handler first in the pipeline
                if let tlsCtx = self.tlsContext {
                    do {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: tlsCtx))
                    } catch {
                        Logger.error("Failed to add TLS handler: \(error)")
                    }
                }
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
                
                return channel.pipeline.addHandlers([ByteToMessageHandler(PDUBytesDecoder()), assoc])
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        // Prepare TLS context if requested and configured
        if let tls = tls, tls.enabled {
            if let certPath = tls.certificatePath, let keyPath = tls.privateKeyPath {
                do {
                    let certs = try NIOSSLCertificate.fromPEMFile(certPath)
                    let key = try NIOSSLPrivateKey(file: keyPath, format: .pem)
                    var tcfg = TLSConfiguration.makeServerConfiguration(
                        certificateChain: certs.map { .certificate($0) },
                        privateKey: .privateKey(key)
                    )
                    // Reasonable defaults per BCP 195 (NIO defaults are fine for now)
                    tcfg.minimumTLSVersion = .tlsv12
                    self.tlsContext = try NIOSSLContext(configuration: tcfg)
                    Logger.info("TLS context initialized for DICOM Server")
                } catch {
                    Logger.error("Failed to initialize TLS: \(error). Server will run without TLS.")
                    self.tlsContext = nil
                }
            } else {
                Logger.warning("TLS enabled but certificate or key path not provided. Server will run without TLS.")
            }
        }
    }
    
    
    deinit {
//        channel.close(mode: .all, promise: nil)
//
//        try? group.syncShutdownGracefully()
    }
    
    /**
     Starts the server
     */
    public func start(completion: (() -> Void)? = nil) throws {
        channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
        
        Logger.info("Server listening on port \(port)...")
        
        completion?()
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
