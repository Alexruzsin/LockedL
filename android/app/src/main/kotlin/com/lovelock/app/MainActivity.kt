package com.lovelock.app

import android.app.WallpaperManager
import android.graphics.BitmapFactory
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.lovelock/wallpaper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setLockWallpaper") {
                val bytes = call.argument<ByteArray>("imageBytes")
                if (bytes != null) {
                    try {
                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        val wallpaperManager = WallpaperManager.getInstance(applicationContext)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            // Közvetlenül a zárolt képernyő (FLAG_LOCK) hátterét cseréli le!
                            wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                        } else {
                            wallpaperManager.setBitmap(bitmap)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WALLPAPER_ERR", e.localizedMessage, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Hiányzó képadat", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
