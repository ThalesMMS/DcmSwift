//   DataTFStatusTests.swift
// 
//   DcmSwift
//
//   Created by Thales on 2025/09/10.
// 

import XCTest
import DcmSwift

final class DataTFStatusTests: XCTestCase {
    func testDataOnlyPDVDoesNotSetSuccess() {
        // Build a minimal DATA-TF with one PDV (data only, last fragment)
        // PDU: [04, 00, length(4), PDV_length(4), pcid(1), flags(1)=0x02, payload(2 bytes)]
        var payload = Data()
        payload.append(uint32: 4, bigEndian: true) // PDV length = 4 (pcid+flags+2 bytes data)
        payload.append(uint8: 1, bigEndian: true)   // pc id
        payload.append(byte: 0x02)                 // flags: data + last
        payload.append(uint16: 0x1234, bigEndian: false)

        var pdu = Data()
        pdu.append(uint8: PDUType.dataTF.rawValue, bigEndian: true)
        pdu.append(byte: 0x00)
        pdu.append(uint32: UInt32(payload.count), bigEndian: true)
        pdu.append(payload)

        // Decode via a DataTF instance
        let assoc = DicomAssociation(group: MultiThreadedEventLoopGroup(numberOfThreads: 1),
                                     callingAE: DicomEntity(title: "A", hostname: "h", port: 1),
                                     calledAE: DicomEntity(title: "B", hostname: "h", port: 1))
        let msg = DataTF(pduType: .dataTF, commandField: .NONE, association: assoc)
        let status = msg.decodeData(data: pdu)

        // Should be Pending, not Success
        XCTAssertEqual(status, .Pending)
    }
}

