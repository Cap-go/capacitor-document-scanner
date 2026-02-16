package app.capgo.plugin.documentscanner;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.net.Uri;
import android.os.Build;
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
import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.GoogleApiAvailability;
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

    private final String pluginVersion = "7.1.7";

    private static final String RESPONSE_TYPE_BASE64 = "base64";
    private static final String RESPONSE_TYPE_FILE_PATH = "imageFilePath";

    private static final String SCANNER_MODE_BASE = "base";
    private static final String SCANNER_MODE_BASE_WITH_FILTER = "base_with_filter";
    private static final String SCANNER_MODE_FULL = "full";

    private ActivityResultLauncher<IntentSenderRequest> scannerLauncher;
    private PendingScan pendingScan;

    private static class PendingScan {

        private final String callId;
        private final String responseType;
        private final int quality;
        private final float brightness;
        private final float contrast;

        PendingScan(String callId, String responseType, int quality, float brightness, float contrast) {
            this.callId = callId;
            this.responseType = responseType;
            this.quality = quality;
            this.brightness = brightness;
            this.contrast = contrast;
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

        // Check if running on emulator first (doesn't require activity reference)
        if (isRunningOnEmulator()) {
            call.reject(
                "Document scanner is not supported on Android emulators. " +
                    "The ML Kit Document Scanner requires a physical device with a hardware camera. " +
                    "Please test on a real Android device."
            );
            return;
        }

        Activity activity = getActivity();
        if (activity == null) {
            call.reject("Activity reference is unavailable.");
            return;
        }

        // Check Google Play Services availability
        GoogleApiAvailability apiAvailability = GoogleApiAvailability.getInstance();
        int resultCode = apiAvailability.isGooglePlayServicesAvailable(activity);
        if (resultCode != ConnectionResult.SUCCESS) {
            StringBuilder errorMessage = new StringBuilder(
                "The ML Kit Document Scanner requires Google Play Services, which is not available or needs an update. "
            );
            if (apiAvailability.isUserResolvableError(resultCode)) {
                errorMessage.append("Please update Google Play Services and try again.");
            } else {
                errorMessage.append("This device may not support the document scanner.");
            }
            call.reject(errorMessage.toString());
            return;
        }

        int quality = clamp(call.getInt("croppedImageQuality", 100), 0, 100);
        String responseType = normalizeResponseType(call.getString("responseType"));
        int pageLimit = clamp(call.getInt("maxNumDocuments", 24), 1, 24);
        float brightness = clampFloat(call.getFloat("brightness", 0f), -255f, 255f);
        float contrast = clampFloat(call.getFloat("contrast", 1f), 0f, 10f);
        String scannerMode = normalizeScannerMode(call.getString("scannerMode"));
        // Only default letUserAdjustCrop to true if scannerMode is FULL
        // This ensures scannerMode takes precedence when explicitly set
        boolean defaultAllowCrop = SCANNER_MODE_FULL.equals(scannerMode);
        boolean allowAdjustCrop = call.getBoolean("letUserAdjustCrop", defaultAllowCrop);

        GmsDocumentScannerOptions.Builder optionsBuilder = new GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setPageLimit(pageLimit);

        // Determine scanner mode based on scannerMode parameter and letUserAdjustCrop
        int mlKitScannerMode = determineScannerMode(scannerMode, allowAdjustCrop);
        optionsBuilder.setScannerMode(mlKitScannerMode);

        GmsDocumentScanner scanner = GmsDocumentScanning.getClient(optionsBuilder.build());

        bridge.saveCall(call);
        pendingScan = new PendingScan(call.getCallbackId(), responseType, quality, brightness, contrast);

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

        // Apply brightness/contrast adjustments if needed
        boolean needsAdjustment = scan.brightness != 0f || scan.contrast != 1f;
        if (needsAdjustment || scan.quality < 100) {
            imageBytes = processImage(imageBytes, scan.quality, scan.brightness, scan.contrast);
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

    private byte[] processImage(byte[] source, int quality, float brightness, float contrast) throws IOException {
        Bitmap bitmap = BitmapFactory.decodeByteArray(source, 0, source.length);
        if (bitmap == null) {
            throw new IOException("Unable to decode scanned image.");
        }

        try {
            // Apply brightness and contrast adjustments if needed
            if (brightness != 0f || contrast != 1f) {
                bitmap = applyBrightnessContrast(bitmap, brightness, contrast);
            }

            // Compress with quality setting
            try (ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)) {
                    throw new IOException("Unable to compress scanned image.");
                }
                return outputStream.toByteArray();
            }
        } finally {
            bitmap.recycle();
        }
    }

    /**
     * Applies brightness and contrast adjustments to a bitmap using ColorMatrix.
     * @param bitmap The source bitmap
     * @param brightness Brightness adjustment (-255 to 255, 0 = no change)
     * @param contrast Contrast adjustment (0.0 to 10.0, 1.0 = no change)
     * @return A new bitmap with adjustments applied
     */
    private Bitmap applyBrightnessContrast(Bitmap bitmap, float brightness, float contrast) {
        // Create ColorMatrix for brightness and contrast
        ColorMatrix colorMatrix = new ColorMatrix(
            new float[] { contrast, 0, 0, 0, brightness, 0, contrast, 0, 0, brightness, 0, 0, contrast, 0, brightness, 0, 0, 0, 1, 0 }
        );

        // Create a new bitmap with the same dimensions
        Bitmap adjustedBitmap = Bitmap.createBitmap(bitmap.getWidth(), bitmap.getHeight(), bitmap.getConfig());

        // Apply the color matrix
        Canvas canvas = new Canvas(adjustedBitmap);
        Paint paint = new Paint();
        paint.setColorFilter(new ColorMatrixColorFilter(colorMatrix));
        canvas.drawBitmap(bitmap, 0, 0, paint);

        return adjustedBitmap;
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

    private float clampFloat(Float value, float min, float max) {
        if (value == null) {
            return min;
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

    private String normalizeScannerMode(String value) {
        if (value == null) {
            return SCANNER_MODE_FULL;
        }
        String normalized = value.toLowerCase(Locale.ROOT);
        if (
            SCANNER_MODE_BASE.equals(normalized) || SCANNER_MODE_BASE_WITH_FILTER.equals(normalized) || SCANNER_MODE_FULL.equals(normalized)
        ) {
            return normalized;
        }
        return SCANNER_MODE_FULL;
    }

    /**
     * Determines the ML Kit scanner mode based on scannerMode and letUserAdjustCrop settings.
     * Note: letUserAdjustCrop requires SCANNER_MODE_FULL, so it takes precedence over scannerMode.
     * @param scannerMode The requested scanner mode (base, base_with_filter, full)
     * @param allowAdjustCrop Whether to allow manual crop adjustment
     * @return The ML Kit scanner mode constant
     */
    private int determineScannerMode(String scannerMode, boolean allowAdjustCrop) {
        // If letUserAdjustCrop is true, we must use SCANNER_MODE_FULL
        // because only FULL mode supports manual crop adjustment
        if (allowAdjustCrop) {
            return GmsDocumentScannerOptions.SCANNER_MODE_FULL;
        }

        // Otherwise, use the requested scanner mode
        switch (scannerMode) {
            case SCANNER_MODE_BASE:
                return GmsDocumentScannerOptions.SCANNER_MODE_BASE;
            case SCANNER_MODE_BASE_WITH_FILTER:
                return GmsDocumentScannerOptions.SCANNER_MODE_BASE_WITH_FILTER;
            case SCANNER_MODE_FULL:
            default:
                return GmsDocumentScannerOptions.SCANNER_MODE_FULL;
        }
    }

    /**
     * Detects if the app is running on an Android emulator.
     * Uses multiple heuristics to reliably detect emulator environments.
     * @return true if running on an emulator, false otherwise
     */
    private boolean isRunningOnEmulator() {
        String model = Build.MODEL.toLowerCase(Locale.ROOT);
        String product = Build.PRODUCT.toLowerCase(Locale.ROOT);
        String fingerprint = Build.FINGERPRINT.toLowerCase(Locale.ROOT);
        String manufacturer = Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        String brand = Build.BRAND.toLowerCase(Locale.ROOT);
        String device = Build.DEVICE.toLowerCase(Locale.ROOT);
        String hardware = Build.HARDWARE.toLowerCase(Locale.ROOT);
        String board = Build.BOARD.toLowerCase(Locale.ROOT);

        // Check for emulator characteristics
        boolean isEmulator = (fingerprint.startsWith("generic") ||
            fingerprint.startsWith("unknown") ||
            fingerprint.contains("test-keys") ||
            model.contains("google_sdk") ||
            model.contains("emulator") ||
            model.contains("android sdk built for x86") ||
            model.contains("sdk_gphone") ||
            manufacturer.contains("genymotion") ||
            (brand.startsWith("generic") && device.startsWith("generic")) ||
            "google_sdk".equals(product) ||
            product.contains("sdk_gphone") ||
            product.contains("sdk_google") ||
            product.contains("emulator") ||
            product.contains("vbox") ||
            hardware.contains("ranchu") ||
            hardware.contains("goldfish") ||
            board.contains("ranchu") ||
            board.contains("goldfish") ||
            board.contains("qemu"));

        // Additional check: Build.SERIAL property for common emulator identifiers
        // Emulators often have "emulator" in their serial number
        // Note: We don't check for "unknown" as some real devices (e.g., OnePlus PJX110)
        // have "unknown" as their serial for privacy/security reasons
        if (!isEmulator) {
            try {
                String serial = Build.SERIAL;
                if (serial != null) {
                    serial = serial.toLowerCase(Locale.ROOT);
                    isEmulator = serial.contains("emulator");
                }
            } catch (SecurityException e) {
                // Ignore if Build.SERIAL access is restricted (Android 8.0+)
            }
        }

        return isEmulator;
    }

    @PluginMethod
    public void getPluginVersion(final PluginCall call) {
        try {
            final JSObject ret = new JSObject();
            ret.put("version", this.pluginVersion);
            call.resolve(ret);
        } catch (final Exception e) {
            call.reject("Could not get plugin version", e);
        }
    }
}
