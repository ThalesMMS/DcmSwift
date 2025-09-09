//
//  WindowLevelService.swift
//  DICOMViewer
//
//  Window/Level management service for DICOM images
//  Extracted from SwiftDetailViewController for Phase 6C
//

import UIKit
import Foundation

// MARK: - Data Models

public struct WindowLevelSettings: Sendable {
    let windowWidth: Int
    let windowLevel: Int
    let rescaleSlope: Double
    let rescaleIntercept: Double
    
    init(width: Int, level: Int, slope: Double = 1.0, intercept: Double = 0.0) {
        self.windowWidth = width
        self.windowLevel = level
        self.rescaleSlope = slope
        self.rescaleIntercept = intercept
    }
}

public struct ServiceWindowLevelPreset: Sendable {
    let name: String
    let windowWidth: Int
    let windowLevel: Int
    let modality: DICOMModality?
    
    init(name: String, width: Int, level: Int, modality: DICOMModality? = nil) {
        self.name = name
        self.windowWidth = width
        self.windowLevel = level
        self.modality = modality
    }
}

// Convenience alias for shorter usage
public typealias WLPreset = ServiceWindowLevelPreset

public struct WindowLevelCalculationResult: Sendable {
    let pixelWidth: Int
    let pixelLevel: Int
    let huWidth: Double
    let huLevel: Double
    let rescaleSlope: Double
    let rescaleIntercept: Double
}

// MARK: - Protocol Definition

@MainActor
public protocol WindowLevelServiceProtocol {
    func calculateWindowLevel(huWidth: Double, huLevel: Double, rescaleSlope: Double, rescaleIntercept: Double) -> WindowLevelCalculationResult
    func calculateFullDynamicPreset(from decoder: DCMDecoder) -> ServiceWindowLevelPreset?
    func getPresetsForModality(_ modality: DICOMModality) -> [ServiceWindowLevelPreset]
    func getDefaultWindowLevel(for modality: DICOMModality) -> (level: Int, width: Int)
    func convertPixelToHU(pixelValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double
    func convertHUToPixel(huValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double
    func adjustWindowLevel(currentWidth: Double, currentLevel: Double, deltaX: CGFloat, deltaY: CGFloat, rescaleSlope: Double, rescaleIntercept: Double) -> WindowLevelSettings
    func retrievePresetsForViewController(modality: DICOMModality?) -> [ServiceWindowLevelPreset]
}

// MARK: - Service Implementation

@MainActor
public final class WindowLevelService: WindowLevelServiceProtocol {
    
    // MARK: - Singleton
    
    public static let shared = WindowLevelService()
    private init() {}
    
    // MARK: - Core Window/Level Calculations
    
    public func calculateWindowLevel(huWidth: Double, huLevel: Double, rescaleSlope: Double, rescaleIntercept: Double) -> WindowLevelCalculationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Convert HU to pixel values for the rendering layer
        let pixelWidth: Int
        let pixelLevel: Int
        
        if rescaleSlope != 0 && rescaleSlope != 1.0 || rescaleIntercept != 0 {
            // Convert HU values to pixel values
            // HU = slope * pixel + intercept
            // Therefore: pixel = (HU - intercept) / slope
            let centerPixel = (huLevel - rescaleIntercept) / rescaleSlope
            let widthPixel = huWidth / rescaleSlope
            
            pixelLevel = Int(round(centerPixel))
            pixelWidth = Int(round(widthPixel))
            
            print("🔬 HU→Pixel conversion: \(huLevel)HU → \(pixelLevel)px, \(huWidth)HU → \(pixelWidth)px")
        } else {
            // No rescaling needed - values are already in pixel space
            pixelLevel = Int(round(huLevel))
            pixelWidth = Int(round(huWidth))
            print("🔬 Direct pixel values (no rescaling): W=\(pixelWidth)px L=\(pixelLevel)px")
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 1.0 {
            print("[PERF] Window/Level calculation: \(String(format: "%.2f", elapsed))ms")
        }
        
        return WindowLevelCalculationResult(
            pixelWidth: pixelWidth,
            pixelLevel: pixelLevel,
            huWidth: huWidth,
            huLevel: huLevel,
            rescaleSlope: rescaleSlope,
            rescaleIntercept: rescaleIntercept
        )
    }
    
    public func calculateFullDynamicPreset(from decoder: DCMDecoder) -> ServiceWindowLevelPreset? {
        guard decoder.dicomFileReadSuccess else {
            print("⚠️ Full Dynamic: Decoder not available.")
            return nil
        }
        
        let _ = CFAbsoluteTimeGetCurrent() // Performance tracking
        
        let width = Int(decoder.width)
        let height = Int(decoder.height)
        let pixelCount = width * height
        
        var minPixelValue: Double = decoder.bitDepth == 16 ? Double(UInt16.max) : Double(UInt8.max)
        var maxPixelValue: Double = decoder.bitDepth == 16 ? Double(UInt16.min) : Double(UInt8.min)
        
        // Access pixel data to find min/max values
        if decoder.bitDepth == 16, let pixels16 = decoder.getPixels16() {
            let stepSize = max(1, pixelCount / 10000) // Sample for performance
            
            for i in stride(from: 0, to: pixels16.count, by: stepSize) {
                let pixelValue = Double(pixels16[i])
                if pixelValue < minPixelValue { minPixelValue = pixelValue }
                if pixelValue > maxPixelValue { maxPixelValue = pixelValue }
            }
            
        } else if decoder.bitDepth == 8, let pixels8 = decoder.getPixels8() {
            let stepSize = max(1, pixelCount / 10000) // Sample for performance
            
            for i in stride(from: 0, to: pixels8.count, by: stepSize) {
                let pixelValue = Double(pixels8[i])
                if pixelValue < minPixelValue { minPixelValue = pixelValue }
                if pixelValue > maxPixelValue { maxPixelValue = pixelValue }
            }
        } else {
            print("⚠️ Full Dynamic: Unable to access pixel data.")
            return nil
        }
        
        // Convert pixel values to HU
        let rescaleSlope = Double(decoder.info(for: 0x00281053)) ?? 1.0
        let rescaleIntercept = Double(decoder.info(for: 0x00281052)) ?? 0.0
        
        let minHU = convertPixelToHU(pixelValue: minPixelValue, rescaleSlope: rescaleSlope, rescaleIntercept: rescaleIntercept)
        let maxHU = convertPixelToHU(pixelValue: maxPixelValue, rescaleSlope: rescaleSlope, rescaleIntercept: rescaleIntercept)
        
        let windowWidth = Int(maxHU - minHU)
        let windowLevel = Int((maxHU + minHU) / 2)
        
        print("🎯 Full Dynamic calculated: W=\(windowWidth)HU L=\(windowLevel)HU (from \(minHU) to \(maxHU))")
        
        return ServiceWindowLevelPreset(name: "Full Dynamic", width: windowWidth, level: windowLevel)
    }
    
    public func getPresetsForModality(_ modality: DICOMModality) -> [ServiceWindowLevelPreset] {
        var presets: [ServiceWindowLevelPreset] = []
        
        switch modality {
        case .ct:
            presets = [
                ServiceWindowLevelPreset(name: "Abdomen", width: 350, level: 40, modality: .ct),
                ServiceWindowLevelPreset(name: "Bone", width: 1500, level: 300, modality: .ct),
                ServiceWindowLevelPreset(name: "Brain", width: 100, level: 50, modality: .ct),
                ServiceWindowLevelPreset(name: "Chest", width: 1400, level: -500, modality: .ct),
                ServiceWindowLevelPreset(name: "Lung", width: 1400, level: -500, modality: .ct),
                ServiceWindowLevelPreset(name: "Mediastinum", width: 350, level: 50, modality: .ct),
                ServiceWindowLevelPreset(name: "Spine", width: 1500, level: 300, modality: .ct)
            ]
        case .mr:
            presets = [
                ServiceWindowLevelPreset(name: "Brain T1", width: 600, level: 300, modality: .mr),
                ServiceWindowLevelPreset(name: "Brain T2", width: 1200, level: 600, modality: .mr),
                ServiceWindowLevelPreset(name: "Spine", width: 800, level: 400, modality: .mr)
            ]
        case .cr, .dx:
            presets = [
                ServiceWindowLevelPreset(name: "Chest", width: 2000, level: 1000, modality: modality),
                ServiceWindowLevelPreset(name: "Bone", width: 3000, level: 1500, modality: modality),
                ServiceWindowLevelPreset(name: "Soft Tissue", width: 600, level: 300, modality: modality)
            ]
        default:
            presets = [
                ServiceWindowLevelPreset(name: "Default", width: 400, level: 200, modality: modality),
                ServiceWindowLevelPreset(name: "High Contrast", width: 200, level: 100, modality: modality),
                ServiceWindowLevelPreset(name: "Low Contrast", width: 800, level: 400, modality: modality)
            ]
        }
        
        // Add Full Dynamic as the last option
        presets.append(ServiceWindowLevelPreset(name: "Full Dynamic", width: 0, level: 0, modality: modality))
        
        return presets
    }
    
    public func getDefaultWindowLevel(for modality: DICOMModality) -> (level: Int, width: Int) {
        switch modality {
        case .ct:
            return (level: 40, width: 350) // Abdomen preset
        case .mr:
            return (level: 300, width: 600) // Brain T1 preset
        case .cr, .dx:
            return (level: 1000, width: 2000) // Chest preset
        case .us:
            return (level: 128, width: 256) // Ultrasound
        default:
            return (level: 200, width: 400) // Generic preset
        }
    }
    
    // MARK: - HU Conversion Utilities
    
    public func convertPixelToHU(pixelValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double {
        return rescaleSlope * pixelValue + rescaleIntercept
    }
    
    public func convertHUToPixel(huValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double {
        guard rescaleSlope != 0 else { return huValue }
        return (huValue - rescaleIntercept) / rescaleSlope
    }
    
    // MARK: - Gesture-Based Adjustment
    
    public func adjustWindowLevel(currentWidth: Double, currentLevel: Double, deltaX: CGFloat, deltaY: CGFloat, rescaleSlope: Double, rescaleIntercept: Double) -> WindowLevelSettings {
        let _ = CFAbsoluteTimeGetCurrent() // Performance tracking
        
        // Sensitivity factors for smooth adjustment
        let levelSensitivity: Double = 2.0
        let widthSensitivity: Double = 4.0
        
        // Calculate new values
        let newWindowCenterHU = currentLevel - Double(deltaY) * levelSensitivity
        let newWindowWidthHU = max(1.0, currentWidth + Double(deltaX) * widthSensitivity)
        
        print("🎨 W/L gesture adjustment: ΔX=\(deltaX) ΔY=\(deltaY)")
        print("🎨 New values: W=\(Int(newWindowWidthHU))HU L=\(Int(newWindowCenterHU))HU")
        
        return WindowLevelSettings(
            width: Int(newWindowWidthHU),
            level: Int(newWindowCenterHU),
            slope: rescaleSlope,
            intercept: rescaleIntercept
        )
    }
    
    // MARK: - MVVM-C Migration: Preset Retrieval
    
    public func retrievePresetsForViewController(modality: DICOMModality?) -> [ServiceWindowLevelPreset] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let presets: [ServiceWindowLevelPreset]
        
        if let modality = modality {
            // Get modality-specific presets
            presets = getPresetsForModality(modality)
            print("📋 Retrieved \(presets.count) presets for modality: \(modality.shortDisplayName)")
        } else {
            // Default presets when modality is unknown
            presets = [
                ServiceWindowLevelPreset(name: "Default", width: 400, level: 200),
                ServiceWindowLevelPreset(name: "High Contrast", width: 200, level: 100),
                ServiceWindowLevelPreset(name: "Low Contrast", width: 800, level: 400),
                ServiceWindowLevelPreset(name: "Full Dynamic", width: 0, level: 0)
            ]
            print("📋 Retrieved \(presets.count) default presets (unknown modality)")
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 0.5 {
            print("[PERF] Preset retrieval: \(String(format: "%.2f", elapsed))ms")
        }
        
        return presets
    }
    
    // MARK: - Phase 11B: UI Presentation Methods
    
    /// Present custom Window/Level dialog
    public func presentWindowLevelDialog(
        currentWidth: Int?,
        currentLevel: Int?,
        from viewController: UIViewController,
        completion: @escaping (Bool, Double, Double) -> Void
    ) {
        print("🪟 [MVVM-C Phase 11B] Presenting W/L dialog via WindowLevelService")
        
        let alertController = UIAlertController(
            title: "Custom Window/Level",
            message: "Enter values in Hounsfield Units",
            preferredStyle: .alert
        )
        
        // Width text field
        alertController.addTextField { textField in
            textField.placeholder = "Window Width (HU)"
            textField.keyboardType = .numberPad
            textField.text = currentWidth.map(String.init) ?? "400"
        }
        
        // Level text field
        alertController.addTextField { textField in
            textField.placeholder = "Window Level (HU)"
            textField.keyboardType = .numberPad
            textField.text = currentLevel.map(String.init) ?? "50"
        }
        
        // Apply action
        let applyAction = UIAlertAction(title: "Apply", style: .default) { _ in
            guard let widthText = alertController.textFields?[0].text,
                  let levelText = alertController.textFields?[1].text,
                  let width = Double(widthText),
                  let level = Double(levelText) else {
                print("❌ Invalid W/L values entered")
                completion(false, 0, 0)
                return
            }
            
            print("✅ [MVVM-C Phase 11B] W/L dialog completed: W=\(width)HU L=\(level)HU")
            completion(true, width, level)
        }
        
        // Cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            print("⏹️ [MVVM-C Phase 11B] W/L dialog cancelled")
            completion(false, 0, 0)
        }
        
        alertController.addAction(applyAction)
        alertController.addAction(cancelAction)
        
        viewController.present(alertController, animated: true)
    }
    
    /// Present Window/Level preset selector
    public func presentPresetSelector(
        modality: DICOMModality,
        from viewController: UIViewController,
        onPresetSelected: @escaping (ServiceWindowLevelPreset) -> Void,
        onCustomSelected: @escaping () -> Void
    ) {
        print("🎨 [MVVM-C Phase 11B] Presenting preset selector via WindowLevelService")
        
        let alertController = UIAlertController(
            title: "Window/Level Presets",
            message: "Select a preset for \(modality.shortDisplayName)",
            preferredStyle: .actionSheet
        )
        
        // Add preset actions
        let presets = getPresetsForModality(modality)
        for preset in presets {
            let action = UIAlertAction(title: preset.name, style: .default) { _ in
                print("✅ [MVVM-C Phase 11B] Preset selected: \(preset.name)")
                onPresetSelected(preset)
            }
            alertController.addAction(action)
        }
        
        // Add custom option
        let customAction = UIAlertAction(title: "Custom...", style: .default) { _ in
            print("🎨 [MVVM-C Phase 11B] Custom preset option selected")
            onCustomSelected()
        }
        alertController.addAction(customAction)
        
        // Add cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            print("⏹️ [MVVM-C Phase 11B] Preset selector cancelled")
        }
        alertController.addAction(cancelAction)
        
        // Configure for iPad
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        viewController.present(alertController, animated: true)
    }
}

// MARK: - Extensions

extension DICOMModality {
    var shortDisplayName: String {
        switch self {
        case .ct: return "CT"
        case .mr: return "MR"
        case .cr: return "CR"
        case .dx: return "DX"
        case .us: return "US"
        case .mg: return "MG"
        case .rf: return "RF"
        case .xc: return "XC"
        case .sc: return "SC"
        case .pt: return "PT"
        case .nm: return "NM"
        default: return "Unknown"
        }
    }
}