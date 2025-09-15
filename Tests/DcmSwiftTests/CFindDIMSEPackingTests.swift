//   CFindDIMSEPackingTests.swift
// 
//   DcmSwift
//
//   Created by Thales on 2025/09/10.
// 

import XCTest
import DcmSwift
import NIO

final class CFindDIMSEPackingTests: XCTestCase {
    func testCFind_CommandDataSetTypeAndPDVPacking() throws {
        // Setup minimal association with accepted Study Root FIND PC
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let calling = DicomEntity(title: "IPHONE", hostname: "127.0.0.1", port: 4096)
        let called = DicomEntity(title: "RADIANT", hostname: "127.0.0.1", port: 11112)
        let assoc = DicomAssociation(group: group, callingAE: calling, calledAE: called)

        // Presentation Context for Study Root Query/Retrieve Information Model - FIND
        let pcID: UInt8 = 4
        let asuid = DicomConstants.StudyRootQueryRetrieveInformationModelFIND
        let tsuid = TransferSyntax.explicitVRLittleEndian
        let pc = PresentationContext(abstractSyntax: asuid, transferSyntaxes: [tsuid], contextID: pcID)
        assoc.presentationContexts[pcID] = pc
        assoc.acceptedPresentationContexts[pcID] = pc

        // Build a minimal query dataset
        let qr = DataSet()
        _ = qr.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = qr.set(value: "DX", forTagName: "ModalitiesInStudy")

        // Build C-FIND-RQ via encoder
        guard let msg = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: .C_FIND_RQ, association: assoc) as? CFindRQ else {
            return XCTFail("Failed to create CFindRQ")
        }
        msg.queryDataset = qr

        // Generate bytes
        guard let bytes = msg.data() else {
            return XCTFail("CFindRQ.data() returned nil")
        }
        // No additional PDUs expected (dataset sent with command)
        XCTAssertTrue(msg.messagesData().isEmpty)

        // Parse P-DATA-TF header
        XCTAssertEqual(bytes[0], PDUType.dataTF.rawValue)
        XCTAssertEqual(bytes[1], 0x00)
        let totalLen = bytes.subdata(in: 2..<6).toUInt32(byteOrder: .BigEndian)
        XCTAssertEqual(totalLen, UInt32(bytes.count - 6))

        var offset = 6
        // PDV #1 (Command)
        let pdv1Len = bytes.subdata(in: offset..<(offset+4)).toUInt32(byteOrder: .BigEndian)
        offset += 4
        XCTAssertTrue(pdv1Len > 2)
        let pdv1pc = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        let pdv1hdr = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        XCTAssertEqual(pdv1pc, pcID)
        XCTAssertEqual(pdv1hdr, 0x03) // command + last
        let cmdData = bytes.subdata(in: offset..<(offset + Int(pdv1Len - 2)))
        offset += Int(pdv1Len - 2)

        // Verify CommandDataSetType == 0x0000 (dataset present)
        let dis = DicomInputStream(data: cmdData)
        dis.vrMethod = .Implicit
        dis.byteOrder = .LittleEndian
        let cmdDS = try XCTUnwrap(try dis.readDataset(enforceVR: false))
        let dsType = try XCTUnwrap(cmdDS.integer16(forTag: "CommandDataSetType"))
        XCTAssertEqual(dsType, 0x0000)

        // PDV #2 (Dataset)
        XCTAssertLessThan(offset, bytes.count)
        let pdv2Len = bytes.subdata(in: offset..<(offset+4)).toUInt32(byteOrder: .BigEndian)
        offset += 4
        XCTAssertTrue(pdv2Len > 2)
        let pdv2pc = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        let pdv2hdr = bytes.subdata(in: offset..<(offset+1)).toUInt8(byteOrder: .BigEndian)
        offset += 1
        XCTAssertEqual(pdv2pc, pcID)
        XCTAssertEqual(pdv2hdr, 0x02) // last only
        // Ensure dataset bytes exist
        XCTAssertEqual(offset + Int(pdv2Len - 2) <= bytes.count, true)
    }
}

