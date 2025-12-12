import {
  DocumentScanner,
  ResponseType,
  ScanDocumentResponseStatus,
  ScannerMode,
} from '@capgo/capacitor-document-scanner';
import { Capacitor } from '@capacitor/core';

const scanButton = document.getElementById('scanButton');
const statusText = document.getElementById('statusText');
const resultsSection = document.getElementById('resultsSection');
const resultsContainer = document.getElementById('results');

const responseTypeSelect = document.getElementById('responseType');
const qualityInput = document.getElementById('croppedImageQuality');
const maxDocsInput = document.getElementById('maxNumDocuments');
const scannerModeSelect = document.getElementById('scannerMode');
const letUserAdjustCropInput = document.getElementById('letUserAdjustCrop');
const brightnessInput = document.getElementById('brightness');
const contrastInput = document.getElementById('contrast');

const setStatus = (message, type = 'idle') => {
  if (statusText) {
    // Remove all status classes
    statusText.className = 'status-badge';
    
    // Add appropriate class based on type
    switch (type) {
      case 'scanning':
        statusText.classList.add('status-scanning');
        break;
      case 'success':
        statusText.classList.add('status-success');
        break;
      case 'error':
        statusText.classList.add('status-error');
        break;
      case 'cancel':
        statusText.classList.add('status-cancel');
        break;
      default:
        statusText.classList.add('status-idle');
    }
    
    statusText.innerHTML = `
      <span class="status-indicator"></span>
      <span>${message}</span>
    `;
  }
};

const clearResults = () => {
  if (resultsContainer) {
    resultsContainer.innerHTML = '';
  }
  if (resultsSection) {
    resultsSection.hidden = true;
  }
};

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

const buildOptions = () => {
  const options = {};
  const selectedResponse = responseTypeSelect?.value === ResponseType.Base64 ? ResponseType.Base64 : ResponseType.ImageFilePath;
  options.responseType = selectedResponse;

  const quality = Number(qualityInput?.value);
  if (!Number.isNaN(quality)) {
    options.croppedImageQuality = clamp(quality, 0, 100);
  }

  const maxDocs = Number(maxDocsInput?.value);
  if (!Number.isNaN(maxDocs) && maxDocs > 0) {
    options.maxNumDocuments = Math.floor(maxDocs);
  }

  const scannerMode = scannerModeSelect?.value;
  if (scannerMode && Object.values(ScannerMode).includes(scannerMode)) {
    options.scannerMode = scannerMode;
  }

  if (typeof letUserAdjustCropInput?.checked === 'boolean') {
    options.letUserAdjustCrop = letUserAdjustCropInput.checked;
  }

  const brightness = Number(brightnessInput?.value);
  if (!Number.isNaN(brightness)) {
    options.brightness = clamp(brightness, -255, 255);
  }

  const contrast = Number(contrastInput?.value);
  if (!Number.isNaN(contrast)) {
    options.contrast = clamp(contrast, 0, 10);
  }

  return options;
};

const renderResults = (images = [], responseType) => {
  if (!resultsContainer) {
    return;
  }

  resultsContainer.innerHTML = '';

  if (images.length === 0) {
    const emptyState = document.createElement('div');
    emptyState.className = 'empty-state';
    emptyState.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
      </svg>
      <p>No documents scanned</p>
    `;
    resultsContainer.appendChild(emptyState);
  } else {
    images.forEach((image, index) => {
      const wrapper = document.createElement('div');
      wrapper.className = 'scan-result';
      
      const title = document.createElement('h3');
      title.textContent = `Document ${index + 1}`;
      wrapper.appendChild(title);

      const imageContainer = document.createElement('div');
      imageContainer.className = 'image-container';

      const img = document.createElement('img');
      img.alt = `Scanned document ${index + 1}`;
      img.loading = 'lazy';

      if (responseType === ResponseType.Base64) {
        // Base64 strings need a data URI prefix to render in the browser.
        img.src = `data:image/jpeg;base64,${image}`;
      } else {
        // Convert the file path to a web-accessible URL using Capacitor
        img.src = Capacitor.convertFileSrc(image);
        
        // Also show the file path for reference
        const filePath = document.createElement('div');
        filePath.className = 'file-path';
        filePath.textContent = image;
        wrapper.appendChild(filePath);
      }

      imageContainer.appendChild(img);
      wrapper.insertBefore(imageContainer, wrapper.children[1]);
      resultsContainer.appendChild(wrapper);
    });
  }

  if (resultsSection) {
    resultsSection.hidden = false;
  }
};

const handleScan = async () => {
  clearResults();
  setStatus('Starting scan...', 'scanning');
  
  // Disable button during scan
  if (scanButton) {
    scanButton.disabled = true;
  }

  try {
    const options = buildOptions();
    const response = await DocumentScanner.scanDocument(options);
    const status = response.status ?? 'unknown';

    if (response.status === ScanDocumentResponseStatus.Success && response.scannedImages?.length) {
      const count = response.scannedImages.length;
      setStatus(`Successfully scanned ${count} document${count > 1 ? 's' : ''}`, 'success');
      renderResults(response.scannedImages, options.responseType);
    } else if (response.status === ScanDocumentResponseStatus.Cancel) {
      setStatus('Scan cancelled', 'cancel');
      renderResults([], options.responseType);
    } else {
      setStatus('No documents scanned', 'idle');
      renderResults([], options.responseType);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setStatus(`Error: ${message}`, 'error');
    clearResults();
  } finally {
    // Re-enable button
    if (scanButton) {
      scanButton.disabled = false;
    }
  }
};

if (scanButton) {
  scanButton.addEventListener('click', handleScan);
}

// Set initial status
setStatus('Ready to scan', 'idle');
