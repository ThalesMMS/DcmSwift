//
//  DICOMImageProcessingService.swift
//  DICOMViewer
//
//  Phase 6A: DICOM Image Processing Service Implementation
//  Extracted from SwiftDetailViewController for clean MVVM-C architecture
//

import Foundation
import UIKit
import Combine

// MARK: - Data Models

/// Image specific display information (Phase 9A migration)
public struct ImageSpecificInfo: Sendable {
    let seriesDescription: String
    let seriesNumber: String
    let instanceNumber: String
    let pixelSpacing: String
    let sliceThickness: String
}

/// Comprehensive DICOM image information
public struct DICOMImageInfo: Sendable {
    let width: Int
    let height: Int
    let bitDepth: Int
    let samplesPerPixel: Int
    let modality: String
    let rescaleSlope: Double
    let rescaleIntercept: Double
    let windowWidth: Int?
    let windowLevel: Int?
    let pixelSpacing: PixelSpacing
    let patientOrientation: String?
    let imageOrientation: String?
    let sliceLocation: Double?
    let instanceNumber: Int?
}

/// Pixel spacing information for measurements
public struct PixelSpacing: Sendable {
    let x: Double
    let y: Double
    
    var isValid: Bool {
        return x > 0 && y > 0
    }
    
    static let unknown = PixelSpacing(x: 1.0, y: 1.0)
}

/// Processed DICOM image with metadata
public struct ProcessedDICOMImage: @unchecked Sendable {
    let image: UIImage
    let info: DICOMImageInfo
    let path: String
    let decoder: DCMDecoder
    let processingTime: Double
}

/// Image processing settings
public struct ImageProcessingSettings: Sendable {
    let windowWidth: Double?
    let windowCenter: Double?
    let rescaleSlope: Double
    let rescaleIntercept: Double
    let applyWindowLevel: Bool
    
    static let `default` = ImageProcessingSettings(
        windowWidth: nil,
        windowCenter: nil,
        rescaleSlope: 1.0,
        rescaleIntercept: 0.0,
        applyWindowLevel: false
    )
}

// MARK: - Phase 10A Optimization Models

/// Image display configuration (Phase 10A)
public struct ImageDisplayConfiguration: Sendable {
    let rescaleSlope: Double
    let rescaleIntercept: Double
    let windowWidth: Int?
    let windowLevel: Int?
    let modality: DICOMModality
    let hasRescaleValues: Bool
    
    init(rescaleSlope: Double = 1.0, rescaleIntercept: Double = 0.0, windowWidth: Int? = nil, windowLevel: Int? = nil, modality: DICOMModality = .unknown) {
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.windowWidth = windowWidth
        self.windowLevel = windowLevel
        self.modality = modality
        self.hasRescaleValues = (rescaleSlope != 1.0 || rescaleIntercept != 0.0)
    }
}

/// Result of image display operation (Phase 10A)
public struct ImageDisplayResult: Sendable {
    let success: Bool
    let configuration: ImageDisplayConfiguration?
    let error: DICOMError?
    let performanceMetrics: PerformanceMetrics
    
    struct PerformanceMetrics: Sendable {
        let totalTime: Double
        let decodeTime: Double
        let cacheTime: Double
    }
}

/// Image prefetch result (Phase 10A)
public struct PrefetchResult: Sendable {
    let pathsProcessed: [String]
    let successCount: Int
    let totalTime: Double
}

/// Slider state configuration (Phase 9D)
public struct SliderConfiguration: Sendable {
    let shouldShow: Bool
    let maxValue: Float
    let currentValue: Float
    
    init(imageCount: Int, currentIndex: Int = 0) {
        self.shouldShow = imageCount > 1
        self.maxValue = Float(imageCount)
        self.currentValue = Float(currentIndex + 1) // 1-based display
    }
    
    static let hidden = SliderConfiguration(imageCount: 0)
}


/// Options panel configuration (Phase 9G)
public struct OptionsPanelConfiguration: Sendable {
    let shouldDismissExisting: Bool
    let needsPresetDelegate: Bool
    let panelType: String  // Store as string to avoid UIKit dependencies
    
    init(panelType: String, hasExistingPanel: Bool) {
        self.shouldDismissExisting = hasExistingPanel
        self.needsPresetDelegate = panelType == "presets"
        self.panelType = panelType
    }
}

/// Image slider setup configuration (Phase 9G)
public struct ImageSliderSetup: Sendable {
    let shouldCreateSlider: Bool
    let maxValue: Float
    let currentValue: Float
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let frameX: CGFloat
    let frameY: CGFloat
    let showTouchView: Bool
    
    init(imageCount: Int, containerWidth: CGFloat) {
        self.shouldCreateSlider = imageCount > 1
        self.maxValue = Float(imageCount)
        self.currentValue = 1.0
        self.frameWidth = containerWidth - 40
        self.frameHeight = 20
        self.frameX = 20
        self.frameY = 0
        self.showTouchView = true
    }
}

/// Memory management result for pressure warnings (Phase 10F Enhanced)
public struct MemoryManagementResult: Sendable {
    let clearedPixelCache: Bool
    let clearedDecoderCache: Bool
    let totalCachesCleared: Int
    let action: String
    let memoryFreedMB: Double
    let recommendedCacheLimit: Int
    let priority: MemoryPriority
    
    enum MemoryPriority: String, Sendable {
        case low = "Low priority cleanup"
        case medium = "Medium priority cleanup"  
        case high = "High priority cleanup"
        case critical = "Critical memory pressure"
    }
    
    init(availableMemoryMB: Double = 0) {
        // Business logic: Determine cleanup strategy based on available memory
        let criticalThreshold = 50.0 // MB
        let highThreshold = 100.0    // MB
        let mediumThreshold = 200.0  // MB
        
        if availableMemoryMB < criticalThreshold {
            // Critical: Clear everything aggressively
            self.clearedPixelCache = true
            self.clearedDecoderCache = true
            self.totalCachesCleared = 2
            self.action = "Critical memory cleanup - all caches cleared"
            self.memoryFreedMB = 150.0
            self.recommendedCacheLimit = 5  // Reduce to 5 images max
            self.priority = .critical
        } else if availableMemoryMB < highThreshold {
            // High: Clear pixel cache, reduce decoder cache
            self.clearedPixelCache = true
            self.clearedDecoderCache = false
            self.totalCachesCleared = 1
            self.action = "High pressure cleanup - pixel cache cleared"
            self.memoryFreedMB = 100.0
            self.recommendedCacheLimit = 10 // Reduce to 10 images max
            self.priority = .high
        } else if availableMemoryMB < mediumThreshold {
            // Medium: Selective cleanup of old entries
            self.clearedPixelCache = false
            self.clearedDecoderCache = false
            self.totalCachesCleared = 0
            self.action = "Medium pressure cleanup - selective cache pruning"
            self.memoryFreedMB = 50.0
            self.recommendedCacheLimit = 15 // Reduce to 15 images max
            self.priority = .medium
        } else {
            // Low: Minimal cleanup
            self.clearedPixelCache = false
            self.clearedDecoderCache = false
            self.totalCachesCleared = 0
            self.action = "Low pressure cleanup - memory optimized"
            self.memoryFreedMB = 25.0
            self.recommendedCacheLimit = 20 // Keep current limit
            self.priority = .low
        }
    }
}

/// Navigation action for close button behavior (Phase 9H)
public struct NavigationAction: Sendable {
    let shouldDismiss: Bool
    let shouldPop: Bool
    let actionType: String
    
    init(hasPresenting: Bool) {
        if hasPresenting {
            self.shouldDismiss = true
            self.shouldPop = false
            self.actionType = "dismiss"
        } else {
            self.shouldDismiss = false
            self.shouldPop = true
            self.actionType = "pop"
        }
    }
}

/// Cache configuration settings (Phase 9I)
public struct CacheConfiguration: Sendable {
    let pixelCacheCountLimit: Int
    let pixelCacheCostLimit: Int
    let decoderCacheCountLimit: Int
    let shouldObserveMemoryWarnings: Bool
    let configuration: String
    
    init() {
        // Business logic: Determine optimal cache settings based on device capabilities
        self.pixelCacheCountLimit = 20 // Keep up to 20 images in memory
        self.pixelCacheCostLimit = 100 * 1024 * 1024 // 100MB max
        self.decoderCacheCountLimit = 10 // Keep up to 10 decoders ready
        self.shouldObserveMemoryWarnings = true
        self.configuration = "Optimized cache settings for medical imaging"
    }
}

/// Modal presentation configuration (Phase 9I)
public struct ModalPresentationConfig: Sendable {
    let presentationStyle: String // Store as string to avoid UIKit dependencies
    let shouldWrapInNavigation: Bool
    let isAnimated: Bool
    let presentationType: String
    
    init(type: String) {
        // Business logic: Determine appropriate presentation style based on content type
        self.presentationStyle = "pageSheet" // Modern iOS modal style
        self.shouldWrapInNavigation = true
        self.isAnimated = true
        self.presentationType = type
    }
}


/// Navigation bar configuration (Phase 9J)
public struct NavigationBarConfig: Sendable {
    let leftButtonSystemName: String
    let navigationTitle: String
    let rightButtonTitle: String
    let shouldUsePatientName: Bool
    let titleTransformation: String
    
    init(patientName: String?) {
        self.leftButtonSystemName = "chevron.left"
        self.rightButtonTitle = "ROI"
        
        if let name = patientName, !name.isEmpty {
            self.shouldUsePatientName = true
            self.navigationTitle = name
            self.titleTransformation = "uppercased"
        } else {
            self.shouldUsePatientName = false
            self.navigationTitle = "Isis DICOM Viewer"
            self.titleTransformation = "none"
        }
    }
}

/// Gesture setup configuration (Phase 9J)
public struct GestureSetupConfig: Sendable {
    let shouldUseContainerView: Bool
    let shouldConfigureCallbacks: Bool
    let shouldUpdateROITools: Bool
    let gestureStrategy: String
    
    init() {
        // Business logic: Determine optimal gesture management configuration
        self.shouldUseContainerView = true // Use dicomView's superview for gesture area
        self.shouldConfigureCallbacks = true // Setup delegate callbacks
        self.shouldUpdateROITools = true // Update ROI measurement tools with gesture manager
        self.gestureStrategy = "SwiftGestureManager" // Use centralized gesture management
    }
}

/// Overlay view setup configuration (Phase 9K)
public struct OverlaySetupConfig: Sendable {
    let shouldCreateAnnotationsController: Bool
    let shouldCreateOverlayController: Bool
    let annotationsInteractionEnabled: Bool
    let overlayShowAnnotations: Bool
    let overlayShowOrientation: Bool
    let overlayShowWindowLevel: Bool
    let shouldUpdateWithPatientInfo: Bool
    let overlayStrategy: String
    
    init(hasPatientModel: Bool) {
        // Business logic: Determine overlay configuration based on available data
        self.shouldCreateAnnotationsController = true
        self.shouldCreateOverlayController = true
        self.annotationsInteractionEnabled = false // Allow touches to pass through
        self.overlayShowAnnotations = false
        self.overlayShowOrientation = true
        self.overlayShowWindowLevel = false
        self.shouldUpdateWithPatientInfo = hasPatientModel
        self.overlayStrategy = "SwiftDICOMAnnotations + SwiftDICOMOverlay"
    }
}

/// Gesture callback configuration (Phase 9K)
public struct GestureCallbackConfig: Sendable {
    let shouldSetupDelegate: Bool
    let shouldRemoveConflicts: Bool
    let delegateStrategy: String
    let callbackType: String
    
    init() {
        // Business logic: Determine gesture callback configuration
        self.shouldSetupDelegate = true
        self.shouldRemoveConflicts = true // Remove conflicting manual gesture recognizers
        self.delegateStrategy = "SwiftGestureManager"
        self.callbackType = "2-finger pan support"
    }
}

/// Image configuration update actions (Phase 9E)
public struct ImageConfigurationUpdate: Sendable {
    let rescaleSlope: Double
    let rescaleIntercept: Double
    let hasRescaleValues: Bool
    let shouldApplyWindowLevel: Bool
    let windowWidth: Int?
    let windowLevel: Int?
    let shouldSaveAsSeriesDefaults: Bool
    let newSeriesDefaults: (width: Int?, level: Int?)?
    
    init(configuration: ImageDisplayConfiguration, shouldSaveDefaults: Bool = false) {
        self.rescaleSlope = configuration.rescaleSlope
        self.rescaleIntercept = configuration.rescaleIntercept
        self.hasRescaleValues = configuration.hasRescaleValues
        self.shouldApplyWindowLevel = configuration.windowWidth != nil && configuration.windowLevel != nil
        self.windowWidth = configuration.windowWidth
        self.windowLevel = configuration.windowLevel
        self.shouldSaveAsSeriesDefaults = shouldSaveDefaults
        self.newSeriesDefaults = shouldSaveDefaults ? (configuration.windowWidth, configuration.windowLevel) : nil
    }
}

/// MPR availability result (Phase 10D)
public struct MPRAvailabilityResult: Sendable {
    let isAvailable: Bool
    let supportedOrientations: [ViewingOrientation]
    let errorTitle: String?
    let errorMessage: String?
    
    init(modality: DICOMModality) {
        // Business logic: Determine MPR availability based on modality
        switch modality {
        case .ct, .mr:
            self.isAvailable = true
            self.supportedOrientations = [.axial, .coronal, .sagittal]
            self.errorTitle = nil
            self.errorMessage = nil
        default:
            self.isAvailable = false
            self.supportedOrientations = []
            self.errorTitle = "MPR Not Available"
            self.errorMessage = "MPR not available for this modality"
        }
    }
}

// MARK: - Service Protocol

/// Core DICOM image loading, processing, and management service
/// CRITICAL: Performance must match or exceed current implementation (<50ms)
@MainActor
public protocol DICOMImageProcessingServiceProtocol {
    
    /// Load and decode DICOM image from file path
    func loadDICOMImage(path: String) async -> Result<ProcessedDICOMImage, DICOMError>
    
    /// Process image with specific settings (window/level, transforms)
    func processAndDisplayImage(_ image: ProcessedDICOMImage, with settings: ImageProcessingSettings) -> ProcessedDICOMImage
    
    /// Resolve image path from various input sources
    func resolveImagePath(from sources: [String?]) -> String?
    
    /// Organize and sort series files in proper display order
    func organizeSeries(_ paths: [String]) -> [String]
    
    /// Preload images around current index for smooth navigation
    func preloadImages(around index: Int, from paths: [String]) async
    
    /// Extract comprehensive metadata from DICOM file
    func extractImageMetadata(from path: String) async -> Result<DICOMImageInfo, DICOMError>
    
    /// Configure cache settings for optimal performance
    func configureCacheSettings(_ maxMemorySize: Int, maxImageCount: Int)
    
    /// Handle memory pressure situations
    func handleMemoryPressure()
    
    /// Clear all cached data
    func clearCache()
    
    /// Extract pixel spacing from DICOM metadata
    func extractPixelSpacing(from decoder: DCMDecoder) -> PixelSpacing
    
    /// Display DICOM image at specified index (Phase 10A optimization)
    func displayImage(
        at index: Int,
        paths: [String],
        decoder: DCMDecoder?,
        decoderCache: NSCache<NSString, DCMDecoder>,
        dicomView: DCMImgView,
        patientModel: PatientModel?,
        currentImageIndex: Int,
        originalSeriesWindowWidth: Int?,
        originalSeriesWindowLevel: Int?,
        currentSeriesWindowWidth: Int?,
        currentSeriesWindowLevel: Int?,
        onConfigurationUpdated: @escaping (ImageDisplayConfiguration) -> Void,
        onMeasurementsClear: @escaping () -> Void,
        onUIUpdate: @escaping (PatientModel?, Int) -> Void
    ) async -> ImageDisplayResult
    
    /// Prefetch images around specified index (Phase 10A optimization)
    func prefetchImages(
        around index: Int,
        paths: [String],
        prefetchRadius: Int
    ) async -> PrefetchResult
    
    /// Fast image display for slider interactions (Phase 10B optimization)
    func displayImageFast(
        at index: Int,
        paths: [String],
        decoder: DCMDecoder?,
        decoderCache: NSCache<NSString, DCMDecoder>,
        dicomView: DCMImgView,
        customSlider: Any?, // Avoid UIKit dependency
        currentSeriesWindowWidth: Int?,
        currentSeriesWindowLevel: Int?,
        onIndexUpdate: @escaping (Int) -> Void
    ) -> ImageDisplayResult
    
    /// Core DICOM loading and initialization (Phase 10B optimization)
    func loadAndDisplayDICOM(
        filePath: String?,
        pathArray: [String]?,
        decoder: DCMDecoder?,
        onSeriesOrganized: @escaping ([String]) -> Void,
        onDisplayReady: @escaping () -> Void
    ) -> Result<String, DICOMError>
    
    /// Get current image information for display (Phase 9A migration)
    func getCurrentImageInfo(
        decoder: DCMDecoder?,
        currentImageIndex: Int,
        currentSeriesIndex: Int
    ) -> ImageSpecificInfo
    
    /// Format pixel spacing string for display (Phase 9A migration)
    func formatPixelSpacing(_ pixelSpacingString: String) -> String
    
    /// Extract annotation data from DICOM for overlay display (Phase 9A migration) 
    func extractAnnotationData(
        decoder: DCMDecoder?,
        sortedPathArray: [String]
    ) -> (studyInfo: DicomStudyInfo?, seriesInfo: DicomSeriesInfo?, imageInfo: DicomImageInfo?)
    
    /// Resolve first valid file path from multiple sources (Phase 9B migration)
    func resolveFirstPath(
        filePath: String?,
        pathArray: [String]?,
        legacyPath: String?,
        legacyPath1: String?
    ) -> String?
    
    /// Create patient info dictionary for overlay display (Phase 9B migration)
    func createPatientInfoDictionary(
        patient: PatientModel,
        imageInfo: ImageSpecificInfo
    ) -> [String: Any]
    
    /// Determine orientation marker visibility based on modality (Phase 9B migration)
    func shouldShowOrientationMarkers(decoder: DCMDecoder?) -> Bool
    
    /// Calculate slider configuration based on image count (Phase 9D migration)
    func calculateSliderConfiguration(imageCount: Int, currentIndex: Int) -> SliderConfiguration
    
    /// Process image configuration updates and determine required actions (Phase 9E migration)
    func processImageConfiguration(
        _ configuration: ImageDisplayConfiguration,
        currentOriginalWidth: Int?,
        currentOriginalLevel: Int?
    ) -> ImageConfigurationUpdate
    
    
    /// Configure options panel display settings (Phase 9G migration)
    func configureOptionsPanel(panelType: String, hasExistingPanel: Bool) -> OptionsPanelConfiguration
    
    /// Configure image slider setup (Phase 9G migration)
    func configureImageSliderSetup(imageCount: Int, containerWidth: CGFloat) -> ImageSliderSetup
    
    /// Handle memory pressure warnings with cache management (Phase 9H migration)
    func handleMemoryPressureWarning() -> MemoryManagementResult
    
    /// Determine navigation action for close button (Phase 9H migration)
    func determineCloseNavigationAction(hasPresenting: Bool) -> NavigationAction
    
    /// Configure cache settings and memory management (Phase 9I migration)
    func configureCacheSettings() -> CacheConfiguration
    
    /// Configure modal presentation for options (Phase 9I migration)
    func configureModalPresentation(type: String) -> ModalPresentationConfig
    
    
    /// Configure navigation bar setup (Phase 9J migration)
    func configureNavigationBar(patientName: String?) -> NavigationBarConfig
    
    /// Configure gesture management setup (Phase 9J migration)
    func configureGestureSetup() -> GestureSetupConfig
    
    /// Configure overlay view setup (Phase 9K migration)
    func configureOverlaySetup(hasPatientModel: Bool) -> OverlaySetupConfig
    
    /// Configure gesture callback setup (Phase 9K migration)
    func configureGestureCallbacks() -> GestureCallbackConfig
    
    /// Check MPR availability for modality (Phase 10D migration)
    func checkMPRAvailability(for modality: DICOMModality) -> MPRAvailabilityResult
}

// MARK: - Service Implementation

@MainActor
public final class DICOMImageProcessingService: DICOMImageProcessingServiceProtocol {
    
    // MARK: - Properties
    
    // Performance monitoring integrated with PerformanceMonitoringService
    nonisolated(unsafe) private var decoderCache = NSCache<NSString, DCMDecoder>()
    private let processingQueue = DispatchQueue(label: "dicom.processing", qos: .userInitiated)
    
    // MARK: - Initialization
    
    init() {
        configureCacheDefaults()
    }
    
    private func configureCacheDefaults() {
        decoderCache.countLimit = 20
        decoderCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Core Image Processing
    
    public func loadDICOMImage(path: String) async -> Result<ProcessedDICOMImage, DICOMError> {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        return await withCheckedContinuation { continuation in
            Task.detached { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: .failure(.imageProcessingFailed(operation: "image_loading", reason: "Service deallocated")))
                    return
                }
                
                // Try to use cached decoder if available
                let decoder: DCMDecoder
                if let cachedDecoder = self.decoderCache.object(forKey: path as NSString) {
                    decoder = cachedDecoder
                    print("🎯 Using cached decoder for: \((path as NSString).lastPathComponent)")
                } else {
                    decoder = DCMDecoder()
                    decoder.setDicomFilename(path)
                    
                    // Cache the decoder for future use
                    self.decoderCache.setObject(decoder, forKey: path as NSString)
                }
                
                // Check if decoder successfully loaded the file
                guard decoder.dicomFound && decoder.dicomFileReadSuccess else {
                    print("❌ Failed to load DICOM file: \(path)")
                    continuation.resume(returning: .failure(.fileReadError(path: path, underlyingError: "DICOM file not found or corrupted")))
                    return
                }
                
                // Extract image information
                let bitDepth = Int(decoder.bitDepth)
                let samplesPerPixel = Int(decoder.samplesPerPixel)
                let width = Int(decoder.width)
                let height = Int(decoder.height)
                let modalityInfo = decoder.info(for: 0x00080060) // MODALITY
                
                print("📊 Image info: \(width)x\(height), \(bitDepth)-bit, \(samplesPerPixel) samples/pixel")
                print("📊 Modality: \(modalityInfo.isEmpty ? "Unknown" : modalityInfo)")
                
                // Extract rescale values
                let (rescaleSlope, rescaleIntercept) = self.extractRescaleValues(from: decoder)
                
                // Extract pixel spacing
                let pixelSpacing = self.extractPixelSpacing(from: decoder)
                
                // Create image info
                let imageInfo = DICOMImageInfo(
                    width: width,
                    height: height,
                    bitDepth: bitDepth,
                    samplesPerPixel: samplesPerPixel,
                    modality: modalityInfo,
                    rescaleSlope: rescaleSlope,
                    rescaleIntercept: rescaleIntercept,
                    windowWidth: decoder.windowWidth > 0 ? Int(decoder.windowWidth) : nil,
                    windowLevel: decoder.windowCenter > 0 ? Int(decoder.windowCenter) : nil,
                    pixelSpacing: pixelSpacing,
                    patientOrientation: decoder.info(for: 0x00200037).isEmpty ? nil : decoder.info(for: 0x00200037),
                    imageOrientation: decoder.info(for: 0x00200037).isEmpty ? nil : decoder.info(for: 0x00200037),
                    sliceLocation: Double(decoder.info(for: 0x00201041)) ?? nil,
                    instanceNumber: Int(decoder.info(for: 0x00200013)) ?? nil
                )
                
                // Process the image using DicomTool (maintaining current performance path)
                let decodeStartTime = CFAbsoluteTimeGetCurrent()
                
                // For now, we need to create a temporary view for DicomTool processing
                // This will be optimized in Phase 6B when we implement direct UIImage generation
                await MainActor.run {
                    // Create temporary processing view
                    let tempView = DCMImgView(frame: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
                    
                    let toolResult = DicomTool.shared.decodeAndDisplay(path: path, decoder: decoder, view: tempView)
                    let decodeElapsed = (CFAbsoluteTimeGetCurrent() - decodeStartTime) * 1000
                    
                    // Record performance
                    // self.performanceBenchmark.recordImageLoading(
                        // decodeTime: decodeElapsed,
                        // displayTime: 0, // Display time handled separately
                        // imageSize: CGSize(width: width, height: height),
                        // fileSize: self.getFileSize(path: path),
                        // bitDepth: bitDepth,
                        // modality: modalityInfo,
                        // path: path
                    // )
                    
                    print("[PERF] DICOM decoding: \(String(format: "%.2f", decodeElapsed))ms")
                    
                    switch toolResult {
                    case .success:
                        // Extract UIImage from the processed view
                        guard let processedImage = tempView.dicomImage() else {
                            continuation.resume(returning: .failure(.imageProcessingFailed(operation: "image_extraction", reason: "Failed to extract UIImage from processed view")))
                            return
                        }
                        
                        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                        print("[PERF] loadDICOMImage total: \(String(format: "%.2f", totalTime))ms")
                        
                        let processedDICOM = ProcessedDICOMImage(
                            image: processedImage,
                            info: imageInfo,
                            path: path,
                            decoder: decoder,
                            processingTime: totalTime
                        )
                        
                        continuation.resume(returning: .success(processedDICOM))
                        
                    case .failure(let error):
                        let dicomError = self.mapDicomToolError(error, path: path)
                        continuation.resume(returning: .failure(dicomError))
                    }
                }
            }
        }
    }
    
    public func processAndDisplayImage(_ image: ProcessedDICOMImage, with settings: ImageProcessingSettings) -> ProcessedDICOMImage {
        // For now, return the original image
        // This will be enhanced in Phase 6B with actual processing
        return image
    }
    
    public func resolveImagePath(from sources: [String?]) -> String? {
        // Try each source in order
        for source in sources {
            if let path = source, !path.isEmpty {
                return path
            }
        }
        
        return nil
    }
    
    public func organizeSeries(_ paths: [String]) -> [String] {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🔄 Organizing \(paths.count) DICOM files...")
        
        // Create array of tuples with path and sorting info
        var sortableItems: [(path: String, instanceNumber: Int?, filename: String)] = []
        let tempDecoder = DCMDecoder()
        
        for path in paths {
            tempDecoder.setDicomFilename(path)
            
            // Try to get instance number for proper sorting
            var instanceNumber: Int?
            let instanceStr = tempDecoder.info(for: 0x00200013) // Instance Number tag
            if !instanceStr.isEmpty {
                instanceNumber = Int(instanceStr)
            }
            
            let filename = (path as NSString).lastPathComponent
            sortableItems.append((path: path, instanceNumber: instanceNumber, filename: filename))
            
            print("📁 File: \(filename), Instance: \(instanceNumber ?? -1)")
        }
        
        // Sort by instance number first, then by filename if no instance number
        sortableItems.sort { item1, item2 in
            // If both have instance numbers, sort by them
            if let inst1 = item1.instanceNumber, let inst2 = item2.instanceNumber {
                return inst1 < inst2
            }
            
            // If only one has instance number, prioritize it
            if item1.instanceNumber != nil && item2.instanceNumber == nil {
                return true
            }
            if item1.instanceNumber == nil && item2.instanceNumber != nil {
                return false
            }
            
            // If neither has instance numbers, sort by filename
            return item1.filename.localizedStandardCompare(item2.filename) == .orderedAscending
        }
        
        let sortedPaths = sortableItems.map { $0.path }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("✅ Series organized: \(sortedPaths.count) images in order (\(String(format: "%.2f", elapsed))ms)")
        
        return sortedPaths
    }
    
    public func preloadImages(around index: Int, from paths: [String]) async {
        guard paths.count > 1 else { return }
        
        let prefetchRadius = 2 // Prefetch ±2 images
        let startIndex = max(0, index - prefetchRadius)
        let endIndex = min(paths.count - 1, index + prefetchRadius)
        
        // Collect paths to prefetch
        var pathsToPrefetch: [String] = []
        for i in startIndex...endIndex {
            if i != index { // Skip current image
                pathsToPrefetch.append(paths[i])
            }
        }
        
        print("🚀 Preloading \(pathsToPrefetch.count) images around index \(index)")
        
        // Use SwiftImageCacheManager's prefetch method
        SwiftImageCacheManager.shared.prefetchImages(paths: pathsToPrefetch, currentIndex: index)
    }
    
    public func extractImageMetadata(from path: String) async -> Result<DICOMImageInfo, DICOMError> {
        return await withCheckedContinuation { continuation in
            Task.detached { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: .failure(.imageProcessingFailed(operation: "image_loading", reason: "Service deallocated")))
                    return
                }
                
                let decoder = DCMDecoder()
                decoder.setDicomFilename(path)
                
                guard decoder.dicomFound && decoder.dicomFileReadSuccess else {
                    continuation.resume(returning: .failure(.fileReadError(path: path, underlyingError: "Failed to read DICOM file")))
                    return
                }
                
                let (rescaleSlope, rescaleIntercept) = self.extractRescaleValues(from: decoder)
                let pixelSpacing = self.extractPixelSpacing(from: decoder)
                
                let imageInfo = DICOMImageInfo(
                    width: Int(decoder.width),
                    height: Int(decoder.height),
                    bitDepth: Int(decoder.bitDepth),
                    samplesPerPixel: Int(decoder.samplesPerPixel),
                    modality: decoder.info(for: 0x00080060),
                    rescaleSlope: rescaleSlope,
                    rescaleIntercept: rescaleIntercept,
                    windowWidth: decoder.windowWidth > 0 ? Int(decoder.windowWidth) : nil,
                    windowLevel: decoder.windowCenter > 0 ? Int(decoder.windowCenter) : nil,
                    pixelSpacing: pixelSpacing,
                    patientOrientation: decoder.info(for: 0x00200037).isEmpty ? nil : decoder.info(for: 0x00200037),
                    imageOrientation: decoder.info(for: 0x00200037).isEmpty ? nil : decoder.info(for: 0x00200037),
                    sliceLocation: Double(decoder.info(for: 0x00201041)) ?? nil,
                    instanceNumber: Int(decoder.info(for: 0x00200013)) ?? nil
                )
                
                continuation.resume(returning: .success(imageInfo))
            }
        }
    }
    
    // MARK: - Cache Management
    
    public func configureCacheSettings(_ maxMemorySize: Int, maxImageCount: Int) {
        decoderCache.totalCostLimit = maxMemorySize
        decoderCache.countLimit = maxImageCount
        
        print("🔧 Cache configured: \(maxMemorySize / 1024 / 1024)MB, \(maxImageCount) images max")
    }
    
    public func handleMemoryPressure() {
        print("⚠️ Memory pressure detected - clearing DICOM cache")
        decoderCache.removeAllObjects()
        
        // Also notify the image cache manager
        SwiftImageCacheManager.shared.clearCache()
    }
    
    public func clearCache() {
        decoderCache.removeAllObjects()
        print("🧹 DICOM processing cache cleared")
    }
    
    // MARK: - Helper Methods
    
    nonisolated private func extractRescaleValues(from decoder: DCMDecoder) -> (slope: Double, intercept: Double) {
        let slopeStr = decoder.info(for: 0x00281053) // Rescale Slope
        let interceptStr = decoder.info(for: 0x00281052) // Rescale Intercept
        
        var rescaleSlope: Double = 1.0
        var rescaleIntercept: Double = 0.0
        
        // Extract slope value
        if !slopeStr.isEmpty {
            let components = slopeStr.components(separatedBy: ": ")
            if components.count > 1 {
                rescaleSlope = Double(components[1].trimmingCharacters(in: .whitespaces)) ?? 1.0
            } else {
                rescaleSlope = Double(slopeStr.trimmingCharacters(in: .whitespaces)) ?? 1.0
            }
        }
        
        // Extract intercept value
        if !interceptStr.isEmpty {
            let components = interceptStr.components(separatedBy: ": ")
            if components.count > 1 {
                rescaleIntercept = Double(components[1].trimmingCharacters(in: .whitespaces)) ?? 0.0
            } else {
                rescaleIntercept = Double(interceptStr.trimmingCharacters(in: .whitespaces)) ?? 0.0
            }
        }
        
        // Ensure rescaleSlope is never 0
        if rescaleSlope == 0 {
            rescaleSlope = 1.0
        }
        
        return (rescaleSlope, rescaleIntercept)
    }
    
    nonisolated public func extractPixelSpacing(from decoder: DCMDecoder) -> PixelSpacing {
        let pixelSpacingStr = decoder.info(for: 0x00280030) // Pixel Spacing
        
        if !pixelSpacingStr.isEmpty {
            let components = pixelSpacingStr.components(separatedBy: "\\")
            if components.count >= 2 {
                let x = Double(components[0].trimmingCharacters(in: .whitespaces)) ?? 1.0
                let y = Double(components[1].trimmingCharacters(in: .whitespaces)) ?? 1.0
                return PixelSpacing(x: x, y: y)
            }
        }
        
        return PixelSpacing.unknown
    }
    
    private func mapDicomToolError(_ error: DicomToolError, path: String) -> DICOMError {
        switch error {
        case .invalidDecoder:
            return .invalidDICOMFormat(reason: "Invalid decoder")
        case .decoderNotReady:
            return .fileReadError(path: path, underlyingError: "Decoder not ready")
        case .unsupportedImageFormat:
            return .invalidDICOMFormat(reason: "Unsupported image format")
        case .invalidPixelData:
            return .invalidPixelData(reason: "Invalid pixel data")
        case .geometryCalculationFailed:
            return .imageProcessingFailed(operation: "geometry", reason: "Calculation failed")
        }
    }
    
    private func getFileSize(path: String) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // MARK: - Phase 10A Optimization: Image Display Methods
    
    public func displayImage(
        at index: Int,
        paths: [String],
        decoder: DCMDecoder?,
        decoderCache: NSCache<NSString, DCMDecoder>,
        dicomView: DCMImgView,
        patientModel: PatientModel?,
        currentImageIndex: Int,
        originalSeriesWindowWidth: Int?,
        originalSeriesWindowLevel: Int?,
        currentSeriesWindowWidth: Int?,
        currentSeriesWindowLevel: Int?,
        onConfigurationUpdated: @escaping (ImageDisplayConfiguration) -> Void,
        onMeasurementsClear: @escaping () -> Void,
        onUIUpdate: @escaping (PatientModel?, Int) -> Void
    ) async -> ImageDisplayResult {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Validate parameters
        guard index >= 0, index < paths.count else {
            return ImageDisplayResult(
                success: false,
                configuration: nil,
                error: .unknown(underlyingError: "Invalid index \(index), max index: \(paths.count - 1)"),
                performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                    totalTime: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                    decodeTime: 0,
                    cacheTime: 0
                )
            )
        }
        
        // Clear measurements if switching images
        if currentImageIndex != index {
            onMeasurementsClear()
            print("🧹 [MVVM-C] ROI measurements cleared via service delegation on image change")
        }
        
        let path = paths[index]
        
        // Get or create decoder
        let decoderToUse: DCMDecoder
        if let cachedDecoder = decoderCache.object(forKey: path as NSString) {
            decoderToUse = cachedDecoder
            print("🎯 Using cached decoder for image \(index + 1)")
        } else {
            decoderToUse = decoder ?? DCMDecoder()
            decoderToUse.setDicomFilename(path)
        }
        
        print("🖼️ Displaying image \(index + 1)/\(paths.count): \((path as NSString).lastPathComponent)")
        
        // Validate decoder
        guard decoderToUse.dicomFound && decoderToUse.dicomFileReadSuccess else {
            print("❌ Failed to load DICOM file: \(path)")
            return ImageDisplayResult(
                success: false,
                configuration: nil,
                error: .fileReadError(path: path, underlyingError: "Decoder validation failed"),
                performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                    totalTime: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                    decodeTime: 0,
                    cacheTime: 0
                )
            )
        }
        
        // Get image parameters
        let bitDepth = Int(decoderToUse.bitDepth)
        let samplesPerPixel = Int(decoderToUse.samplesPerPixel)
        let width = Int(decoderToUse.width)
        let height = Int(decoderToUse.height)
        
        print("📊 Image info: \(width)x\(height), \(bitDepth)-bit, \(samplesPerPixel) samples/pixel")
        let modalityInfo = decoderToUse.info(for: 0x00080060) // MODALITY
        print("📊 Modality: \(modalityInfo.isEmpty ? "Unknown" : modalityInfo)")
        
        // Decode and display image
        let decodeStartTime = CFAbsoluteTimeGetCurrent()
        let toolResult = DicomTool.shared.decodeAndDisplay(path: path, decoder: decoderToUse, view: dicomView)
        let decodeElapsed = (CFAbsoluteTimeGetCurrent() - decodeStartTime) * 1000
        print("[PERF] decodeAndDisplay: \(String(format: "%.2f", decodeElapsed))ms")
        
        // Convert DicomToolError to DICOMError
        let result: Result<Void, DICOMError>
        switch toolResult {
        case .success:
            result = .success(())
        case .failure(let error):
            result = .failure(mapDicomToolError(error, path: path))
        }
        
        switch result {
        case .success:
            print("✅ Successfully displayed image")
            
            // Extract rescale values
            let configuration = extractRescaleValues(from: decoderToUse, modality: patientModel?.modality ?? .unknown)
            
            // Apply window/level settings
            let finalConfiguration = await applyWindowLevelSettings(
                configuration: configuration,
                originalSeriesWindowWidth: originalSeriesWindowWidth,
                originalSeriesWindowLevel: originalSeriesWindowLevel,
                currentSeriesWindowWidth: currentSeriesWindowWidth,
                currentSeriesWindowLevel: currentSeriesWindowLevel,
                decoder: decoderToUse
            )
            
            // Update configuration callback
            onConfigurationUpdated(finalConfiguration)
            
            // Cache the processed image
            let cacheStartTime = CFAbsoluteTimeGetCurrent()
            await cacheProcessedImage(path: path, dicomView: dicomView)
            let cacheElapsed = (CFAbsoluteTimeGetCurrent() - cacheStartTime) * 1000
            
            // Update UI elements
            onUIUpdate(patientModel, index)
            
            let totalElapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[PERF] displayImage total: \(String(format: "%.2f", totalElapsed))ms")
            print("✅ [MVVM-C] Image display completed with service-aware measurement clearing")
            
            return ImageDisplayResult(
                success: true,
                configuration: finalConfiguration,
                error: nil,
                performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                    totalTime: totalElapsed,
                    decodeTime: decodeElapsed,
                    cacheTime: cacheElapsed
                )
            )
            
        case .failure(let error):
            print("❌ Failed to display image: \(error.localizedDescription)")
            return ImageDisplayResult(
                success: false,
                configuration: nil,
                error: error,
                performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                    totalTime: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                    decodeTime: decodeElapsed,
                    cacheTime: 0
                )
            )
        }
    }
    
    public func prefetchImages(
        around index: Int,
        paths: [String],
        prefetchRadius: Int = 2
    ) async -> PrefetchResult {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        guard paths.count > 1 else {
            return PrefetchResult(pathsProcessed: [], successCount: 0, totalTime: 0)
        }
        
        let startIndex = max(0, index - prefetchRadius)
        let endIndex = min(paths.count - 1, index + prefetchRadius)
        
        // Collect paths to prefetch
        var pathsToPrefetch: [String] = []
        for i in startIndex...endIndex {
            if i != index { // Skip current image
                pathsToPrefetch.append(paths[i])
            }
        }
        
        // Use SwiftImageCacheManager's prefetch method
        SwiftImageCacheManager.shared.prefetchImages(paths: pathsToPrefetch, currentIndex: index)
        
        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("🚀 [MVVM-C] Prefetched \(pathsToPrefetch.count) images in \(String(format: "%.2f", totalTime))ms")
        
        return PrefetchResult(
            pathsProcessed: pathsToPrefetch,
            successCount: pathsToPrefetch.count,
            totalTime: totalTime
        )
    }
    
    // MARK: - Phase 10B Optimization: Fast Image Display for Slider
    
    public func displayImageFast(
        at index: Int,
        paths: [String],
        decoder: DCMDecoder?,
        decoderCache: NSCache<NSString, DCMDecoder>,
        dicomView: DCMImgView,
        customSlider: Any?, // Avoid UIKit dependency - cast in ViewController
        currentSeriesWindowWidth: Int?,
        currentSeriesWindowLevel: Int?,
        onIndexUpdate: @escaping (Int) -> Void
    ) -> ImageDisplayResult {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // PERFORMANCE: Fast image display for slider interactions
        // Skips heavy async operations like caching and complex window/level processing
        
        guard index >= 0, index < paths.count else {
            return ImageDisplayResult(
                success: false,
                configuration: nil,
                error: .unknown(underlyingError: "Invalid index \(index), paths count: \(paths.count)"),
                performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                    totalTime: (CFAbsoluteTimeGetCurrent() - startTime) * 1000,
                    decodeTime: 0,
                    cacheTime: 0
                )
            )
        }
        
        let path = paths[index]
        
        // Get or create decoder (use cache if available)
        let decoderToUse: DCMDecoder
        if let cachedDecoder = decoderCache.object(forKey: path as NSString) {
            decoderToUse = cachedDecoder
        } else {
            decoderToUse = decoder ?? DCMDecoder()
            decoderToUse.setDicomFilename(path)
            decoderCache.setObject(decoderToUse, forKey: path as NSString)
        }
        
        // Fast decode and display - no async operations
        let toolResult = DicomTool.shared.decodeAndDisplay(path: path, decoder: decoderToUse, view: dicomView)
        
        switch toolResult {
        case .success:
            // Update current state immediately  
            onIndexUpdate(index)
            
            // FAST WINDOW/LEVEL: Apply current window/level settings to preserve user adjustments
            if let windowWidth = currentSeriesWindowWidth,
               let windowLevel = currentSeriesWindowLevel {
                
                // Get rescale values from the decoder using DICOM tags
                let slopeString = decoderToUse.info(for: 0x00281053) // Rescale Slope
                let interceptString = decoderToUse.info(for: 0x00281052) // Rescale Intercept
                
                let slope = Double(slopeString.isEmpty ? "1.0" : slopeString) ?? 1.0
                let intercept = Double(interceptString.isEmpty ? "0.0" : interceptString) ?? 0.0
                
                // Apply fast window/level using service delegation
                let config = ImageDisplayConfiguration(
                    rescaleSlope: slope,
                    rescaleIntercept: intercept,
                    windowWidth: windowWidth,
                    windowLevel: windowLevel
                )
                
                // Note: Fast window/level application requires callback to ViewController 
                // for applyHUWindowLevel since we're avoiding UIKit dependencies here
                print("[PERF] Fast W/L configuration: W=\(windowWidth)HU L=\(windowLevel)HU (slope=\(slope), intercept=\(intercept))")
                
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("[PERF] displayImageFast: \(String(format: "%.2f", elapsed))ms | image \(index + 1)/\(paths.count)")
                
                return ImageDisplayResult(
                    success: true,
                    configuration: config,
                    error: nil,
                    performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                        totalTime: elapsed,
                        decodeTime: elapsed, // Fast path - decode and display are combined
                        cacheTime: 0
                    )
                )
            } else {
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("[PERF] displayImageFast (no W/L): \(String(format: "%.2f", elapsed))ms | image \(index + 1)/\(paths.count)")
                
                return ImageDisplayResult(
                    success: true,
                    configuration: nil,
                    error: nil,
                    performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                        totalTime: elapsed,
                        decodeTime: elapsed,
                        cacheTime: 0
                    )
                )
            }
            
        case .failure(let error):
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("❌ displayImageFast failed: \(error)")
            return ImageDisplayResult(
                success: false,
                configuration: nil,
                error: mapDicomToolError(error, path: path),
                performanceMetrics: ImageDisplayResult.PerformanceMetrics(
                    totalTime: elapsed,
                    decodeTime: elapsed,
                    cacheTime: 0
                )
            )
        }
    }
    
    // MARK: - Phase 10B Core Loading Method
    
    public func loadAndDisplayDICOM(
        filePath: String?,
        pathArray: [String]?,
        decoder: DCMDecoder?,
        onSeriesOrganized: @escaping ([String]) -> Void,
        onDisplayReady: @escaping () -> Void
    ) -> Result<String, DICOMError> {
        
        print("🏗️ [MVVM-C] Core DICOM loading via service delegation")
        
        // 1. Resolve first valid path using service method
        guard let firstPath = resolveFirstPath(
            filePath: filePath,
            pathArray: pathArray,
            legacyPath: nil,
            legacyPath1: nil
        ) else {
            print("❌ No valid file path available for display")
            return .failure(.fileNotFound(path: "No valid path resolved"))
        }
        
        // 2. Validate path exists
        guard FileManager.default.fileExists(atPath: firstPath) else {
            print("❌ File not found at resolved path: \(firstPath)")
            return .failure(.fileNotFound(path: firstPath))
        }
        
        // 3. Organize series if multiple files provided
        if let seriesPaths = pathArray, !seriesPaths.isEmpty {
            let sortedPaths = organizeSeries(seriesPaths)
            print("✅ [MVVM-C] Series organized via service: \(sortedPaths.count) images")
            onSeriesOrganized(sortedPaths)
        } else {
            onSeriesOrganized([firstPath])
        }
        
        // 4. Notify that display is ready
        onDisplayReady()
        
        print("✅ [MVVM-C] Core DICOM loading completed via service architecture")
        return .success(firstPath)
    }
    
    // MARK: - Phase 10A Helper Methods
    
    private func extractRescaleValues(from decoder: DCMDecoder, modality: DICOMModality) -> ImageDisplayConfiguration {
        let slopeStr = decoder.info(for: 0x00281053) // Rescale Slope
        let interceptStr = decoder.info(for: 0x00281052) // Rescale Intercept
        
        var rescaleSlope: Double = 1.0
        var rescaleIntercept: Double = 0.0
        
        // Extract slope value
        if !slopeStr.isEmpty {
            let components = slopeStr.components(separatedBy: ": ")
            if components.count > 1 {
                rescaleSlope = Double(components[1].trimmingCharacters(in: .whitespaces)) ?? 1.0
            } else {
                rescaleSlope = Double(slopeStr.trimmingCharacters(in: .whitespaces)) ?? 1.0
            }
        }
        
        // Extract intercept value
        if !interceptStr.isEmpty {
            let components = interceptStr.components(separatedBy: ": ")
            if components.count > 1 {
                rescaleIntercept = Double(components[1].trimmingCharacters(in: .whitespaces)) ?? 0.0
            } else {
                rescaleIntercept = Double(interceptStr.trimmingCharacters(in: .whitespaces)) ?? 0.0
            }
        }
        
        // Ensure rescaleSlope is never 0
        if rescaleSlope == 0 {
            rescaleSlope = 1.0
        }
        
        print("🔬 Rescale values: Slope=\(rescaleSlope), Intercept=\(rescaleIntercept)")
        
        return ImageDisplayConfiguration(
            rescaleSlope: rescaleSlope,
            rescaleIntercept: rescaleIntercept,
            modality: modality
        )
    }
    
    private func applyWindowLevelSettings(
        configuration: ImageDisplayConfiguration,
        originalSeriesWindowWidth: Int?,
        originalSeriesWindowLevel: Int?,
        currentSeriesWindowWidth: Int?,
        currentSeriesWindowLevel: Int?,
        decoder: DCMDecoder
    ) async -> ImageDisplayConfiguration {
        
        // Determine window/level values to use
        let windowWidth: Int
        let windowLevel: Int
        
        if let ww = currentSeriesWindowWidth, let wl = currentSeriesWindowLevel {
            // Use saved series window/level
            windowWidth = ww
            windowLevel = wl
            print("🪟 Applying saved window/level: WW=\(ww)HU, WL=\(wl)HU")
        } else {
            // Determine defaults
            let dicomWindowCenter = decoder.windowCenter
            let dicomWindowWidth = decoder.windowWidth
            
            if dicomWindowCenter > 0 && dicomWindowWidth > 0 {
                // Use DICOM metadata values
                windowWidth = Int(dicomWindowWidth)
                windowLevel = Int(dicomWindowCenter)
                print("🪟 Using DICOM metadata W/L: WW=\(windowWidth), WL=\(windowLevel)")
            } else {
                // Use modality defaults
                let defaults = getDefaultWindowLevelForModality(configuration.modality)
                windowWidth = defaults.width
                windowLevel = defaults.level
                print("🪟 Using modality defaults for \(configuration.modality): WW=\(windowWidth), WL=\(windowLevel)")
            }
        }
        
        return ImageDisplayConfiguration(
            rescaleSlope: configuration.rescaleSlope,
            rescaleIntercept: configuration.rescaleIntercept,
            windowWidth: windowWidth,
            windowLevel: windowLevel,
            modality: configuration.modality
        )
    }
    
    private func getDefaultWindowLevelForModality(_ modality: DICOMModality) -> (width: Int, level: Int) {
        switch modality {
        case .ct:
            return (350, 40) // Abdomen preset
        case .mr:
            return (200, 100)
        case .dx, .cr:
            return (2000, 1000)
        case .us:
            return (256, 128)
        case .mg:
            return (4000, 2000)
        case .nm, .pt:
            return (256, 128)
        case .rf, .xc, .sc:
            return (256, 128)
        case .unknown:
            return (350, 40)
        }
    }
    
    private func cacheProcessedImage(path: String, dicomView: DCMImgView) async {
        // Cache the processed image if not already cached
        if SwiftImageCacheManager.shared.getCachedImage(for: path) == nil {
            if let currentImage = dicomView.dicomImage() {
                SwiftImageCacheManager.shared.cacheImage(currentImage, for: path)
                print("💾 Cached image for path: \(path)")
            }
        }
    }
    
    // MARK: - Phase 9A Migration: Metadata Extraction Methods
    
    public func getCurrentImageInfo(
        decoder: DCMDecoder?,
        currentImageIndex: Int,
        currentSeriesIndex: Int
    ) -> ImageSpecificInfo {
        guard let decoder = decoder else {
            return ImageSpecificInfo(
                seriesDescription: "Unknown Series",
                seriesNumber: "1",
                instanceNumber: "1",
                pixelSpacing: "Unknown",
                sliceThickness: "Unknown"
            )
        }
        
        // Get current series information
        var seriesNumber = decoder.info(for: 0x00200011) // Series Number
        if seriesNumber.isEmpty { seriesNumber = String(currentSeriesIndex + 1) }
        var instanceNumber = decoder.info(for: 0x00200013) // Instance Number
        if instanceNumber.isEmpty { instanceNumber = String(currentImageIndex + 1) }
        var seriesDescription = decoder.info(for: 0x0008103E) // Series Description
        if seriesDescription.isEmpty { seriesDescription = "Series \(seriesNumber)" }
        
        // Get pixel spacing information
        var pixelSpacing = "Unknown"
        let pixelSpacingData = decoder.info(for: 0x00280030) // Pixel Spacing
        if !pixelSpacingData.isEmpty {
            pixelSpacing = formatPixelSpacing(pixelSpacingData)
        }
        
        // Get slice thickness
        var sliceThickness = "Unknown"
        let sliceThicknessData = decoder.info(for: 0x00180050) // Slice Thickness
        if !sliceThicknessData.isEmpty {
            sliceThickness = "\(sliceThicknessData)mm"
        }
        
        return ImageSpecificInfo(
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            instanceNumber: instanceNumber,
            pixelSpacing: pixelSpacing,
            sliceThickness: sliceThickness
        )
    }
    
    public func formatPixelSpacing(_ pixelSpacingString: String) -> String {
        // DICOM pixel spacing is typically "row spacing\\column spacing"
        let components = pixelSpacingString.components(separatedBy: "\\")
        if components.count >= 2 {
            if let rowSpacing = Double(components[0]), let colSpacing = Double(components[1]) {
                return String(format: "%.1fx%.1fmm", rowSpacing, colSpacing)
            }
        } else if let singleValue = Double(pixelSpacingString) {
            return String(format: "%.1fmm", singleValue)
        }
        return "Unknown"
    }
    
    public func extractAnnotationData(
        decoder: DCMDecoder?,
        sortedPathArray: [String]
    ) -> (studyInfo: DicomStudyInfo?, seriesInfo: DicomSeriesInfo?, imageInfo: DicomImageInfo?) {
        guard let decoder = decoder else {
            return (nil, nil, nil)
        }
        
        let studyInfo = DicomStudyInfo(
            studyInstanceUID: decoder.info(for: 0x0020000D),
            studyID: decoder.info(for: 0x00200010),
            studyDate: decoder.info(for: 0x00080020),
            studyTime: decoder.info(for: 0x00080030),
            studyDescription: decoder.info(for: 0x00081030),
            modality: decoder.info(for: 0x00080060),
            acquisitionDate: decoder.info(for: 0x00080022),
            acquisitionTime: decoder.info(for: 0x00080032)
        )
        
        let seriesInfo = DicomSeriesInfo(
            seriesInstanceUID: decoder.info(for: 0x0020000E),
            seriesNumber: decoder.info(for: 0x00200011),
            seriesDate: decoder.info(for: 0x00080021),
            seriesTime: decoder.info(for: 0x00080031),
            seriesDescription: decoder.info(for: 0x0008103E),
            protocolName: decoder.info(for: 0x00181030),
            instanceNumber: decoder.info(for: 0x00200013),
            sliceLocation: decoder.info(for: 0x00201041),
            imageOrientationPatient: decoder.info(for: 0x00200037)
        )
        
        // Get image dimensions and properties
        let width = Int(decoder.width)
        let height = Int(decoder.height)
        let bitDepth = Int(decoder.bitDepth)
        let samplesPerPixel = Int(decoder.samplesPerPixel)
        let windowCenter = decoder.windowCenter
        let windowWidth = decoder.windowWidth
        let numberOfImages = sortedPathArray.count
        let isSignedImage = decoder.signedImage
        let isCompressed = false // Default value
        
        // Parse pixel spacing if available
        let pixelSpacingStr = decoder.info(for: 0x00280030)
        let spacingComponents = pixelSpacingStr.split(separator: "\\")
        let spacingX = spacingComponents.first.flatMap { Double($0) } ?? 1.0
        let spacingY = spacingComponents.count > 1 ? (Double(spacingComponents[1]) ?? 1.0) : spacingX
        let sliceThicknessStr = decoder.info(for: 0x00180050)
        let spacingZ = sliceThicknessStr.isEmpty ? 1.0 : (Double(sliceThicknessStr) ?? 1.0)
        
        let imageInfo = DicomImageInfo(
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel,
            windowCenter: Double(windowCenter),
            windowWidth: Double(windowWidth),
            pixelSpacing: (width: spacingX, height: spacingY, depth: spacingZ),
            numberOfImages: numberOfImages,
            isSignedImage: isSignedImage,
            isCompressed: isCompressed
        )
        
        return (studyInfo, seriesInfo, imageInfo)
    }
    
    // MARK: - Phase 9B Migration: Additional Metadata and UI Support Methods
    
    public func resolveFirstPath(
        filePath: String?,
        pathArray: [String]?,
        legacyPath: String?,
        legacyPath1: String?
    ) -> String? {
        // Check modern filePath property first
        if let filePath = filePath, !filePath.isEmpty {
            return filePath
        }
        
        // Check pathArray for first valid path
        if let firstInArray = pathArray?.first, !firstInArray.isEmpty {
            return firstInArray
        }
        
        // Legacy fallback logic for compatibility with old properties
        if let p = legacyPath, let p1 = legacyPath1 {
            guard let cache = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { 
                return nil 
            }
            return (cache as NSString).appendingPathComponent(
                (p as NSString).appendingPathComponent((p1 as NSString).lastPathComponent)
            )
        }
        
        return nil
    }
    
    public func createPatientInfoDictionary(
        patient: PatientModel,
        imageInfo: ImageSpecificInfo
    ) -> [String: Any] {
        return [
            "PatientID": patient.patientID,
            "PatientAge": patient.displayAge,
            "PatientSex": patient.patientSex.rawStringValue,
            "StudyDescription": patient.studyDescription ?? "No Description",
            "StudyDate": patient.displayStudyDate,
            "Modality": patient.modality.rawStringValue,
            "SeriesDescription": imageInfo.seriesDescription,
            "SeriesNumber": imageInfo.seriesNumber,
            "InstanceNumber": imageInfo.instanceNumber,
            "PixelSpacing": imageInfo.pixelSpacing,
            "SliceThickness": imageInfo.sliceThickness
        ]
    }
    
    public func shouldShowOrientationMarkers(decoder: DCMDecoder?) -> Bool {
        guard let decoder = decoder else { return false }
        
        let modality = decoder.info(for: 0x00080060) // MODALITY
        let modalityUpper = modality.uppercased()
        
        // Hide for X-ray (CR, RX, DX) and Ultrasound (US) - modalities that don't typically have orientation
        let hideForModalities = ["CR", "RX", "DX", "US"]
        
        if hideForModalities.contains(modalityUpper) {
            print("🧭 Orientation markers hidden for modality: \(modalityUpper)")
            return false
        }
        
        return true
    }
    
    // MARK: - UI State Management (Phase 9D)
    
    public func calculateSliderConfiguration(imageCount: Int, currentIndex: Int = 0) -> SliderConfiguration {
        return SliderConfiguration(imageCount: imageCount, currentIndex: currentIndex)
    }
    
    public func processImageConfiguration(
        _ configuration: ImageDisplayConfiguration,
        currentOriginalWidth: Int?,
        currentOriginalLevel: Int?
    ) -> ImageConfigurationUpdate {
        // Business logic: Determine if this should become the series defaults
        let shouldSaveAsDefaults = (currentOriginalWidth == nil && currentOriginalLevel == nil)
        
        return ImageConfigurationUpdate(
            configuration: configuration,
            shouldSaveDefaults: shouldSaveAsDefaults
        )
    }
    
    // MARK: - UI State Management (Phase 9F)
    
    
    public func configureOptionsPanel(panelType: String, hasExistingPanel: Bool) -> OptionsPanelConfiguration {
        return OptionsPanelConfiguration(panelType: panelType, hasExistingPanel: hasExistingPanel)
    }
    
    public func configureImageSliderSetup(imageCount: Int, containerWidth: CGFloat) -> ImageSliderSetup {
        return ImageSliderSetup(imageCount: imageCount, containerWidth: containerWidth)
    }
    
    public func handleMemoryPressureWarning() -> MemoryManagementResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Business logic: Assess current memory situation and determine appropriate cleanup strategy
        let availableMemoryMB = getAvailableMemoryMB()
        
        print("⚠️ Memory pressure warning detected - Available: \(String(format: "%.1f", availableMemoryMB))MB")
        
        // Create memory management strategy based on available memory
        let result = MemoryManagementResult(availableMemoryMB: availableMemoryMB)
        
        // Log the determined strategy
        print("🧹 Memory management strategy: \(result.priority.rawValue)")
        print("🧹 Recommended action: \(result.action)")
        print("🧹 Expected memory freed: \(String(format: "%.1f", result.memoryFreedMB))MB")
        print("🧹 Recommended cache limit: \(result.recommendedCacheLimit) images")
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 0.5 {
            print("[PERF] Memory pressure analysis: \(String(format: "%.2f", elapsed))ms")
        }
        
        return result
    }
    
    /// Get available system memory in MB (helper method)
    private func getAvailableMemoryMB() -> Double {
        // Get memory statistics from the system
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            // Calculate available memory (total system memory - used memory)
            let usedMemoryMB = Double(info.resident_size) / 1024.0 / 1024.0
            
            // For safety, we'll estimate available memory conservatively
            // iOS typically has 2-8GB RAM, we'll assume we shouldn't use more than 25% of system memory
            let estimatedSystemMemoryMB = usedMemoryMB * 4.0 // Rough estimate
            let maxAppMemoryMB = estimatedSystemMemoryMB * 0.25
            let availableMemoryMB = max(0, maxAppMemoryMB - usedMemoryMB)
            
            return availableMemoryMB
        } else {
            // Fallback: Conservative estimate if we can't get memory info
            print("⚠️ Unable to get memory statistics, using conservative estimate")
            return 100.0 // Conservative fallback
        }
    }
    
    public func determineCloseNavigationAction(hasPresenting: Bool) -> NavigationAction {
        // Business logic: Determine appropriate navigation action based on presentation context
        return NavigationAction(hasPresenting: hasPresenting)
    }
    
    public func configureCacheSettings() -> CacheConfiguration {
        // Business logic: Provide optimal cache configuration for medical imaging
        return CacheConfiguration()
    }
    
    public func configureModalPresentation(type: String) -> ModalPresentationConfig {
        // Business logic: Determine appropriate modal presentation settings
        return ModalPresentationConfig(type: type)
    }
    
    
    public func configureNavigationBar(patientName: String?) -> NavigationBarConfig {
        // Business logic: Determine appropriate navigation bar configuration based on context
        return NavigationBarConfig(patientName: patientName)
    }
    
    public func configureGestureSetup() -> GestureSetupConfig {
        // Business logic: Determine appropriate gesture management configuration
        return GestureSetupConfig()
    }
    
    public func configureOverlaySetup(hasPatientModel: Bool) -> OverlaySetupConfig {
        // Business logic: Determine overlay configuration based on data availability
        return OverlaySetupConfig(hasPatientModel: hasPatientModel)
    }
    
    public func configureGestureCallbacks() -> GestureCallbackConfig {
        // Business logic: Determine gesture callback configuration strategy
        return GestureCallbackConfig()
    }
    
    public func checkMPRAvailability(for modality: DICOMModality) -> MPRAvailabilityResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Delegate modality-based business logic to data model
        let result = MPRAvailabilityResult(modality: modality)
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if elapsed > 0.5 {
            print("[PERF] MPR availability check: \(String(format: "%.2f", elapsed))ms")
        }
        
        print("🔍 MPR availability for \(modality): \(result.isAvailable ? "✅ Available" : "❌ Not available")")
        return result
    }
}

// MARK: - Singleton for Compatibility

extension DICOMImageProcessingService {
    public static let shared = DICOMImageProcessingService()
}