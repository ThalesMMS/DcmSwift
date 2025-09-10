//  WindowLevelCalculator.swift
//  DcmSwift
//
//  Created by Thales on 2025/09/08.
//

import Foundation

/// Represents a minimal context for window/level calculations.
public struct DicomImageContext: Sendable {
    public let windowWidths: [Int]
    public let windowCenters: [Int]
    public let currentWindowWidth: Int?
    public let currentWindowCenter: Int?
    public let rescaleSlope: Double
    public let rescaleIntercept: Double

    public init(
        windowWidths: [Int] = [],
        windowCenters: [Int] = [],
        currentWindowWidth: Int? = nil,
        currentWindowCenter: Int? = nil,
        rescaleSlope: Double = 1.0,
        rescaleIntercept: Double = 0.0
    ) {
        self.windowWidths = windowWidths
        self.windowCenters = windowCenters
        self.currentWindowWidth = currentWindowWidth
        self.currentWindowCenter = currentWindowCenter
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
    }
}

/// Enumeration of common DICOM modalities.
public enum DICOMModality: Sendable {
    case ct
    case mr
    case cr
    case dx
    case us
    case mg
    case rf
    case xc
    case sc
    case pt
    case nm
    // Additional modalities recognized by the app
    case au
    case dr
    case bmd
    case es
    case rg
    case sr
    case vl
    case xa
    case px
    case ot
    case other
}

/// Model describing a window/level preset for a modality.
public struct ServiceWindowLevelPreset: Sendable {
    public let name: String
    public let windowWidth: Int
    public let windowLevel: Int
    public let huWidth: Int
    public let huLevel: Int
    public let modality: DICOMModality?

    public init(name: String, width: Int, level: Int, modality: DICOMModality? = nil) {
        self.name = name
        self.windowWidth = width
        self.windowLevel = level
        self.huWidth = width
        self.huLevel = level
        self.modality = modality
    }

    public init(name: String, windowWidth: Int, windowLevel: Int, huWidth: Int, huLevel: Int, modality: DICOMModality? = nil) {
        self.name = name
        self.windowWidth = windowWidth
        self.windowLevel = windowLevel
        self.huWidth = huWidth
        self.huLevel = huLevel
        self.modality = modality
    }
}

/// Utility responsible for computing window/level and conversions.
public struct WindowLevelCalculator: Sendable {
    public init() {}

    // MARK: - Presets

    /// Return presets for a given modality.
    public func getPresets(for modality: DICOMModality) -> [ServiceWindowLevelPreset] {
        var presets: [ServiceWindowLevelPreset]

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
        case .cr, .dx, .dr, .rg, .xa:
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

        presets.append(ServiceWindowLevelPreset(name: "Full Dynamic", width: 0, level: 0, modality: modality))
        return presets
    }

    /// Return default window/level values for a modality.
    public func defaultWindowLevel(for modality: DICOMModality) -> (level: Int, width: Int) {
        switch modality {
        case .ct:
            return (level: 40, width: 350)
        case .mr:
            return (level: 300, width: 600)
        case .cr, .dx:
            return (level: 1000, width: 2000)
        case .us:
            return (level: 128, width: 256)
        default:
            return (level: 200, width: 400)
        }
    }

    // MARK: - Window/Level calculations

    /// Calculate pixel window/level from a context containing HU values.
    public func calculateWindowLevel(context: DicomImageContext) -> (pixelWidth: Int, pixelLevel: Int) {
        let huWidth = Double(context.currentWindowWidth ?? context.windowWidths.first ?? 400)
        let huLevel = Double(context.currentWindowCenter ?? context.windowCenters.first ?? 40)
        return calculateWindowLevel(
            huWidth: huWidth,
            huLevel: huLevel,
            rescaleSlope: context.rescaleSlope,
            rescaleIntercept: context.rescaleIntercept
        )
    }

    /// Calculate pixel window/level from HU values and rescale information.
    public func calculateWindowLevel(huWidth: Double, huLevel: Double, rescaleSlope: Double, rescaleIntercept: Double) -> (pixelWidth: Int, pixelLevel: Int) {
        if rescaleSlope != 0 && (rescaleSlope != 1.0 || rescaleIntercept != 0.0) {
            let centerPixel = (huLevel - rescaleIntercept) / rescaleSlope
            let widthPixel = huWidth / rescaleSlope
            return (pixelWidth: Int(round(widthPixel)), pixelLevel: Int(round(centerPixel)))
        } else {
            return (pixelWidth: Int(round(huWidth)), pixelLevel: Int(round(huLevel)))
        }
    }

    // MARK: - Conversions

    /// Convert a pixel value to HU using a context.
    public func convertPixelToHU(pixelValue: Double, context: DicomImageContext) -> Double {
        convertPixelToHU(pixelValue: pixelValue, rescaleSlope: context.rescaleSlope, rescaleIntercept: context.rescaleIntercept)
    }

    /// Convert a pixel value to HU using slope and intercept.
    public func convertPixelToHU(pixelValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double {
        rescaleSlope * pixelValue + rescaleIntercept
    }

    /// Convert a HU value to pixel using a context.
    public func convertHUToPixel(huValue: Double, context: DicomImageContext) -> Double {
        convertHUToPixel(huValue: huValue, rescaleSlope: context.rescaleSlope, rescaleIntercept: context.rescaleIntercept)
    }

    /// Convert a HU value to pixel using slope and intercept.
    public func convertHUToPixel(huValue: Double, rescaleSlope: Double, rescaleIntercept: Double) -> Double {
        guard rescaleSlope != 0 else { return huValue }
        return (huValue - rescaleIntercept) / rescaleSlope
    }
}
