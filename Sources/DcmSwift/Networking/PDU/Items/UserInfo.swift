//
//  UserInfo.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 User Information Item Structure
 
 TODO: rewrite with OffsetInputStream
 
 User Information consists of:
 - item type
 - 1 reserved byte
 - 2 item length
 - user data
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.3.3
 */
public class UserInfo {
    public var implementationUID:String = DicomConstants.implementationUID
    public var implementationVersion:String = DicomConstants.implementationVersion
    public var maxPDULength:Int = 16384
    
    public init(implementationVersion:String = DicomConstants.implementationVersion, implementationUID:String = DicomConstants.implementationUID, maxPDULength:Int = 16384) {
        self.implementationVersion = implementationVersion
        self.implementationUID = implementationUID
        self.maxPDULength = maxPDULength
    }
    
    /**
     - Remark: Why read max pdu length ? it's only a sub field in user info
     */
    public init?(data:Data) {
        let uiItemData = data
        
        var offset = 0
        while offset < uiItemData.count-1 {
            // read type
            let uiItemType = uiItemData.subdata(in: offset..<offset+1).toInt8(byteOrder: .BigEndian)
            let uiItemLength = uiItemData.subdata(in: offset+2..<offset+4).toInt16(byteOrder: .BigEndian)
            offset += 4
            
            if uiItemType == ItemType.maxPduLength.rawValue {
                let maxPDU = uiItemData.subdata(in: offset..<offset+Int(uiItemLength)).toInt32(byteOrder: .BigEndian)
                self.maxPDULength = Int(maxPDU)
                Logger.verbose("    -> Local  Max PDU: \(DicomConstants.maxPDULength)", "UserInfo")
                Logger.verbose("    -> Remote Max PDU: \(self.maxPDULength)", "UserInfo")
            }
            else if uiItemType == ItemType.implClassUID.rawValue {
                let impClasslUID = uiItemData.subdata(in: offset..<offset+Int(uiItemLength)).toString()
                self.implementationUID = impClasslUID
                //Logger.info("    -> Implementation class UID: \(self.association!.remoteImplementationUID ?? "")")
            }
            else if uiItemType == ItemType.implVersionName.rawValue {
                let impVersion = uiItemData.subdata(in: offset..<offset+Int(uiItemLength)).toString()
                self.implementationVersion = impVersion
                //Logger.info("    -> Implementation version: \(self.association!.remoteImplementationVersion ?? "")")
                
            }
            
            offset += Int(uiItemLength)
        }
    }
    
    
    public func data() -> Data {
        var data = Data()
        var itemsData = Data()
        
        // Max PDU length item (required)
        var pduLength = UInt32(self.maxPDULength).bigEndian
        itemsData.append(Data(repeating: ItemType.maxPduLength.rawValue, count: 1)) // 51H
        itemsData.append(Data(repeating: 0x00, count: 1)) // Reserved
        itemsData.append(uint16: UInt16(4), bigEndian: true) // Item length
        itemsData.append(UnsafeBufferPointer(start: &pduLength, count: 1)) // PDU Length value
        
        // Implementation Class UID item (required by many PACS)
        if !implementationUID.isEmpty {
            let uidData = implementationUID.data(using: .ascii) ?? Data()
            itemsData.append(Data(repeating: ItemType.implClassUID.rawValue, count: 1)) // 52H
            itemsData.append(Data(repeating: 0x00, count: 1)) // Reserved
            itemsData.append(uint16: UInt16(uidData.count), bigEndian: true) // Item length
            itemsData.append(uidData) // UID value
        }
        
        // Implementation Version Name item (optional but recommended)
        if !implementationVersion.isEmpty {
            var versionData = implementationVersion.data(using: .ascii) ?? Data()
            // Pad to even length if needed
            if versionData.count % 2 != 0 {
                versionData.append(0x20) // Space padding
            }
            itemsData.append(Data(repeating: ItemType.implVersionName.rawValue, count: 1)) // 55H
            itemsData.append(Data(repeating: 0x00, count: 1)) // Reserved
            itemsData.append(uint16: UInt16(versionData.count), bigEndian: true) // Item length
            itemsData.append(versionData) // Version value
        }
        
        // Build complete User Information item
        data.append(Data(repeating: ItemType.userInfo.rawValue, count: 1)) // 50H
        data.append(Data(repeating: 0x00, count: 1)) // Reserved
        data.append(uint16: UInt16(itemsData.count), bigEndian: true) // Total items length
        data.append(itemsData) // All sub-items
        
        return data
    }
}
