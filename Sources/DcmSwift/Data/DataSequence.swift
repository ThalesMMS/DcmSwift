//
//  DataSequence.swift
//  DICOM Test
//
//  Created by Rafael Warnault, OPALE on 18/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation


/**
 `DataSequence` is a specific type of `DataElement` with the ability of nesting n `DataItem` objects.
 Each `DataItem` object can have n `DataElement` objects.
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_7.5.html
 */
public class DataSequence: DataElement {
    public var items:[DataItem] = []
    
    override public var description: String {
        var string = super.description + "\n"
        
        for item in self.items {
            string += "  > " + item.description + "\n"
            for se in item.elements {
                string += "    > " + se.description + "\n"
            }
        }
        
        return string
    }
    
    
    
    
    override public func toJSONArray() -> Any {
        var itemsArray:[Any] = []
        
        for item in self.items {
            itemsArray.append(item.toJSONArray())
        }
        
        let json:[String:Any] = [
            "\(self.tagCode().uppercased())":
                [
                    "vr": "\(self.vr)",
                    "value": itemsArray
            ]
        ]
        
        return json
    }
    

    
    public override func toData(vrMethod inVrMethod:VRMethod = .Explicit, byteOrder inByteOrder:ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        // write tag code
        //print("self.tag : (\(self.tag.group),\(self.tag.element))")
        data.append(self.tag.data(withByteOrder: inByteOrder))
                
        // write VR (only explicit)
        if inVrMethod == .Explicit  {
            let vrString = "\(self.vr)"
            let vrData = vrString.data(using: .ascii)
            data.append(vrData!)
                        
            if self.vr == .SQ {
                data.append(byte: 0x00, count: 2)
            }
            else if self.vr == .OB ||
                self.vr == .OW ||
                self.vr == .OF ||
                self.vr == .SQ ||
                self.vr == .UT ||
                self.vr == .UN {
                data.append(byte: 0x00, count: 2)
            }
        }
        
        
        // write length
        if self.vr == .SQ {
            if self.length == -1 {
                data.append(byte: 0xff, count: 4)
            } else {
                var intLength = UInt32(self.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            }
        }
        else if self.vr == .OB ||
            self.vr == .OW ||
            self.vr == .OF ||
            self.vr == .UT ||
            self.vr == .UN {
            if self.length >= 0 {
                let intLength = UInt32(self.length)
                var convertedNumber = inByteOrder == .LittleEndian ?
                    intLength.littleEndian : intLength.bigEndian
                
                let lengthData = Data(bytes: &convertedNumber, count: 4)
                data.append(lengthData)
            }
                // negative length indicate sequence here
            else if self.length == -1 {
                // if OB/OW is a Pixel Sequence
                if let _ = self as? PixelSequence {
                    data.append(byte: 0xff, count: 4)
                }
            }
        }
        else {
            if inVrMethod == .Explicit {
                // we only take care of endianneess with Explicit
                let intLength = UInt16(self.length)
                var convertedNumber = inByteOrder == .LittleEndian ?
                    intLength.littleEndian : intLength.bigEndian
                
                withUnsafePointer(to: &convertedNumber) {
                    data.append(UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: 2)
                }
            }
            else if inVrMethod == .Implicit {
                var intLength = UInt32(self.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            }
        }
        
        
        for item in self.items {
            // write item tag
            data.append(item.tag.data)
            
            // write item length
            if item.length != -1 {
                var intLength = UInt32(item.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            } else {
                data.append(byte: 0xff, count: 4)
            }
            
            // write item sub-elements
            for element in item.elements {
                data.append(element.toData(vrMethod: inVrMethod, byteOrder: inByteOrder))
            }
            
            // write item delimiter
            if item.length == -1 {
                let tag = DataTag(withGroup: "fffe", element: "e00d")
                data.append(tag.data)
                data.append(byte: 0x00, count: 4)
            }
        }
        
        // write sequence delimiter
        if length == -1 {
            let tag = DataTag(withGroup: "fffe", element: "e0dd")
            data.append(tag.data)
            data.append(byte: 0x00, count: 4)
        }
        
        return data
    }
}
