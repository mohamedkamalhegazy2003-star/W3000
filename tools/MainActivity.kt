package com.wpdf.wpdf

import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    // Ask Android for the highest refresh rate the display supports (120 Hz).
    private fun requestHighRefreshRate() {
        try {
            if (Build.VERSION.SDK_INT >= 23) {
                val display = if (Build.VERSION.SDK_INT >= 30) display else windowManager.defaultDisplay
                val current = display?.mode ?: return
                val best = display.supportedModes
                    .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
                    .maxByOrNull { it.refreshRate } ?: return
                val lp = window.attributes
                lp.preferredDisplayModeId = best.modeId
                if (Build.VERSION.SDK_INT >= 30) lp.preferredRefreshRate = best.refreshRate
                window.attributes = lp
            }
        } catch (_: Throwable) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wpdf/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method == "recognize") {
                    val path = call.argument<String>("path") ?: ""
                    val lang = call.argument<String>("lang") ?: "ara+eng"
                    executor.execute {
                        try {
                            val text = recognize(path, lang)
                            mainHandler.post { result.success(text) }
                        } catch (e: Throwable) {
                            mainHandler.post { result.error("OCR_FAILED", e.message, null) }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun ensureTessData(): File {
        val root = File(filesDir, "tess")
        val dir = File(root, "tessdata")
        if (!dir.exists()) dir.mkdirs()
        val loader = FlutterInjector.instance().flutterLoader()
        for (name in listOf("ara.traineddata", "eng.traineddata")) {
            val out = File(dir, name)
            if (out.exists() && out.length() > 0) continue
            val key = loader.getLookupKeyForAsset("assets/tessdata/$name")
            assets.open(key).use { input ->
                FileOutputStream(out).use { output -> input.copyTo(output) }
            }
        }
        return root
    }

    private fun recognize(path: String, lang: String): String {
        val root = ensureTessData()
        val api = TessBaseAPI()
        try {
            if (!api.init(root.absolutePath, lang)) {
                throw IllegalStateException("Tesseract init failed")
            }
            api.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO
            api.setImage(File(path))
            return api.getUTF8Text() ?: ""
        } finally {
            api.recycle()
        }
    }
}
