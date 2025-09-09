//
//  DICOMOverlayView.swift
//  DICOMViewer
//
//  Created by extraction from SwiftDetailViewController for Phase 10A optimization
//  Provides DICOM image overlay UI components including labels and orientation markers
//

import UIKit

// MARK: - Overlay Data Protocol

protocol DICOMOverlayDataSource: AnyObject {
    var patientModel: PatientModel? { get }
    var dicomDecoder: DCMDecoder? { get }
}

// MARK: - DICOM Overlay View

class DICOMOverlayView: UIView {
    
    // MARK: - Properties
    
    weak var dataSource: DICOMOverlayDataSource?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = .clear
    }
    
    // MARK: - Overlay Creation Methods
    
    func createOverlayLabelsView() -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        
        // Top-left labels
        let topLeftStack = createTopLeftLabels()
        container.addSubview(topLeftStack)
        
        // Top-right labels
        let topRightStack = createTopRightLabels()
        container.addSubview(topRightStack)
        
        // Bottom-left labels
        let bottomLeftStack = createBottomLeftLabels()
        container.addSubview(bottomLeftStack)
        
        // Bottom-right labels
        let bottomRightStack = createBottomRightLabels()
        container.addSubview(bottomRightStack)
        
        // Orientation markers
        let orientationViews = createOrientationMarkers()
        orientationViews.forEach {
            container.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        // Setup constraints for all elements
        setupOverlayConstraints(
            container: container,
            topLeft: topLeftStack,
            topRight: topRightStack,
            bottomLeft: bottomLeftStack,
            bottomRight: bottomRightStack,
            orientationViews: orientationViews
        )
        
        return container
    }
    
    // MARK: - Label Stack Creation
    
    private func createTopLeftLabels() -> UIStackView {
        let studyLabel = createOverlayLabel(text: dataSource?.patientModel?.studyDescription ?? "Unknown Study")
        let seriesLabel = createOverlayLabel(text: "Series: 1")
        let modalityLabel = createOverlayLabel(text: dataSource?.patientModel?.modality.rawStringValue ?? "Unknown")
        
        let stack = UIStackView(arrangedSubviews: [studyLabel, seriesLabel, modalityLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        return stack
    }
    
    private func createTopRightLabels() -> UIStackView {
        let wlLabel = createOverlayLabel(text: "WL: 50")
        let wwLabel = createOverlayLabel(text: "WW: 400")
        let zoomLabel = createOverlayLabel(text: "Zoom: 100%")
        let angleLabel = createOverlayLabel(text: "Angle: 0°")
        
        let stack = UIStackView(arrangedSubviews: [wlLabel, wwLabel, zoomLabel, angleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .trailing
        return stack
    }
    
    private func createBottomLeftLabels() -> UIStackView {
        let imageLabel = createOverlayLabel(text: "Im: 1 / 1")
        let positionLabel = createOverlayLabel(text: "L: 0.00 mm")
        let thicknessLabel = createOverlayLabel(text: "T: 0.00 mm")
        
        let stack = UIStackView(arrangedSubviews: [imageLabel, positionLabel, thicknessLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        return stack
    }
    
    private func createBottomRightLabels() -> UIStackView {
        let sizeLabel = createOverlayLabel(text: "Size: 256 x 256")
        let dateLabel = createOverlayLabel(text: "Today")
        let techLabel = createOverlayLabel(text: "TE: 0ms TR: 0ms")
        
        let stack = UIStackView(arrangedSubviews: [sizeLabel, dateLabel, techLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .trailing
        return stack
    }
    
    // MARK: - Orientation Markers
    
    func createOrientationMarkers() -> [UILabel] {
        // Get dynamic orientation markers based on DICOM series orientation
        let markers = getDynamicOrientationMarkers()
        
        let topLabel = createOrientationLabel(text: markers.top)
        let bottomLabel = createOrientationLabel(text: markers.bottom)
        let leftLabel = createOrientationLabel(text: markers.left)
        let rightLabel = createOrientationLabel(text: markers.right)
        
        // Set tags for identification
        topLabel.tag = 1001
        bottomLabel.tag = 1002
        leftLabel.tag = 1003
        rightLabel.tag = 1004
        
        return [topLabel, bottomLabel, leftLabel, rightLabel]
    }
    
    func getDynamicOrientationMarkers() -> (top: String, bottom: String, left: String, right: String) {
        guard let decoder = dataSource?.dicomDecoder else {
            // Cannot determine orientation without decoder
            return (top: "?", bottom: "?", left: "?", right: "?")
        }
        
        // First try to get Image Orientation Patient (0020,0037) - this is the most accurate
        let imageOrientation = decoder.info(for: 0x00200037) // IMAGE_ORIENTATION_PATIENT
        if !imageOrientation.isEmpty {
            print("🧭 Image Orientation Patient: \(imageOrientation)")
            let markers = parseImageOrientationPatient(imageOrientation)
            if markers.top != "?" { // Valid orientation found
                return markers
            }
        }
        
        // Fallback: Try Patient Position (0018,5100) for position info
        let patientPosition = decoder.info(for: 0x00185100) // PATIENT_POSITION
        if !patientPosition.isEmpty {
            print("🧭 Patient Position: \(patientPosition)")
            let markers = parsePatientPosition(patientPosition)
            if markers.top != "?" { // Valid orientation found
                return markers
            }
        }
        
        // Check for orientation in series description as last resort
        if let modality = dataSource?.patientModel?.modality.rawStringValue {
            print("🧭 Trying modality-based orientation for: \(modality)")
            // For certain modalities, we might have standard orientations
            // This is less accurate but better than nothing
        }
        
        // Cannot determine orientation
        return (top: "?", bottom: "?", left: "?", right: "?")
    }
    
    // MARK: - Orientation Parsing
    
    private func parseImageOrientationPatient(_ orientation: String) -> (top: String, bottom: String, left: String, right: String) {
        // Image Orientation Patient contains 6 values: row direction (3 values) and column direction (3 values)
        // Format: "cosX_row\\cosY_row\\cosZ_row\\cosX_col\\cosY_col\\cosZ_col"
        
        let components = orientation.components(separatedBy: "\\")
        guard components.count >= 6,
              let rowX = Double(components[0]),
              let rowY = Double(components[1]),
              let rowZ = Double(components[2]),
              let colX = Double(components[3]),
              let colY = Double(components[4]),
              let colZ = Double(components[5]) else {
            print("⚠️ Could not parse Image Orientation Patient: \(orientation)")
            return (top: "?", bottom: "?", left: "?", right: "?")
        }
        
        // Determine primary orientation based on direction cosines
        // Row direction (left-right on screen)
        let rightDir = getDominantDirection(x: rowX, y: rowY, z: rowZ)
        let leftDir = getOppositeDirection(rightDir)
        
        // Column direction (up-down on screen)
        let topDir = getDominantDirection(x: -colX, y: -colY, z: -colZ) // Negative because DICOM Y increases downward
        let bottomDir = getOppositeDirection(topDir)
        
        print("🧭 Calculated orientation - Top: \(topDir), Bottom: \(bottomDir), Left: \(leftDir), Right: \(rightDir)")
        
        return (top: topDir, bottom: bottomDir, left: leftDir, right: rightDir)
    }
    
    private func parsePatientPosition(_ position: String) -> (top: String, bottom: String, left: String, right: String) {
        // Patient Position like "HFS" (Head First Supine), "FFS" (Feet First Supine), etc.
        let pos = position.uppercased()
        
        if pos.contains("HFS") || pos.contains("HEAD") && pos.contains("SUPINE") {
            // Head First Supine - typical axial
            return (top: "A", bottom: "P", left: "L", right: "R")
        } else if pos.contains("HFP") || pos.contains("HEAD") && pos.contains("PRONE") {
            // Head First Prone
            return (top: "P", bottom: "A", left: "L", right: "R")
        } else if pos.contains("HFDL") || pos.contains("HEAD") && pos.contains("LEFT") {
            // Head First Decubitus Left - sagittal
            return (top: "S", bottom: "I", left: "A", right: "P")
        } else if pos.contains("HFDR") || pos.contains("HEAD") && pos.contains("RIGHT") {
            // Head First Decubitus Right - sagittal
            return (top: "S", bottom: "I", left: "P", right: "A")
        }
        
        // Default fallback
        return (top: "?", bottom: "?", left: "?", right: "?")
    }
    
    private func getDominantDirection(x: Double, y: Double, z: Double) -> String {
        let absX = abs(x)
        let absY = abs(y)
        let absZ = abs(z)
        
        if absX > absY && absX > absZ {
            return x > 0 ? "L" : "R" // Patient's Left/Right
        } else if absY > absZ {
            return y > 0 ? "P" : "A" // Patient's Posterior/Anterior
        } else {
            return z > 0 ? "S" : "I" // Patient's Superior/Inferior
        }
    }
    
    private func getOppositeDirection(_ direction: String) -> String {
        switch direction {
        case "L": return "R"
        case "R": return "L"
        case "A": return "P"
        case "P": return "A"
        case "S": return "I"
        case "I": return "S"
        default: return "?"
        }
    }
    
    // MARK: - Label Creation Helpers
    
    private func createOverlayLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 2
        label.clipsToBounds = true
        return label
    }
    
    private func createOrientationLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        return label
    }
    
    // MARK: - Constraints Setup
    
    private func setupOverlayConstraints(
        container: UIView,
        topLeft: UIStackView,
        topRight: UIStackView,
        bottomLeft: UIStackView,
        bottomRight: UIStackView,
        orientationViews: [UILabel]
    ) {
        // Disable autoresizing masks
        topLeft.translatesAutoresizingMaskIntoConstraints = false
        topRight.translatesAutoresizingMaskIntoConstraints = false
        bottomLeft.translatesAutoresizingMaskIntoConstraints = false
        bottomRight.translatesAutoresizingMaskIntoConstraints = false
        
        let safeAreaGuide = container.safeAreaLayoutGuide
        
        NSLayoutConstraint.activate([
            // Top-left stack
            topLeft.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor, constant: 20),
            topLeft.leadingAnchor.constraint(equalTo: safeAreaGuide.leadingAnchor, constant: 20),
            
            // Top-right stack
            topRight.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor, constant: 20),
            topRight.trailingAnchor.constraint(equalTo: safeAreaGuide.trailingAnchor, constant: -20),
            
            // Bottom-left stack
            bottomLeft.bottomAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor, constant: -20),
            bottomLeft.leadingAnchor.constraint(equalTo: safeAreaGuide.leadingAnchor, constant: 20),
            
            // Bottom-right stack
            bottomRight.bottomAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor, constant: -20),
            bottomRight.trailingAnchor.constraint(equalTo: safeAreaGuide.trailingAnchor, constant: -20),
        ])
        
        // Setup orientation markers constraints
        setupOrientationConstraints(container: container, orientationViews: orientationViews)
    }
    
    private func setupOrientationConstraints(container: UIView, orientationViews: [UILabel]) {
        guard orientationViews.count == 4 else { return }
        
        let topLabel = orientationViews[0]      // tag 1001
        let bottomLabel = orientationViews[1]   // tag 1002
        let leftLabel = orientationViews[2]     // tag 1003
        let rightLabel = orientationViews[3]    // tag 1004
        
        NSLayoutConstraint.activate([
            // Top orientation marker
            topLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            topLabel.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 60),
            topLabel.widthAnchor.constraint(equalToConstant: 24),
            topLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Bottom orientation marker
            bottomLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            bottomLabel.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            bottomLabel.widthAnchor.constraint(equalToConstant: 24),
            bottomLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Left orientation marker
            leftLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftLabel.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            leftLabel.widthAnchor.constraint(equalToConstant: 24),
            leftLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Right orientation marker
            rightLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            rightLabel.widthAnchor.constraint(equalToConstant: 24),
            rightLabel.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
}

// MARK: - Update Methods

extension DICOMOverlayView {
    
    func updateOverlayData() {
        // Method to refresh overlay data when needed
        // This can be called by the parent view controller when data changes
    }
    
    func updateOrientationMarkers(showOrientation: Bool = true) {
        // Find orientation labels by their tags and update visibility
        for subview in subviews {
            for orientationView in subview.subviews {
                if orientationView.tag >= 1001 && orientationView.tag <= 1004 {
                    orientationView.isHidden = !showOrientation
                }
            }
        }
    }
}