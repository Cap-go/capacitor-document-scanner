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
   * Android only: allow the user to adjust the detected crop before saving.
   * Disabling this forces single-document capture.
   * @default true
   */
  letUserAdjustCrop?: boolean;

  /**
   * Maximum number of documents to scan.
   * On Android: limits documents the user can scan (1-24).
   * On iOS: prevents scanning more than the specified number of pages (uses internal API swizzling).
   * Set to 1 for single-scan mode where the scanner stops after one document.
   * @default 24 on Android, unlimited on iOS
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
