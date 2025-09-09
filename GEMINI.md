# Gemini Development Plan: DcmSwift Optimization

This document outlines the strategic plan for refactoring and optimizing the `DcmSwift` library. The goal is to significantly improve the image rendering performance and network reliability of its primary consumer, the `Isis DICOM Viewer`.

The plan is based on the detailed guidelines in `instructions.md`.

## Core Objectives

1.  **Performance:** Achieve high-performance image rendering and scrolling by adopting a real-time pixel pipeline, inspired by the efficient architecture of the legacy project located in the `/Users/thales/GitHub/References/` directory.
2.  **Reliability:** Correct critical bugs in the DIMSE networking protocols (C-FIND, C-GET, C-MOVE) to ensure stable and correct communication with remote PACS nodes.
3.  **Separation of Concerns:** Solidify the architecture where `DcmSwift` handles all core DICOM logic (parsing, rendering, networking), while `Isis DICOM Viewer` remains focused on UI/UX.

---

## Task 1: Image Rendering Pipeline Optimization

**Objective:** Replace the current, inefficient image rendering workflow with a high-performance, buffer-based pipeline.

### Subtask 1.1: Implement High-Performance Image View

*   **Action:** Re-implement `DcmSwift/Sources/DcmSwift/Graphics/DicomPixelView.swift`.
*   **Strategy:** Adapt the logic from the reference file `/Users/thales/GitHub/References/DicomPixelView.swift`.
    *   Maintain a persistent buffer for raw pixel data (`pix16` or `pix8`) to eliminate redundant file reads.
    *   Implement `computeLookUpTable16` and `createImage16` for fast, on-the-fly conversion from 16-bit raw pixels to an 8-bit displayable buffer.
    *   Ensure the `updateWindowLevel` function only triggers a recalculation of the 8-bit buffer and a lightweight `CGImage` recreation, avoiding the expensive `UIImage` process.

### Subtask 1.2: Integrate New View into the `DcmSwift` Pipeline

*   **Action:** Modify `DcmSwift/Sources/DcmSwift/Graphics/DicomImage.swift`.
*   **Strategy:** The `image(forFrame:wwl:inverted:)` function will be rewritten. Instead of performing the rendering itself, it will:
    1.  Use a decoder (inspired by `/Users/thales/GitHub/References/DCMDecoder.swift`) to get the raw pixel buffer.
    2.  Pass this buffer to the new, optimized `DicomPixelView` (or a similar canvas object) which will handle the final W/L mapping and rendering.

### Subtask 1.3: Optimize the `Isis DICOM Viewer` Image Pipeline

*   **Action:** Refactor `Isis DICOM Viewer/Isis DICOM Viewer/Data/Services/DcmSwiftImagePipeline.swift`.
*   **Strategy:**
    *   The `framePixels` method will be optimized to read raw pixels from a DICOM file only once per series, caching them in memory.
    *   This cached raw pixel buffer will be passed directly to the new `DicomPixelCanvas` (which will be based on the new `DicomPixelView` logic), offloading all W/L and rendering calculations to the optimized component.

### Subtask 1.4: Implement High-Speed Thumbnail Generation

*   **Action:** Integrate down-sampling logic into `Isis DICOM Viewer/Isis DICOM Viewer/Data/Services/DICOM/ThumbnailGenerator.swift`.
*   **Strategy:** Port the `getDownsampledPixels16` logic from the reference `DCMDecoder.swift` to enable extremely fast, low-overhead thumbnail creation without full image decoding.

---

## Task 2: Network Protocol Correction

**Objective:** Fix critical bugs in the C-FIND, C-GET, and C-MOVE implementations to ensure reliable and compliant DICOM network communication.

### Subtask 2.1: Correct C-FIND Query Filtering

*   **Action:** Modify `DcmSwift/Sources/DcmSwift/Networking/CFindSCU.swift` and `PDUEncoder.swift`.
*   **Strategy:**
    1.  Correct the `request(association:channel:)` method in `CFindSCU` to ensure the `queryDataset` (containing search filters) is included in the same PDU as the C-FIND-RQ command.
    2.  Adjust the `PDUEncoder` to correctly serialize the `queryDataset` alongside the command dataset, preventing the server from ignoring the filters.

### Subtask 2.2: Stabilize C-GET/C-MOVE Data Reception

*   **Action:** Improve `DicomAssociation.swift`, `PDUBytesDecoder.swift`, and `CGetSCU.swift`.
*   **Strategy:**
    1.  Enhance `PDUBytesDecoder` to correctly reassemble fragmented PDU messages, especially those containing large pixel data payloads from C-STORE sub-operations.
    2.  Update `CGetSCU` to properly handle multiple incoming C-STORE-RQ data transfers, accumulating the pixel data into a temporary buffer until the complete file is received.
    3.  Audit and fortify the temporary C-STORE-SCP server logic initiated by `DicomClient.move()`. Ensure the server starts reliably and that the C-MOVE operation only completes after all C-STORE sub-operations have successfully finished.