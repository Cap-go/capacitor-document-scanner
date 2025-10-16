import {
  DocumentScanner,
  ResponseType,
  ScanDocumentResponseStatus,
} from '@capgo/capacitor-document-scanner';

const scanButton = document.getElementById('scanButton');
const statusText = document.getElementById('statusText');
const resultsSection = document.getElementById('resultsSection');
const resultsContainer = document.getElementById('results');

const responseTypeSelect = document.getElementById('responseType');
const qualityInput = document.getElementById('croppedImageQuality');
const maxDocsInput = document.getElementById('maxNumDocuments');
const letUserAdjustCropInput = document.getElementById('letUserAdjustCrop');

const setStatus = (message) => {
  if (statusText) {
    statusText.textContent = `Status: ${message}`;
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

  if (typeof letUserAdjustCropInput?.checked === 'boolean') {
    options.letUserAdjustCrop = letUserAdjustCropInput.checked;
  }

  return options;
};

const renderResults = (images = [], responseType) => {
  if (!resultsContainer) {
    return;
  }

  resultsContainer.innerHTML = '';

  images.forEach((image, index) => {
    const wrapper = document.createElement('div');
    wrapper.className = 'scan-result';
    const title = document.createElement('h3');
    title.textContent = `Document ${index + 1}`;
    wrapper.appendChild(title);

    if (responseType === ResponseType.Base64) {
      const img = document.createElement('img');
      // Base64 strings need a data URI prefix to render in the browser.
      img.src = `data:image/jpeg;base64,${image}`;
      img.alt = `Scanned document ${index + 1}`;
      img.style.maxWidth = '100%';
      img.style.height = 'auto';
      wrapper.appendChild(img);
    } else {
      const codeBlock = document.createElement('code');
      codeBlock.textContent = image;
      wrapper.appendChild(codeBlock);
    }

    resultsContainer.appendChild(wrapper);
  });

  if (resultsSection) {
    resultsSection.hidden = images.length === 0;
  }
};

const handleScan = async () => {
  clearResults();
  setStatus('Starting scan...');

  try {
    const options = buildOptions();
    const response = await DocumentScanner.scanDocument(options);
    const status = response.status ?? 'unknown';
    setStatus(status);

    if (response.status === ScanDocumentResponseStatus.Success && response.scannedImages?.length) {
      renderResults(response.scannedImages, options.responseType);
    } else {
      renderResults([], options.responseType);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setStatus(`Error - ${message}`);
    clearResults();
  }
};

if (scanButton) {
  scanButton.addEventListener('click', handleScan);
}
