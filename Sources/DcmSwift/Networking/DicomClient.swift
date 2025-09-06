//
//  DicomClient.swift
//  
//
//  Created by Rafael Warnault, OPALE on 20/07/2021.
//

import Foundation
import NIO


/**
 A client with implementation of the basic DICOM services.
 
 This class provides its own `MultiThreadedEventLoopGroup` based on `System.coreCount`
 number of threads, but can also be instanciated with your own NIO event loop if you need.
 
 Example of use:
 
     // create a DICOM client
     let client = DicomClient(
         callingAE: callingAE,
         calledAE: calledAE)
     
     // run C-ECHO SCU service
     do {
         if try client.echo() {
             print("C-ECHO \(calledAE) SUCCEEDED")
         } else {
             print("C-ECHO \(callingAE) FAILED")
         }
     } catch let e {
         Logger.error(e.localizedDescription)
     }
 
 */
public class DicomClient {
    /**
     The NIO event loop used by the client
     */
    private var eventLoopGroup:MultiThreadedEventLoopGroup
    
    /**
     The self AE, aka calling AE, which represent the local AE requesting the remote AE
     */
    private var callingAE:DicomEntity
    
    /**
     The called AE represents the remote AE requested by the local AE
     */
    private var calledAE:DicomEntity
    

    /**
     Init a client with a self AET, regarless to the hostname and port (they are unused for the `callingAE`)
     The NIO event loop will be created automatically
     
     - Parameter aet: yourself Application Entity Title
     - Parameter calledAE: the remote `DicomEntity`to request
     
     */
    public init(aet: String, calledAE:DicomEntity) {
        self.calledAE       = calledAE
        self.callingAE      = DicomEntity(title: aet, hostname: "localhost", port: 11112)
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    /**
     Init a client with `callingAE` and `calledAE` objects
     The NIO event loop will be created automatically
     
     - Parameter callingAE: yourself `DicomEntity`
     - Parameter calledAE: the remote `DicomEntity`to request
     
     */
    public init(callingAE: DicomEntity, calledAE:DicomEntity) {
        self.calledAE       = calledAE
        self.callingAE      = callingAE
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    
    /**
     Init a client with your own NIO event loop
     
     - Parameter callingAE: yourself `DicomEntity`
     - Parameter calledAE: the remote `DicomEntity`to request
     - Parameter eventLoopGroup: your own NIO event loop
     */
    public init(callingAE: DicomEntity, calledAE:DicomEntity, eventLoopGroup:MultiThreadedEventLoopGroup? = nil) {
        self.calledAE   = calledAE
        self.callingAE  = callingAE
        
        if let elg = eventLoopGroup {
            self.eventLoopGroup = elg
        } else {
            self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        }
    }
    
    
    /**
     Perform a C-ECHO request to the `calledAE`
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: `true` if the C-ECHO-RSP DIMSE Status is `Success`
     
     Example of use:
     
         // create a DICOM client
         let client = DicomClient(
             callingAE: callingAE,
             calledAE: calledAE)
         
         // run C-ECHO SCU service
         do {
             if try client.echo() {
                 print("C-ECHO \(calledAE) SUCCEEDED")
             } else {
                 print("C-ECHO \(callingAE) FAILED")
             }
         } catch let e {
             Logger.error(e.localizedDescription)
         }
     
     */
    public func echo() throws -> Bool {
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        
        assoc.setServiceClassUser(CEchoSCU())
        
        return try assoc.start()
    }
    
    
    /**
     Perform a C-FIND request to the `calledAE`
          
     - Parameter queryDataset: Your query dataset, primarilly used by the C-FIND SCP to determine
     what attributes you want to get as result, and also to set filters to precise your search. If no query dataset
     is given, the `CFindSCUService` will provide you some default attributes (see `CFindSCUService.init()`)
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: a dataset array if the C-FIND-RSP DIMSE Status is `Success`. If the returned array is empty,
     the C-FIND SCP probably has no result for the given query.
     
     Example of use:
     
            // create a dataset
            let queryDataset = DataSet()
     
            queryDataset.set(value:"", forTagName: "PatientID")
            queryDataset.set(value:"", forTagName: "PatientName")
            queryDataset.set(value:"", forTagName: "PatientBirthDate")
            queryDataset.set(value:"", forTagName: "StudyDescription")
            queryDataset.set(value:"", forTagName: "StudyDate")
            queryDataset.set(value:"", forTagName: "StudyTime")
            queryDataset.set(value:"MR", forTagName: "ModalitiesInStudy") // only MR modality studies
            queryDataset.set(value:"", forTagName: "AccessionNumber")

             // create a DICOM client
             let client = DicomClient(
                 callingAE: callingAE,
                 calledAE: calledAE)
             
             // run C-FIND SCU service
             print(try? client.find())
     
     */
    public func find(queryDataset:DataSet? = nil, queryLevel:QueryRetrieveLevel = .STUDY, instanceUID:String? = nil) throws -> [DataSet] {
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        let service = CFindSCU(queryDataset, queryLevel: queryLevel)
        var result = false
        
        assoc.setServiceClassUser(service)
        
        result = try assoc.start()

        if !result {
            return []
        }
        
        return service.resultsDataset
    }
    
    /**
     Perform a C-STORE request to the `calledAE`
          
     - Parameter filePaths: an array of absolute path of DICOM files
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: `true` if the C-STORE-RSP DIMSE Status is `Success`
     
     Example of use:
     
         let client = DicomClient(
             callingAE: callingAE,
             calledAE:  calledAE)
         
         // run C-STORE SCU service to send files
         try? client.store(filePaths: flattenPaths(filePaths))
     
     */
    public func store(filePaths:[String]) throws -> Bool {
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        
        assoc.setServiceClassUser(CStoreSCU(filePaths))

        return try assoc.start()
    }
    
    
    /**
     Perform a C-MOVE request to the `calledAE`
     
     This operation instructs the remote DICOM node to send the specified objects
     to a destination AE. The actual data transfer happens through a separate
     C-STORE association initiated by the remote node.
     
     - Parameter queryDataset: Optional query dataset for filtering
     - Parameter queryLevel: The query/retrieve level (STUDY, SERIES, IMAGE)
     - Parameter instanceUID: Optional specific instance UID
     - Parameter destinationAET: The destination AE title where files should be sent
     - Parameter startTemporaryServer: If true, starts a temporary C-STORE SCP server to receive files
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: A tuple containing success status and optionally received files if a temporary server was used
     
     Example of use:
     
         let client = DicomClient(
             callingAE: callingAE,
             calledAE: calledAE)
         
         // Move studies to another AE
         let result = try client.move(
             instanceUID: studyUID,
             queryLevel: .STUDY,
             destinationAET: "DESTINATION_AE"
         )
     
     */
    public func move(queryDataset: DataSet? = nil,
                    queryLevel: QueryRetrieveLevel = .STUDY,
                    instanceUID: String? = nil,
                    destinationAET: String,
                    startTemporaryServer: Bool = false) throws -> (success: Bool, files: [DicomFile]?) {
        
        var receivedFiles: [DicomFile] = []
        var server: DicomServer?
        
        // If requested, start a temporary C-STORE SCP server
        if startTemporaryServer {
            // Create temporary server with the destination AET
            let serverEntity = DicomEntity(
                title: destinationAET,
                hostname: "0.0.0.0",
                port: 11113  // Use a different port than default
            )
            
            server = DicomServer(port: 11113, localAET: destinationAET)
            
            // Set up the server to collect received files
            server?.storeSCPDelegate = { dataset in
                let tempFile = DicomFile()
                tempFile.dataset = dataset
                receivedFiles.append(tempFile)
                return .Success
            }
            
            // Start server in background
            DispatchQueue.global(qos: .background).async {
                do {
                    try server?.start()
                } catch {
                    Logger.error("Failed to start temporary C-STORE server: \(error)")
                }
            }
            
            // Give the server time to start
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Create and configure the C-MOVE association
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        let service = CMoveSCU(
            queryDataset,
            queryLevel: queryLevel,
            instanceUID: instanceUID,
            moveDestinationAET: destinationAET
        )
        
        assoc.setServiceClassUser(service)
        
        let result = try assoc.start()
        
        // Stop the temporary server if it was started
        if let server = server {
            Thread.sleep(forTimeInterval: 1.0) // Give time for last transfers
            server.stop()
        }
        
        if startTemporaryServer {
            return (result && service.isSuccessful, receivedFiles)
        } else {
            return (result && service.isSuccessful, nil)
        }
    }
    
    /**
     Perform a C-GET request to the `calledAE`
     
     This operation retrieves DICOM objects directly through the same association
     used for the request. The remote node sends the data through C-STORE
     sub-operations on the same connection.
     
     - Parameter queryDataset: Optional query dataset for filtering
     - Parameter queryLevel: The query/retrieve level (STUDY, SERIES, IMAGE)
     - Parameter instanceUID: Optional specific instance UID
     - Parameter temporaryStoragePath: Path where received files will be temporarily stored
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: Array of received DicomFile objects
     
     Example of use:
     
         let client = DicomClient(
             callingAE: callingAE,
             calledAE: calledAE)
         
         // Get studies directly
         let files = try client.get(
             instanceUID: studyUID,
             queryLevel: .STUDY
         )
         
         print("Received \(files.count) files")
     
     */
    public func get(queryDataset: DataSet? = nil,
                   queryLevel: QueryRetrieveLevel = .STUDY,
                   instanceUID: String? = nil,
                   temporaryStoragePath: String = NSTemporaryDirectory()) throws -> [DicomFile] {
        
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        let service = CGetSCU(
            queryDataset,
            queryLevel: queryLevel,
            instanceUID: instanceUID
        )
        
        service.temporaryStoragePath = temporaryStoragePath
        
        assoc.setServiceClassUser(service)
        
        let result = try assoc.start()
        
        if !result {
            return []
        }
        
        return service.receivedFiles
    }
}
