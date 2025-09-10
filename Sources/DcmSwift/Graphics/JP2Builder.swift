//
//  JP2Builder.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/10.
//
//  Builds a minimal JP2 container around a JPEG 2000 codestream for ImageIO decoding.
//

import Foundation

public enum JP2BuildError: Error { case invalidParams }

public enum JP2Builder {
    /// Build a simple JP2 file in memory with signature, ftyp, jp2h { ihdr, colr }, and jp2c boxes.
    public static func makeJP2(from codestream: Data, info: J2KCodestreamInfo) throws -> Data {
        guard info.components == 1 || info.components == 3 else { throw JP2BuildError.invalidParams }
        var out = Data()

        func appendBox(_ type: String, payload: Data) {
            var box = Data()
            let length = UInt32(payload.count + 8)
            box.append(contentsOf: withUnsafeBytes(of: length.bigEndian, Array.init))
            box.append(type.data(using: .ascii)!)
            box.append(payload)
            out.append(box)
        }

        // Signature box: "jP  \r\n\x87\n"
        out.append([0x00,0x00,0x00,0x0C, 0x6A,0x50,0x20,0x20, 0x0D,0x0A,0x87,0x0A])

        // ftyp ('jp2 ')
        do {
            var p = Data()
            p.append("jp2 ".data(using: .ascii)!)
            p.append(contentsOf: [0x00,0x00,0x00,0x00])
            p.append("jp2 ".data(using: .ascii)!)
            appendBox("ftyp", payload: p)
        }

        // jp2h { ihdr, colr }
        var jp2hPayload = Data()
        // ihdr
        do {
            var ihdr = Data()
            for v in [UInt32(info.height), UInt32(info.width)] {
                ihdr.append(contentsOf: withUnsafeBytes(of: v.bigEndian, Array.init))
            }
            ihdr.append(contentsOf: withUnsafeBytes(of: UInt16(info.components).bigEndian, Array.init))
            let bpc7 = UInt8((info.bitsPerComponent - 1) & 0x7F)
            let signedBit: UInt8 = info.isSigned ? 0x80 : 0x00
            ihdr.append(bpc7 | signedBit) // BPC
            ihdr.append(contentsOf: [0x07, 0x00, 0x00]) // Compression=7(J2K), UnkC=0, IPR=0
            var box = Data()
            let len = UInt32(ihdr.count + 8)
            box.append(contentsOf: withUnsafeBytes(of: len.bigEndian, Array.init))
            box.append("ihdr".data(using: .ascii)!)
            box.append(ihdr)
            jp2hPayload.append(box)
        }
        // colr (Enumerated: 16=sRGB, 17=Grayscale)
        do {
            var colr = Data()
            colr.append(0x01) // METH=1
            colr.append(0x00) // PREC=0
            colr.append(0x00) // APPROX=0
            let enumCS: UInt32 = (info.components == 1) ? 17 : 16
            colr.append(contentsOf: withUnsafeBytes(of: enumCS.bigEndian, Array.init))
            var box = Data()
            let len = UInt32(colr.count + 8)
            box.append(contentsOf: withUnsafeBytes(of: len.bigEndian, Array.init))
            box.append("colr".data(using: .ascii)!)
            box.append(colr)
            jp2hPayload.append(box)
        }
        // wrap jp2h
        do {
            var hdr = Data()
            let len = UInt32(jp2hPayload.count + 8)
            hdr.append(contentsOf: withUnsafeBytes(of: len.bigEndian, Array.init))
            hdr.append("jp2h".data(using: .ascii)!)
            hdr.append(jp2hPayload)
            out.append(hdr)
        }

        // jp2c (raw codestream)
        do {
            var jp2c = Data()
            let len = UInt32(codestream.count + 8)
            jp2c.append(contentsOf: withUnsafeBytes(of: len.bigEndian, Array.init))
            jp2c.append("jp2c".data(using: .ascii)!)
            jp2c.append(codestream)
            out.append(jp2c)
        }

        return out
    }
}

