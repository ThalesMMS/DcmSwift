#!/usr/bin/env swift

import Foundation
import DcmSwift

// Simple test to verify C-ECHO connectivity with RADIANT PACS

let callingAE = DicomEntity(
    title: "IPHONE",
    hostname: DicomEntity.getLocalIPAddress(),
    port: 4096
)

let calledAE = DicomEntity(
    title: "RADIANT",
    hostname: "192.168.100.92",
    port: 11112
)

print("Testing C-ECHO connection:")
print("  Calling AE: \(callingAE.title) @ \(callingAE.hostname):\(callingAE.port)")
print("  Called AE: \(calledAE.title) @ \(calledAE.hostname):\(calledAE.port)")

do {
    let client = DicomClient(callingAE: callingAE, calledAE: calledAE)
    let success = try client.echo()
    
    if success {
        print("✅ C-ECHO SUCCESS! Connection is working.")
        print("\nNow testing C-FIND with minimal query...")
        
        // Test with minimal C-FIND query
        let queryDataset = DataSet()
        _ = queryDataset.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = queryDataset.set(value: "", forTagName: "StudyInstanceUID")
        
        let results = try client.find(queryDataset: queryDataset, queryLevel: .STUDY)
        print("✅ C-FIND returned \(results.count) results")
        
    } else {
        print("❌ C-ECHO FAILED")
    }
} catch {
    print("❌ Error: \(error)")
}