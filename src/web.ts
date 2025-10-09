import { WebPlugin } from '@capacitor/core';

import type { DocumentScannerPlugin, ScanDocumentOptions, ScanDocumentResponse } from './definitions';

export class DocumentScannerWeb extends WebPlugin implements DocumentScannerPlugin {
  async scanDocument(_options?: ScanDocumentOptions): Promise<ScanDocumentResponse> {
    throw this.unimplemented('Document scanning is not supported on the web.');
  }
}
