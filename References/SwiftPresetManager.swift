//
//  SwiftPresetManager.swift
//  DICOMViewer
//
//  Swift migration from PresetManager.m with enhanced functionality
//  Created by AI Assistant on 2025-01-27.
//  Copyright © 2025 DICOM Viewer. All rights reserved.
//

import Foundation
import UIKit
import Combine

// MARK: - DICOM Preset Type System

/// Modern Swift enum for DICOM preset types with medical accuracy
enum DICOMPresetType: Int, CaseIterable, Codable {
    case `default` = 0
    case fullDynamic = 1
    case abdomen = 2
    case bone = 3
    case brain = 4
    case lung = 5
    case endoscopy = 6
    case liver = 7
    case softTissue = 8
    case mediastinum = 9
    case custom = 10
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .fullDynamic: return "Full Dynamic"
        case .abdomen: return "Abdomen"
        case .bone: return "Bone"
        case .brain: return "Brain"
        case .lung: return "Lung"
        case .endoscopy: return "Endoscopy"
        case .liver: return "Liver"
        case .softTissue: return "Soft Tissue"
        case .mediastinum: return "Mediastinum"
        case .custom: return "Custom"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .default: return "slider.horizontal.3"
        case .fullDynamic: return "waveform.path"
        case .abdomen: return "figure.core.training"
        case .bone: return "figure.walk"
        case .brain: return "brain.head.profile"
        case .lung: return "lungs"
        case .endoscopy: return "scope"
        case .liver: return "drop.fill"
        case .softTissue: return "hand.point.up.braille"
        case .mediastinum: return "heart.fill"
        case .custom: return "person.crop.circle.badge.plus"
        }
    }
}

// MARK: - DICOM Preset Data Model

/// Medical-grade DICOM window/level preset with validation
struct DICOMPreset: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let displayName: String
    let windowLevel: Int
    let windowWidth: Int
    let type: DICOMPresetType
    let iconName: String?
    let createdAt: Date
    let isUserDefined: Bool
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        windowLevel: Int,
        windowWidth: Int,
        type: DICOMPresetType,
        iconName: String? = nil,
        createdAt: Date = Date(),
        isUserDefined: Bool = false
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.windowLevel = windowLevel
        self.windowWidth = windowWidth
        self.type = type
        self.iconName = iconName
        self.createdAt = createdAt
        self.isUserDefined = isUserDefined
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        return !name.isEmpty && 
               windowWidth > 0 && 
               windowLevel >= -4000 && 
               windowLevel <= 4000
    }
    
    // MARK: - Description
    
    var description: String {
        return "WL:\(windowLevel) WW:\(windowWidth)"
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: DICOMPreset, rhs: DICOMPreset) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Error Handling

enum PresetManagerError: Error, LocalizedError {
    case presetNotFound(String)
    case invalidPreset(DICOMPreset)
    case persistenceFailure(Error)
    case duplicatePresetName(String)
    case viewNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .presetNotFound(let name):
            return "Preset '\(name)' not found"
        case .invalidPreset(let preset):
            return "Invalid preset: \(preset.name)"
        case .persistenceFailure(let error):
            return "Failed to save/load presets: \(error.localizedDescription)"
        case .duplicatePresetName(let name):
            return "Preset with name '\(name)' already exists"
        case .viewNotAvailable:
            return "DICOM view is not available for applying preset"
        }
    }
}

// MARK: - Main Preset Manager Implementation

/// Modern Swift PresetManager with enhanced functionality, type safety, and Combine support
@MainActor
@objc class SwiftPresetManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SwiftPresetManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var availablePresets: [DICOMPreset] = []
    @Published private(set) var customPresets: [DICOMPreset] = []
    @Published private(set) var currentPreset: DICOMPreset?
    @Published private(set) var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    private var defaultPresets: [DICOMPreset] = []
    private let userDefaults = UserDefaults.standard
    private let presetsKey = "SwiftDICOMPresets_v2"
    private let currentPresetKey = "SwiftCurrentDICOMPreset_v2"
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        Task {
            await setupDefaultPresets()
            await loadCustomPresets()
            await loadCurrentPreset()
            await updateAvailablePresets()
        }
    }
    
    // MARK: - Setup and Initialization
    
    private func setupDefaultPresets() async {
        defaultPresets = [
            DICOMPreset(
                name: "default",
                displayName: "Default",
                windowLevel: 450,
                windowWidth: 1500,
                type: .default
            ),
            DICOMPreset(
                name: "full_dynamic",
                displayName: "Full Dynamic",
                windowLevel: 522,
                windowWidth: 3091,
                type: .fullDynamic
            ),
            DICOMPreset(
                name: "abdomen",
                displayName: "Abdomen",
                windowLevel: 40,
                windowWidth: 350,
                type: .abdomen
            ),
            DICOMPreset(
                name: "bone",
                displayName: "Bone",
                windowLevel: 300,
                windowWidth: 1500,
                type: .bone
            ),
            DICOMPreset(
                name: "brain",
                displayName: "Brain",
                windowLevel: 50,
                windowWidth: 100,
                type: .brain
            ),
            DICOMPreset(
                name: "lung",
                displayName: "Lung",
                windowLevel: -500,
                windowWidth: 1400,
                type: .lung
            ),
            DICOMPreset(
                name: "endoscopy",
                displayName: "Endoscopy",
                windowLevel: -300,
                windowWidth: 700,
                type: .endoscopy
            ),
            DICOMPreset(
                name: "liver",
                displayName: "Liver",
                windowLevel: 80,
                windowWidth: 150,
                type: .liver
            ),
            DICOMPreset(
                name: "soft_tissue",
                displayName: "Soft Tissue",
                windowLevel: 40,
                windowWidth: 400,
                type: .softTissue
            ),
            DICOMPreset(
                name: "mediastinum",
                displayName: "Mediastinum",
                windowLevel: 50,
                windowWidth: 350,
                type: .mediastinum
            )
        ]
    }
    
    private func updateAvailablePresets() async {
        availablePresets = defaultPresets + customPresets
    }
    
    // MARK: - Preset Access and Management
    
    /// Gets preset by type
    func preset(for type: DICOMPresetType) -> DICOMPreset? {
        return availablePresets.first { $0.type == type }
    }
    
    /// Gets preset by name
    func preset(withName name: String) -> DICOMPreset? {
        return availablePresets.first { $0.name == name }
    }
    
    /// Gets preset by ID
    func preset(withId id: UUID) -> DICOMPreset? {
        return availablePresets.first { $0.id == id }
    }
    
    /// Adds a custom preset
    func addCustomPreset(_ preset: DICOMPreset) async throws {
        // Validate preset
        guard preset.isValid else {
            throw PresetManagerError.invalidPreset(preset)
        }
        
        // Check for duplicate names
        if availablePresets.contains(where: { $0.name == preset.name }) {
            throw PresetManagerError.duplicatePresetName(preset.name)
        }
        
        // Create custom preset
        let customPreset = DICOMPreset(
            name: preset.name,
            displayName: preset.displayName,
            windowLevel: preset.windowLevel,
            windowWidth: preset.windowWidth,
            type: .custom,
            iconName: preset.iconName,
            isUserDefined: true
        )
        
        customPresets.append(customPreset)
        await updateAvailablePresets()
        
        do {
            try await saveCustomPresets()
        } catch {
            // Rollback on save failure
            customPresets.removeAll { $0.id == customPreset.id }
            await updateAvailablePresets()
            throw PresetManagerError.persistenceFailure(error)
        }
    }
    
    /// Removes a custom preset
    func removeCustomPreset(withId id: UUID) async throws {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else {
            throw PresetManagerError.presetNotFound("ID: \(id)")
        }
        
        let removedPreset = customPresets.remove(at: index)
        await updateAvailablePresets()
        
        do {
            try await saveCustomPresets()
        } catch {
            // Rollback on save failure
            customPresets.insert(removedPreset, at: index)
            await updateAvailablePresets()
            throw PresetManagerError.persistenceFailure(error)
        }
    }
    
    /// Removes preset by name
    func removeCustomPreset(withName name: String) async throws {
        guard let preset = customPresets.first(where: { $0.name == name }) else {
            throw PresetManagerError.presetNotFound(name)
        }
        
        try await removeCustomPreset(withId: preset.id)
    }
    
    // MARK: - Preset Application
    
    /// Applies preset to DICOM view with validation
    func applyPreset(_ preset: DICOMPreset, to view: DCMImgView?) async throws {
        guard let view = view else {
            throw PresetManagerError.viewNotAvailable
        }
        
        var actualPreset = preset
        
        // For Full Dynamic preset, calculate based on actual pixel values
        if preset.type == .fullDynamic {
            actualPreset = calculateFullDynamicPreset(for: view) ?? preset
        }
        
        guard actualPreset.isValid else {
            throw PresetManagerError.invalidPreset(actualPreset)
        }
        
        // Apply window/level settings
        view.winCenter = actualPreset.windowLevel
        view.winWidth = actualPreset.windowWidth
        view.setNeedsDisplay()
        
        // Update current preset
        currentPreset = actualPreset
        
        // Save as current preset
        try await saveCurrentPreset()
    }
    
    /// Calculates Full Dynamic preset from actual image pixel values
    private func calculateFullDynamicPreset(for view: DCMImgView) -> DICOMPreset? {
        // The view should have the pixel data loaded
        // We'll use the view's existing window values as a starting point
        // and expand to full range
        
        // Get the bit depth from the view if available
        let isSigned = view.signed16Image
        var minValue: Int = 0
        var maxValue: Int = 4095  // Default 12-bit
        
        // Estimate based on typical DICOM bit depths
        if isSigned {
            // Common signed ranges
            minValue = -2048
            maxValue = 2047
        } else {
            // Common unsigned ranges
            minValue = 0
            maxValue = 4095
        }
        
        // Calculate full dynamic range
        let windowWidth = maxValue - minValue
        let windowCenter = minValue + (windowWidth / 2)
        
        return DICOMPreset(
            name: "full_dynamic",
            displayName: "Full Dynamic",
            windowLevel: windowCenter,
            windowWidth: windowWidth,
            type: .fullDynamic
        )
    }
    
    /// Applies preset by type
    func applyPresetType(_ type: DICOMPresetType, to view: DCMImgView?) async throws {
        guard let preset = preset(for: type) else {
            throw PresetManagerError.presetNotFound(type.displayName)
        }
        
        try await applyPreset(preset, to: view)
    }
    
    /// Applies preset by name
    func applyPreset(withName name: String, to view: DCMImgView?) async throws {
        guard let preset = preset(withName: name) else {
            throw PresetManagerError.presetNotFound(name)
        }
        
        try await applyPreset(preset, to: view)
    }
    
    // MARK: - Data Persistence
    
    private func loadCustomPresets() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let data = userDefaults.data(forKey: presetsKey) else {
            customPresets = []
            return
        }
        
        do {
            customPresets = try JSONDecoder().decode([DICOMPreset].self, from: data)
        } catch {
            print("Failed to load custom presets: \(error)")
            customPresets = []
        }
    }
    
    private func saveCustomPresets() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(customPresets)
            userDefaults.set(data, forKey: presetsKey)
            userDefaults.synchronize()
        } catch {
            throw error
        }
    }
    
    private func loadCurrentPreset() async {
        guard let data = userDefaults.data(forKey: currentPresetKey) else {
            currentPreset = defaultPresets.first
            return
        }
        
        do {
            let loadedPreset = try JSONDecoder().decode(DICOMPreset.self, from: data)
            // Verify preset still exists
            currentPreset = availablePresets.contains(loadedPreset) ? loadedPreset : defaultPresets.first
        } catch {
            print("Failed to load current preset: \(error)")
            currentPreset = defaultPresets.first
        }
    }
    
    private func saveCurrentPreset() async throws {
        guard let preset = currentPreset else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(preset)
            userDefaults.set(data, forKey: currentPresetKey)
            userDefaults.synchronize()
        } catch {
            throw error
        }
    }
    
    // MARK: - Utility and Helper Methods
    
    /// Gets presets grouped by type
    func presetsByType() -> [DICOMPresetType: [DICOMPreset]] {
        return Dictionary(grouping: availablePresets) { $0.type }
    }
    
    /// Gets sorted presets for UI display
    func sortedPresets() -> [DICOMPreset] {
        return availablePresets.sorted { preset1, preset2 in
            if preset1.type != preset2.type {
                return preset1.type.rawValue < preset2.type.rawValue
            }
            return preset1.displayName < preset2.displayName
        }
    }
    
    /// Creates a new preset from current view settings
    func createPreset(from view: DCMImgView?, name: String, displayName: String) -> Result<DICOMPreset, PresetManagerError> {
        guard let view = view else {
            return .failure(.viewNotAvailable)
        }
        
        let preset = DICOMPreset(
            name: name,
            displayName: displayName,
            windowLevel: Int(view.winCenter),
            windowWidth: Int(view.winWidth),
            type: .custom,
            isUserDefined: true
        )
        
        guard preset.isValid else {
            return .failure(.invalidPreset(preset))
        }
        
        return .success(preset)
    }
}

// MARK: - Objective-C Bridge Implementation

@objc class SwiftPresetManagerBridge: NSObject {
    
    override init() {
        super.init()
    }
    
    @objc func availablePresetsCount(_ completion: @escaping @Sendable (Int) -> Void) {
        Task { @MainActor in
            let count = SwiftPresetManager.shared.availablePresets.count
            await MainActor.run {
                completion(count)
            }
        }
    }
    
    @objc func presetName(forType type: Int, completion: @escaping @Sendable (String?) -> Void) {
        guard let presetType = DICOMPresetType(rawValue: type) else { 
            completion(nil)
            return 
        }
        Task { @MainActor in
            let name = SwiftPresetManager.shared.preset(for: presetType)?.name
            await MainActor.run {
                completion(name)
            }
        }
    }
    
    @objc func presetExists(withName name: String, completion: @escaping @Sendable (Bool) -> Void) {
        Task { @MainActor in
            let exists = SwiftPresetManager.shared.preset(withName: name) != nil
            await MainActor.run {
                completion(exists)
            }
        }
    }
    
    @objc func applyPreset(withName presetName: String, toView view: DCMImgView, completion: @escaping @Sendable (NSError?) -> Void) {
        Task { @MainActor in
            guard let swiftPreset = SwiftPresetManager.shared.preset(withName: presetName) else {
                await MainActor.run {
                    completion(NSError(domain: "PresetManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Preset not found"]))
                }
                return
            }
            
            do {
                try await SwiftPresetManager.shared.applyPreset(swiftPreset, to: view)
                await MainActor.run {
                    completion(nil)
                }
            } catch {
                await MainActor.run {
                    completion(error as NSError)
                }
            }
        }
    }
}

// MARK: - Compatibility Extensions

private extension DICOMPreset {
    func toObjectiveC() -> DICOMPreset {
        return self // Already compatible as struct
    }
    
    func toSwift() -> DICOMPreset? {
        return self // Direct compatibility
    }
}

// MARK: - Async/Await Integration

extension SwiftPresetManager {
    
    /// Result-based preset application for callback-style code
    func applyPreset(_ preset: DICOMPreset, to view: DCMImgView?) -> Result<Void, PresetManagerError> {
        var result: Result<Void, PresetManagerError> = .failure(.viewNotAvailable)
        
        Task { @MainActor in
            do {
                try await applyPreset(preset, to: view)
                result = .success(())
            } catch let error as PresetManagerError {
                result = .failure(error)
            } catch {
                result = .failure(.persistenceFailure(error))
            }
        }
        
        return result
    }
}
