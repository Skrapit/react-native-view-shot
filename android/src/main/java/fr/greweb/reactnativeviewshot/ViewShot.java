package fr.greweb.reactnativeviewshot;

import javax.annotation.Nullable;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.net.Uri;
import android.util.Base64;
import android.view.View;
import android.webkit.WebView;
import android.widget.ScrollView;
import android.view.View.MeasureSpec;

import com.facebook.react.bridge.Promise;
import com.facebook.react.uimanager.NativeViewHierarchyManager;
import com.facebook.react.uimanager.UIBlock;
import com.facebook.react.views.view.ReactViewGroup;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;


/**
 * Snapshot utility class allow to screenshot a view.
 */
public class ViewShot implements UIBlock {

    static final String ERROR_UNABLE_TO_SNAPSHOT = "E_UNABLE_TO_SNAPSHOT";

    private int tag;
    private String extension;
    private Bitmap.CompressFormat format;
    private double quality;
    private Integer width;
    private Integer height;
    private File output;
    private String result;
    private Promise promise;
    private Boolean snapshotContentContainer;
    private Boolean fullWebView;
    private Integer areaX;
    private Integer areaY;
    private Integer areaWidth;
    private Integer areaHeight;

    public ViewShot(
            int tag,
            String extension,
            Bitmap.CompressFormat format,
            double quality,
            @Nullable Integer width,
            @Nullable Integer height,
            File output,
            String result,
            Boolean snapshotContentContainer,
            Boolean fullWebView,
            @Nullable Integer areaX,
            @Nullable Integer areaY,
            @Nullable Integer areaWidth,
            @Nullable Integer areaHeight,
            Promise promise) {
        this.tag = tag;
        this.extension = extension;
        this.format = format;
        this.quality = quality;
        this.width = width;
        this.height = height;
        this.output = output;
        this.result = result;
        this.snapshotContentContainer = snapshotContentContainer;
        this.fullWebView = fullWebView;
        this.areaX = areaX;
        this.areaY = areaY;
        this.areaWidth = areaWidth;
        this.areaHeight = areaHeight;
        this.promise = promise;
    }

    @Override
    public void execute(NativeViewHierarchyManager nativeViewHierarchyManager) {
        OutputStream os = null;
        View view = nativeViewHierarchyManager.resolveView(tag);
        if (view == null) {
            promise.reject(ERROR_UNABLE_TO_SNAPSHOT, "No view found with reactTag: "+tag);
            return;
        }
        try {
            if ("file".equals(result)) {
                os = new FileOutputStream(output);
                captureView(view, os);
                String uri = Uri.fromFile(output).toString();
                promise.resolve(uri);
            }
            else if ("base64".equals(result)) {
                os = new ByteArrayOutputStream();
                captureView(view, os);
                byte[] bytes = ((ByteArrayOutputStream) os).toByteArray();
                String data = Base64.encodeToString(bytes, Base64.NO_WRAP);
                promise.resolve(data);
            }
            else if ("data-uri".equals(result)) {
                os = new ByteArrayOutputStream();
                captureView(view, os);
                byte[] bytes = ((ByteArrayOutputStream) os).toByteArray();
                String data = Base64.encodeToString(bytes, Base64.NO_WRAP);
                data = "data:image/"+extension+";base64," + data;
                promise.resolve(data);
            }
            else {
                promise.reject(ERROR_UNABLE_TO_SNAPSHOT, "Unsupported result: "+result+". Try one of: file | base64 | data-uri");
            }
        }
        catch (Exception e) {
            e.printStackTrace();
            promise.reject(ERROR_UNABLE_TO_SNAPSHOT, "Failed to capture view snapshot");
        }
        finally {
            if (os != null) {
                try {
                    os.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
        }
    }

    /**
     * Screenshot a view and return the captured bitmap.
     * @param view the view to capture
     * @return the screenshot or null if it failed.
     */
    private void captureView (View view, OutputStream os) {
        int w = view.getWidth();
        int h = view.getHeight();

        if (w <= 0 || h <= 0) {
            throw new RuntimeException("Impossible to snapshot the view: view is invalid");
        }

        if (areaX == null || areaX < 0) {
            areaX = 0;
        }
        if (areaY == null || areaY < 0) {
            areaY = 0;
        }
        if (areaWidth == null || areaWidth < 0.1) {
            areaWidth = w;
        }
        if (areaHeight == null || areaHeight < 0.1) {
            areaHeight = 0;
        }
        Bitmap bitmap = null;
        if (fullWebView){
            // Snapshot full content of webview
            ReactViewGroup viewGroup = (ReactViewGroup)view;
            if (viewGroup.getChildCount() > 0 && (viewGroup.getChildAt(0) instanceof WebView)) {
                WebView webView = (WebView)viewGroup.getChildAt(0);
                webView.measure(MeasureSpec.makeMeasureSpec(
                        View.MeasureSpec.UNSPECIFIED, MeasureSpec.UNSPECIFIED),
                        MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED));
                webView.layout(0, 0, webView.getMeasuredWidth(), webView.getMeasuredHeight());
                webView.setDrawingCacheEnabled(true);
                webView.buildDrawingCache();
                bitmap = Bitmap.createBitmap(webView.getMeasuredWidth(),
                        webView.getMeasuredHeight(), Bitmap.Config.ARGB_8888);

                Canvas canvas = new Canvas(bitmap);
                Paint paint = new Paint();
                int iHeight = bitmap.getHeight();
                canvas.drawBitmap(bitmap, 0, iHeight, paint);
                webView.draw(canvas);
                webView.setDrawingCacheEnabled(false);
            }
        } else {
            if (snapshotContentContainer) {
                //evaluate real height
                h = 0;
                ScrollView scrollView = (ScrollView) view;
                for (int i = 0; i < scrollView.getChildCount(); i++) {
                    h += scrollView.getChildAt(i).getHeight();
                }
            }

            bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas c = new Canvas(bitmap);
            view.draw(c);
        }

        if (areaHeight > 0 && bitmap.getWidth() >= areaX && bitmap.getHeight() >= areaHeight) {
            bitmap = Bitmap.createBitmap(bitmap, areaX, areaY, areaWidth, areaHeight);
        }
        if (width != null && height != null && (width != w || height != h)) {
            bitmap = Bitmap.createScaledBitmap(bitmap, width, height, true);
        }
        if (bitmap == null) {
            throw new RuntimeException("Impossible to snapshot the view");
        }
        bitmap.compress(format, (int)(100.0 * quality), os);
    }
}
