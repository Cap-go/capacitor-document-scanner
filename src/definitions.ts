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
   * Android only: maximum number of documents the user can scan.
   * @default 24
   */
  maxNumDocuments?: number;

  /**
   * Format to return scanned images in (file paths or base64 strings).
   * @default ResponseType.ImageFilePath
   */
  responseType?: ResponseType;
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
