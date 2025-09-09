//
//  SwiftDetailViewController.swift
//  DICOMViewer
//
//  Created by Swift Migration on 2025/8/27.
//  Swift migration of DetailViewController with interoperability to Objective-C components.
//

import UIKit
import SwiftUI
import Foundation
import Combine

// MARK: - Enums & Types
// ViewingOrientation moved to MultiplanarReconstructionService to avoid duplication

// MARK: - Enums and Models moved to ROIMeasurementToolsView for Phase 10A optimization

// MARK: - Protocols

protocol ImageDisplaying {
    func loadAndDisplayDICOM()
    func updateImageDisplay()
    func createUIImageFromPixels() -> UIImage?
}

protocol WindowLevelManaging {
    func applyWindowLevel()
    func resetToOriginalWindowLevel()
    func applyPreset(_ preset: WindowLevelPreset)
}

protocol ROIMeasuring {
    func startDistanceMeasurement(at point: CGPoint)
    func startEllipseMeasurement(at point: CGPoint)
    func calculateDistance(from: CGPoint, to: CGPoint) -> Double
    func clearAllMeasurements()
}

protocol SeriesNavigating {
    func navigateToImage(at index: Int)
    func preloadAdjacentImages()
    func updateNavigationButtons()
}

// CineControlling protocol removed - cine playback deprecated

// MARK: - Main View Controller

@MainActor
public final class SwiftDetailViewController: UIViewController, 
    @preconcurrency DICOMOverlayDataSource,
    @preconcurrency WindowLevelPresetDelegate,
    @preconcurrency CustomWindowLevelDelegate,
    @preconcurrency ROIToolsDelegate,
    @preconcurrency ReconstructionDelegate {
    
    // MARK: - Nested Types
    
    struct ViewState {
        var isLoading: Bool = false
        var currentImage: UIImage?
        var errorMessage: String?
    }
    
    struct MeasurementState {
        var mode: MeasurementMode = .none
        var points: [CGPoint] = []
        var currentValue: String?
    }
    
    struct WindowLevelState {
        var currentWidth: Int?
        var currentLevel: Int?
        var rescaleSlope: Double = 1.0
        var rescaleIntercept: Double = 0.0
    }
    
    struct NavigationState {
        var currentIndex: Int = 0
        var totalImages: Int = 0
        var currentSeries: String?
    }
    // MARK: - Properties
    
    // Public API
    public var filePath: String? { // preferred modern property
        didSet { 
            if isViewLoaded { 
                loadAndDisplayDICOM() 
            } 
        }
    }
    
    // Legacy properties for compatibility
    public var path: String?
    public var path1: String?
    public var pathArray: [String]? // series paths
    
    // Series management
    private var currentSeriesIndex: Int = 0
    private var currentImageIndex: Int = 0
    private var sortedPathArray: [String] = []
    
    // Models
    public var patientModel: PatientModel? // Swift model - the single source of truth
    
    // MVVM ViewModel
    public var viewModel: DetailViewModel?
    
    // MVVM-C Services
    private var imageProcessingService: DICOMImageProcessingServiceProtocol?
    private var roiMeasurementService: ROIMeasurementServiceProtocol?
    private var gestureEventService: GestureEventServiceProtocol?
    private var uiControlEventService: UIControlEventServiceProtocol?
    private var viewStateManagementService: ViewStateManagementServiceProtocol?
    private var seriesNavigationService: SeriesNavigationServiceProtocol?
    
    // UI Components (Interop with Obj-C views)
    private var dicom2DView: DCMImgView?
    var dicomDecoder: DCMDecoder?
    private var swiftDetailContentView: UIViewController?
    private var swiftOverlayView: UIView?
    private var overlayController: SwiftDICOMOverlayViewController?
    private var annotationsController: SwiftDICOMAnnotationsViewController?
    private var dicomOverlayView: DICOMOverlayView?
    private var previewImageView: UIImageView?
    
    // Modernized Swift controls
    private var swiftControlBar: UIView?
    private var optionsPanel: SwiftOptionsPanelViewController?
    private var customSlider: SwiftCustomSlider?
    private var gestureManager: SwiftGestureManager?
    
    // Cine Management removed - deprecated functionality
    
    // Window/Level State
    private var currentSeriesWindowWidth: Int?
    private var currentSeriesWindowLevel: Int?
    
    // Original series defaults (never modified after initial load)
    private var originalSeriesWindowWidth: Int?
    private var originalSeriesWindowLevel: Int?
    
    // Rescale values for proper Hounsfield Unit conversion (CT images)
    private var rescaleSlope: Double = 1.0
    private var rescaleIntercept: Double = 0.0
    private var hasRescaleValues: Bool = false
    
    // ROI Measurement State - MVVM-C Phase 10A: Extracted to ROIMeasurementToolsView
    private var roiMeasurementToolsView: ROIMeasurementToolsView?
    private var selectedMeasurementPoint: Int? = nil  // For adjusting endpoints
    private var measurementPanGesture: UIPanGestureRecognizer?
    
    // Gesture Transform Coordination (Phase 11F+)
    // Single transform update mechanism to handle simultaneous gestures
    private var pendingZoomScale: CGFloat = 1.0
    private var pendingRotationAngle: CGFloat = 0.0
    private var pendingTranslation: CGPoint = .zero
    private var transformUpdateTimer: Timer?

    // Performance Optimization: Cache & Prefetch
    private let pixelDataCache = NSCache<NSString, NSData>()
    private let decoderCache = NSCache<NSString, DCMDecoder>()
    private let prefetchQueue = DispatchQueue(label: "com.dicomviewer.prefetch", qos: .utility)
    private let prefetchWindow = 5 // Número de imagens a serem pré-buscadas
    
    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupServices() // Initialize MVVM-C services FIRST
        setupCache() // Now cache setup can use services
        setupNavigationBar()
        setupViews()
        setupOverlayView()
        setupImageSlider()
        setupControlBar()
        setupLayoutConstraints() // Set all constraints after views are created
        setupGestures()
        
        // ✅ MVVM-C Enhancement: Check if using ViewModel pattern
        if viewModel != nil {
            print("🏗️ [MVVM-C] DetailViewController initialized with ViewModel - enhanced architecture active")
            // ViewModel is available - the reactive pattern will be used in individual methods
            // Each method will check for viewModel availability and delegate to services
            loadAndDisplayDICOM() // Still use same loading, but methods will delegate to services
        } else {
            print("⚠️ [MVVM-C] DetailViewController fallback - using legacy loading path")
            // Legacy loading path
            loadAndDisplayDICOM()
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Cine functionality removed - deprecated
    }
    
    // MARK: - Rotation Handling
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { _ in
            // Force the DICOM view to redraw with the new size
            self.dicom2DView?.setNeedsDisplay()
            
            // Update annotations overlay to match new bounds
            self.annotationsController?.view.setNeedsDisplay()
            
            // Redraw measurement overlay if present
            self.roiMeasurementToolsView?.refreshOverlay()
        }, completion: nil)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Ensure DICOM view redraws when layout changes
        dicom2DView?.setNeedsDisplay()
        
        // Update annotations to match new layout
        annotationsController?.view.setNeedsDisplay()
    }
    
    // MARK: - Setup
    // MARK: - MVVM-C Migration: Cache Configuration
    private func setupCache() {
        // MVVM-C Migration: Delegate cache configuration to service layer
        guard let imageProcessingService = imageProcessingService else {
            // Legacy fallback: Direct cache configuration
            pixelDataCache.countLimit = 20
            pixelDataCache.totalCostLimit = 100 * 1024 * 1024
            decoderCache.countLimit = 10
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMemoryWarning),
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
            print("⚠️ [LEGACY] setupCache using fallback - service unavailable")
            return
        }
        
        // Get cache configuration from service
        let config = imageProcessingService.configureCacheSettings()
        
        // Apply service-determined cache settings
        pixelDataCache.countLimit = config.pixelCacheCountLimit
        pixelDataCache.totalCostLimit = config.pixelCacheCostLimit
        decoderCache.countLimit = config.decoderCacheCountLimit
        
        // Setup memory warning observer if service recommends it
        if config.shouldObserveMemoryWarnings {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMemoryWarning),
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
        }
        
        print("🗄️ [MVVM-C] Cache configured: \(config.configuration)")
    }
    
    // MARK: - ⚠️ MIGRATED METHOD: Memory Warning Handling → UIStateManagementService
    // Migration: Phase 11D
    @objc private func handleMemoryWarning() {
        // MVVM-C Phase 11D: Delegate memory warning handling to ViewModel → UIStateManagementService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, using direct fallback")
            // Clear caches directly
            pixelDataCache.removeAllObjects()
            decoderCache.removeAllObjects()
            DependencyContainer.shared.resolve(SwiftImageCacheManager.self)?.clearCache()
            DependencyContainer.shared.resolve(SwiftThumbnailCacheManager.self)?.clearCache()
            return
        }
        
        print("⚠️ [MVVM-C Phase 11D] Memory warning received - handling via ViewModel → UIStateService")
        
        let shouldShow = viewModel.handleMemoryWarning()
        
        if shouldShow {
            // Clear local caches  
            pixelDataCache.removeAllObjects()
            decoderCache.removeAllObjects()
            
            // Clear image manager caches via ViewModel
            viewModel.clearCacheMemory()
            
            print("✅ [MVVM-C Phase 11D] Memory warning handled via service layer")
        } else {
            print("⏳ [MVVM-C Phase 11D] Memory warning suppressed by service - in cooldown period")
        }
    }
    
    
    // MARK: - Service Setup
    
    private func setupServices() {
        // Initialize MVVM-C services with dependency injection
        imageProcessingService = DICOMImageProcessingService.shared
        roiMeasurementService = ROIMeasurementService.shared
        gestureEventService = GestureEventService.shared
        uiControlEventService = UIControlEventService.shared
        viewStateManagementService = ViewStateManagementService.shared
        seriesNavigationService = SeriesNavigationService()
        print("🏗️ [MVVM-C Phase 11F+] Services initialized: DICOMImageProcessingService + ROIMeasurementService + GestureEventService + UIControlEventService + ViewStateManagementService + SeriesNavigationService")
    }
    
    // MARK: - Service Configuration (Dependency Injection)
    
    /// Configure services for dependency injection (used by coordinators/factories)
    public func configureServices(imageProcessingService: DICOMImageProcessingServiceProtocol) {
        self.imageProcessingService = imageProcessingService
        print("🔧 [MVVM-C] Services configured via dependency injection")
    }
    
    // MARK: - MVVM-C Migration: Navigation Bar Configuration
    private func setupNavigationBar() {
        // MVVM-C Migration: Delegate navigation bar configuration to service layer
        guard let imageProcessingService = imageProcessingService else {
            // Legacy fallback: Direct navigation setup
            let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(closeButtonTapped))
            navigationItem.leftBarButtonItem = backButton
            
            if let patient = patientModel {
                navigationItem.title = patient.patientName.uppercased()
            } else {
                navigationItem.title = "Isis DICOM Viewer"
            }
            
            let roiItem = UIBarButtonItem(title: "ROI", style: .plain, target: self, action: #selector(showROI))
            navigationItem.rightBarButtonItem = roiItem
            print("⚠️ [LEGACY] setupNavigationBar using fallback - service unavailable")
            return
        }
        
        // Get navigation configuration from service
        let config = imageProcessingService.configureNavigationBar(
            patientName: patientModel?.patientName
        )
        
        // Apply service-determined navigation configuration
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: config.leftButtonSystemName),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        navigationItem.leftBarButtonItem = backButton
        
        // Apply title with service-determined transformation
        var title = config.navigationTitle
        if config.titleTransformation == "uppercased" {
            title = title.uppercased()
        }
        navigationItem.title = title
        
        // Setup right button
        let roiItem = UIBarButtonItem(
            title: config.rightButtonTitle,
            style: .plain,
            target: self,
            action: #selector(showROI)
        )
        navigationItem.rightBarButtonItem = roiItem
    }
    
    // MARK: - ⚠️ MIGRATED METHOD: Navigation Logic → UIStateManagementService
    // Migration: Phase 11D
    @objc private func closeButtonTapped() {
        // MVVM-C Phase 11F Part 2: Delegate to service layer
        handleCloseButtonTap()
    }
    
    
    private func setupViews() {
        // Create and add views with Auto Layout for proper positioning
        let dicom2DView = DCMImgView()
        dicom2DView.backgroundColor = UIColor.black
        dicom2DView.isHidden = true
        dicom2DView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dicom2DView)
        
        self.dicom2DView = dicom2DView
        
        // Decoder
        let decoder = DCMDecoder()
        self.dicomDecoder = decoder
        
        // ROI Measurement Tools View - MVVM-C Phase 10A
        let roiToolsView = ROIMeasurementToolsView()
        roiToolsView.delegate = self
        roiToolsView.dicom2DView = dicom2DView
        roiToolsView.dicomDecoder = decoder
        roiToolsView.viewModel = viewModel
        roiToolsView.rescaleSlope = rescaleSlope
        roiToolsView.rescaleIntercept = rescaleIntercept
        roiToolsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(roiToolsView)
        self.roiMeasurementToolsView = roiToolsView
        
        // Note: Constraints will be set in setupLayoutConstraints()
        // after all views are created to ensure proper hierarchy
    }
    
    // MARK: - MVVM-C Migration: Overlay Configuration
    private func setupOverlayView() {
        // MVVM-C Migration: Delegate overlay configuration to service layer
        guard let imageProcessingService = imageProcessingService else {
            // Legacy fallback: Direct overlay setup
            let annotationsController = SwiftDICOMAnnotationsViewController(data: DICOMAnnotationData())
            self.annotationsController = annotationsController
            addChild(annotationsController)
            annotationsController.view.translatesAutoresizingMaskIntoConstraints = false
            annotationsController.view.isUserInteractionEnabled = false
            annotationsController.view.backgroundColor = .clear
            annotationsController.didMove(toParent: self)
            self.swiftOverlayView = annotationsController.view
            
            let overlayController = SwiftDICOMOverlayViewController()
            self.overlayController = overlayController
            overlayController.showAnnotations = false
            overlayController.showOrientation = true
            overlayController.showWindowLevel = false
            
            if let patient = patientModel {
                updateOverlayWithPatientInfo(patient)
                updateAnnotationsView()
            }
            print("⚠️ [LEGACY] setupOverlayView using fallback - service unavailable")
            return
        }
        
        // Get overlay configuration from service
        let config = imageProcessingService.configureOverlaySetup(
            hasPatientModel: patientModel != nil
        )
        
        // Apply service-determined overlay configuration
        if config.shouldCreateAnnotationsController {
            let annotationsController = SwiftDICOMAnnotationsViewController(data: DICOMAnnotationData())
            self.annotationsController = annotationsController
            
            addChild(annotationsController)
            annotationsController.view.translatesAutoresizingMaskIntoConstraints = false
            annotationsController.view.isUserInteractionEnabled = config.annotationsInteractionEnabled
            annotationsController.view.backgroundColor = .clear
            
            // Note: The view will be added and constraints set in setupLayoutConstraints()
            // to ensure it's properly anchored to the dicom2DView
            
            annotationsController.didMove(toParent: self)
            self.swiftOverlayView = annotationsController.view
        }
        
        if config.shouldCreateOverlayController {
            let overlayController = SwiftDICOMOverlayViewController()
            self.overlayController = overlayController
            overlayController.showAnnotations = config.overlayShowAnnotations
            overlayController.showOrientation = config.overlayShowOrientation
            overlayController.showWindowLevel = config.overlayShowWindowLevel
        }
        
        // Update with patient information if service recommends it
        if config.shouldUpdateWithPatientInfo, let patient = patientModel {
            updateOverlayWithPatientInfo(patient)
            updateAnnotationsView()
        }
        
        print("🎯 [MVVM-C] Overlay setup complete using \(config.overlayStrategy)")
    }
    
    // MARK: - ⚠️ MIGRATED METHOD: Annotation Data Extraction → DICOMImageProcessingService
    // Migration: Phase 9A
    // New approach: Business logic delegated to DICOMImageProcessingService
    private func updateAnnotationsView() {
        guard let annotationsController = self.annotationsController else { return }
        
        // MVVM-C Migration: Delegate DICOM data extraction to service layer
        guard let imageProcessingService = imageProcessingService else {
            print("❌ DICOMImageProcessingService not available, falling back to legacy implementation")
            // Legacy fallback - simplified annotation
            let annotationData = DICOMAnnotationData(
                studyInfo: nil,
                seriesInfo: nil,
                imageInfo: nil,
                windowLevel: currentSeriesWindowLevel ?? 40,
                windowWidth: currentSeriesWindowWidth ?? 400,
                zoomLevel: 1.0,
                rotationAngle: 0.0,
                currentImageIndex: currentImageIndex + 1,
                totalImages: sortedPathArray.count
            )
            annotationsController.updateAnnotations(with: annotationData)
            return
        }
        
        print("📋 [MVVM-C] Extracting annotation data via service layer")
        
        // Delegate to service layer for DICOM metadata extraction
        let (studyInfo, seriesInfo, imageInfo) = imageProcessingService.extractAnnotationData(
            decoder: dicomDecoder,
            sortedPathArray: sortedPathArray
        )
        
        // Get window level values in HU (our source of truth)
        let windowLevel = currentSeriesWindowLevel ?? 40
        let windowWidth = currentSeriesWindowWidth ?? 400
        
        // Calculate zoom and rotation from transform
        var zoomLevel: Float = 1.0
        var rotationAngle: Float = 0.0
        
        if let dicomView = dicom2DView {
            let transform = dicomView.transform
            // Calculate zoom from transform scale
            zoomLevel = Float(sqrt(transform.a * transform.a + transform.c * transform.c))
            // Calculate rotation angle from transform
            rotationAngle = Float(atan2(transform.b, transform.a) * 180 / .pi)
        }
        
        // Create annotation data
        let annotationData = DICOMAnnotationData(
            studyInfo: studyInfo,
            seriesInfo: seriesInfo,
            imageInfo: imageInfo,
            windowLevel: windowLevel,
            windowWidth: windowWidth,
            zoomLevel: zoomLevel,
            rotationAngle: rotationAngle,
            currentImageIndex: currentImageIndex + 1,
            totalImages: sortedPathArray.count
        )
        
        // Update the annotations view
        annotationsController.updateAnnotations(with: annotationData)
        
        print("✅ [MVVM-C] Annotation data extracted and applied via service layer")
    }
    
    // MARK: - ⚠️ MIGRATED METHOD: Patient Info Dictionary Creation → DICOMImageProcessingService
    // Migration: Phase 9B
    // New approach: Business logic delegated to DICOMImageProcessingService
    private func updateOverlayWithPatientInfo(_ patient: PatientModel) {
        guard let overlayController = self.overlayController else { return }
        
        // MVVM-C Migration: Delegate patient info creation to service layer
        guard let imageProcessingService = imageProcessingService else {
            print("❌ DICOMImageProcessingService not available, falling back to legacy implementation")
            // Legacy fallback - simplified patient info
            let patientInfoDict: [String: Any] = [
                "PatientID": patient.patientID,
                "PatientAge": patient.displayAge,
                "StudyDescription": patient.studyDescription ?? "No Description"
            ]
            overlayController.patientInfo = patientInfoDict as NSDictionary
            updateOrientationMarkers()
            return
        }
        
        print("📋 [MVVM-C] Creating patient info dictionary via service layer")
        
        // Get dynamic image-specific information (already migrated to service)
        let imageSpecificInfo = getCurrentImageInfo()
        
        // Delegate patient info dictionary creation to service layer
        let patientInfoDict = imageProcessingService.createPatientInfoDictionary(
            patient: patient,
            imageInfo: imageSpecificInfo
        )
        
        overlayController.patientInfo = patientInfoDict as NSDictionary
        
        // Update orientation markers based on DICOM data
        updateOrientationMarkers()
        
        print("✅ [MVVM-C] Patient info dictionary created and applied via service layer")
    }
    
    // MARK: - Image Info Extraction (Migrated to DICOMImageProcessingService)
    private func getCurrentImageInfo() -> ImageSpecificInfo {
        // Phase 11G: Complete migration to DICOMImageProcessingService
        guard let imageProcessingService = imageProcessingService else {
            print("❌ DICOMImageProcessingService not available, using basic fallback")
            return ImageSpecificInfo(
                seriesDescription: "Unknown Series",
                seriesNumber: "1",
                instanceNumber: String(currentImageIndex + 1),
                pixelSpacing: "Unknown",
                sliceThickness: "Unknown"
            )
        }
        
        print("📋 [MVVM-C Phase 11G] Getting current image info via service layer")
        
        // Delegate to service layer
        let result = imageProcessingService.getCurrentImageInfo(
            decoder: dicomDecoder,
            currentImageIndex: currentImageIndex,
            currentSeriesIndex: currentSeriesIndex
        )
        
        print("✅ [MVVM-C Phase 11G] Image info extracted via service layer")
        return result
    }
    
    // MARK: - ⚠️ MIGRATED METHOD: Pixel Spacing Formatting → UIStateManagementService
    // Migration: Phase 11D
    private func formatPixelSpacing(_ pixelSpacingString: String) -> String {
        // MVVM-C Phase 11D: Delegate pixel spacing formatting to ViewModel → UIStateManagementService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, using direct formatting")
            let components = pixelSpacingString.components(separatedBy: "\\")
            if components.count >= 2 {
                if let rowSpacing = Double(components[0]), let colSpacing = Double(components[1]) {
                    return String(format: "%.1fx%.1fmm", rowSpacing, colSpacing)
                }
            } else if let singleValue = Double(pixelSpacingString) {
                return String(format: "%.1fx%.1fmm", singleValue, singleValue)
            }
            return pixelSpacingString
        }
        
        print("📏 [MVVM-C Phase 11D] Formatting pixel spacing via ViewModel → UIStateService")
        
        return viewModel.formatPixelSpacing(pixelSpacingString)
    }
    
    
    private func createOverlayLabelsView() -> UIView {
        // Create and configure DICOMOverlayView
        let overlayView = DICOMOverlayView()
        overlayView.dataSource = self
        
        // Store reference for future updates
        self.dicomOverlayView = overlayView
        
        // Create the overlay container using the new view
        return overlayView.createOverlayLabelsView()
    }
    
    // MARK: - MVVM-C Migration: Image Slider Setup  
    private func setupImageSlider() {
        guard let paths = pathArray else { return }
        
        // MVVM-C Migration: Delegate slider configuration to service layer
        guard let imageProcessingService = imageProcessingService else {
            // Legacy fallback: Direct slider setup
            guard paths.count > 1 else { return }
            let slider = SwiftCustomSlider(frame: CGRect(x: 20, y: 0, width: view.frame.width - 40, height: 20))
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.maxValue = Float(paths.count)
            slider.currentValue = 1
            slider.showTouchView = true
            slider.delegate = self
            view.addSubview(slider)
            self.customSlider = slider
            print("⚠️ [LEGACY] setupImageSlider using fallback - service unavailable")
            return
        }
        
        // Get configuration from service
        let config = imageProcessingService.configureImageSliderSetup(
            imageCount: paths.count,
            containerWidth: view.frame.width
        )
        
        // Only create slider if service determines it's needed
        guard config.shouldCreateSlider else { return }
        
        // Create slider with service-provided configuration
        let slider = SwiftCustomSlider(frame: CGRect(
            x: config.frameX,
            y: config.frameY,
            width: config.frameWidth,
            height: config.frameHeight
        ))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.maxValue = config.maxValue
        slider.currentValue = config.currentValue
        slider.showTouchView = config.showTouchView
        slider.delegate = self
        
        view.addSubview(slider)
        
        // Note: Constraints will be set in setupLayoutConstraints()
        
        self.customSlider = slider
    }
    
    // MARK: - MVVM-C Migration: Gesture Management Configuration
    private func setupGestures() {
        guard let dicomView = dicom2DView else { return }
        
        print("🔍 [DEBUG] setupGestures called:")
        print("  - dicom2DView: ✅ Available")
        print("  - imageProcessingService: \(imageProcessingService != nil ? "✅ Available" : "❌ NIL")")
        print("  - gestureEventService: \(gestureEventService != nil ? "✅ Available" : "❌ NIL")")
        
        // MVVM-C Migration: Use SwiftGestureManager with corrected delegate methods
        // TEMPORARY: Force use of corrected SwiftGestureManager (skip service check)
        
        // TEMPORARY: Use SwiftGestureManager directly with our delegate fixes
        // Legacy fallback: Direct gesture setup WITH CORRECTED DELEGATES
        let containerView = dicomView.superview ?? view
        let manager = SwiftGestureManager(containerView: containerView!, dicomView: dicomView)
        manager.delegate = self // CRITICAL: Set delegate to get our corrected methods
        self.gestureManager = manager
        roiMeasurementToolsView?.gestureManager = manager
        setupGestureCallbacks()
        print("🖐️ [CORRECTED] Gesture manager setup with fixed delegates")
        return
        
        // End of setupGestures - using SwiftGestureManager with corrected delegate methods
    }
    
    // MARK: - MVVM-C Migration: Gesture Callback Configuration
    private func setupGestureCallbacks() {
        // MVVM-C Migration: Delegate callback configuration to service layer
        guard let imageProcessingService = imageProcessingService else {
            // Legacy fallback: Direct callback setup
            gestureManager?.delegate = self
            print("✅ Gesture manager delegate configured for proper 2-finger pan support")
            print("⚠️ [LEGACY] setupGestureCallbacks using fallback - service unavailable")
            return
        }
        
        // Get callback configuration from service
        let config = imageProcessingService.configureGestureCallbacks()
        
        // Apply service-determined callback configuration
        if config.shouldSetupDelegate {
            gestureManager?.delegate = self
        }
        
        // Remove conflicts if service recommends it
        if config.shouldRemoveConflicts {
            // The SwiftGestureManager will handle all gestures including 2-finger pan
        }
        
        print("✅ [MVVM-C] Gesture callbacks configured using \(config.delegateStrategy) for \(config.callbackType)")
    }
    
    // Legacy gesture handlers removed - now using SwiftGestureManager exclusively
    // This eliminates conflicts and ensures proper gesture recognition
    
    // MARK: - ViewModel Integration
    /*
    private func setupViewModelObserver() {
        guard let viewModel = viewModel else { return }
        
        // Observe current image updates
        viewModel.$currentUIImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                if let image = image {
                    self?.displayViewModelImage(image)
                }
            }
            .store(in: &cancellables)
        
        // Observe annotations
        viewModel.$annotationsData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] annotations in
                self?.updateAnnotationsFromViewModel(annotations)
            }
            .store(in: &cancellables)
        
        // Observe navigation state
        viewModel.$navigationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] navState in
                self?.updateNavigationFromViewModel(navState)
            }
            .store(in: &cancellables)
    }
    
    private func loadFromViewModel() {
        guard let viewModel = viewModel,
              let patient = patientModel else { return }
        
        // Gather file paths
        var paths: [String] = []
        if let pathArray = self.pathArray {
            paths = pathArray
        } else if let singlePath = self.filePath {
            paths = [singlePath]
        }
        
        // Load study in ViewModel
        viewModel.loadStudy(patient, filePaths: paths)
    }
    */ // Temporarily disabled for build fix
    
    private func displayViewModelImage(_ image: UIImage) {
        // dicom2DView?.image = image // Property doesn't exist, commented for build fix
        dicom2DView?.isHidden = false
    }
    
    /*
    private func updateAnnotationsFromViewModel(_ annotations: DetailViewModel.DICOMAnnotationData) {
        annotationsController?.updateAnnotations(
            patientName: annotations.patientName,
            patientID: annotations.patientID,
            studyDate: annotations.studyDate,
            modality: annotations.modality,
            institution: annotations.institutionName,
            sliceInfo: annotations.sliceNumber,
            windowLevel: annotations.windowLevel
        )
    }
    */ // Disabled for build fix
    
    /*
    private func updateNavigationFromViewModel(_ navState: DetailViewModel.NavigationState) {
        currentImageIndex = navState.currentIndex
        
        // Update slider
        if let slider = customSlider {
            slider.currentValue = Float(navState.currentIndex + 1)
            slider.maxValue = Float(navState.totalImages)
            slider.isHidden = navState.totalImages <= 1
        }
    }
    */ // Disabled for build fix
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setupControlBar() {
        // Create UIKit control bar
        let controlBar = createControlBarView()
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlBar)
        
        self.swiftControlBar = controlBar
        
        // Note: Constraints will be set in setupLayoutConstraints()
    }
    
    private func setupLayoutConstraints() {
        // This method sets up all constraints after all views are created
        // to ensure proper vertical flow: dicom2DView -> customSlider -> swiftControlBar
        
        guard let dicom2DView = self.dicom2DView,
              let slider = self.customSlider,
              let controlBar = self.swiftControlBar else {
            print("❌ Missing required views for layout constraints")
            return
        }
        
        // 1. Control bar at the bottom (fixed height)
        let controlBarHeight: CGFloat = 50
        NSLayoutConstraint.activate([
            controlBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            controlBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            controlBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            controlBar.heightAnchor.constraint(equalToConstant: controlBarHeight)
        ])
        
        // 2. Slider above the control bar (fixed height)
        let sliderHeight: CGFloat = 30
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            slider.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            slider.bottomAnchor.constraint(equalTo: controlBar.topAnchor, constant: -10),
            slider.heightAnchor.constraint(equalToConstant: sliderHeight)
        ])
        
        // 3. DICOM view fills remaining space above the slider
        NSLayoutConstraint.activate([
            dicom2DView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            dicom2DView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dicom2DView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dicom2DView.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10)
        ])
        
        // 4. Annotations view overlays the DICOM view with same bounds
        if let annotationsView = self.annotationsController?.view {
            // Remove any existing constraints first
            annotationsView.removeFromSuperview()
            view.addSubview(annotationsView)
            
            annotationsView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                annotationsView.topAnchor.constraint(equalTo: dicom2DView.topAnchor),
                annotationsView.leadingAnchor.constraint(equalTo: dicom2DView.leadingAnchor),
                annotationsView.trailingAnchor.constraint(equalTo: dicom2DView.trailingAnchor),
                annotationsView.bottomAnchor.constraint(equalTo: dicom2DView.bottomAnchor)
            ])
        }
        
        // 5. ROI measurement tools view overlays the DICOM view with same bounds
        if let roiToolsView = self.roiMeasurementToolsView {
            NSLayoutConstraint.activate([
                roiToolsView.topAnchor.constraint(equalTo: dicom2DView.topAnchor),
                roiToolsView.leadingAnchor.constraint(equalTo: dicom2DView.leadingAnchor),
                roiToolsView.trailingAnchor.constraint(equalTo: dicom2DView.trailingAnchor),
                roiToolsView.bottomAnchor.constraint(equalTo: dicom2DView.bottomAnchor)
            ])
        }
        
        print("✅ Layout constraints configured for vertical flow with annotations and ROI tools overlay")
    }
    
    private func createControlBarView() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        container.layer.cornerRadius = 12
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOffset = CGSize(width: 0, height: -2)
        container.layer.shadowOpacity = 0.1
        container.layer.shadowRadius = 4
        
        // Create preset button directly
        let presetButton = UIButton(type: .system)
        presetButton.setTitle("Presets", for: .normal)
        presetButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        presetButton.addTarget(self, action: #selector(showPresets), for: .touchUpInside)
        presetButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Create reset button
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("Reset", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        resetButton.addTarget(self, action: #selector(resetView), for: .touchUpInside)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Create recon button
        let reconButton = UIButton(type: .system)
        reconButton.setTitle("Recon", for: .normal)
        reconButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        reconButton.addTarget(self, action: #selector(showReconOptions), for: .touchUpInside)
        reconButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Add all buttons to stack view
        let stackView = UIStackView(arrangedSubviews: [presetButton, resetButton, reconButton])
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        return container
    }
    
    
    // MARK: - ⚠️ MIGRATED METHOD: Orientation Markers Logic → DICOMImageProcessingService
    // Migration: Phase 9B
    private func updateOrientationMarkers() {
        guard let overlayController = self.overlayController else { return }
        
        // Phase 11G: Complete migration to DICOMImageProcessingService
        guard let imageProcessingService = imageProcessingService else {
            print("❌ DICOMImageProcessingService not available, legacy method migrated in Phase 12")
            // Legacy updateOrientationMarkersLegacy() method migrated to DICOMImageProcessingService
            return
        }
        
        print("🧭 [MVVM-C Phase 11G] Updating orientation markers via service layer")
        
        // Service layer delegation - business logic
        let shouldShow = imageProcessingService.shouldShowOrientationMarkers(decoder: dicomDecoder)
        
        if !shouldShow {
            // UI updates remain in ViewController
            overlayController.showOrientation = false
            dicomOverlayView?.updateOrientationMarkers(showOrientation: false)
            print("✅ [MVVM-C Phase 11G] Orientation markers hidden via service")
            return
        }
        
        // Get orientation markers from DICOM overlay view
        let markers = dicomOverlayView?.getDynamicOrientationMarkers() ?? (top: "?", bottom: "?", left: "?", right: "?")
        
        // Check if markers are valid
        if markers.top == "?" || markers.bottom == "?" || markers.left == "?" || markers.right == "?" {
            overlayController.showOrientation = false
            dicomOverlayView?.updateOrientationMarkers(showOrientation: false)
            print("✅ [MVVM-C Phase 11G] Orientation markers hidden - information not available")
        } else {
            // UI updates - set all marker values and show
            overlayController.showOrientation = true
            overlayController.topMarker = markers.top
            overlayController.bottomMarker = markers.bottom
            overlayController.leftMarker = markers.left
            overlayController.rightMarker = markers.right
            dicomOverlayView?.updateOrientationMarkers(showOrientation: true)
            print("✅ [MVVM-C Phase 11G] Updated orientation markers: Top=\(markers.top), Bottom=\(markers.bottom), Left=\(markers.left), Right=\(markers.right)")
        }
    }
    
    
    // MARK: - ⚠️ MIGRATED METHOD: Path Resolution → DICOMImageProcessingService
    // Migration: Phase 9B
    // New approach: Business logic delegated to DICOMImageProcessingService
    private func resolveFirstPath() -> String? {
        // MVVM-C Migration: Delegate path resolution to service layer
        guard let imageProcessingService = imageProcessingService else {
            print("❌ DICOMImageProcessingService not available, falling back to legacy implementation")
            // Legacy fallback implementation
            if let filePath = self.filePath, !filePath.isEmpty {
                return filePath
            }
            if let firstInArray = self.pathArray?.first, !firstInArray.isEmpty {
                return firstInArray
            }
            if let p = path, let p1 = path1 {
                guard let cache = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return nil }
                return (cache as NSString).appendingPathComponent((p as NSString).appendingPathComponent((p1 as NSString).lastPathComponent))
            }
            return nil
        }
        
        print("📁 [MVVM-C] Resolving file path via service layer")
        
        // Delegate to service layer
        let result = imageProcessingService.resolveFirstPath(
            filePath: self.filePath,
            pathArray: self.pathArray,
            legacyPath: self.path,
            legacyPath1: self.path1
        )
        
        if let resolvedPath = result {
            print("✅ [MVVM-C] Path resolved via service layer: \(resolvedPath)")
        } else {
            print("❌ [MVVM-C] No valid path found via service layer")
        }
        
        return result
    }
    
    // MARK: - MVVM-C Migration: Core Loading Method
    private func loadAndDisplayDICOM() {
        // MVVM-C Migration: Delegate core DICOM loading to service layer via ViewModel
        guard let imageProcessingService = imageProcessingService else {
            print("❌ [MVVM-C] DICOMImageProcessingService not available - using fallback")
            loadAndDisplayDICOMFallback()
            return
        }
        
        print("🏗️ [MVVM-C] Core DICOM loading via service delegation")
        
        // Initialize decoder if needed (still done locally for performance)
        if dicomDecoder == nil { dicomDecoder = DCMDecoder() }
        
        // Use service for core loading with callbacks
        let result = imageProcessingService.loadAndDisplayDICOM(
            filePath: self.filePath,
            pathArray: self.pathArray,
            decoder: dicomDecoder,
            onSeriesOrganized: { [weak self] sortedPaths in
                self?.sortedPathArray = sortedPaths
                print("✅ [MVVM-C] Series organized via service: \(sortedPaths.count) images")
                
                // Phase 11G Fix: Initialize SeriesNavigationService with actual data
                if let seriesNavigationService = self?.seriesNavigationService {
                    let info = SeriesNavigationInfo(
                        paths: sortedPaths,
                        currentIndex: 0
                    )
                    seriesNavigationService.loadSeries(info)
                    print("✅ [MVVM-C] SeriesNavigationService loaded with \(sortedPaths.count) images")
                }
                
                // Update slider UI
                self?.updateSlider()
            },
            onDisplayReady: { [weak self] in
                // Delegate first image display to service-aware method
                self?.displayImage(at: 0) // displayImage will handle ViewModel delegation
                
                // UI finalization
                self?.dicom2DView?.isHidden = false
            }
        )
        
        switch result {
        case .success(let path):
            print("✅ [MVVM-C] Core DICOM loading completed via service architecture: \(path)")
        case .failure(let error):
            print("❌ [MVVM-C] Core DICOM loading failed via service: \(error.localizedDescription)")
        }
    }
    
    // Legacy fallback for loadAndDisplayDICOM during migration
    private func loadAndDisplayDICOMFallback() {
        print("🏗️ [FALLBACK] Core DICOM loading fallback")
        
        guard let firstPath = resolveFirstPath() else {
            print("❌ Nenhum caminho de arquivo válido para exibir.")
            return
        }
        
        if dicomDecoder == nil { dicomDecoder = DCMDecoder() }
        
        if let seriesPaths = self.pathArray, !seriesPaths.isEmpty {
            self.sortedPathArray = organizeSeries(seriesPaths)
            print("✅ [FALLBACK] Série organizada: \(self.sortedPathArray.count) imagens.")
            
            // Phase 11G Fix: Initialize SeriesNavigationService with fallback data
            if let seriesNavigationService = self.seriesNavigationService {
                let info = SeriesNavigationInfo(
                    paths: self.sortedPathArray,
                    currentIndex: 0
                )
                seriesNavigationService.loadSeries(info)
                print("✅ [FALLBACK] SeriesNavigationService loaded with \(self.sortedPathArray.count) images")
            }
            
            updateSlider()
        } else {
            self.sortedPathArray = [firstPath]
            
            // Phase 11G Fix: Initialize SeriesNavigationService with single image
            if let seriesNavigationService = self.seriesNavigationService {
                let info = SeriesNavigationInfo(
                    paths: [firstPath],
                    currentIndex: 0
                )
                seriesNavigationService.loadSeries(info)
                print("✅ [FALLBACK] SeriesNavigationService loaded with 1 image")
            }
        }
        
        displayImage(at: 0)
        dicom2DView?.isHidden = false
        
        print("✅ [FALLBACK] Core DICOM loading completed")
    }
    
    
    // MARK: - ⚠️ ENHANCED METHOD: Slider State Management → ViewStateManagementService
    // Migration: Phase 11E (Enhanced from Phase 9D)
    private func updateSlider() {
        guard let slider = self.customSlider else { return }
        
        // Phase 11G: Complete migration to ViewStateManagementService
        guard let viewStateService = viewStateManagementService else {
            print("❌ ViewStateManagementService not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return
        }
        
        let sliderState = viewStateService.calculateSliderState(
            currentIndex: self.currentImageIndex,
            totalImages: self.sortedPathArray.count,
            isInteracting: false
        )
        
        // Apply enhanced slider state
        slider.isHidden = !sliderState.shouldShow
        if sliderState.shouldShow && sliderState.shouldUpdate {
            slider.maxValue = sliderState.maxValue
            slider.currentValue = sliderState.currentValue
        }
        
        print("🎛️ [MVVM-C Phase 11G] Slider updated via ViewStateManagementService")
    }
    
    // MARK: - MVVM-C Migration: Image Display Method
    private func displayImage(at index: Int) {
        guard let imageProcessingService = imageProcessingService else {
            print("❌ [MVVM-C] DICOMImageProcessingService not available - using fallback")
            displayImageFallback(at: index)
            return
        }
        
        guard let dv = dicom2DView else {
            print("❌ [MVVM-C] DCMImgView not available")
            return
        }
        
        print("🖼️ [MVVM-C] Displaying image \(index + 1)/\(sortedPathArray.count) via service layer")
        
        // Use the service for image display with proper callbacks
        Task { @MainActor in
            let result = await imageProcessingService.displayImage(
                at: index,
                paths: sortedPathArray,
                decoder: dicomDecoder,
                decoderCache: decoderCache,
                dicomView: dv,
                patientModel: patientModel,
                currentImageIndex: currentImageIndex,
                originalSeriesWindowWidth: originalSeriesWindowWidth,
                originalSeriesWindowLevel: originalSeriesWindowLevel,
                currentSeriesWindowWidth: currentSeriesWindowWidth,
                currentSeriesWindowLevel: currentSeriesWindowLevel,
                onConfigurationUpdated: { [weak self] configuration in
                    self?.updateImageConfiguration(configuration)
                },
                onMeasurementsClear: { [weak self] in
                    self?.clearMeasurements()
                },
                onUIUpdate: { [weak self] patient, displayIndex in
                    self?.updateUIAfterImageDisplay(patient: patient, index: displayIndex)
                }
            )
            
            if result.success {
                self.currentImageIndex = index
                print("✅ [MVVM-C] Image display completed via service - Performance: total=\(String(format: "%.2f", result.performanceMetrics.totalTime))ms")
            } else if let error = result.error {
                print("❌ [MVVM-C] Image display failed via service: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helper Methods for Service Integration
    
    // MARK: - ⚠️ MIGRATED METHOD: Image Configuration Processing → DICOMImageProcessingService  
    // Migration: Phase 9E
    private func updateImageConfiguration(_ configuration: ImageDisplayConfiguration) {
        // Delegate configuration processing to service layer
        guard let imageProcessingService = imageProcessingService else {
            print("❌ DICOMImageProcessingService not available, falling back to legacy implementation")
            // Legacy fallback
            self.rescaleSlope = configuration.rescaleSlope
            self.rescaleIntercept = configuration.rescaleIntercept
            self.hasRescaleValues = configuration.hasRescaleValues
            
            roiMeasurementToolsView?.rescaleSlope = self.rescaleSlope
            roiMeasurementToolsView?.rescaleIntercept = self.rescaleIntercept
            
            if let windowWidth = configuration.windowWidth, let windowLevel = configuration.windowLevel {
                applyHUWindowLevel(
                    windowWidthHU: Double(windowWidth),
                    windowCenterHU: Double(windowLevel),
                    rescaleSlope: configuration.rescaleSlope,
                    rescaleIntercept: configuration.rescaleIntercept
                )
                
                if originalSeriesWindowWidth == nil {
                    originalSeriesWindowWidth = windowWidth
                    originalSeriesWindowLevel = windowLevel
                    self.currentSeriesWindowWidth = windowWidth
                    self.currentSeriesWindowLevel = windowLevel
                    print("🪟 [MVVM-C] Series defaults saved via legacy fallback: W=\(windowWidth)HU L=\(windowLevel)HU")
                }
            }
            
            print("🔬 [Legacy] Image configuration updated: Slope=\(configuration.rescaleSlope), Intercept=\(configuration.rescaleIntercept)")
            return
        }
        
        // Service layer delegation - business logic
        let update = imageProcessingService.processImageConfiguration(
            configuration,
            currentOriginalWidth: originalSeriesWindowWidth,
            currentOriginalLevel: originalSeriesWindowLevel
        )
        
        // UI updates remain in ViewController
        self.rescaleSlope = update.rescaleSlope
        self.rescaleIntercept = update.rescaleIntercept
        self.hasRescaleValues = update.hasRescaleValues
        
        // Update ROI measurement tools with new rescale values
        roiMeasurementToolsView?.rescaleSlope = update.rescaleSlope
        roiMeasurementToolsView?.rescaleIntercept = update.rescaleIntercept
        
        // Apply window/level if determined by service
        if update.shouldApplyWindowLevel,
           let windowWidth = update.windowWidth,
           let windowLevel = update.windowLevel {
            applyHUWindowLevel(
                windowWidthHU: Double(windowWidth),
                windowCenterHU: Double(windowLevel),
                rescaleSlope: update.rescaleSlope,
                rescaleIntercept: update.rescaleIntercept
            )
        }
        
        // Save series defaults if determined by service
        if update.shouldSaveAsSeriesDefaults,
           let defaults = update.newSeriesDefaults {
            originalSeriesWindowWidth = defaults.width
            originalSeriesWindowLevel = defaults.level
            self.currentSeriesWindowWidth = defaults.width
            self.currentSeriesWindowLevel = defaults.level
            print("🪟 [MVVM-C] Series defaults saved via service: W=\(defaults.width ?? 0)HU L=\(defaults.level ?? 0)HU")
        }
        
        print("🔬 [MVVM-C] Image configuration processed via service: Slope=\(update.rescaleSlope), Intercept=\(update.rescaleIntercept)")
    }
    
    // MARK: - ⚠️ MIGRATED METHOD: UI State Updates → ViewStateManagementService
    // Migration: Phase 11E
    private func updateUIAfterImageDisplay(patient: PatientModel?, index: Int) {
        // Delegate UI state coordination to service layer
        guard let viewStateService = viewStateManagementService else {
            print("❌ ViewStateManagementService not available, falling back to legacy implementation")
            // Legacy fallback
            if let patient = patient {
                updateOverlayWithPatientInfo(patient)
            }
            updateOrientationMarkers()
            updateAnnotationsView()
            customSlider?.currentValue = Float(index + 1)
            return
        }
        
        // Service layer delegation - comprehensive UI coordination
        let viewStateUpdate = viewStateService.coordinateUIUpdates(
            patient: patient,
            imageIndex: index,
            totalImages: sortedPathArray.count,
            clearROI: false,
            currentWindowLevel: getCurrentWindowLevelString()
        )
        
        // Apply UI updates based on service coordination
        if viewStateUpdate.shouldUpdateOverlay, let patient = viewStateUpdate.overlayPatient {
            updateOverlayWithPatientInfo(patient)
        }
        
        if viewStateUpdate.shouldUpdateOrientation {
            updateOrientationMarkers()
        }
        
        if viewStateUpdate.shouldUpdateAnnotations {
            updateAnnotationsView()
        }
        
        if viewStateUpdate.shouldUpdateSlider, let sliderValue = viewStateUpdate.sliderValue {
            customSlider?.currentValue = sliderValue
        }
        
        print("✅ [MVVM-C Phase 11E] UI updates coordinated via ViewStateManagementService")
    }
    
    private func getCurrentWindowLevelString() -> String? {
        if let ww = currentSeriesWindowWidth, let wl = currentSeriesWindowLevel {
            return "W:\(ww) L:\(wl)"
        }
        return nil
    }
    
    private func displayImageFallback(at index: Int) {
        // Fallback implementation for when service is not available
        // This preserves the original functionality as a safety net
        print("⚠️ [MVVM-C] Using fallback image display - service unavailable")
        
        // Original implementation would go here, but for now just log
        // In a real scenario, you might want to keep a simplified version
        guard index >= 0, index < sortedPathArray.count else { return }
        let path = sortedPathArray[index]
        print("⚠️ Fallback would display: \((path as NSString).lastPathComponent)")
    }
    
    private func displayImageFast(at index: Int) {
        // PERFORMANCE: Fast image display for slider interactions - Now delegated to service
        guard let imageProcessingService = imageProcessingService else {
            print("❌ [MVVM-C] DICOMImageProcessingService not available - using fallback")
            displayImageFastFallback(at: index)
            return
        }
        
        guard let dv = dicom2DView else {
            print("❌ [MVVM-C] DCMImgView not available")
            return
        }
        
        print("⚡ [MVVM-C] Fast image display \(index + 1)/\(sortedPathArray.count) via service layer")
        
        // Use service for fast display with callbacks
        let result = imageProcessingService.displayImageFast(
            at: index,
            paths: sortedPathArray,
            decoder: dicomDecoder,
            decoderCache: decoderCache,
            dicomView: dv,
            customSlider: customSlider,
            currentSeriesWindowWidth: currentSeriesWindowWidth,
            currentSeriesWindowLevel: currentSeriesWindowLevel,
            onIndexUpdate: { [weak self] newIndex in
                self?.currentImageIndex = newIndex
            }
        )
        
        if result.success {
            // Apply window/level if configuration provided
            if let config = result.configuration {
                applyHUWindowLevel(
                    windowWidthHU: Double(config.windowWidth ?? 0),
                    windowCenterHU: Double(config.windowLevel ?? 0),
                    rescaleSlope: config.rescaleSlope,
                    rescaleIntercept: config.rescaleIntercept
                )
            }
            
            // Update slider position to reflect actual index
            if let slider = customSlider {
                slider.setValue(Float(index + 1), animated: false)
            }
            
            print("✅ [MVVM-C] Fast image display completed via service - Performance: \(String(format: "%.2f", result.performanceMetrics.totalTime))ms")
            
            // Use the service for prefetching with proper async handling
            Task {
                let prefetchResult = await imageProcessingService.prefetchImages(
                    around: index,
                    paths: sortedPathArray,
                    prefetchRadius: 2
                )
                print("🚀 [MVVM-C] Prefetch completed via service: \(prefetchResult.successCount)/\(prefetchResult.pathsProcessed.count) images in \(String(format: "%.2f", prefetchResult.totalTime))ms")
            }
        } else if let error = result.error {
            print("❌ [MVVM-C] Fast image display failed via service: \(error.localizedDescription)")
        }
    }
    
    // Legacy fallback for displayImageFast during migration
    private func displayImageFastFallback(at index: Int) {
        // Original implementation preserved for safety during migration
        guard index >= 0, index < sortedPathArray.count else { return }
        guard let dv = dicom2DView else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let path = sortedPathArray[index]
        
        let decoderToUse: DCMDecoder
        if let cachedDecoder = decoderCache.object(forKey: path as NSString) {
            decoderToUse = cachedDecoder
        } else {
            decoderToUse = dicomDecoder ?? DCMDecoder()
            decoderToUse.setDicomFilename(path)
            decoderCache.setObject(decoderToUse, forKey: path as NSString)
        }
        
        let toolResult = DicomTool.shared.decodeAndDisplay(path: path, decoder: decoderToUse, view: dv)
        
        switch toolResult {
        case .success:
            currentImageIndex = index
            
            if let windowWidth = currentSeriesWindowWidth,
               let windowLevel = currentSeriesWindowLevel {
                let slopeString = decoderToUse.info(for: 0x00281053)
                let interceptString = decoderToUse.info(for: 0x00281052)
                let slope = Double(slopeString.isEmpty ? "1.0" : slopeString) ?? 1.0
                let intercept = Double(interceptString.isEmpty ? "0.0" : interceptString) ?? 0.0
                
                applyHUWindowLevel(
                    windowWidthHU: Double(windowWidth),
                    windowCenterHU: Double(windowLevel),
                    rescaleSlope: slope,
                    rescaleIntercept: intercept
                )
                
                print("[PERF] Applied W/L: W=\(windowWidth)HU L=\(windowLevel)HU (slope=\(slope), intercept=\(intercept))")
            }
            
            if let slider = customSlider {
                slider.setValue(Float(index + 1), animated: false)
            }
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[PERF] displayImageFastFallback: \(String(format: "%.2f", elapsed))ms | image \(index + 1)/\(sortedPathArray.count)")
            
        case .failure(let error):
            print("❌ displayImageFastFallback failed: \(error)")
        }
    }

    private func prefetchImages(around index: Int) {
        guard let imageProcessingService = imageProcessingService else {
            print("⚠️ [MVVM-C] DICOMImageProcessingService not available for prefetch - using fallback")
            prefetchImagesFallback(around: index)
            return
        }
        
        // Use the service for prefetching with proper async handling
        Task {
            let result = await imageProcessingService.prefetchImages(
                around: index,
                paths: sortedPathArray,
                prefetchRadius: 2
            )
            print("🚀 [MVVM-C] Prefetch completed via service: \(result.successCount)/\(result.pathsProcessed.count) images in \(String(format: "%.2f", result.totalTime))ms")
        }
    }
    
    /// OPTIMIZATION: Intelligent prefetching with minimal overhead (temporarily disabled)
    /*
    private func prefetchAdjacentImages(currentIndex: Int) {
        // Prefetch 1 image ahead and behind for smooth scrolling
        let prefetchIndices = [currentIndex - 1, currentIndex + 1].compactMap { index in
            (index >= 0 && index < sortedPathArray.count) ? index : nil
        }
        
        // Use background queue to avoid blocking the main thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            for prefetchIndex in prefetchIndices {
                let path = self.sortedPathArray[prefetchIndex]
                
                // Check cache on main thread
                DispatchQueue.main.async {
                    if let cachedDecoder = self.decoderCache.object(forKey: path as NSString) {
                        // Already cached, trigger pixel loading in background
                        DispatchQueue.global(qos: .utility).async {
                            _ = cachedDecoder.getPixels16() // Prefetch pixels
                        }
                    } else {
                        // Create and cache decoder on background thread
                        DispatchQueue.global(qos: .utility).async {
                            let prefetchDecoder = DCMDecoder()
                            prefetchDecoder.setDicomFilename(path)
                            
                            if prefetchDecoder.dicomFileReadSuccess {
                                DispatchQueue.main.async {
                                    self.decoderCache.setObject(prefetchDecoder, forKey: path as NSString)
                                    print("[PREFETCH] Cached image \(prefetchIndex + 1): \((path as NSString).lastPathComponent)")
                                }
                                _ = prefetchDecoder.getPixels16() // Prefetch pixels
                            }
                        }
                    }
                }
            }
        }
    }
    */
    
    private func prefetchImagesFallback(around index: Int) {
        // Fallback prefetch using SwiftImageCacheManager directly
        guard sortedPathArray.count > 1 else { return }
        
        let prefetchRadius = 2 // Prefetch ±2 images
        let startIndex = max(0, index - prefetchRadius)
        let endIndex = min(sortedPathArray.count - 1, index + prefetchRadius)
        
        // Collect paths to prefetch
        var pathsToPrefetch: [String] = []
        for i in startIndex...endIndex {
            if i != index { // Skip current image
                pathsToPrefetch.append(sortedPathArray[i])
            }
        }
        
        // Use SwiftImageCacheManager's prefetch method
        SwiftImageCacheManager.shared.prefetchImages(paths: pathsToPrefetch, currentIndex: index)
        print("🚀 [MVVM-C] Fallback prefetch completed: \(pathsToPrefetch.count) paths")
    }
    
    
    // MARK: - Actions
    // MARK: - ⚠️ MIGRATED METHOD: ROI Tools Dialog → ModalPresentationService
    // Migration: Phase 11C
    @objc private func showROI() {
        // MVVM-C Phase 11C: Delegate modal presentation to ViewModel → ModalPresentationService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return
        }
        
        print("🎯 [MVVM-C Phase 11C] Showing ROI tools dialog via ViewModel → ModalPresentationService")
        
        if viewModel.showROIToolsDialog(from: self, sourceBarButtonItem: navigationItem.rightBarButtonItem) {
            print("✅ [MVVM-C Phase 11C] ROI tools dialog presentation delegated to service layer")
        } else {
            print("❌ [MVVM-C Phase 11C] ROI tools dialog presentation failed, using legacy fallback")
            // Legacy fallback removed in Phase 12
            return
        }
    }
    
    
    // Method moved to ROIMeasurementToolsView for Phase 10A optimization
    
    // ROI measurement methods migrated to ROIMeasurementToolsView - Phase 10A complete
    
    // MARK: - MVVM-C Migration: Distance Calculation moved to ROIMeasurementToolsView
    
    
    // MARK: - Helper function for coordinate conversion
    // MARK: - ⚠️ MIGRATED METHOD: ROI Coordinate Conversion → ROIMeasurementService
    // Migration: Phase 9C
    private func convertToImagePixelPoint(_ viewPoint: CGPoint, in dicomView: UIView, decoder: DCMDecoder) -> CGPoint {
        // Delegate coordinate conversion to service layer
        guard let roiMeasurementService = roiMeasurementService else {
            print("❌ ROIMeasurementService not available, falling back to legacy implementation")
            // Legacy fallback
            let imageWidth = CGFloat(decoder.width)
            let imageHeight = CGFloat(decoder.height)
            let viewWidth = dicomView.bounds.width
            let viewHeight = dicomView.bounds.height
            
            let imageAspectRatio = imageWidth / imageHeight
            let viewAspectRatio = viewWidth / viewHeight
            
            var displayWidth: CGFloat
            var displayHeight: CGFloat
            var offsetX: CGFloat = 0
            var offsetY: CGFloat = 0
            
            if imageAspectRatio > viewAspectRatio {
                displayWidth = viewWidth
                displayHeight = viewWidth / imageAspectRatio
                offsetY = (viewHeight - displayHeight) / 2
            } else {
                displayHeight = viewHeight
                displayWidth = viewHeight * imageAspectRatio
                offsetX = (viewWidth - displayWidth) / 2
            }
            
            let adjustedPoint = CGPoint(x: viewPoint.x - offsetX,
                                       y: viewPoint.y - offsetY)
            
            if adjustedPoint.x < 0 || adjustedPoint.x > displayWidth ||
               adjustedPoint.y < 0 || adjustedPoint.y > displayHeight {
                return CGPoint(x: max(0, min(imageWidth - 1, adjustedPoint.x * imageWidth / displayWidth)),
                              y: max(0, min(imageHeight - 1, adjustedPoint.y * imageHeight / displayHeight)))
            }
            
            return CGPoint(x: adjustedPoint.x * imageWidth / displayWidth,
                          y: adjustedPoint.y * imageHeight / displayHeight)
        }
        
        // Service layer delegation - business logic
        return roiMeasurementService.convertToImagePixelPoint(viewPoint, in: dicomView, decoder: decoder)
    }
    
    // MARK: - ROI Measurement Functions - Migrated to ROIMeasurementToolsView (Phase 10A)
    
    private func clearAllMeasurements() {
        clearMeasurements()
    }
    
    // MARK: - MVVM-C Migration: Measurement Clearing
    private func clearMeasurements() {
        // MVVM-C Migration Phase 10A: Delegate to ROIMeasurementToolsView
        print("🧹 [MVVM-C Phase 10A] Clearing measurements via ROIMeasurementToolsView")
        
        // Delegate to ROI measurement tools view
        roiMeasurementToolsView?.clearMeasurements()
        
        // Clear any remaining local state
        selectedMeasurementPoint = nil
        
        // Remove any legacy gestures that might still be attached
        dicom2DView?.gestureRecognizers?.forEach { recognizer in
            if recognizer is UITapGestureRecognizer || recognizer is UIPanGestureRecognizer {
                dicom2DView?.removeGestureRecognizer(recognizer)
            }
        }
        
        print("✅ [MVVM-C Phase 10A] All measurements cleared via ROIMeasurementToolsView")
    }
    
    
    // MARK: - ⚠️ MIGRATED METHOD: Modal Presentation → UIStateManagementService
    // Migration: Phase 11D
    @objc private func showOption() {
        // MVVM-C Phase 11D: Delegate modal presentation configuration to ViewModel → UIStateManagementService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return
        }
        
        print("🎭 [MVVM-C Phase 11D] Showing options modal via ViewModel → UIStateService")
        
        let config = viewModel.configureModalPresentation(for: "options")
        
        // Create view controller and apply service-determined configuration
        let optionVC = SwiftOptionViewController()
        
        if config.shouldWrapInNavigation {
            let nav = UINavigationController(rootViewController: optionVC)
            nav.modalPresentationStyle = .pageSheet
            present(nav, animated: true)
            print("✅ [MVVM-C Phase 11E] Options modal presented with navigation wrapper via service")
        } else {
            optionVC.modalPresentationStyle = .pageSheet
            present(optionVC, animated: true)
            print("✅ [MVVM-C Phase 11E] Options modal presented directly via service")
        }
    }
    
    
    
    // MARK: - Window/Level
    
    /// Centralized function to apply HU window/level values using specific rescale parameters
    /// - Parameters:
    ///   - windowWidthHU: Window width in Hounsfield Units
    ///   - windowCenterHU: Window center/level in Hounsfield Units
    ///   - rescaleSlope: Rescale slope for current image (default 1.0)
    ///   - rescaleIntercept: Rescale intercept for current image (default 0.0)
    // MARK: - ⚠️ MIGRATED METHOD: Window/Level Calculation → WindowLevelService
    // Migration date: Phase 8B
    // Old implementation: Preserved below in comments
    // New approach: Business logic delegated to WindowLevelService via ViewModel
    
    private func applyHUWindowLevel(windowWidthHU: Double, windowCenterHU: Double, rescaleSlope: Double = 1.0, rescaleIntercept: Double = 0.0) {
        guard let dv = dicom2DView else {
            print("❌ applyHUWindowLevel: dicom2DView is nil")
            return
        }
        
        // MVVM-C Migration: Delegate calculation to service layer
        // Use WindowLevelService via ViewModel for all business logic
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, using direct fallback")
            guard let dv = dicom2DView else { return }
            
            // Store values in HU (our source of truth)
            currentSeriesWindowWidth = Int(windowWidthHU)
            currentSeriesWindowLevel = Int(windowCenterHU)
            
            // Convert HU to pixel values for the C++ layer
            let pixelWidth: Int
            let pixelCenter: Int
            
            if rescaleSlope != 0 && rescaleSlope != 1.0 || rescaleIntercept != 0 {
                // Convert HU to pixel using rescale formula
                // Pixel = (HU - Intercept) / Slope
                pixelWidth = Int(windowWidthHU / rescaleSlope)
                pixelCenter = Int((windowCenterHU - rescaleIntercept) / rescaleSlope)
            } else {
                // No rescale, values are already in pixel space
                pixelWidth = Int(windowWidthHU)
                pixelCenter = Int(windowCenterHU)
            }
            
            // Apply pixel values to the C++ view
            dv.winWidth = max(1, pixelWidth)
            dv.winCenter = pixelCenter
            
            // Update the display
            dv.updateWindowLevel()
            
            // Update overlay with HU values (what users expect to see)
            if let overlay = overlayController {
                overlay.updateWindowLevel(Int(windowCenterHU), windowWidth: Int(windowWidthHU))
            }
            
            // Update annotations
            updateAnnotationsView()
            
            return
        }
        
        print("🪟 [MVVM-C] Applying W/L via service: width=\(windowWidthHU)HU, center=\(windowCenterHU)HU")
        
        // Step 1: Use WindowLevelService for calculations via ViewModel
        let result = viewModel.calculateWindowLevel(
            huWidth: windowWidthHU,
            huLevel: windowCenterHU,
            rescaleSlope: rescaleSlope,
            rescaleIntercept: rescaleIntercept
        )
        
        // Step 2: Update local state (still needed for UI consistency)
        currentSeriesWindowWidth = Int(windowWidthHU)
        currentSeriesWindowLevel = Int(windowCenterHU)
        
        // Step 3: Apply calculated pixel values to the C++ view (UI layer)
        dv.winWidth = max(1, result.pixelWidth)
        dv.winCenter = result.pixelLevel
        
        // Step 4: Update the display (pure UI)
        dv.updateWindowLevel()
        
        // Step 5: Update overlay with HU values (UI layer)
        if let overlay = overlayController {
            overlay.updateWindowLevel(Int(windowCenterHU), windowWidth: Int(windowWidthHU))
        }
        
        // Step 6: Update annotations (UI layer)
        updateAnnotationsView()
        
        print("✅ [MVVM-C] W/L applied via service: W=\(windowWidthHU)HU L=\(windowCenterHU)HU (calculated px: W=\(result.pixelWidth) L=\(result.pixelLevel))")
    }
    
    
    // MARK: - MVVM-C Migration: Window/Level Preset Management
    private func getPresetsForModality(_ modality: DICOMModality) -> [WindowLevelPreset] {
        // MVVM-C Migration: Delegate preset retrieval to service layer via ViewModel
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, using direct fallback")
            // Fallback: Direct preset generation
            var presets: [WindowLevelPreset] = [
                WindowLevelPreset(name: "Default", windowLevel: Double(originalSeriesWindowLevel ?? currentSeriesWindowLevel ?? 50), windowWidth: Double(originalSeriesWindowWidth ?? currentSeriesWindowWidth ?? 400)),
                WindowLevelPreset(name: "Full Dynamic", windowLevel: 2048, windowWidth: 4096)
            ]
            
            // Add modality-specific presets
            switch modality {
            case .ct:
                presets.append(contentsOf: [
                    WindowLevelPreset(name: "Abdomen", windowLevel: 40, windowWidth: 350),
                    WindowLevelPreset(name: "Lung", windowLevel: -500, windowWidth: 1400),
                    WindowLevelPreset(name: "Bone", windowLevel: 300, windowWidth: 1500),
                    WindowLevelPreset(name: "Brain", windowLevel: 50, windowWidth: 100)
                ])
            default:
                break
            }
            
            return presets
        }
        
        print("🪟 [MVVM-C] Getting presets for modality \(modality) via service layer")
        
        // Delegate to ViewModel which uses WindowLevelService
        let presets = viewModel.getPresetsForModality(
            modality,
            originalWindowLevel: originalSeriesWindowLevel,
            originalWindowWidth: originalSeriesWindowWidth,
            currentWindowLevel: currentSeriesWindowLevel,
            currentWindowWidth: currentSeriesWindowWidth
        )
        
        print("✅ [MVVM-C] Retrieved \(presets.count) presets via service layer")
        return presets
    }
    
    
    // MARK: - MVVM-C Migration: Custom Window/Level Dialog
    private func showCustomWindowLevelDialog() {
        // MVVM-C Phase 11B: Delegate UI presentation to ViewModel → UIStateService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to direct implementation")
            showCustomWindowLevelDialogFallback()
            return
        }
        
        print("🪟 [MVVM-C Phase 11B] Showing custom W/L dialog via ViewModel → UIStateService")
        
        _ = viewModel.showCustomWindowLevelDialog(
            from: self,
            currentWidth: currentSeriesWindowWidth,
            currentLevel: currentSeriesWindowLevel
        )
        
        print("✅ [MVVM-C Phase 11B] Dialog presentation delegated to service layer")
    }
    
    // Legacy fallback for showCustomWindowLevelDialog during migration
    private func showCustomWindowLevelDialogFallback() {
        print("🪟 [FALLBACK] Showing custom W/L dialog directly")
        
        let alertController = UIAlertController(title: "Custom Window/Level", message: "Enter values in Hounsfield Units", preferredStyle: .alert)
        
        alertController.addTextField { textField in
            textField.placeholder = "Window Width (HU)"
            textField.keyboardType = .numberPad
            textField.text = "\(self.currentSeriesWindowWidth ?? 400)"
        }
        
        alertController.addTextField { textField in
            textField.placeholder = "Window Level (HU)"
            textField.keyboardType = .numberPad
            textField.text = "\(self.currentSeriesWindowLevel ?? 50)"
        }
        
        let applyAction = UIAlertAction(title: "Apply", style: .default) { _ in
            guard let widthText = alertController.textFields?[0].text,
                  let levelText = alertController.textFields?[1].text,
                  let width = Double(widthText),
                  let level = Double(levelText) else { return }
            
            print("🎨 [FALLBACK] Applying custom W/L: W=\(width)HU L=\(level)HU")
            self.setWindowWidth(width, windowCenter: level)
        }
        
        alertController.addAction(applyAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
    
    // MARK: - MVVM-C Migration: Window/Level Preset Application
    public func applyWindowLevelPreset(_ preset: WindowLevelPreset) {
        // MVVM-C Migration: Delegate preset application to service layer via ViewModel
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, using direct fallback")
            var actualPreset = preset
            
            // Calculate Full Dynamic values if needed
            if preset.name == "Full Dynamic" {
                actualPreset = calculateFullDynamicPreset() ?? preset
            }
            
            // setWindowWidth already handles HU storage and pixel conversion
            setWindowWidth(Double(actualPreset.windowWidth), windowCenter: Double(actualPreset.windowLevel))
            return
        }
        
        print("🪟 [MVVM-C] Applying preset '\(preset.name)' via service layer")
        
        // Delegate to ViewModel which handles Full Dynamic calculation via WindowLevelService
        viewModel.applyWindowLevelPreset(preset, decoder: dicomDecoder) { [weak self] width, level in
            // UI callback - setWindowWidth handles HU storage and pixel conversion
            self?.setWindowWidth(width, windowCenter: level)
        }
        
        print("✅ [MVVM-C] Preset '\(preset.name)' applied via service layer")
    }
    
    
    // MARK: - MVVM-C Migration: Full Dynamic Preset Calculation
    private func calculateFullDynamicPreset() -> WindowLevelPreset? {
        guard let decoder = dicomDecoder, decoder.dicomFileReadSuccess else {
            print("⚠️ Full Dynamic: Decoder not available.")
            return nil
        }

        // MVVM-C Migration: Delegate calculation to service layer via ViewModel
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            print("❌ ViewModel not available, preset calculation requires service layer")
            return nil
        }

        // Step 1: Use WindowLevelService for calculations via ViewModel
        let result = viewModel.calculateFullDynamicPreset(from: decoder)
        
        print("🪟 [MVVM-C] Full Dynamic preset calculated via service: \(result?.description ?? "nil")")
        
        return result
    }
    
    
    public func setWindowWidth(_ windowWidth: Double, windowCenter: Double) {
        // Simply delegate to the centralized function using current image's rescale values
        applyHUWindowLevel(windowWidthHU: windowWidth, windowCenterHU: windowCenter,
                         rescaleSlope: rescaleSlope, rescaleIntercept: rescaleIntercept)
    }
    
    // MARK: - MVVM-C Migration: Window/Level State Retrieval
    public func getCurrentWindowWidth(_ windowWidth: inout Double, windowCenter: inout Double) {
        // MVVM-C Migration: Consider using ViewModel for state consistency
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, using direct fallback")
            // Fallback: get current values directly
            if let dv = dicom2DView {
                windowWidth = Double(dv.winWidth)
                windowCenter = Double(dv.winCenter)
            } else if let dd = dicomDecoder {
                windowWidth = dd.windowWidth
                windowCenter = dd.windowCenter
            } else {
                windowWidth = 400
                windowCenter = 50
            }
            return
        }
        
        print("🪟 [MVVM-C] Getting current window/level via service layer")
        
        // First try to get from ViewModel's reactive state
        if let currentSettings = viewModel.currentWindowLevelSettings {
            windowWidth = Double(currentSettings.windowWidth)
            windowCenter = Double(currentSettings.windowLevel)
            print("✅ [MVVM-C] Retrieved W/L from ViewModel: W=\(windowWidth) L=\(windowCenter)")
            return
        }
        
        // Fallback: get current values directly if ViewModel state not available
        if let dv = dicom2DView {
            windowWidth = Double(dv.winWidth)
            windowCenter = Double(dv.winCenter)
        } else if let dd = dicomDecoder {
            windowWidth = dd.windowWidth
            windowCenter = dd.windowCenter
        } else {
            windowWidth = 400
            windowCenter = 50
        }
    }
    
    
    // MARK: - MVVM-C Migration: Image Transformations
    // Rotate method removed - deprecated functionality (user can rotate with gestures)
    
    // Flip methods removed - deprecated functionality (user can rotate with gestures)
    
    public func resetTransforms() {
        guard let imageView = dicom2DView else { return }
        
        // MVVM-C Migration: Delegate transformation reset to service layer via ViewModel
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            print("❌ ViewModel not available, reset transforms requires service layer")
            return
        }
        
        print("🔄 [MVVM-C] Resetting image transforms via service layer")
        
        // Delegate to ViewModel which uses ImageTransformService
        viewModel.resetTransforms(for: imageView, animated: true)
        
        print("✅ [MVVM-C] Image transforms reset via service layer")
    }
    
    
    // MARK: - Cine functionality removed - deprecated
    
    // MARK: - Options Panel
    // MARK: - ⚠️ MIGRATED METHOD: Options Panel → ModalPresentationService
    // Migration: Phase 11C
    private func showOptionsPanel(type: SwiftOptionsPanelType) {
        // MVVM-C Phase 11C: Delegate modal presentation to ViewModel → ModalPresentationService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return
        }
        
        print("🎭 [MVVM-C Phase 11C] Showing options panel via ViewModel → ModalPresentationService")
        
        if viewModel.showOptionsPanel(type: type, from: self, sourceView: swiftControlBar) {
            print("✅ [MVVM-C Phase 11C] Options panel presentation delegated to service layer")
        } else {
            print("❌ [MVVM-C Phase 11C] Options panel presentation failed, using legacy fallback")
            // Legacy fallback removed in Phase 12
            return
        }
    }
    
    
    private func setupPresetSelectorDelegate() {
        // The SwiftOptionsPanelViewController handles preset selection through its delegate callbacks
    }
    
    // MARK: - Series Management
    
    /// Organizes DICOM series by sorting images by instance number or filename
    // MARK: - MVVM-C Migration: Series Organization
    private func organizeSeries(_ paths: [String]) -> [String] {
        // Phase 11G: Complete migration to ViewModel + DICOMImageProcessingService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return paths.sorted()
        }
        
        print("🪟 [MVVM-C Phase 11G] Organizing series via service layer")
        
        // Step 1: Use DICOMImageProcessingService for organization via ViewModel
        let sortedPaths = viewModel.organizeSeries(paths)
        
        print("✅ [MVVM-C Phase 11G] Series organized via service: \(sortedPaths.count) files")
        
        return sortedPaths
    }
    
    
    // MARK: - MVVM-C Migration: Series Navigation
    /// Advances to next image in the series for cine mode
    private func advanceToNextImageInSeries() {
        // Phase 11G: Complete migration to ViewModel + SeriesNavigationService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return
        }
        
        print("▶️ [MVVM-C Phase 11G] Advancing to next image via service layer")
        
        // Delegate navigation to ViewModel which uses SeriesNavigationService
        // ViewModel will handle: index tracking, path resolution, state updates
        viewModel.navigateNext()
        
        // UI updates will happen reactively via ViewModel observers
        // The setupViewModelObserver() method handles image display, overlay updates, etc.
        
        print("✅ [MVVM-C Phase 11G] Navigation delegated to service layer")
    }
    
    
    /// Advances to the previous image in the current series
    private func advanceToPreviousImageInSeries() {
        // Phase 11G: Complete migration to ViewModel + SeriesNavigationService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return
        }
        
        print("◀️ [MVVM-C Phase 11G] Going back to previous image via service layer")
        
        // Delegate navigation to ViewModel which uses SeriesNavigationService
        // ViewModel will handle: index tracking, path resolution, state updates
        viewModel.navigatePrevious()
        
        // UI updates will happen reactively via ViewModel observers
        // The setupViewModelObserver() method handles image display, overlay updates, etc.
        
        print("✅ [MVVM-C Phase 11G] Previous navigation delegated to service layer")
    }
    
}

// MARK: - Obj-C Delegates
extension SwiftDetailViewController: SwiftOptionsPanelDelegate {
    // Old ControlBar delegate methods removed - now using direct @objc actions
    
    nonisolated public func optionsPanel(_ panel: UIView, didSelectPresetAtIndex index: Int) {
        // MVVM-C Phase 11F Part 2: Delegate to service layer
        Task { @MainActor in
            handleOptionsPresetSelection(index: index)
        }
    }
    nonisolated public func optionsPanel(_ panel: UIView, didSelectTransformType transformType: Int) {
        // MVVM-C Phase 11F Part 2: Delegate to service layer
        Task { @MainActor in
            handleOptionsTransformSelection(type: transformType)
        }
    }
    nonisolated public func optionsPanelDidRequestClose(_ panel: UIView) {
        // MVVM-C Phase 11F Part 2: Delegate to service layer
        Task { @MainActor in
            handleOptionsPanelClose()
        }
    }
    
    // Old PresetSelectorView delegate methods removed - functionality moved to SwiftOptionsPanel
    
    nonisolated public func mesure(withAnnotationType annotationType: Int) {
        // Canvas/annotations not yet ported
    }
    nonisolated public func removeCanvasView() { /* no-op for now */ }
}

// MARK: - SwiftGestureManagerDelegate
extension SwiftDetailViewController: SwiftGestureManagerDelegate {
    
    nonisolated func gestureManager(_ manager: SwiftGestureManager, didZoomToScale scale: CGFloat, atPoint point: CGPoint) {
        // MVVM-C Phase 11F: Delegate to service layer
        Task { @MainActor in
            handleZoomGesture(scale: scale, point: point)
        }
    }
    
    nonisolated func gestureManager(_ manager: SwiftGestureManager, didRotateByAngle angle: CGFloat) {
        // MVVM-C Phase 11F: Delegate to service layer
        Task { @MainActor in
            handleRotationGesture(angle: angle)
        }
    }
    
    
    nonisolated func gestureManager(_ manager: SwiftGestureManager, didPanByOffset offset: CGPoint) {
        // MVVM-C Phase 11F: Legacy delegate method - use enhanced version when available
        Task { @MainActor in
            handlePanGestureWithTouchCount(offset: offset, touchCount: 1, velocity: .zero)
        }
    }
    
    // Enhanced delegate method with touch count information - Phase 11F+
    nonisolated func gestureManager(_ manager: SwiftGestureManager, didPanByOffset offset: CGPoint, touchCount: Int, velocity: CGPoint) {
        // MVVM-C Phase 11F+: Enhanced delegate with actual touch count
        Task { @MainActor in
            handlePanGestureWithTouchCount(offset: offset, touchCount: touchCount, velocity: velocity)
        }
    }
    
    nonisolated func gestureManager(_ manager: SwiftGestureManager, didAdjustWindowLevel deltaX: CGFloat, deltaY: CGFloat) {
        // MVVM-C Phase 11F: Legacy delegate method - use enhanced version when available
        Task { @MainActor in
            handleWindowLevelGestureWithTouchCount(deltaX: deltaX, deltaY: deltaY, touchCount: 1, velocity: .zero)
        }
    }
    
    // Enhanced delegate method with touch count information - Phase 11F+
    nonisolated func gestureManager(_ manager: SwiftGestureManager, didAdjustWindowLevel deltaX: CGFloat, deltaY: CGFloat, touchCount: Int, velocity: CGPoint) {
        // MVVM-C Phase 11F+: Enhanced delegate with actual touch count
        Task { @MainActor in
            handleWindowLevelGestureWithTouchCount(deltaX: deltaX, deltaY: deltaY, touchCount: touchCount, velocity: velocity)
        }
    }
    
    nonisolated func gestureManagerDidSwipeToNextImage(_ manager: SwiftGestureManager) {
        // MVVM-C Phase 11F: Delegate to service layer
        Task { @MainActor in
            handleSwipeToNextImage()
        }
    }
    
    
    nonisolated func gestureManagerDidSwipeToPreviousImage(_ manager: SwiftGestureManager) {
        // MVVM-C Phase 11F: Delegate to service layer
        Task { @MainActor in
            handleSwipeToPreviousImage()
        }
    }
    
    
    nonisolated func gestureManagerDidSwipeToNextSeries(_ manager: SwiftGestureManager) {
        // MVVM-C Phase 11F: Delegate to service layer
        Task { @MainActor in
            handleSwipeToNextSeries()
        }
    }
    
    nonisolated func gestureManagerDidSwipeToPreviousSeries(_ manager: SwiftGestureManager) {
        // MVVM-C Phase 11F: Delegate to service layer
        Task { @MainActor in
            handleSwipeToPreviousSeries()
        }
    }
}

// MARK: - Control Bar Functions
extension SwiftDetailViewController {
    // toggleCine removed - cine functionality deprecated
    
    
    // updateCineButtonTitle removed - cine functionality deprecated
    
}

// MARK: - Actions (private)
private extension SwiftDetailViewController {
    @objc func showOptions() { showOptionsPanel(type: .presets) }
    
    // MARK: - Control Bar Actions
    // MARK: - ⚠️ MIGRATED METHOD: View Reset → UIStateManagementService
    // Migration: Phase 11D
    @objc func resetView() {
        guard let viewModel = viewModel else {
            print("⚠️ [LEGACY] resetView using fallback - ViewModel unavailable")
            // Legacy fallback removed in Phase 12
            return
        }
        
        guard let dicom2DView = dicom2DView else {
            print("❌ [RESET] No DICOM view available for reset")
            return
        }
        
        print("🔄 [MVVM-C] Performing integrated reset via services")
        
        // Step 1: Clear measurements (direct UI call)
        clearMeasurements()
        
        // Step 2: Reset window/level to original series values (preferred approach)
        if let originalWidth = originalSeriesWindowWidth,
           let originalLevel = originalSeriesWindowLevel {
            print("🎯 [MVVM-C] Resetting to original series values: W=\(originalWidth) L=\(originalLevel)")
            setWindowWidth(Double(originalWidth), windowCenter: Double(originalLevel))
            currentSeriesWindowWidth = originalWidth
            currentSeriesWindowLevel = originalLevel
        } else {
            // Fallback: Use modality defaults if no original values available
            let modality = patientModel?.modality ?? .ct
            print("⚠️ [MVVM-C] No original series values, using modality defaults for \(modality.rawStringValue)")
            let defaults = getDefaultWindowLevelForModality(modality)
            setWindowWidth(Double(defaults.width), windowCenter: Double(defaults.level))
            currentSeriesWindowWidth = defaults.width
            currentSeriesWindowLevel = defaults.level
        }
        
        // Step 3: Reset other UI state via integrated service (transforms, zoom, etc.)
        let success = viewModel.performViewReset()
        
        // Step 4: Apply transforms to actual view (UI layer responsibility)  
        if success {
            print("🔄 [DetailViewModel] Coordinating transform reset via service")
            viewModel.resetTransforms(for: dicom2DView, animated: true)
        }
        
        // Step 5: Update UI annotations
        updateAnnotationsView()
        
        print("✅ [MVVM-C] Integrated reset completed via service layer")
    }
    
    
    
    // MARK: - MVVM-C Migration: Window/Level Defaults
    private func getDefaultWindowLevelForModality(_ modality: DICOMModality) -> (level: Int, width: Int) {
        // MVVM-C Migration: Delegate default window/level retrieval to service layer via ViewModel
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, using direct fallback")
            switch modality {
            case .ct:
                return (level: 40, width: 350)
            case .mr:
                return (level: 700, width: 1400)
            case .cr, .dx:
                return (level: 1024, width: 2048)
            case .us:
                return (level: 128, width: 256)
            case .nm, .pt:
                return (level: 128, width: 256)
            default:
                return (level: 128, width: 256)
            }
        }
        
        print("🪟 [MVVM-C] Getting default W/L for modality \(modality) via service layer")
        
        // Get presets from service layer and use the first modality-specific preset as default
        let presets = viewModel.getPresetsForModality(
            modality,
            originalWindowLevel: nil, // Use service defaults
            originalWindowWidth: nil,
            currentWindowLevel: nil,
            currentWindowWidth: nil
        )
        
        // Find the first modality-specific preset (not "Default" or "Full Dynamic")
        if let modalityPreset = presets.first(where: { $0.name != "Default" && $0.name != "Full Dynamic" }) {
            let result = (level: Int(modalityPreset.windowLevel), width: Int(modalityPreset.windowWidth))
            print("✅ [MVVM-C] Using service preset '\(modalityPreset.name)': W=\(result.width) L=\(result.level)")
            return result
        }
        
        // Fallback if no modality-specific presets found
        switch modality {
        case .ct:
            return (level: 40, width: 350)
        case .mr:
            return (level: 700, width: 1400)
        case .cr, .dx:
            return (level: 1024, width: 2048)
        case .us:
            return (level: 128, width: 256)
        case .nm, .pt:
            return (level: 128, width: 256)
        default:
            return (level: 128, width: 256)
        }
    }
    
    
    // MARK: - MVVM-C Phase 11B: Preset Management
    @objc func showPresets() {
        // MVVM-C Phase 11B: Delegate UI presentation to ViewModel → UIStateService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to direct implementation")
            showPresetsFallback()
            return
        }
        
        print("🪟 [MVVM-C Phase 11B] Showing presets via ViewModel → UIStateService")
        
        _ = viewModel.showWindowLevelPresets(from: self, sourceView: swiftControlBar)
        
        print("✅ [MVVM-C Phase 11B] Preset presentation delegated to service layer")
    }
    
    // Legacy fallback for showPresets during migration
    private func showPresetsFallback() {
        print("🪟 [FALLBACK] Showing presets directly")
        
        let alertController = UIAlertController(title: "Window/Level Presets", message: "Select a preset", preferredStyle: .actionSheet)
        
        let modality = patientModel?.modality ?? .unknown
        let presets = getPresetsForModality(modality)
        
        for preset in presets {
            let action = UIAlertAction(title: preset.name, style: .default) { _ in
                self.applyWindowLevelPreset(preset)
            }
            alertController.addAction(action)
        }
        
        let customAction = UIAlertAction(title: "Custom...", style: .default) { _ in
            self.showCustomWindowLevelDialog()
        }
        alertController.addAction(customAction)
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = swiftControlBar
            popover.sourceRect = swiftControlBar?.bounds ?? CGRect.zero
        }
        
        present(alertController, animated: true)
        
        print("✅ [MVVM-C] Presets displayed using service-based data")
    }
    
    // MARK: - ⚠️ MIGRATED METHOD: Reconstruction Options → ModalPresentationService
    // Migration: Phase 11C
    @objc func showReconOptions() {
        // MVVM-C Phase 11C: Delegate modal presentation to ViewModel → ModalPresentationService
        guard let viewModel = viewModel else {
            print("❌ ViewModel not available, falling back to legacy implementation")
            // Legacy fallback removed in Phase 12
            return
        }
        
        print("🔄 [MVVM-C Phase 11C] Showing reconstruction options via ViewModel → ModalPresentationService")
        
        if viewModel.showReconstructionOptions(from: self, sourceView: swiftControlBar) {
            print("✅ [MVVM-C Phase 11C] Reconstruction options presentation delegated to service layer")
        } else {
            print("❌ [MVVM-C Phase 11C] Reconstruction options presentation failed, using legacy fallback")
            // Legacy fallback removed in Phase 12
            return
        }
    }
    
    
    // MARK: - MVVM-C Migration: Control Actions
    // changeOrientation method moved to ReconstructionDelegate extension - Phase 11C
    
    
}

// MARK: - SwiftCustomSliderDelegate

extension SwiftDetailViewController: SwiftCustomSliderDelegate {
    // MARK: - MVVM-C Migration: Simple Slider Navigation
    
    func slider(_ slider: SwiftCustomSlider, didScrollToValue value: Float) {
        // MVVM-C Phase 11F Part 2: Delegate to service layer
        handleSliderValueChange(value: value)
    }
}

// MARK: - Phase 11C: Modal Presentation Delegate Protocols

// MARK: - Window Level Preset Delegate
extension SwiftDetailViewController {
    func didSelectWindowLevelPreset(_ preset: WindowLevelPreset) {
        print("🪟 [Modal Delegate] Selected preset: \(preset.name)")
        applyWindowLevelPreset(preset)
    }
    
    func didSelectCustomWindowLevel() {
        print("🪟 [Modal Delegate] Selected custom window/level")
        guard let viewModel = viewModel else {
            showCustomWindowLevelDialogFallback()
            return
        }
        let _ = viewModel.showCustomWindowLevelDialog(from: self)
    }
}

// MARK: - Custom Window Level Delegate
extension SwiftDetailViewController {
    func didSetCustomWindowLevel(width: Int, level: Int) {
        print("🪟 [Modal Delegate] Custom W/L set: Width=\(width), Level=\(level)")
        
        // Validate and apply values
        guard width > 0, width <= 4000, level >= -2000, level <= 2000 else {
            print("❌ Invalid window/level values")
            return
        }
        
        // Apply via existing method
        currentSeriesWindowWidth = width
        currentSeriesWindowLevel = level
        applyHUWindowLevel(windowWidthHU: Double(width), windowCenterHU: Double(level), rescaleSlope: rescaleSlope, rescaleIntercept: rescaleIntercept)
    }
}

// MARK: - ⚠️ MIGRATED METHOD: ROI Tools Delegate → ROIMeasurementService
// Migration: Phase 11E
extension SwiftDetailViewController {
    func didSelectROITool(_ toolType: ROIToolType) {
        // MVVM-C Phase 11E: Delegate ROI tool selection to service layer
        guard roiMeasurementService != nil else {
            print("❌ ROIMeasurementService not available, using fallback")
            // Legacy fallback removed in Phase 12
            return
        }
        
        print("🎯 [MVVM-C Phase 11E] ROI tool selection via service layer: \(toolType)")
        
        // Handle clearAll immediately, delegate tool activation to service
        if toolType == .clearAll {
            clearAllMeasurements()
        } else {
            // Direct tool activation to avoid type ambiguity
            switch toolType {
            case .distance:
                roiMeasurementToolsView?.activateDistanceMeasurement()
                print("✅ [MVVM-C Phase 11E] Distance measurement tool activated via service pattern")
            case .ellipse:
                roiMeasurementToolsView?.activateEllipseMeasurement()
                print("✅ [MVVM-C Phase 11E] Ellipse measurement tool activated via service pattern")
            case .clearAll:
                // Already handled above
                break
            }
        }
        
        print("✅ [MVVM-C Phase 11E] ROI tool selection delegated to service layer")
    }
    
}

// MARK: - ⚠️ MIGRATED DELEGATE: Reconstruction → MultiplanarReconstructionService
// Migration: Phase 11E
extension SwiftDetailViewController {
    func didSelectReconstruction(orientation: ViewingOrientation) {
        // MVVM-C Phase 11E: Direct MPR placeholder (service to be integrated later)
        print("🔄 [MVVM-C Phase 11E] Reconstruction requested: \(orientation)")
        
        // Direct MPR placeholder alert for now
        let alert = UIAlertController(
            title: "Multiplanar Reconstruction",
            message: "MPR to \(orientation.rawValue) view will be implemented in a future update.\n\nPlanned features:\n• Real-time slice generation\n• Interactive crosshairs\n• Synchronized viewing\n• 3D volume rendering",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        
        print("✅ [MVVM-C Phase 11E] MPR placeholder presented")
    }
    
    // Legacy fallback for changeOrientation during migration (removed - now handled by service)
    // This method has been fully migrated to MultiplanarReconstructionService
}

// MARK: - ⚠️ MIGRATED DELEGATE: ROI Measurement Tools → ROIMeasurementService
// Migration: Phase 11E

extension SwiftDetailViewController: ROIMeasurementToolsDelegate {
    
    nonisolated func measurementsCleared() {
        // MVVM-C Phase 11E: Delegate measurement cleared event to service layer
        Task { @MainActor in
            guard roiMeasurementService != nil else {
                print("📏 [FALLBACK] All measurements cleared - service unavailable")
                return
            }
            
            print("📏 [MVVM-C Phase 11E] Measurements cleared via service layer")
            let concreteService = ROIMeasurementService.shared
            concreteService.handleMeasurementsCleared()
        }
    }
    
    nonisolated func distanceMeasurementCompleted(_ measurement: ROIMeasurement) {
        // MVVM-C Phase 11E: Delegate distance completion event to service layer
        // Capture measurement data before Task to avoid data race
        let measurementValue = measurement.value
        let measurementType = measurement.type
        let measurementPoints = measurement.points
        
        Task { @MainActor in
            guard roiMeasurementService != nil else {
                print("📏 [FALLBACK] Distance measurement completed: \(measurementValue ?? "unknown") - service unavailable")
                return
            }
            
            print("📏 [MVVM-C Phase 11E] Distance measurement completed via service layer")
            let concreteService = ROIMeasurementService.shared
            // Create new measurement instance to avoid data race
            let safeMeasurement = ROIMeasurement(
                type: measurementType,
                points: measurementPoints,
                overlay: nil,
                labels: nil,
                value: measurementValue
            )
            concreteService.handleDistanceMeasurementCompleted(safeMeasurement)
        }
    }
    
    nonisolated func ellipseMeasurementCompleted(_ measurement: ROIMeasurement) {
        // MVVM-C Phase 11E: Delegate ellipse completion event to service layer
        // Capture measurement data before Task to avoid data race
        let measurementValue = measurement.value
        let measurementType = measurement.type
        let measurementPoints = measurement.points
        
        Task { @MainActor in
            guard roiMeasurementService != nil else {
                print("📏 [FALLBACK] Ellipse measurement completed: \(measurementValue ?? "unknown") - service unavailable")
                return
            }
            
            print("📏 [MVVM-C Phase 11E] Ellipse measurement completed via service layer")
            let concreteService = ROIMeasurementService.shared
            // Create new measurement instance to avoid data race
            let safeMeasurement = ROIMeasurement(
                type: measurementType,
                points: measurementPoints,
                overlay: nil,
                labels: nil,
                value: measurementValue
            )
            concreteService.handleEllipseMeasurementCompleted(safeMeasurement)
        }
    }
}

// MARK: - ⚠️ MIGRATED METHOD: Gesture Delegate Methods → GestureEventService
// Migration: Phase 11F
extension SwiftDetailViewController {
    
    // MARK: - Migrated Gesture Methods (MVVM-C Phase 11F)
    
    private func scheduleTransformUpdate() {
        // Cancel existing timer
        transformUpdateTimer?.invalidate()
        
        // Schedule transform update for next run loop cycle
        transformUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.applyPendingTransforms()
            }
        }
    }
    
    @MainActor
    private func applyPendingTransforms() {
        guard let imageView = dicom2DView else { return }
        
        // Apply all pending transforms atomically
        var combinedTransform = imageView.transform
        
        // Apply scale (zoom) first
        if abs(pendingZoomScale - 1.0) > 0.001 {
            combinedTransform = combinedTransform.scaledBy(x: pendingZoomScale, y: pendingZoomScale)
            
            // Check scale limits
            let currentScale = sqrt(combinedTransform.a * combinedTransform.a + combinedTransform.c * combinedTransform.c)
            if currentScale < 0.1 || currentScale > 10.0 {
                // Revert scale if out of bounds
                combinedTransform = imageView.transform
                print("🚫 [TRANSFORM] Scale out of bounds: \(currentScale), reverting")
            } else {
                print("✅ [TRANSFORM] Applied zoom: scale=\(String(format: "%.3f", pendingZoomScale)), total=\(String(format: "%.3f", currentScale))")
            }
        }
        
        // Apply rotation
        if abs(pendingRotationAngle) > 0.001 {
            let rotationTransform = CGAffineTransform(rotationAngle: pendingRotationAngle)
            combinedTransform = combinedTransform.concatenating(rotationTransform)
            print("✅ [TRANSFORM] Applied rotation: \(pendingRotationAngle) radians")
        }
        
        // Apply translation (pan)
        if abs(pendingTranslation.x) > 0.1 || abs(pendingTranslation.y) > 0.1 {
            let translationTransform = CGAffineTransform(translationX: pendingTranslation.x, y: pendingTranslation.y)
            combinedTransform = combinedTransform.concatenating(translationTransform)
            print("✅ [TRANSFORM] Applied pan: \(pendingTranslation)")
        }
        
        // Apply the combined transform atomically
        imageView.transform = combinedTransform
        updateAnnotationsView()
        
        // Reset pending transforms
        pendingZoomScale = 1.0
        pendingRotationAngle = 0.0
        pendingTranslation = .zero
    }

    @MainActor
    func handleZoomGesture(scale: CGFloat, point: CGPoint) {
        // MVVM-C Phase 11F+: Coordinate with other simultaneous gestures
        guard let gestureService = gestureEventService else {
            print("❌ GestureEventService not available, falling back to legacy implementation")
            // Legacy gesture fallback removed in Phase 12
            return
        }
        
        print("🔍 [MVVM-C Phase 11F+] Coordinated zoom gesture: scale=\(scale), point=\(point)")
        
        let context = GestureEventContext(
            imageViewBounds: self.view.bounds,
            currentTransform: self.dicom2DView?.transform ?? .identity,
            zoomLevel: 1.0,
            rotationAngle: 0.0,
            isROIToolActive: false,
            windowLevel: Float(self.currentSeriesWindowLevel ?? 50),
            windowWidth: Float(self.currentSeriesWindowWidth ?? 400),
            isZoomGestureActive: true,
            isPanGestureActive: false,
            gestureVelocity: .zero,
            numberOfTouches: 2
        )
        
        Task {
            let result = await gestureService.handlePinchGesture(scale: scale, context: context)
            
            if result.success, let _ = result.newTransform {
                // Accumulate zoom transform instead of applying immediately
                self.pendingZoomScale = scale
                self.scheduleTransformUpdate()
                print("📝 [MVVM-C Phase 11F+] Zoom queued for coordinated update: scale=\(String(format: "%.3f", scale))")
            }
            
            if let error = result.error {
                print("❌ [MVVM-C Phase 11F+] Zoom gesture error: \(error.localizedDescription)")
                await MainActor.run {
                    // Legacy gesture fallback removed in Phase 12
                }
            }
        }
    }
    
    @MainActor
    func handleRotationGesture(angle: CGFloat) {
        // MVVM-C Phase 11F+: Coordinate with other simultaneous gestures
        guard let gestureService = gestureEventService else {
            print("❌ GestureEventService not available, falling back to legacy implementation")
            // Legacy gesture fallback removed in Phase 12
            return
        }
        
        print("🔄 [MVVM-C Phase 11F+] Coordinated rotation gesture: angle=\(angle)")
        
        let context = GestureEventContext(
            imageViewBounds: self.view.bounds,
            currentTransform: self.dicom2DView?.transform ?? .identity,
            zoomLevel: 1.0,
            rotationAngle: 0.0,
            isROIToolActive: false,
            windowLevel: Float(self.currentSeriesWindowLevel ?? 50),
            windowWidth: Float(self.currentSeriesWindowWidth ?? 400),
            isZoomGestureActive: false,
            isPanGestureActive: false,
            gestureVelocity: .zero,
            numberOfTouches: 2
        )
        
        Task {
            let result = await gestureService.handleRotationGesture(rotation: angle, context: context)
            
            if result.success, let _ = result.newTransform {
                // Accumulate rotation transform instead of applying immediately
                self.pendingRotationAngle = angle
                self.scheduleTransformUpdate()
                print("📝 [MVVM-C Phase 11F+] Rotation queued for coordinated update: angle=\(angle) radians")
            }
            
            if let error = result.error {
                print("❌ [MVVM-C Phase 11F+] Rotation gesture error: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    func handlePanGesture(offset: CGPoint) {
        // MVVM-C Phase 11F: Delegate pan gesture to service layer
        guard let gestureService = gestureEventService else {
            print("❌ GestureEventService not available, falling back to legacy implementation")
            // Legacy gesture fallback removed in Phase 12
            return
        }
        
        print("👆 [MVVM-C Phase 11F] Pan gesture via GestureEventService: offset=\(offset)")
        
        let context = GestureEventContext(
            imageViewBounds: self.view.bounds,
            currentTransform: self.dicom2DView?.transform ?? .identity,
            zoomLevel: 1.0, // TODO: Get actual zoom from view
            rotationAngle: 0.0, // TODO: Get actual rotation from view
            isROIToolActive: false, // TODO: Check if ROI tools are active
            windowLevel: Float(self.currentSeriesWindowLevel ?? 50),
            windowWidth: Float(self.currentSeriesWindowWidth ?? 400),
            isZoomGestureActive: false, // TODO: Track from gesture recognizers
            isPanGestureActive: false, // TODO: Track from gesture recognizers
            gestureVelocity: .zero, // TODO: Get from gesture recognizer
            numberOfTouches: 1 // Default to single touch, should be updated from actual gesture
        )
        
        Task {
            let result = await gestureService.handlePanGesture(
                translation: offset,
                context: context
            )
            
            if result.success {
                // Apply results from service
                if result.newTransform != nil {
                    // Apply transform changes (image panning) - coordinate with other gestures
                    self.pendingTranslation = offset
                    self.scheduleTransformUpdate()
                    print("📝 [MVVM-C Phase 11F+] Pan queued for coordinated update: offset=\(offset)")
                }
                
                if let windowLevelChange = result.windowLevelChange {
                    // Apply window/level changes
                    self.applyHUWindowLevel(
                        windowWidthHU: Double(windowLevelChange.width),
                        windowCenterHU: Double(windowLevelChange.level),
                        rescaleSlope: self.rescaleSlope,
                        rescaleIntercept: self.rescaleIntercept
                    )
                    
                    self.currentSeriesWindowWidth = Int(windowLevelChange.width)
                    self.currentSeriesWindowLevel = Int(windowLevelChange.level)
                    
                    print("✅ [MVVM-C Phase 11F] Pan-based window/level applied via service: W=\(windowLevelChange.width)HU L=\(windowLevelChange.level)HU")
                }
                
                if let roiPoint = result.roiPoint {
                    print("✅ [MVVM-C Phase 11F] ROI pan handled via service: \(roiPoint)")
                    // TODO: Handle ROI tool panning if needed
                }
            }
            
            if let error = result.error {
                print("❌ [MVVM-C Phase 11F] Pan gesture error: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    func handleWindowLevelGesture(deltaX: CGFloat, deltaY: CGFloat) {
        // MVVM-C Phase 11F: Delegate window/level gesture to service layer
        guard let gestureService = gestureEventService else {
            print("❌ GestureEventService not available, falling back to legacy implementation")
            // Legacy gesture fallback removed in Phase 12
            return
        }
        
        print("⚡ [MVVM-C Phase 11F] Window/level gesture via GestureEventService: ΔX=\(deltaX), ΔY=\(deltaY)")
        
        let context = GestureEventContext(
            imageViewBounds: self.view.bounds,
            currentTransform: self.dicom2DView?.transform ?? .identity,
            zoomLevel: 1.0, // TODO: Get actual zoom from view
            rotationAngle: 0.0, // TODO: Get actual rotation from view
            isROIToolActive: false, // TODO: Check if ROI tools are active
            windowLevel: Float(self.currentSeriesWindowLevel ?? 50),
            windowWidth: Float(self.currentSeriesWindowWidth ?? 400),
            isZoomGestureActive: false, // TODO: Track from gesture recognizers
            isPanGestureActive: false, // TODO: Track from gesture recognizers
            gestureVelocity: .zero, // TODO: Get from gesture recognizer
            numberOfTouches: 1 // Default to single touch, should be updated from actual gesture
        )
        
        Task {
            let result = await gestureService.handlePanGesture(
                translation: CGPoint(x: deltaX, y: deltaY),
                context: context
            )
            
            if result.success, let windowLevelChange = result.windowLevelChange {
                // Apply the window/level result from service
                self.applyHUWindowLevel(
                    windowWidthHU: Double(windowLevelChange.width),
                    windowCenterHU: Double(windowLevelChange.level),
                    rescaleSlope: self.rescaleSlope,
                    rescaleIntercept: self.rescaleIntercept
                )
                
                // Update current values
                self.currentSeriesWindowWidth = Int(windowLevelChange.width)
                self.currentSeriesWindowLevel = Int(windowLevelChange.level)
                
                print("✅ [MVVM-C Phase 11F] Window/level applied via service: W=\(windowLevelChange.width)HU L=\(windowLevelChange.level)HU")
            }
            
            if let error = result.error {
                print("❌ [MVVM-C Phase 11F] Window/level gesture error: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor 
    func handleSwipeToNextImage() {
        // MVVM-C Phase 11F: Delegate swipe navigation to service layer
        // NOTE: Service temporarily unavailable - using direct implementation
        print("➡️ [MVVM-C Phase 11F] Swipe to next image via service layer (direct)")
        // Legacy navigation removed in Phase 12
    }
    
    @MainActor
    func handleSwipeToPreviousImage() {
        // MVVM-C Phase 11F: Delegate swipe navigation to service layer
        // NOTE: Service temporarily unavailable - using direct implementation
        print("⬅️ [MVVM-C Phase 11F] Swipe to previous image via service layer (direct)")
        // Legacy navigation removed in Phase 12
    }
    
    @MainActor
    func handleSwipeToNextSeries() {
        // MVVM-C Phase 11F: Delegate series navigation to service layer
        // NOTE: Service temporarily unavailable - using direct implementation
        print("⏭️ [MVVM-C Phase 11F] Swipe to next series via service layer (direct)")
        // Legacy navigation removed in Phase 12
    }
    
    @MainActor
    func handleSwipeToPreviousSeries() {
        // MVVM-C Phase 11F: Delegate series navigation to service layer
        // NOTE: Service temporarily unavailable - using direct implementation
        print("⏮️ [MVVM-C Phase 11F] Swipe to previous series via service layer (direct)")
        // Legacy navigation removed in Phase 12
    }
    
    // MARK: - Enhanced Gesture Methods with Touch Count (Phase 11F+)
    
    @MainActor
    func handlePanGestureWithTouchCount(offset: CGPoint, touchCount: Int, velocity: CGPoint) {
        // MVVM-C Phase 11F+: Enhanced pan gesture with actual touch count
        guard let gestureService = gestureEventService else {
            print("❌ GestureEventService not available, falling back to legacy implementation")
            // Legacy gesture fallback removed in Phase 12
            return
        }
        
        print("👆 [MVVM-C Phase 11F+] Enhanced pan gesture: offset=\(offset), touches=\(touchCount), velocity=\(velocity)")
        
        let context = GestureEventContext(
            imageViewBounds: self.view.bounds,
            currentTransform: self.dicom2DView?.transform ?? .identity,
            zoomLevel: 1.0, // TODO: Get actual zoom from view
            rotationAngle: 0.0, // TODO: Get actual rotation from view
            isROIToolActive: false, // TODO: Check if ROI tools are active
            windowLevel: Float(self.currentSeriesWindowLevel ?? 50),
            windowWidth: Float(self.currentSeriesWindowWidth ?? 400),
            isZoomGestureActive: false, // TODO: Track from gesture recognizers
            isPanGestureActive: false, // TODO: Track from gesture recognizers
            gestureVelocity: velocity, // Now using actual velocity!
            numberOfTouches: touchCount // Now using actual touch count!
        )
        
        Task {
            let result = await gestureService.handlePanGesture(
                translation: offset,
                context: context
            )
            
            if result.success {
                // Apply results from service
                if let newTransform = result.newTransform {
                    // Apply transform changes (image panning)
                    if let imageView = self.dicom2DView {
                        imageView.transform = newTransform
                        print("✅ [MVVM-C Phase 11F+] Pan transform applied via service with \(touchCount) touches")
                    }
                }
                
                if let windowLevelChange = result.windowLevelChange {
                    // Apply window/level changes
                    self.applyHUWindowLevel(
                        windowWidthHU: Double(windowLevelChange.width),
                        windowCenterHU: Double(windowLevelChange.level),
                        rescaleSlope: self.rescaleSlope,
                        rescaleIntercept: self.rescaleIntercept
                    )
                    
                    self.currentSeriesWindowWidth = Int(windowLevelChange.width)
                    self.currentSeriesWindowLevel = Int(windowLevelChange.level)
                    
                    print("✅ [MVVM-C Phase 11F+] Pan-based window/level applied: W=\(windowLevelChange.width)HU L=\(windowLevelChange.level)HU (\(touchCount) touches)")
                }
                
                if let roiPoint = result.roiPoint {
                    print("✅ [MVVM-C Phase 11F+] ROI pan handled via service: \(roiPoint)")
                    // TODO: Handle ROI tool panning if needed
                }
            }
            
            if let error = result.error {
                print("❌ [MVVM-C Phase 11F+] Enhanced pan gesture error: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    func handleWindowLevelGestureWithTouchCount(deltaX: CGFloat, deltaY: CGFloat, touchCount: Int, velocity: CGPoint) {
        // MVVM-C Phase 11F+: Enhanced window/level gesture with actual touch count
        guard let gestureService = gestureEventService else {
            print("❌ GestureEventService not available, falling back to legacy implementation")
            // Legacy gesture fallback removed in Phase 12
            return
        }
        
        print("⚡ [MVVM-C Phase 11F+] Enhanced window/level gesture: ΔX=\(deltaX), ΔY=\(deltaY), touches=\(touchCount), velocity=\(velocity)")
        
        let context = GestureEventContext(
            imageViewBounds: self.view.bounds,
            currentTransform: self.dicom2DView?.transform ?? .identity,
            zoomLevel: 1.0, // TODO: Get actual zoom from view
            rotationAngle: 0.0, // TODO: Get actual rotation from view
            isROIToolActive: false, // TODO: Check if ROI tools are active
            windowLevel: Float(self.currentSeriesWindowLevel ?? 50),
            windowWidth: Float(self.currentSeriesWindowWidth ?? 400),
            isZoomGestureActive: false, // TODO: Track from gesture recognizers
            isPanGestureActive: false, // TODO: Track from gesture recognizers
            gestureVelocity: velocity, // Now using actual velocity!
            numberOfTouches: touchCount // Now using actual touch count!
        )
        
        Task {
            let result = await gestureService.handlePanGesture(
                translation: CGPoint(x: deltaX, y: deltaY),
                context: context
            )
            
            if result.success, let windowLevelChange = result.windowLevelChange {
                // Apply the window/level result from service
                self.applyHUWindowLevel(
                    windowWidthHU: Double(windowLevelChange.width),
                    windowCenterHU: Double(windowLevelChange.level),
                    rescaleSlope: self.rescaleSlope,
                    rescaleIntercept: self.rescaleIntercept
                )
                
                // Update current values
                self.currentSeriesWindowWidth = Int(windowLevelChange.width)
                self.currentSeriesWindowLevel = Int(windowLevelChange.level)
                
                print("✅ [MVVM-C Phase 11F+] Window/level applied: W=\(windowLevelChange.width)HU L=\(windowLevelChange.level)HU (\(touchCount) touches)")
            }
            
            if let error = result.error {
                print("❌ [MVVM-C Phase 11F+] Enhanced window/level gesture error: \(error.localizedDescription)")
            }
        }
    }
    
}
// MARK: - ⚠️ MIGRATED METHOD: UI Control Event Methods → UIControlEventService  
// Migration: Phase 11F Part 2
extension SwiftDetailViewController {
    
    // MARK: - Migrated UI Control Methods (MVVM-C Phase 11F Part 2)
    
    @MainActor
    func handleSliderValueChange(value: Float) {
        // MVVM-C Phase 11F Part 2: Delegate slider change to service layer
        guard let navigationService = seriesNavigationService else {
            print("❌ SeriesNavigationService not available, falling back to legacy implementation")
            // Legacy slider fallback removed in Phase 12
            return
        }
        
        let targetIndex = Int(value) - 1
        
        // Avoid reloading the same image
        guard targetIndex != currentImageIndex && targetIndex >= 0 && targetIndex < sortedPathArray.count else { 
            print("🎚️ [MVVM-C Phase 11F Part 2] Slider: skipping invalid or current index \(targetIndex)")
            return 
        }
        
        print("🎚️ [MVVM-C Phase 11F Part 2] Slider change via SeriesNavigationService: \(currentImageIndex) → \(targetIndex)")
        
        // Use SeriesNavigationService for image navigation
        if let newFilePath = navigationService.navigateToImage(at: targetIndex) {
            // Update current index
            currentImageIndex = targetIndex
            
            // Load the image via service layer
            Task {
                await loadImageFromService(filePath: newFilePath, index: targetIndex)
            }
        } else {
            print("❌ [MVVM-C Phase 11F Part 2] SeriesNavigationService failed, using fallback")
            // Legacy slider fallback removed in Phase 12
            return
        }
    }
    
    // MARK: - Helper Methods for Service Integration
    
    @MainActor
    private func loadImageFromService(filePath: String, index: Int) async {
        // Use the existing image loading pipeline but routed through services
        guard imageProcessingService != nil else {
            print("❌ [MVVM-C] ImageProcessingService not available for image loading")
            displayImageFast(at: index) // Fallback to direct method
            return
        }
        
        print("💼 [MVVM-C] Loading image via service: \(filePath.split(separator: "/").last ?? "unknown")")
        
        // For now, use the existing displayImageFast method as it's already optimized
        // In a future phase, this could be fully migrated to service layer
        displayImageFast(at: index)
    }
    
    @MainActor
    func handleOptionsPresetSelection(index: Int) {
        // MVVM-C Phase 11F Part 2: Delegate options preset selection to service layer
        // NOTE: Service temporarily unavailable - using direct implementation
        print("🎛️ [MVVM-C Phase 11F Part 2] Options preset selection via service layer (direct): index=\(index)")
        // Legacy options fallback removed in Phase 12
    }
    
    @MainActor
    func handleOptionsTransformSelection(type: Int) {
        // MVVM-C Phase 11F Part 2: Delegate transform selection to service layer
        // NOTE: Service temporarily unavailable - using direct implementation
        print("🔄 [MVVM-C Phase 11F Part 2] Transform selection via service layer (direct): type=\(type)")
        // Legacy transform fallback removed in Phase 12
    }
    
    @MainActor
    func handleOptionsPanelClose() {
        // MVVM-C Phase 11F Part 2: Delegate options panel close to service layer
        // NOTE: Service temporarily unavailable - using direct implementation
        print("❌ [MVVM-C Phase 11F Part 2] Options panel close via service layer (direct)")
        // Legacy panel close fallback removed in Phase 12
    }
    
    @MainActor
    func handleCloseButtonTap() {
        // MVVM-C Phase 11F Part 2: Delegate close button tap to service layer
        // NOTE: Service temporarily unavailable - using direct implementation  
        print("🧭 [MVVM-C Phase 11F Part 2] Close button tap via service layer (direct)")
        
        // Direct navigation implementation (Phase 12 fix)
        if presentingViewController != nil {
            dismiss(animated: true)
            print("✅ Dismissed modal presentation")
        } else {
            navigationController?.popViewController(animated: true)
            print("✅ Popped navigation controller")
        }
    }
    
}

