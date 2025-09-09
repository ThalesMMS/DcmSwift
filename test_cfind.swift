#!/usr/bin/env swift

import Foundation

// Simple script to test C-FIND with RADIANT PACS

let callingAET = "IPHONE"
let calledAET = "RADIANT"
let hostname = "127.0.0.1"
let port = 11112

print("Testing C-FIND connection to \(calledAET)@\(hostname):\(port)")
print("Using calling AET: \(callingAET)")

// Build C-FIND command - directly use DcmFind tool
let process = Process()
process.executableURL = URL(fileURLWithPath: ".build/debug/DcmFind")
process.arguments = ["--calling-aet", callingAET, calledAET, hostname, String(port)]

let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe

do {
    try process.run()
    process.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    print("\nOutput:")
    print(output)
    
    if process.terminationStatus == 0 {
        print("\n✅ C-FIND test PASSED!")
    } else {
        print("\n❌ C-FIND test FAILED with status: \(process.terminationStatus)")
    }
} catch {
    print("❌ Failed to run test: \(error)")
}