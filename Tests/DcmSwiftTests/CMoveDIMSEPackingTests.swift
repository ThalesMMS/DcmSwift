//   CMoveDIMSEPackingTests.swift
// 
//   DcmSwift
//
//   Created by Thales on 2025/09/11.
// 

import XCTest
import DcmSwift
import NIO

final class CMoveDIMSEPackingTests: XCTestCase {
    func testCMove_CommandDataSetTypeAndPDVPacking() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let calling = DicomEntity(title: "TEST_AE", hostname: "127.0.0.1", port: 4096)
        let called = DicomEntity(title: "REMOTE", hostname: "127.0.0.1", port: 11112)
        let assoc = DicomAssociation(group: group, callingAE: calling, calledAE: called)

        // Presentation Context for Study Root MOVE
        let pcID: UInt8 = 5
        let asuid = DicomConstants.StudyRootQueryRetrieveInformationModelMOVE
        let tsuid = TransferSyntax.explicitVRLittleEndian
        let pc = PresentationContext(abstractSyntax: asuid, transferSyntaxes: [tsuid], contextID: pcID)
        assoc.presentationContexts[pcID] = pc
        assoc.acceptedPresentationContexts[pcID] = pc

        // Minimal MOVE query (Study level)
        let ds = DataSet()
        _ = ds.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = ds.set(value: "1.2.3.4", forTagName: "StudyInstanceUID")

        guard let msg = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: .C_MOVE_RQ, association: assoc) as? CMoveRQ else {
            return XCTFail("Failed to create CMoveRQ")
        }
        msg.queryDataset = ds
        msg.moveDestinationAET = "DEST_AE"
        guard let bytes = msg.data() else { return XCTFail("CMoveRQ.data() returned nil") }
        XCTAssertTrue(msg.messagesData().isEmpty)

        XCTAssertEqual(bytes[0], PDUType.dataTF.rawValue)
        XCTAssertEqual(bytes[1], 0x00)
        let totalLen = bytes.subdata(in: 2..<6).toUInt32(byteOrder: .BigEndian)
        XCTAssertEqual(totalLen, UInt32(bytes.count - 6))

        var offset = 6
        // Command PDV
        let pdv1Len = bytes.subdata(in: offset..<(offset+4)).toUInt32(byteOrder: .BigEndian)
        offset += 4
        let pdv1pc = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        let pdv1hdr = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        XCTAssertEqual(pdv1pc, pcID)
        XCTAssertEqual(pdv1hdr, 0x03)
        let cmdData = bytes.subdata(in: offset..<(offset + Int(pdv1Len - 2)))
        offset += Int(pdv1Len - 2)
        let dis = DicomInputStream(data: cmdData)
        dis.vrMethod = .Implicit
        dis.byteOrder = .LittleEndian
        let cmdDS = try XCTUnwrap(try dis.readDataset(enforceVR: false))
        let dsType = try XCTUnwrap(cmdDS.integer16(forTag: "CommandDataSetType"))
        XCTAssertEqual(dsType, 0x0000)
        XCTAssertEqual(cmdDS.string(forTag: "MoveDestination"), "DEST_AE")

        // Dataset PDV present
        let pdv2Len = bytes.subdata(in: offset..<(offset+4)).toUInt32(byteOrder: .BigEndian)
        offset += 4
        let pdv2pc = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        let pdv2hdr = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        XCTAssertEqual(pdv2pc, pcID)
        XCTAssertEqual(pdv2hdr, 0x02)
        XCTAssertTrue(offset + Int(pdv2Len - 2) <= bytes.count)
    }
}

