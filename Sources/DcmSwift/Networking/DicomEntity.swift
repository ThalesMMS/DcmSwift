//
//  DicomEntity.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 20/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
#if canImport(Network)
import Network
#endif

/**
 A DicomEntity represents a Dicom Applicatin Entity (AE).
 It is composed of a title, a hostname and a port and
 */
public class DicomEntity : Codable, CustomStringConvertible {
    /**
     A string description of the DICOM object
     */
    public var description: String { return self.fullname() }
    
    public var title:String
    public var hostname:String
    public var port:Int
    
    public init(title:String, hostname:String, port:Int) {
        self.title      = title
        self.hostname   = hostname
        self.port       = port
    }
    
    public func paddedTitleData() -> Data? {
        var data = self.title.data(using: .utf8)
        
        if data!.count < 16 {
            // AE titles must be padded with SPACE (0x20), not NULL (0x00)
            data!.append(Data(repeating: 0x20, count: 16-data!.count))
        }
        
        return data
    }
    
    public func fullname() -> String {
        return "\(self.title)@\(self.hostname):\(self.port)"
    }
    
    /// Get the local IP address of the machine on the WiFi/Ethernet network
    public static func getLocalIPAddress() -> String {
        var address = "127.0.0.1"
        
        // Get list of all interfaces on the local machine
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }
        
        // For each interface
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            // Check for IPv4 interface
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                
                // Check interface name (en0 is typically WiFi on macOS/iOS)
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" || name.starts(with: "eth") {
                    
                    // Convert interface address to a human readable string
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    
                    let foundAddress = String(cString: hostname)
                    if !foundAddress.starts(with: "127.") && !foundAddress.starts(with: "169.254.") {
                        address = foundAddress
                        break
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        
        return address
    }
}
