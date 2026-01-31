# @capgo/capacitor-document-scanner
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin_document_scanner"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin_document_scanner"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>
Capacitor plugin to scan document iOS and Android

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/document-scanner/

## Compatibility

| Plugin version | Capacitor compatibility | Maintained |
| -------------- | ----------------------- | ---------- |
| v8.\*.\*       | v8.\*.\*                | ✅          |
| v7.\*.\*       | v7.\*.\*                | On demand   |
| v6.\*.\*       | v6.\*.\*                | ❌          |
| v5.\*.\*       | v5.\*.\*                | ❌          |

> **Note:** The major version of this plugin follows the major version of Capacitor. Use the version that matches your Capacitor installation (e.g., plugin v8 for Capacitor 8). Only the latest major version is actively maintained.

## Install

```bash
npm install @capgo/capacitor-document-scanner
npx cap sync
```

## Demo

### Scanning one note

| iOS | Android |
|:---:|:-------:|
| ![iOS Demo](videos/ios.gif) | ![Android Demo](videos/android.gif) |

## API

<docgen-index>

* [`scanDocument(...)`](#scandocument)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)
* [Enums](#enums)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### scanDocument(...)

```typescript
scanDocument(options?: ScanDocumentOptions | undefined) => Promise<ScanDocumentResponse>
```

Opens the device camera and starts the document scanning experience.

| Param         | Type                                                                |
| ------------- | ------------------------------------------------------------------- |
| **`options`** | <code><a href="#scandocumentoptions">ScanDocumentOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#scandocumentresponse">ScanDocumentResponse</a>&gt;</code>

--------------------


### Interfaces


#### ScanDocumentResponse

| Prop                | Type                                                                              | Description                                            |
| ------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------ |
| **`scannedImages`** | <code>string[]</code>                                                             | Scanned images in the requested response format.       |
| **`status`**        | <code><a href="#scandocumentresponsestatus">ScanDocumentResponseStatus</a></code> | Indicates whether the scan completed or was cancelled. |

| Method               | Signature                                    | Description                             |
| -------------------- | -------------------------------------------- | --------------------------------------- |
| **getPluginVersion** | () =&gt; Promise&lt;{ version: string; }&gt; | Get the native Capacitor plugin version |


#### ScanDocumentOptions

| Prop                      | Type                                                  | Description                                                                                                                                                                                                                                                                                      | Default                                      |
| ------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------- |
| **`croppedImageQuality`** | <code>number</code>                                   | Android only: quality of the cropped image from 0 - 100 (100 is best).                                                                                                                                                                                                                           | <code>100</code>                             |
| **`letUserAdjustCrop`**   | <code>boolean</code>                                  | Android only: allow the user to adjust the detected crop before saving. Disabling this forces single-document capture.                                                                                                                                                                           | <code>true</code>                            |
| **`maxNumDocuments`**     | <code>number</code>                                   | Maximum number of documents to scan. On Android: limits documents the user can scan (1-24). On iOS: prevents scanning more than the specified number of pages (uses internal API swizzling). Set to 1 for single-scan mode where the scanner stops after one document.                           | <code>24 on Android, unlimited on iOS</code> |
| **`responseType`**        | <code><a href="#responsetype">ResponseType</a></code> | Format to return scanned images in (file paths or base64 strings).                                                                                                                                                                                                                               | <code>ResponseType.ImageFilePath</code>      |
| **`brightness`**          | <code>number</code>                                   | Brightness adjustment applied to scanned images. Range: -255 to 255 (0 = no change, positive = brighter, negative = darker) Useful for compensating low-light scans.                                                                                                                             | <code>0</code>                               |
| **`contrast`**            | <code>number</code>                                   | Contrast adjustment applied to scanned images. Range: 0.0 to 10.0 (1.0 = no change, &gt;1 = more contrast, &lt;1 = less contrast) Helps improve text clarity in poorly lit scans.                                                                                                                | <code>1.0</code>                             |
| **`scannerMode`**         | <code><a href="#scannermode">ScannerMode</a></code>   | Android only: scanner mode that controls ML Kit features and filters. - 'base': Basic scan with crop/rotate, no filters or ML cleaning - 'base_with_filter': Adds grayscale and auto-enhancement filters - 'full': All features including ML-based image cleaning (erases stains, fingers, etc.) | <code>ScannerMode.Full</code>                |


### Type Aliases


#### ResponseType

<code>'basic' | 'cors' | 'default' | 'error' | 'opaque' | 'opaqueredirect'</code>


### Enums


#### ScanDocumentResponseStatus

| Members       | Value                  | Description                       |
| ------------- | ---------------------- | --------------------------------- |
| **`Success`** | <code>'success'</code> | The scan completed successfully.  |
| **`Cancel`**  | <code>'cancel'</code>  | The user cancelled the scan flow. |


#### ResponseType

| Members             | Value                        | Description                                      |
| ------------------- | ---------------------------- | ------------------------------------------------ |
| **`Base64`**        | <code>'base64'</code>        | Return scanned images as base64-encoded strings. |
| **`ImageFilePath`** | <code>'imageFilePath'</code> | Return scanned images as file paths on disk.     |


#### ScannerMode

| Members              | Value                           | Description                                                                                                     |
| -------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **`Base`**           | <code>'base'</code>             | Basic document scanning with crop and rotate features only. No filters or ML-based enhancements.                |
| **`BaseWithFilter`** | <code>'base_with_filter'</code> | Basic features plus automatic filters (grayscale, auto-enhancement).                                            |
| **`Full`**           | <code>'full'</code>             | Full feature set including ML-based image cleaning. Automatically removes stains, fingers, and other artifacts. |

</docgen-api>

## credits

This plugin is a re implementation of the original https://document-scanner.js.org
Thanks for the original work, we recoded it with more modern SDK but explodes the same API
