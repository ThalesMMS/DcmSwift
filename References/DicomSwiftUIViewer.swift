//
//  DicomSwiftUIViewer.swift
//  DICOMViewer
//
//  Modern SwiftUI DICOM viewer using the Swift bridge
//  Demonstrates async/await patterns and medical imaging best practices
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Main DICOM SwiftUI View

@available(iOS 13.0, *)
public struct DicomSwiftUIViewer: View {
    
    // MARK: - Properties
    
    @ObservedObject private var processor = AsyncDicomProcessor()
    @State private var selectedDicomFile: URL?
    @State private var dicomResult: DicomDecodingResult?
    @State private var currentImage: UIImage?
    @State private var windowCenter: Double = 128
    @State private var windowWidth: Double = 256
    @State private var showingFilePicker = false
    @State private var showingMetadata = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @Environment(\.presentationMode) var presentationMode
    
    // MARK: - Initialization
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Toolbar
                toolbarView
                
                // Main content
                if processor.isProcessing {
                    processingView
                } else if let image = currentImage {
                    dicomImageView(image)
                } else {
                    emptyStateView
                }
                
                // Controls
                if dicomResult != nil {
                    controlsView
                }
            }
            .navigationBarTitle("DICOM Viewer")
            .navigationBarItems(
                leading: Button("Select File") { showingFilePicker = true },
                trailing: HStack {
                    if dicomResult != nil {
                        Button("Metadata") { showingMetadata = true }
                    }
                    Button("Settings") { /* Open settings */ }
                }
            )
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                selectedDicomFile = url
                Task {
                    await loadDicomFile(url)
                }
            }
        }
        .sheet(isPresented: $showingMetadata) {
            if let dicomResult = dicomResult {
                DicomMetadataView(result: dicomResult)
            }
        }
        .alert(isPresented: $showingError) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage ?? "An unknown error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Subviews
    
    private var toolbarView: some View {
        HStack {
            Button(action: { showingFilePicker = true }) {
                HStack {
                    Image(systemName: "folder")
                    Text("Open")
                }
            }
            
            Spacer()
            
            if dicomResult != nil {
                Button(action: { Task { await generateThumbnail() } }) {
                    HStack {
                        Image(systemName: "photo")
                        Text("Thumbnail")
                    }
                }
                
                Button(action: { showingMetadata = true }) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Info")
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var processingView: some View {
        VStack(spacing: 20) {
            // iOS 13 compatible loading indicator
            if #available(iOS 14.0, *) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                // Fallback for iOS 13
                ActivityIndicator(isAnimating: true)
            }
            
            Text(processor.currentOperation)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(Int(processor.processingProgress * 100))%")
                .font(.title)
                .fontWeight(.semibold)
        }
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No DICOM File Selected")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Select a DICOM file to begin viewing medical images")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Select DICOM File") {
                showingFilePicker = true
            }
        }
        .padding()
    }
    
    private func dicomImageView(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: max(geometry.size.width, image.size.width),
                        height: max(geometry.size.height, image.size.height)
                    )
            }
            .background(Color.black)
        }
    }
    
    private var controlsView: some View {
        VStack(spacing: 16) {
            // Window/Level Controls
            Group {
                VStack(spacing: 12) {
                    HStack {
                        Text("Window Center")
                        Spacer()
                        Text(String(format: "%.0f", windowCenter))
                    }
                    
                    Slider(
                        value: $windowCenter,
                        in: -1000...3000,
                        step: 1
                    )
                    
                    HStack {
                        Text("Window Width")
                        Spacer()
                        Text(String(format: "%.0f", windowWidth))
                    }
                    
                    Slider(
                        value: $windowWidth,
                        in: 1...4000,
                        step: 1
                    )
                }
            }
            
            // Preset Buttons
            HStack {
                Button("Lung") { applyPreset(.lung) }
                Button("Bone") { applyPreset(.bone) }
                Button("Brain") { applyPreset(.brain) }
                Button("Abdomen") { applyPreset(.abdomen) }
            }
            
            // Image Information
            if let result = dicomResult {
                DicomImageInfoCard(imageInfo: result.imageInfo)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Action Methods
    
    /// Loads and processes a DICOM file from the given URL
    @MainActor
    private func loadDicomFile(_ url: URL) async {
        // Request access to the file
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access selected file"
            showingError = true
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        let result = await processor.decodeDicomFile(at: url.path) { progress, operation in
            // Progress updates are handled by the @Published properties
        }
        
        switch result {
        case .success(let dicomData):
            dicomResult = dicomData
            
            // Set initial window/level values
            windowCenter = dicomData.imageInfo.windowCenter
            windowWidth = dicomData.imageInfo.windowWidth
            
            // Generate initial image
            await generateImage()
            
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    /// Generates a UIImage from the current DICOM result
    private func generateImage() async {
        guard let result = dicomResult else { return }
        
        let image = await processor.generateUIImage(from: result, applyWindowLevel: true)
        
        await MainActor.run {
            currentImage = image
        }
    }
    
    /// Applies a window/level preset to the current image
    private func applyPreset(_ preset: DicomWindowPresetType) {
        switch preset {
        case .lung:
            windowCenter = -600
            windowWidth = 1600
        case .bone:
            windowCenter = 300
            windowWidth = 1500
        case .brain:
            windowCenter = 40
            windowWidth = 80
        case .abdomen:
            windowCenter = 60
            windowWidth = 350
        case .custom:
            break
        }
    }
    
    /// Generates a thumbnail from the current DICOM result
    private func generateThumbnail() async {
        guard let result = dicomResult else { return }
        
        let _ = await processor.generateThumbnail(
            from: result,
            size: CGSize(width: 150, height: 150),
            quality: .high
        )
        
        // Handle thumbnail (save, display, etc.)
    }
}

// MARK: - DicomSwiftUIViewer Extensions

@available(iOS 13.0, *)
extension DicomSwiftUIViewer {
    
    // MARK: - View Builder Helpers
    
    /// Creates a view for displaying DICOM processing status
    private func statusView(for operation: String, progress: Double) -> some View {
        VStack(spacing: 12) {
            if #available(iOS 14.0, *) {
                ProgressView(value: progress)
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                ActivityIndicator(isAnimating: true)
            }
            
            Text(operation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    /// Creates preset button for window/level adjustments
    private func presetButton(title: String, preset: DicomWindowPresetType) -> some View {
        Button(title) {
            applyPreset(preset)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Supporting Views

@available(iOS 13.0, *)
struct DicomImageInfoCard: View {
    let imageInfo: DicomImageInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image Information")
                .font(.headline)
            
            HStack {
                Text("Dimensions:")
                    .fontWeight(.medium)
                Spacer()
                Text("\(imageInfo.width) × \(imageInfo.height)")
            }
            
            HStack {
                Text("Bit Depth:")
                    .fontWeight(.medium)
                Spacer()
                Text("\(imageInfo.bitDepth) bits")
            }
            
            HStack {
                Text("Samples/Pixel:")
                    .fontWeight(.medium)
                Spacer()
                Text("\(imageInfo.samplesPerPixel)")
            }
            
            HStack {
                Text("Signed:")
                    .fontWeight(.medium)
                Spacer()
                Text(imageInfo.isSignedImage ? "Yes" : "No")
            }
            
            HStack {
                Text("Compressed:")
                    .fontWeight(.medium)
                Spacer()
                Text(imageInfo.isCompressed ? "Yes" : "No")
            }
        }
        .padding()
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
}

@available(iOS 13.0, *)
struct DicomMetadataView: View {
    let result: DicomDecodingResult
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Patient Information")) {
                    MetadataRow(title: "Name", value: result.patientInfo.patientName)
                    MetadataRow(title: "ID", value: result.patientInfo.patientID)
                    MetadataRow(title: "Sex", value: result.patientInfo.patientSex)
                    MetadataRow(title: "Age", value: result.patientInfo.patientAge)
                }
                
                Section(header: Text("Study Information")) {
                    MetadataRow(title: "Description", value: result.studyInfo.studyDescription)
                    MetadataRow(title: "Date", value: result.studyInfo.studyDate)
                    MetadataRow(title: "Time", value: result.studyInfo.studyTime)
                    MetadataRow(title: "Modality", value: result.studyInfo.modality)
                    MetadataRow(title: "Study UID", value: result.studyInfo.studyInstanceUID)
                }
                
                Section(header: Text("Image Properties")) {
                    MetadataRow(title: "Dimensions", value: "\(result.imageInfo.width) × \(result.imageInfo.height)")
                    MetadataRow(title: "Bit Depth", value: "\(result.imageInfo.bitDepth) bits")
                    MetadataRow(title: "Window Center", value: String(format: "%.0f", result.imageInfo.windowCenter))
                    MetadataRow(title: "Window Width", value: String(format: "%.0f", result.imageInfo.windowWidth))
                }
            }
            .navigationBarTitle("DICOM Metadata")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct MetadataRow: View {
    let title: String
    let value: String?
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            Spacer()
            Text(value ?? "N/A")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Document Picker

@available(iOS 13.0, *)
struct DocumentPicker: UIViewControllerRepresentable {
    let onFileSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onFileSelected(url)
            }
        }
    }
}

// MARK: - iOS 13 Compatible Activity Indicator

@available(iOS 13.0, *)
struct ActivityIndicator: UIViewRepresentable {
    let isAnimating: Bool
    
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        return indicator
    }
    
    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        if isAnimating {
            uiView.startAnimating()
        } else {
            uiView.stopAnimating()
        }
    }
}

// MARK: - Preview

@available(iOS 13.0, *)
struct DicomSwiftUIViewer_Previews: PreviewProvider {
    static var previews: some View {
        DicomSwiftUIViewer()
    }
}
