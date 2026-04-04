export interface DocumentScannerPlugin {
  /**
   * Opens the device camera and starts the document scanning experience.
   */
  scanDocument(options?: ScanDocumentOptions): Promise<ScanDocumentResponse>;
}

export interface ScanDocumentOptions {
  /**
   * Android only: quality of the cropped image from 0 - 100 (100 is best).
   * @default 100
   */
  croppedImageQuality?: number;

  /**
   * Allow the user to adjust the detected crop before saving.
   * On iOS this forces the native VisionKit preview/editor after each capture using
   * the private VisionKit navigation hooks needed to keep the scanner flow alive.
   * On Android this enables ML Kit's crop adjustment flow.
   * @default true
   */
  letUserAdjustCrop?: boolean;

  /**
   * When enabled, shows the current scanned page before continuing so the user can
   * review it and explicitly continue or finish the flow.
   * On iOS this forces the native VisionKit preview/editor between captures.
   * On Android this switches to a one-page-at-a-time flow between ML Kit sessions.
   * The review/editor screen is still shown automatically when the scan limit is reached.
   * @default false
   */
  reviewCapturedDocument?: boolean;

  /**
   * Maximum number of documents to scan.
   * On iOS: VisionKit caps scans at 24 pages (system limit), and the hacked native flow
   * can still stop earlier when you pass a smaller limit.
   * On Android: customizable limit; defaults to 20 for performance (clamped 1-24).
   * Set to 1 for single-scan mode where the scanner stops after one document.
   * @default 20 on Android, 24 on iOS
   */
  maxNumDocuments?: number;

  /**
   * Format to return scanned images in (file paths or base64 strings).
   * @default ResponseType.ImageFilePath
   */
  responseType?: ResponseType;

  /**
   * Brightness adjustment applied to scanned images.
   * Range: -255 to 255 (0 = no change, positive = brighter, negative = darker)
   * Useful for compensating low-light scans.
   * @default 0
   */
  brightness?: number;

  /**
   * Contrast adjustment applied to scanned images.
   * Range: 0.0 to 10.0 (1.0 = no change, >1 = more contrast, <1 = less contrast)
   * Helps improve text clarity in poorly lit scans.
   * @default 1.0
   */
  contrast?: number;

  /**
   * Android only: scanner mode that controls ML Kit features and filters.
   * - 'base': Basic scan with crop/rotate, no filters or ML cleaning
   * - 'base_with_filter': Adds grayscale and auto-enhancement filters
   * - 'full': All features including ML-based image cleaning (erases stains, fingers, etc.)
   * @default ScannerMode.Full
   */
  scannerMode?: ScannerMode;
}

export enum ScannerMode {
  /**
   * Basic document scanning with crop and rotate features only.
   * No filters or ML-based enhancements.
   */
  Base = 'base',

  /**
   * Basic features plus automatic filters (grayscale, auto-enhancement).
   */
  BaseWithFilter = 'base_with_filter',

  /**
   * Full feature set including ML-based image cleaning.
   * Automatically removes stains, fingers, and other artifacts.
   */
  Full = 'full',
}

export enum ResponseType {
  /**
   * Return scanned images as base64-encoded strings.
   */
  Base64 = 'base64',

  /**
   * Return scanned images as file paths on disk.
   */
  ImageFilePath = 'imageFilePath',
}

export interface ScanDocumentResponse {
  /**
   * Scanned images in the requested response format.
   */
  scannedImages?: string[];

  /**
   * Indicates whether the scan completed or was cancelled.
   */
  status?: ScanDocumentResponseStatus;

  /**
   * Get the native Capacitor plugin version
   *
   * @returns {Promise<{ id: string }>} an Promise with version for this device
   * @throws An error if the something went wrong
   */
  getPluginVersion(): Promise<{ version: string }>;
}

export enum ScanDocumentResponseStatus {
  /**
   * The scan completed successfully.
   */
  Success = 'success',

  /**
   * The user cancelled the scan flow.
   */
  Cancel = 'cancel',
}
