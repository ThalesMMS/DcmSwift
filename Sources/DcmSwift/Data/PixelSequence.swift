//
//  PixelData.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation


/**
 A class used to handle multiframe Pixel Sequence
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_A.4.html
 http://dicom.nema.org/medical/Dicom/2018d/output/chtml/part03/sect_C.7.6.3.html
 */
class PixelSequence: DataSequence {
    enum PixelEncoding {
        case Native
        case Encapsulated
    }
    
    /// Returns the raw Basic Offset Table entries as an array of Int (byte offsets), if present.
    /// Offsets are relative to the first byte of the first pixel fragment (after the BOT item).
    func basicOffsetTable() -> [Int]? {
        guard let first = items.first, let data = first.data else { return nil }
        if data.count == 0 { return [] }
        // BOT is a sequence of UInt32 little-endian offsets
        var offsets: [Int] = []
        let count = data.count / 4
        offsets.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt32.self)
            for i in 0..<count { offsets.append(Int(UInt32(littleEndian: ptr[i]))) }
        }
        return offsets
    }

    /// Returns the pixel codestream Data for a given frame index by reassembling fragments.
    /// Strategy:
    /// - If Basic Offset Table (BOT) contains offsets: concatenate all fragments and slice by [offset[i] .. offset[i+1]).
    /// - If BOT empty: assume one fragment per frame (common in practice) and return the fragment at index.
    /// - If no BOT item exists: treat the first item as fragment 0 (rare) and proceed similarly.
    func frameCodestream(at index: Int) throws -> Data {
        enum PXError: Error { case outOfRange, noFragments }
        guard !items.isEmpty else { throw PXError.noFragments }
        let fragments = items.dropFirst() // after BOT
        let bot = basicOffsetTable()

        if let bot = bot, bot.count > 0 {
            // Build a single contiguous buffer of all fragments
            var total = Data()
            total.reserveCapacity(fragments.reduce(0) { $0 + ($1.data?.count ?? 0) })
            for f in fragments { if let d = f.data { total.append(d) } }
            guard index < bot.count else { throw PXError.outOfRange }
            let start = bot[index]
            let end = (index + 1 < bot.count) ? bot[index + 1] : total.count
            if start < 0 || end > total.count || start >= end { throw PXError.outOfRange }
            return total.subdata(in: start..<end)
        } else {
            // No BOT or empty BOT: best-effort — one fragment per frame
            guard index >= 0 && index < fragments.count else { throw PXError.outOfRange }
            if let d = fragments[fragments.index(fragments.startIndex, offsetBy: index)].data {
                return d
            }
            throw PXError.noFragments
        }
    }
    
    /// Returns the exact frame data for a given frame index using BOT (Basic Offset Table) for precise extraction.
    /// This is the preferred method for encapsulated frames as it provides exact byte boundaries.
    /// - Parameter index: Frame index (0-based)
    /// - Returns: Exact frame data bytes
    /// - Throws: PXError if frame index is out of range or no fragments available
    func frameData(at index: Int) throws -> Data {
        return try frameCodestream(at: index)
    }
    
    
    public override func toData(vrMethod inVrMethod:VRMethod = .Explicit, byteOrder inByteOrder:ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        // item data first because we need to know the length
        var itemsData = Data()
        // write items
        for item in self.items {
            // write item tag
            itemsData.append(item.tag.data)
            
            // write item length
            var intLength = UInt32(item.length)
            let lengthData = Data(bytes: &intLength, count: 4)
            itemsData.append(lengthData)
            
            // write item value
            if intLength > 0 {
                //print(item.data)
                itemsData.append(item.data)
            }
//            
//            // write pixel Sequence Delimiter Item
//            let dtag = DataTag(withGroup: "fffe", element: "e00d")
//            itemsData.append(dtag.data)
//            itemsData.append(Data(repeating: 0x00, count: 4))
        }
        
        
        // write tag code
        //print("self.tag : (\(self.tag.group),\(self.tag.element))")
        //data.append(self.tag.data(withByteOrder: inByteOrder))
        data.append(contentsOf: [0xE0, 0x7f, 0x10, 0x00])
        
        // write VR (only explicit)
        if inVrMethod == .Explicit  {
            let vrString = "\(self.vr)"
            let vrData = vrString.data(using: .ascii)
            data.append(vrData!)
            
            data.append(byte: 0x00, count: 2)
            data.append(byte: 0xff, count: 4)
            
//            if self.vr == .SQ {
//                data.append(Data(repeating: 0x00, count: 2))
//            }
//            else if self.vr == .OB ||
//                self.vr == .OW ||
//                self.vr == .OF ||
//                self.vr == .SQ ||
//                self.vr == .UT ||
//                self.vr == .UN {
//                data.append(Data(repeating: 0x00, count: 2))
//            }
        }
        
        
        
        
        // write length (no length for pixel sequence, only 0xffffffff ?
//        // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_A.4.html)
//        let itemsLength = UInt32(itemsData.count + 4)
//        var convertedNumber = inByteOrder == .LittleEndian ?
//            itemsLength.littleEndian : itemsLength.bigEndian
//
//        let lengthData = Data(bytes: &convertedNumber, count: 4)
//        data.append(lengthData)
        //data.append(Data(repeating: 0xff, count: 4))
        
        
        // append items
        data.append(itemsData)
        
        
        // write pixel Sequence Delimiter Item
        tag = DataTag(withGroup: "fffe", element: "e0dd")
        data.append(tag.data)
        data.append(byte: 0x00, count: 4)

        return data
    }
}
