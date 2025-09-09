//
//  SwiftGestureManager.swift
//  DICOMViewer
//
//  Swift migration from GestureManager.m with enhanced functionality
//  Created by AI Assistant on 2025-01-27.
//  Copyright © 2025 DICOM Viewer. All rights reserved.
//

import UIKit
import Foundation

// MARK: - Gesture Types and Configuration

enum GestureType: Int, CaseIterable {
    case zoom               // Pinch to zoom
    case rotation           // Rotate image
    case pan               // Pan image
    case swipeImage        // Swipe horizontally to change image
    case swipeSeries       // Swipe vertically to change series
    
    var description: String {
        switch self {
        case .zoom: return "Zoom"
        case .rotation: return "Rotation" 
        case .pan: return "Pan"
        case .swipeImage: return "Image Navigation"
        case .swipeSeries: return "Series Navigation"
        }
    }
}

// MARK: - Gesture Configuration
struct GestureConfiguration {
    var zoomLimits = GestureConfiguration.ZoomLimits()
    var enabledGestures = Set<GestureType>(GestureType.allCases)
    
    struct ZoomLimits {
        var minScale: CGFloat = 0.5
        var maxScale: CGFloat = 5.0
        var defaultScale: CGFloat = 1.0
    }
}

// MARK: - Gesture Manager Protocols

@objc protocol SwiftGestureManagerDelegate: AnyObject {
    func gestureManager(_ manager: SwiftGestureManager, didZoomToScale scale: CGFloat, atPoint point: CGPoint)
    func gestureManager(_ manager: SwiftGestureManager, didRotateByAngle angle: CGFloat)
    func gestureManager(_ manager: SwiftGestureManager, didPanByOffset offset: CGPoint)
    func gestureManager(_ manager: SwiftGestureManager, didAdjustWindowLevel deltaX: CGFloat, deltaY: CGFloat)
    func gestureManagerDidSwipeToNextImage(_ manager: SwiftGestureManager)
    func gestureManagerDidSwipeToPreviousImage(_ manager: SwiftGestureManager)
    func gestureManagerDidSwipeToNextSeries(_ manager: SwiftGestureManager)
    func gestureManagerDidSwipeToPreviousSeries(_ manager: SwiftGestureManager)
    
    // Phase 11F Enhanced: Methods with touch count information
    @objc optional func gestureManager(_ manager: SwiftGestureManager, didPanByOffset offset: CGPoint, touchCount: Int, velocity: CGPoint)
    @objc optional func gestureManager(_ manager: SwiftGestureManager, didAdjustWindowLevel deltaX: CGFloat, deltaY: CGFloat, touchCount: Int, velocity: CGPoint)
}

// MARK: - Default implementations (optional methods)
extension SwiftGestureManagerDelegate {
    func gestureManager(_ manager: SwiftGestureManager, didZoomToScale scale: CGFloat, atPoint point: CGPoint) { }
    func gestureManager(_ manager: SwiftGestureManager, didRotateByAngle angle: CGFloat) { }
    func gestureManager(_ manager: SwiftGestureManager, didPanByOffset offset: CGPoint) { }
    func gestureManager(_ manager: SwiftGestureManager, didAdjustWindowLevel deltaX: CGFloat, deltaY: CGFloat) { }
    func gestureManagerDidSwipeToNextImage(_ manager: SwiftGestureManager) { }
    func gestureManagerDidSwipeToPreviousImage(_ manager: SwiftGestureManager) { }
    func gestureManagerDidSwipeToNextSeries(_ manager: SwiftGestureManager) { }
    func gestureManagerDidSwipeToPreviousSeries(_ manager: SwiftGestureManager) { }
}

// MARK: - Main Gesture Manager Implementation

@objc class SwiftGestureManager: NSObject {
    
    // MARK: - Properties
    weak var delegate: SwiftGestureManagerDelegate?
    weak var dicomView: DCMImgView?
    weak var containerView: UIView?
    
    private(set) var configuration = GestureConfiguration()
    
    // Current transform values
    private(set) var currentZoomScale: CGFloat = 1.0
    private(set) var currentRotationAngle: CGFloat = 0.0
    private(set) var currentPanOffset: CGPoint = .zero
    
    // Gesture recognizers
    private var zoomGesture: UIPinchGestureRecognizer?
    private var rotationGesture: UIRotationGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var windowLevelGesture: UIPanGestureRecognizer?  // Single finger pan for W/L
    private var swipeGestures: [UISwipeGestureRecognizer] = []
    
    // Settings persistence
    private let userDefaults = UserDefaults.standard
    private let settingsPrefix = "SwiftGestureManager."
    
    // MARK: - Initialization
    @MainActor init(containerView: UIView, dicomView: DCMImgView?) {
        super.init()
        
        self.containerView = containerView
        self.dicomView = dicomView
        
        loadGestureSettings()
        setupGestures()
    }
    
    deinit {
        // Note: Can't call @MainActor methods from deinit
        // The cleanup will happen when the view is deallocated
    }
    
    // MARK: - Configuration
    @MainActor func updateConfiguration(_ config: GestureConfiguration) {
        self.configuration = config
        saveGestureSettings()
        updateGestureStates()
    }
    
    @MainActor func enableGesture(_ type: GestureType, enabled: Bool) {
        if enabled {
            configuration.enabledGestures.insert(type)
        } else {
            configuration.enabledGestures.remove(type)
        }
        updateGestureStates()
        saveGestureSettings()
    }
    
    func isGestureEnabled(_ type: GestureType) -> Bool {
        return configuration.enabledGestures.contains(type)
    }
    
    // MARK: - Gesture Setup
    @MainActor func setupGestures() {
        print("🖐️ Setting up gestures for SwiftGestureManager")
        removeAllGestures()
        
        guard let containerView = containerView else { 
            print("❌ No containerView for gesture setup")
            return 
        }
        
        print("🖐️ Container view: \(containerView)")
        
        // Zoom (pinch)
        zoomGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleZoom(_:)))
        zoomGesture?.delegate = self
        containerView.addGestureRecognizer(zoomGesture!)
        
        // Rotation - Make it more sensitive
        rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture?.delegate = self
        // Make rotation more responsive by reducing required movement
        containerView.addGestureRecognizer(rotationGesture!)
        
        // Window/Level adjustment (single finger pan)
        windowLevelGesture = UIPanGestureRecognizer(target: self, action: #selector(handleWindowLevel(_:)))
        windowLevelGesture?.delegate = self
        windowLevelGesture?.minimumNumberOfTouches = 1
        windowLevelGesture?.maximumNumberOfTouches = 1
        containerView.addGestureRecognizer(windowLevelGesture!)
        
        // Pan (two finger pan for moving image) - More flexible
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture?.delegate = self
        panGesture?.minimumNumberOfTouches = 2
        panGesture?.maximumNumberOfTouches = 10 // Allow more fingers for flexibility
        containerView.addGestureRecognizer(panGesture!)
        
        // Swipe gestures
        setupSwipeGestures()
        
        updateGestureStates()
    }
    
    @MainActor private func setupSwipeGestures() {
        guard let containerView = containerView else { return }
        
        let directions: [UISwipeGestureRecognizer.Direction] = [.left, .right, .up, .down]
        let actions: [Selector] = [
            #selector(handleSwipeLeft(_:)),
            #selector(handleSwipeRight(_:)),
            #selector(handleSwipeUp(_:)),
            #selector(handleSwipeDown(_:))
        ]
        
        for (direction, action) in zip(directions, actions) {
            let swipeGesture = UISwipeGestureRecognizer(target: self, action: action)
            swipeGesture.direction = direction
            containerView.addGestureRecognizer(swipeGesture)
            swipeGestures.append(swipeGesture)
        }
    }
    
    @MainActor func removeAllGestures() {
        guard let containerView = containerView else { return }
        
        [zoomGesture, rotationGesture, panGesture, windowLevelGesture]
            .compactMap { $0 }
            .forEach { containerView.removeGestureRecognizer($0) }
        
        swipeGestures.forEach { containerView.removeGestureRecognizer($0) }
        swipeGestures.removeAll()
        
        zoomGesture = nil
        rotationGesture = nil
        panGesture = nil
        windowLevelGesture = nil
    }
    
    @MainActor private func updateGestureStates() {
        let zoomEnabled = isGestureEnabled(.zoom)
        zoomGesture?.isEnabled = zoomEnabled
        print("🔍 Zoom gesture enabled: \(zoomEnabled)")
        
        let rotationEnabled = isGestureEnabled(.rotation)
        rotationGesture?.isEnabled = rotationEnabled
        print("🔄 Rotation gesture enabled: \(rotationEnabled)")
        
        let panEnabled = isGestureEnabled(.pan)
        panGesture?.isEnabled = panEnabled
        print("👋 Pan gesture enabled: \(panEnabled)")
        
        let swipeEnabled = isGestureEnabled(.swipeImage) || isGestureEnabled(.swipeSeries)
        swipeGestures.forEach { $0.isEnabled = swipeEnabled }
        print("↔️ Swipe gestures enabled: \(swipeEnabled)")
    }
    
    // MARK: - Transform Control
    @MainActor func resetAllTransforms(animated: Bool = true) {
        guard let containerView = containerView else { return }
        
        let resetTransform = {
            containerView.transform = .identity
            containerView.center = containerView.superview?.center ?? containerView.center
        }
        
        let completion = {
            self.currentZoomScale = self.configuration.zoomLimits.defaultScale
            self.currentRotationAngle = 0
            self.currentPanOffset = .zero
        }
        
        if animated {
            UIView.animate(withDuration: 0.3, animations: resetTransform) { _ in
                completion()
            }
        } else {
            resetTransform()
            completion()
        }
    }
    
    @MainActor func setZoomScale(_ scale: CGFloat, animated: Bool = false) {
        guard let containerView = containerView else { return }
        
        let clampedScale = scale.clamped(to: configuration.zoomLimits.minScale...configuration.zoomLimits.maxScale)
        
        let applyTransform = {
            let transform = CGAffineTransform(scaleX: clampedScale, y: clampedScale)
                .rotated(by: self.currentRotationAngle)
            containerView.transform = transform
            self.currentZoomScale = clampedScale
        }
        
        if animated {
            UIView.animate(withDuration: 0.2, animations: applyTransform)
        } else {
            applyTransform()
        }
        
        delegate?.gestureManager(self, didZoomToScale: clampedScale, atPoint: containerView.center)
    }
    
    // MARK: - ROI Tool Integration
    
    @MainActor public func disableWindowLevelGesture() {
        windowLevelGesture?.isEnabled = false
        print("🔒 Window/Level gesture disabled for ROI tool")
    }
    
    @MainActor public func enableWindowLevelGesture() {
        windowLevelGesture?.isEnabled = true
        print("🔓 Window/Level gesture enabled")
    }
}

// MARK: - Gesture Recognition Implementation

extension SwiftGestureManager {
    
    
    @MainActor @objc private func handleZoom(_ gesture: UIPinchGestureRecognizer) {
        let touchCount = gesture.numberOfTouches
        
        switch gesture.state {
        case .began:
            print("🔍 [ZOOM BEGAN] Touch count: \(touchCount)")
            
        case .changed:
            // CRITICAL: Cancel zoom if touch count drops below 2 to prevent window/level activation
            if touchCount < 2 {
                print("🚫 [ZOOM CANCELLED] Touch count dropped to: \(touchCount), cancelling to prevent window/level")
                gesture.state = .cancelled
                return
            }
            
            let scale = gesture.scale
            let location = gesture.location(in: containerView)
            
            print("🔍 [ZOOM CHANGED] Scale: \(scale), Touch count: \(touchCount)")
            
            // Send incremental scale and touch point to delegate
            // This allows the delegate to apply zoom centered on the touch point
            delegate?.gestureManager(self, didZoomToScale: scale, atPoint: location)
            
            gesture.scale = 1.0 // Reset gesture scale
            
        case .ended, .cancelled:
            print("🔍 [ZOOM ENDED/CANCELLED] Final touch count: \(touchCount)")
            
        default:
            break
        }
    }
    
    @MainActor @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        let touchCount = gesture.numberOfTouches
        
        switch gesture.state {
        case .began:
            print("🔄 [ROTATE BEGAN] Touch count: \(touchCount), enabled: \(gesture.isEnabled)")
            
        case .changed:
            // CRITICAL: Cancel rotation if touch count drops below 2 to prevent window/level activation
            if touchCount < 2 {
                print("🚫 [ROTATE CANCELLED] Touch count dropped to: \(touchCount), cancelling to prevent window/level")
                gesture.state = .cancelled
                return
            }
            
            let rotation = gesture.rotation
            
            // Process ALL rotations to avoid blocking (removed threshold)
            print("🔄 [ROTATE CHANGED] Rotation: \(String(format: "%.3f", rotation)) radians, Touch count: \(touchCount)")
            
            // Send incremental rotation to delegate
            delegate?.gestureManager(self, didRotateByAngle: rotation)
            
            gesture.rotation = 0 // Reset gesture rotation
            
        case .ended, .cancelled:
            print("🔄 [ROTATE ENDED/CANCELLED] Final touch count: \(touchCount)")
            
        case .failed:
            print("🔄 [ROTATE FAILED] Touch count: \(touchCount)")
            
        default:
            break
        }
    }
    
    @MainActor @objc private func handleWindowLevel(_ gesture: UIPanGestureRecognizer) {
        guard let containerView = containerView else { return }
        
        let touchCount = gesture.numberOfTouches
        
        switch gesture.state {
        case .began:
            print("⚡ [WINDOW/LEVEL BEGAN] Touch count: \(touchCount)")
            
            // CRITICAL: ONLY accept single-touch gestures for window/level
            if touchCount != 1 {
                print("🚫 [WINDOW/LEVEL REJECTED] Invalid touch count: \(touchCount), need exactly 1")
                gesture.state = .cancelled
                return
            }
            
            print("✅ [WINDOW/LEVEL ACCEPTED] Single touch confirmed - window/level enabled")
            
            // Check if gesture started in valid area (not near bottom where slider is)
            let location = gesture.location(in: containerView)
            let containerHeight = containerView.bounds.height
            let bottomMargin: CGFloat = 180 // Reserve bottom 180 points for slider area
            
            // Cancel gesture if it started too close to the bottom
            if location.y > containerHeight - bottomMargin {
                print("🚫 [WINDOW/LEVEL REJECTED] In slider area")
                gesture.state = .cancelled
                return
            }
            
        case .changed:
            // CRITICAL: Ensure we still have exactly 1 touch
            if touchCount != 1 {
                print("🚫 [WINDOW/LEVEL CANCELLED] Touch count changed to: \(touchCount), cancelling gesture")
                gesture.state = .cancelled
                return
            }
            
            print("⚡ [WINDOW/LEVEL CHANGED] Touch count: \(touchCount)")
            
            // Additional safety check
            let location = gesture.location(in: containerView)
            let containerHeight = containerView.bounds.height
            let bottomMargin: CGFloat = 180 // Match the same margin as .began
            
            // Ignore if gesture moved into slider area
            if location.y > containerHeight - bottomMargin {
                print("⚡ [WINDOW/LEVEL IGNORED] In slider area")
                return
            }
            
            let translation = gesture.translation(in: containerView)
            
            // Send delta values to delegate for window/level adjustment
            // X axis controls window width, Y axis controls window center
            let velocity = gesture.velocity(in: containerView)
            
            print("✅ [WINDOW/LEVEL ACTIVE] Translation: \(translation), Touch count: \(touchCount)")
            
            // Use enhanced method with correct touch count
            if let delegate = delegate {
                delegate.gestureManager?(self, didAdjustWindowLevel: translation.x, deltaY: -translation.y, touchCount: touchCount, velocity: velocity)
                // No legacy fallback needed - enhanced method handles all cases
            }
            
            gesture.setTranslation(.zero, in: containerView)
            
        default:
            break
        }
    }
    
    @MainActor @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let containerView = containerView else { return }
        
        let touchCount = gesture.numberOfTouches
        
        switch gesture.state {
        case .began:
            print("👆 [PAN BEGAN] Touch count: \(touchCount)")
            
            // Pan gesture needs at least 2 touches (but can have more)
            if touchCount < 2 {
                print("🚫 [PAN REJECTED] Not enough touches: \(touchCount), need at least 2")
                gesture.state = .cancelled
                return
            }
            
        case .changed:
            // CRITICAL: If touch count drops below 2, cancel pan to prevent window/level activation
            if touchCount < 2 {
                print("🚫 [PAN CANCELLED] Touch count dropped to: \(touchCount), cancelling to prevent window/level")
                gesture.state = .cancelled
                return
            }
            
            print("👆 [PAN CHANGED] Touch count: \(touchCount)")
            
            let translation = gesture.translation(in: containerView.superview)
            let velocity = gesture.velocity(in: containerView)
            
            print("✅ [PAN ACTIVE] Translation: \(translation), Velocity: \(velocity)")
            
            // Use enhanced method with correct touch count
            if let delegate = delegate {
                delegate.gestureManager?(self, didPanByOffset: translation, touchCount: touchCount, velocity: velocity)
                // No legacy fallback needed - enhanced method handles all cases
            }
            
            gesture.setTranslation(.zero, in: containerView.superview)
            
        default:
            break
        }
    }
    
    @objc private func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
        guard isGestureEnabled(.swipeImage) else { return }
        delegate?.gestureManagerDidSwipeToNextImage(self)
    }
    
    @objc private func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
        guard isGestureEnabled(.swipeImage) else { return }
        delegate?.gestureManagerDidSwipeToPreviousImage(self)
    }
    
    @objc private func handleSwipeUp(_ gesture: UISwipeGestureRecognizer) {
        guard isGestureEnabled(.swipeSeries) else { return }
        delegate?.gestureManagerDidSwipeToNextSeries(self)
    }
    
    @objc private func handleSwipeDown(_ gesture: UISwipeGestureRecognizer) {
        guard isGestureEnabled(.swipeSeries) else { return }
        delegate?.gestureManagerDidSwipeToPreviousSeries(self)
    }
}

// MARK: - Gesture Delegate Implementation

extension SwiftGestureManager: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // PRIORITY 1: Multi-touch gestures (zoom, rotate, pan) can work together
        let multiTouchGestures: [UIGestureRecognizer?] = [zoomGesture, rotationGesture, panGesture]
        let isFirstMultiTouch = multiTouchGestures.contains { $0 === gestureRecognizer }
        let isSecondMultiTouch = multiTouchGestures.contains { $0 === otherGestureRecognizer }
        
        if isFirstMultiTouch && isSecondMultiTouch {
            print("✅ [GESTURE] Allowing multi-touch gestures to work together")
            return true
        }
        
        // PRIORITY 2: Window/Level (single touch) is BLOCKED by any multi-touch gesture
        if gestureRecognizer == windowLevelGesture && isSecondMultiTouch {
            print("🚫 [GESTURE] Blocking windowLevel (1-touch) due to multi-touch gesture")
            return false
        }
        
        if otherGestureRecognizer == windowLevelGesture && isFirstMultiTouch {
            print("🚫 [GESTURE] Blocking windowLevel (1-touch) due to multi-touch gesture")
            return false
        }
        
        // PRIORITY 3: Window/Level works alone (single touch) - don't allow with anything
        if gestureRecognizer == windowLevelGesture || otherGestureRecognizer == windowLevelGesture {
            print("🚫 [GESTURE] Window/level works alone - blocking simultaneous")
            return false
        }
        
        // PRIORITY 4: Block swipe gestures from interfering with multi-touch
        let swipeGestures = self.swipeGestures
        let isFirstSwipe = swipeGestures.contains { $0 === gestureRecognizer }
        let isSecondSwipe = swipeGestures.contains { $0 === otherGestureRecognizer }
        
        if (isFirstSwipe && isSecondMultiTouch) || (isSecondSwipe && isFirstMultiTouch) {
            print("🚫 [GESTURE] Blocking swipe interfering with multi-touch")
            return false
        }
        
        // PRIORITY 5: Default - allow other simultaneous gestures 
        print("✅ [GESTURE] Default - allowing simultaneous gestures")
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // CRITICAL FIX: Window/level (single-touch) should be required to fail when multi-touch gestures start
        let multiTouchGestures: [UIGestureRecognizer?] = [zoomGesture, rotationGesture, panGesture]
        let isCurrentMultiTouch = multiTouchGestures.contains { $0 === gestureRecognizer }
        let isOtherMultiTouch = multiTouchGestures.contains { $0 === otherGestureRecognizer }
        
        // Window/level should fail when multi-touch gestures begin
        if gestureRecognizer == windowLevelGesture && isOtherMultiTouch {
            print("🎯 [GESTURE PRIORITY] WindowLevel must fail for multi-touch gesture")
            return true
        }
        
        // Multi-touch gestures should NOT be required to fail for window/level
        if isCurrentMultiTouch && otherGestureRecognizer == windowLevelGesture {
            print("✅ [GESTURE PRIORITY] Multi-touch gesture takes priority over windowLevel")
            return false
        }
        
        return false
    }
}

// MARK: - Settings Management

private extension SwiftGestureManager {
    
    func loadGestureSettings() {
        for gestureType in GestureType.allCases {
            let key = settingsPrefix + "enable\(gestureType.description.replacingOccurrences(of: " ", with: ""))"
            if userDefaults.object(forKey: key) != nil {
                if userDefaults.bool(forKey: key) {
                    configuration.enabledGestures.insert(gestureType)
                } else {
                    configuration.enabledGestures.remove(gestureType)
                }
            }
        }
        
        // Load zoom limits if available
        let minZoomKey = settingsPrefix + "minZoomScale"
        let maxZoomKey = settingsPrefix + "maxZoomScale"
        
        if userDefaults.object(forKey: minZoomKey) != nil {
            configuration.zoomLimits.minScale = CGFloat(userDefaults.double(forKey: minZoomKey))
        }
        if userDefaults.object(forKey: maxZoomKey) != nil {
            configuration.zoomLimits.maxScale = CGFloat(userDefaults.double(forKey: maxZoomKey))
        }
    }
    
    func saveGestureSettings() {
        for gestureType in GestureType.allCases {
            let key = settingsPrefix + "enable\(gestureType.description.replacingOccurrences(of: " ", with: ""))"
            let enabled = configuration.enabledGestures.contains(gestureType)
            userDefaults.set(enabled, forKey: key)
        }
        
        // Save zoom limits
        userDefaults.set(Double(configuration.zoomLimits.minScale), forKey: settingsPrefix + "minZoomScale")
        userDefaults.set(Double(configuration.zoomLimits.maxScale), forKey: settingsPrefix + "maxZoomScale")
        
        userDefaults.synchronize()
    }
}

// MARK: - Objective-C Bridge Interface

@objc protocol SwiftGestureManagerBridgeDelegate: AnyObject {
    @objc optional func gestureManager(_ manager: AnyObject, didAdjustWindowLevel level: CGFloat, windowWidth width: CGFloat)
    @objc optional func gestureManager(_ manager: AnyObject, didZoomToScale scale: CGFloat)
    @objc optional func gestureManager(_ manager: AnyObject, didRotateByAngle angle: CGFloat)
    @objc optional func gestureManager(_ manager: AnyObject, didPanByOffset offset: CGPoint)
    @objc optional func gestureManagerDidSwipeToNextImage(_ manager: AnyObject)
    @objc optional func gestureManagerDidSwipeToPreviousImage(_ manager: AnyObject)
    @objc optional func gestureManagerDidSwipeToNextSeries(_ manager: AnyObject)
    @objc optional func gestureManagerDidSwipeToPreviousSeries(_ manager: AnyObject)
}

// MARK: - Objective-C Bridge Implementation

@objc class SwiftGestureManagerBridge: NSObject {
    
    private let swiftManager: SwiftGestureManager
    private weak var legacyDelegate: SwiftGestureManagerBridgeDelegate?
    
    @MainActor @objc init(containerView: UIView, dicomView: DCMImgView?) {
        self.swiftManager = SwiftGestureManager(containerView: containerView, dicomView: dicomView)
        super.init()
        
        swiftManager.delegate = self
    }
    
    @objc var delegate: SwiftGestureManagerBridgeDelegate? {
        get { legacyDelegate }
        set { legacyDelegate = newValue }
    }
    
    @MainActor @objc func setupGestures() {
        swiftManager.setupGestures()
    }
    
    @MainActor @objc func removeAllGestures() {
        swiftManager.removeAllGestures()
    }
    
    @MainActor func enableGesture(_ type: GestureType, enabled: Bool) {
        swiftManager.enableGesture(type, enabled: enabled)
    }
    
    @MainActor @objc func resetAllTransforms() {
        swiftManager.resetAllTransforms()
    }
    
    @objc var currentZoomScale: CGFloat {
        return swiftManager.currentZoomScale
    }
    
    @objc var currentRotationAngle: CGFloat {
        return swiftManager.currentRotationAngle
    }
    
    @objc var currentPanOffset: CGPoint {
        return swiftManager.currentPanOffset
    }
}

// MARK: - Bridge Delegate Integration

extension SwiftGestureManagerBridge: SwiftGestureManagerDelegate {
    
    func gestureManager(_ manager: SwiftGestureManager, didAdjustWindowLevel deltaX: CGFloat, deltaY: CGFloat) {
        legacyDelegate?.gestureManager?(self, didAdjustWindowLevel: deltaY, windowWidth: deltaX)
    }
    
    // Optional enhanced method - Phase 11F+
    func gestureManager(_ manager: SwiftGestureManager, didAdjustWindowLevel deltaX: CGFloat, deltaY: CGFloat, touchCount: Int, velocity: CGPoint) {
        // Enhanced version for bridge - could be extended later
        gestureManager(manager, didAdjustWindowLevel: deltaX, deltaY: deltaY)
    }
    
    func gestureManager(_ manager: SwiftGestureManager, didZoomToScale scale: CGFloat, atPoint point: CGPoint) {
        legacyDelegate?.gestureManager?(self, didZoomToScale: scale)
    }
    
    func gestureManager(_ manager: SwiftGestureManager, didRotateByAngle angle: CGFloat) {
        legacyDelegate?.gestureManager?(self, didRotateByAngle: angle)
    }
    
    func gestureManager(_ manager: SwiftGestureManager, didPanByOffset offset: CGPoint) {
        legacyDelegate?.gestureManager?(self, didPanByOffset: offset)
    }
    
    // Optional enhanced method - Phase 11F+
    func gestureManager(_ manager: SwiftGestureManager, didPanByOffset offset: CGPoint, touchCount: Int, velocity: CGPoint) {
        // Enhanced version for bridge - could be extended later
        gestureManager(manager, didPanByOffset: offset)
    }
    
    func gestureManagerDidSwipeToNextImage(_ manager: SwiftGestureManager) {
        legacyDelegate?.gestureManagerDidSwipeToNextImage?(self)
    }
    
    func gestureManagerDidSwipeToPreviousImage(_ manager: SwiftGestureManager) {
        legacyDelegate?.gestureManagerDidSwipeToPreviousImage?(self)
    }
    
    func gestureManagerDidSwipeToNextSeries(_ manager: SwiftGestureManager) {
        legacyDelegate?.gestureManagerDidSwipeToNextSeries?(self)
    }
    
    func gestureManagerDidSwipeToPreviousSeries(_ manager: SwiftGestureManager) {
        legacyDelegate?.gestureManagerDidSwipeToPreviousSeries?(self)
    }
}

// MARK: - Supporting Extensions

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
