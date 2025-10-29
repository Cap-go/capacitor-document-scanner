package app.capgo.plugin.documentscanner;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.util.Base64;
import androidx.activity.result.ActivityResult;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.IntentSenderRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Logger;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanner;
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult;
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult.Page;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Bridges Capacitor calls to the ML Kit document scanner.
 */
@CapacitorPlugin(name = "DocumentScanner")
public class DocumentScannerPlugin extends Plugin {

    private final String PLUGIN_VERSION = "7.1.7";

    private static final String RESPONSE_TYPE_BASE64 = "base64";
    private static final String RESPONSE_TYPE_FILE_PATH = "imageFilePath";

    private ActivityResultLauncher<IntentSenderRequest> scannerLauncher;
    private PendingScan pendingScan;

    private static class PendingScan {

        private final String callId;
        private final String responseType;
        private final int quality;

        PendingScan(String callId, String responseType, int quality) {
            this.callId = callId;
            this.responseType = responseType;
            this.quality = quality;
        }
    }

    @Override
    public void load() {
        super.load();
        scannerLauncher = bridge.registerForActivityResult(
            new ActivityResultContracts.StartIntentSenderForResult(),
            this::handleScanResult
        );
    }

    @PluginMethod
    public void scanDocument(PluginCall call) {
        if (scannerLauncher == null) {
            call.reject("Document scanner is not ready.");
            return;
        }

        if (pendingScan != null) {
            call.reject("Another scan is in progress.");
            return;
        }

        Activity activity = getActivity();
        if (activity == null) {
            call.reject("Activity reference is unavailable.");
            return;
        }

        int quality = clamp(call.getInt("croppedImageQuality", 100), 0, 100);
        String responseType = normalizeResponseType(call.getString("responseType"));
        int pageLimit = clamp(call.getInt("maxNumDocuments", 24), 1, 24);
        boolean allowAdjustCrop = call.getBoolean("letUserAdjustCrop", true);

        GmsDocumentScannerOptions.Builder optionsBuilder = new GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setPageLimit(pageLimit);

        optionsBuilder.setScannerMode(
            allowAdjustCrop ? GmsDocumentScannerOptions.SCANNER_MODE_FULL : GmsDocumentScannerOptions.SCANNER_MODE_BASE
        );

        GmsDocumentScanner scanner = GmsDocumentScanning.getClient(optionsBuilder.build());

        bridge.saveCall(call);
        pendingScan = new PendingScan(call.getCallbackId(), responseType, quality);

        scanner
            .getStartScanIntent(activity)
            .addOnSuccessListener((intentSender) -> {
                IntentSenderRequest request = new IntentSenderRequest.Builder(intentSender).build();
                scannerLauncher.launch(request);
            })
            .addOnFailureListener((e) -> {
                Logger.error("DocumentScanner", "Failed to start scanner", e);
                PluginCall savedCall = getPendingCall();
                if (savedCall != null) {
                    savedCall.reject("Unable to start document scanner: " + e.getLocalizedMessage(), e);
                    releasePendingCall(savedCall);
                } else {
                    bridge.releaseCall(call);
                    pendingScan = null;
                    call.reject("Unable to start document scanner: " + e.getLocalizedMessage(), e);
                }
            });
    }

    private void handleScanResult(ActivityResult result) {
        PluginCall call = getPendingCall();
        if (call == null) {
            return;
        }

        if (result.getResultCode() != Activity.RESULT_OK) {
            JSObject response = new JSObject();
            response.put("status", "cancel");
            call.resolve(response);
            releasePendingCall(call);
            return;
        }

        Intent data = result.getData();
        if (data == null) {
            call.reject("Document scanner returned no data.");
            releasePendingCall(call);
            return;
        }

        GmsDocumentScanningResult scanningResult = GmsDocumentScanningResult.fromActivityResultIntent(data);
        if (scanningResult == null) {
            call.reject("Unable to parse document scan result.");
            releasePendingCall(call);
            return;
        }

        try {
            List<String> scannedImages = processScanResult(scanningResult);
            JSObject response = new JSObject();
            response.put("status", "success");
            response.put("scannedImages", new JSArray(scannedImages));
            call.resolve(response);
        } catch (IOException ioException) {
            call.reject("Failed to process scanned images: " + ioException.getLocalizedMessage(), ioException);
        } finally {
            releasePendingCall(call);
        }
    }

    private List<String> processScanResult(GmsDocumentScanningResult scanningResult) throws IOException {
        List<String> results = new ArrayList<>();
        List<Page> pages = scanningResult.getPages();
        if (pages == null || pages.isEmpty()) {
            return results;
        }

        for (int index = 0; index < pages.size(); index++) {
            String processed = handlePage(pages.get(index), index);
            if (processed != null) {
                results.add(processed);
            }
        }
        return results;
    }

    private String handlePage(Page page, int pageIndex) throws IOException {
        PendingScan scan = pendingScan;
        if (scan == null) {
            throw new IOException("No active scan.");
        }

        Uri imageUri = page.getImageUri();
        if (imageUri == null) {
            throw new IOException("Missing image URI for scanned page.");
        }

        byte[] imageBytes = readBytesFromUri(imageUri);
        if (scan.quality < 100) {
            imageBytes = reencodeImage(imageBytes, scan.quality);
        }

        if (RESPONSE_TYPE_BASE64.equals(scan.responseType)) {
            return Base64.encodeToString(imageBytes, Base64.NO_WRAP);
        }

        return writeImageFile(imageBytes, pageIndex);
    }

    private byte[] readBytesFromUri(Uri uri) throws IOException {
        Context context = getContext();
        if (context == null) {
            throw new IOException("Context unavailable for reading image.");
        }

        try (InputStream inputStream = context.getContentResolver().openInputStream(uri)) {
            if (inputStream == null) {
                throw new IOException("Unable to open image stream.");
            }
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] data = new byte[8192];
            int nRead;
            while ((nRead = inputStream.read(data, 0, data.length)) != -1) {
                buffer.write(data, 0, nRead);
            }
            return buffer.toByteArray();
        }
    }

    private byte[] reencodeImage(byte[] source, int quality) throws IOException {
        Bitmap bitmap = BitmapFactory.decodeByteArray(source, 0, source.length);
        if (bitmap == null) {
            throw new IOException("Unable to decode scanned image.");
        }
        try (ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)) {
                throw new IOException("Unable to compress scanned image.");
            }
            return outputStream.toByteArray();
        } finally {
            bitmap.recycle();
        }
    }

    private String writeImageFile(byte[] imageBytes, int pageIndex) throws IOException {
        Context context = getContext();
        if (context == null) {
            throw new IOException("Context unavailable for writing image.");
        }

        File directory = new File(context.getCacheDir(), "document_scanner");
        if (!directory.exists() && !directory.mkdirs()) {
            throw new IOException("Unable to create cache directory.");
        }

        String fileName = String.format(Locale.US, "DOCUMENT_SCAN_%d_%d.jpg", pageIndex, System.currentTimeMillis());
        File outputFile = new File(directory, fileName);
        try (FileOutputStream outputStream = new FileOutputStream(outputFile)) {
            outputStream.write(imageBytes);
        }

        return outputFile.getAbsolutePath();
    }

    private PluginCall getPendingCall() {
        if (pendingScan == null) {
            return null;
        }
        return bridge.getSavedCall(pendingScan.callId);
    }

    private void releasePendingCall(PluginCall call) {
        if (pendingScan != null) {
            bridge.releaseCall(call);
            pendingScan = null;
        }
    }

    private int clamp(Integer value, int min, int max) {
        if (value == null) {
            return max;
        }
        return Math.max(min, Math.min(max, value));
    }

    private String normalizeResponseType(String value) {
        if (value == null) {
            return RESPONSE_TYPE_FILE_PATH;
        }
        String normalized = value.toLowerCase(Locale.ROOT);
        if (RESPONSE_TYPE_BASE64.equals(normalized) || RESPONSE_TYPE_FILE_PATH.equals(normalized)) {
            return normalized;
        }
        return RESPONSE_TYPE_FILE_PATH;
    }

    @PluginMethod
    public void getPluginVersion(final PluginCall call) {
        try {
            final JSObject ret = new JSObject();
            ret.put("version", this.PLUGIN_VERSION);
            call.resolve(ret);
        } catch (final Exception e) {
            call.reject("Could not get plugin version", e);
        }
    }
}
