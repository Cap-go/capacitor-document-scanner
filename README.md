# @capgo/capacitor-document-scanner
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin_document_scanner"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin_document_scanner"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>
Capacitor plugin to scan document iOS and Android

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/document-scanner/

## Install

```bash
npm install @capgo/capacitor-document-scanner
npx cap sync
```

## API

<docgen-index>

* [`scanDocument(...)`](#scandocument)
* [Interfaces](#interfaces)
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

| Prop                      | Type                                                  | Description                                                                                                            | Default                                 |
| ------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| **`croppedImageQuality`** | <code>number</code>                                   | Android only: quality of the cropped image from 0 - 100 (100 is best).                                                 | <code>100</code>                        |
| **`letUserAdjustCrop`**   | <code>boolean</code>                                  | Android only: allow the user to adjust the detected crop before saving. Disabling this forces single-document capture. | <code>true</code>                       |
| **`maxNumDocuments`**     | <code>number</code>                                   | Android only: maximum number of documents the user can scan.                                                           | <code>24</code>                         |
| **`responseType`**        | <code><a href="#responsetype">ResponseType</a></code> | Format to return scanned images in (file paths or base64 strings).                                                     | <code>ResponseType.ImageFilePath</code> |


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

</docgen-api>

## credits

This plugin is a re implementation of the original https://document-scanner.js.org
Thanks for the original work, we recoded it with more modern SDK but explose the same API
