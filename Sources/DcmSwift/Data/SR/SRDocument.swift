//
//  SRDocument.swift
//  
//
//  Created by Rafael Warnault, OPALE on 05/07/2021.
//

import Foundation
import Html


/**
 SR document types (DICOM IOD)
 
 Pasted from DCMTK for reference:
 
 TODO: unused for now!
 
 https://support.dcmtk.org/docs/classDSRTypes.html#a6545d88cf751a0b97c56c509dc644b85
 */
public enum DocumentType {
    case BasicTextSR                                // DICOM IOD: Basic Text SR.
    case EnhancedSR                                 // DICOM IOD: Enhanced SR.
    case ComprehensiveSR                            // DICOM IOD: Comprehensive SR.
    case KeyObjectSelectionDocument                 // DICOM IOD: Key Object Selection Document.
    case MammographyCadSR                           // DICOM IOD: Mammography CAD SR.
    case ChestCadSR                                 // DICOM IOD: Chest CAD SR.
    case ColonCadSR                                 // DICOM IOD: Colon CAD SR.
    case ProcedureLog                               // DICOM IOD: Procedure Log.
    case XRayRadiationDoseSR                        // DICOM IOD: X-Ray Radiation Dose SR.
    case SpectaclePrescriptionReport                // DICOM IOD: Spectacle Prescription Report.
    case MacularGridThicknessAndVolumeReport        // DICOM IOD: Macular Grid Thickness and Volume Report.
    case ImplantationPlanSRDocument                 // DICOM IOD: Implantation Plan SR Document.
    case Comprehensive3DSR                          // DICOM IOD: Comprehensive 3D SR.
    case RadiopharmaceuticalRadiationDoseSR         // DICOM IOD: Radiopharmaceutical Radiation Dose SR.
    case ExtensibleSR                               // DICOM IOD: Extensible SR (not yet implemented)
    case AcquisitionContextSR                       // DICOM IOD: Acquisition Context SR.
    case SimplifiedAdultEchoSR                      // DICOM IOD: Simplified Adult Echo SR.
    case PatientRadiationDoseSR                     // DICOM IOD: Patient Radiation Dose SR.
    case PerformedImagingAgentAdministrationSR      // DICOM IOD: Performed Imaging Agent Administration SR.
    case PlannedImagingAgentAdministrationSR        // DICOM IOD: Planned Imaging Agent Administration SR.
    case RenditionSelectionDocument                 // DICOM IOD: Rendition Selection Document.
}


// TODO: unused for now!
public enum PreliminaryFlag {
    case PRELIMINARY
    case FINAL
}

public enum VerificationFlag {
    case UNVERIFIED
    case VERIFIED
}

public enum CompletionFlag {
    case PARTIAL
    case COMPLETE
}

/**
 Class representing a DICOM Structured Report file
 This class provides specific tools and implementation to deals with DICOM SR document.
 
 TODO: Unit tests for SRDocument class
 */
public class SRDocument: CustomStringConvertible {
    private var dataset:DataSet
    private var root:SRItemNode
    
    public var conceptName:SRCode?
    
    public var preliminaryFlag:PreliminaryFlag      = .PRELIMINARY
    public var verificationFlag:VerificationFlag    = .UNVERIFIED
    public var completionFlag:CompletionFlag        = .PARTIAL
    
    
    
    /**
        Init a DICOM SR document with a given dataset
     */
    public init?(withDataset dataset:DataSet) {
        self.dataset = dataset
    
        self.root = SRItemNode(valueType: .Container, relationshipType: .root, parent: nil)
        
        if !load() {
            return nil
        }
    }
    
    
    public var title:String {
        get {
            if let sopclass = dataset.string(forTag: "MediaStorageSOPClassUID") {
                return DicomSpec.shared.nameForUID(withUID: sopclass)
            }
            
            return "No Title"
        }
    }
    
    
    public var contentDate:Date? {
        get {
            dataset.date(forTag: "ContentDate")
        }
    }
    
    public var contentTime:Date? {
        get {
            dataset.date(forTag: "ContentTime")
        }
    }
    
    public var patientName:String? {
        get {
            dataset.string(forTag: "PatientName")
        }
    }
    
    public var patientID:String? {
        get {
            dataset.string(forTag: "PatientID")
        }
    }
    
    public var patientBirthDate:Date? {
        get {
            dataset.date(forTag: "PatientBirthDate")
        }
    }
    
    public var patientSex:String? {
        get {
            dataset.string(forTag: "PatientSex")
        }
    }
    
    public var studyDescription:String? {
        get {
            dataset.string(forTag: "StudyDescription")
        }
    }
    
    public var seriesDescription:String? {
        get {
            dataset.string(forTag: "SeriesDescription")
        }
    }
    
    public var institutionName:String? {
        get {
            dataset.string(forTag: "InstitutionName")
        }
    }

    
    
    public var description: String {
        get {
            var str = "* Patient: \(patientName ?? "") [\(patientID ?? "")] (\(patientSex ?? ""))\n"
            
            if let ddns = patientBirthDate?.format(accordingTo: .DA) {
                str += "\n\t\u{021B3} Patient Birthdate: \(ddns)"
            }
            
            if let std = studyDescription {
                str += "\n\t\u{021B3} Study Description: \(std)"
            }
            
            if let std = seriesDescription {
                str += "\n\t\u{021B3} Series Description: \(std)"
            }
            
            if let cn = conceptName {
                str += "\n\t\u{021B3} Concept Name: \(cn)\n"
            }
            
            // TODO: add more attributes (ContentDate, flags, etc.)
            
            for n in root.nodes {
                str += "\n\(n.description)"
            }
            
            return str
        }
    }
}


// MARK: -
public extension SRDocument {
    var html:String {
        get {
            var contentDateTime = Node.text("")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            
            if let d = dataset.date(forTag: "ContentDate"),
               let t = dataset.date(forTag: "ContentTime"),
               let dt = Date(date: d, time: t) {
                let dateTime = dateFormatter.string(from: dt)
                contentDateTime = Node.text("\(dateTime)")
            }
            
            var contentDiv = Node.div()
            
            for n in root.nodes {
                if let itemNode = n as? SRItemNode {
                    contentDiv.append(itemNode.htmlNode)
                }
            }
            
            let document: Node = .document(
                .html(
                    .head(
                        .title(title)
                    ),
                    .body(
                        .h1(Node.text(title)),
                        .table(
                            .tr(
                                .td(.b(Node.text("Institution: "))),
                                .td(Node.text("\(institutionName ?? "")"))
                            ),
                            .tr(
                                .td(.b(Node.text("Patient: "))),
                                .td(Node.text("\(patientName ?? "") [\(patientID ?? "")] (\(patientSex ?? ""))"))
                            ),
                            .tr(
                                .td(.b(Node.text("Study: "))),
                                .td(Node.text("\(studyDescription ?? "")"))
                            ),
                            .tr(
                                .td(.b(Node.text("Serie: "))),
                                .td(Node.text("\(seriesDescription ?? "")"))
                            ),
                            .tr(
                                .td(.b(Node.text("Preliminary Flag: "))),
                                .td(Node.text("\(preliminaryFlag)"))
                            ),
                            .tr(
                                .td(.b(Node.text("Completion Flag: "))),
                                .td(Node.text("\(completionFlag)"))
                            ),
                            .tr(
                                .td(.b(Node.text("Verification Flag: "))),
                                .td(Node.text("\(verificationFlag)"))
                            ),
                            .tr(
                                .td(.b(Node.text("Content Date/Time: "))),
                                .td(contentDateTime)
                            )
                        ),
                        .hr(),
                        .h2("Structured Report"),
                        contentDiv
                    )
                )
            )
            return render(document)
        }
    }
}



// MARK: -
private extension SRDocument {
    /**
     Load dataset-level element related to SR document
     
     NOTE: Recursive call in there, be careful
     */
    private func load(force:Bool = false) -> Bool {
        // perform some sanity checks
        guard let modality = dataset.string(forTag: "Modality") else {
            Logger.error("Cannot load SR document, Modality tag not found")
            return false
        }
        
        if !force && modality != "SR" {
            Logger.error("Cannot load SR document, wrong modality given \(modality)")
            return false
        }
        
        // Load dataset-level ConceptNameCodeSequence if exists
        if let sequence = dataset.element(forTagName: "ConceptNameCodeSequence") as? DataSequence {
            conceptName = SRCode(withSequence: sequence)
        }
        
        // TODO: collect dataset-level information
        /// * doc type (via IOD and SOP classes)
        /// * flags (in the file dataset)
        /// * etc.
        
        // load nodes
        guard let sequence = dataset.element(forTagName: "ContentSequence") as? DataSequence else {
            Logger.error("Cannot load SR document, no ContentSequence found")
            return false
        }
        
        // load sequence items
        return load(sequence: sequence, node: root)
    }
    
    
    /**
     Load nodes and childs given a Content Sequence element
     It loads nested Content Sequence recursively if found
     */
    private func load(sequence:DataSequence, node:SRItemNode) -> Bool {
        let dateFormatter = DateFormatter()
            
        // loop items
        for item in sequence.items {
            let child = SRItemNode(withItem: item, parent: node)
                            
            if let conceptNameCodeSequence = item.element(withName: "ConceptNameCodeSequence") as? DataSequence {
                child.setConceptName(withSequence: conceptNameCodeSequence)
            }
            
            // TODO: Implement all types: Code,
            switch child.valueType {
            case .Container:
                if let contentSequence = item.element(withName: "ContentSequence") as? DataSequence {
                    // TODO: Maybe use return value here?
                    _ = load(sequence: contentSequence, node: child)
                }
             
            case .Code:
                if let conceptCodeSequence = item.element(withName: "ConceptCodeSequence") as? DataSequence {
                    if let code = SRCode(withSequence: conceptCodeSequence) {
                        child.value = "\(code.codeMeaning ?? "") (\(code.codeValue ?? ""), \(code.codingSchemeDesignator ?? ""))"
                    }
                }
                
            case .PName:
                if let personName = item.element(withName: "PersonName")?.value as? String {
                    child.value = personName
                }
            
            case .Text:
                if let textValue = item.element(withName: "TextValue")?.value as? String {
                    child.value = textValue
                }
               
            case .Date:
                if let date = item.element(withName: "Date")?.value as? Date {
                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .none
                    child.value = dateFormatter.string(from: date)
                }
              
            case .Time:
                if let date = item.element(withName: "Time")?.value as? Date {
                    dateFormatter.dateStyle = .none
                    dateFormatter.timeStyle = .short
                    child.value = dateFormatter.string(from: date)
                }
                
            case .UIDRef:
                if let textValue = item.element(withName: "UID")?.value as? String {
                    child.value = textValue
                }
                
            case .Image:
                if let referencedSOPSequence = item.element(withName: "ReferencedSOPSequence") as? DataSequence {
                    child.imageReferencedSOPSequence = referencedSOPSequence
                    
                    if let i = referencedSOPSequence.items.first {
                        if let rsiu = i.element(withName: "ReferencedSOPInstanceUID")?.value as? String {
                            child.value = rsiu
                        }
                    }
                }
            
            case .Num:
                if let measuredValueSequence = item.element(withName: "MeasuredValueSequence") as? DataSequence {
                    for item in measuredValueSequence.items {
                        child.measuredValues.append(SRMeasuredValue(withItem: item, parent: child))
                        child.value = child.measuredValues.map { v in "\(v.value) \(v.measurementUnitsCode?.codeValue ?? "")" }
                    }
                }
                
            default: break
            }
            
            node.add(child: child)
        }
        
        return true
    }
}
