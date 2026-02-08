package com.scanlings.camera

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.util.Base64
import androidx.core.content.FileProvider
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File

class ScanlingsCameraPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val REQ_CAPTURE = 42420
    }

    private var lastPhotoFile: File? = null

    override fun getPluginName(): String = "ScanlingsCamera"

    override fun getPluginSignals(): Set<SignalInfo> {
        return setOf(
            SignalInfo("photo_captured_b64", String::class.java),
            SignalInfo("capture_failed", String::class.java),
        )
    }

    @UsedByGodot
    fun capture_photo() {
        val activity: Activity = activity ?: run {
            emitSignal("capture_failed", "no_activity")
            return
        }

        try {
            val file = File(activity.cacheDir, "scanlings_capture.jpg")
            lastPhotoFile = file

            val authority = activity.packageName + ".scanlings.fileprovider"
            val uri: Uri = FileProvider.getUriForFile(activity, authority, file)

            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
            intent.putExtra(MediaStore.EXTRA_OUTPUT, uri)
            intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

            activity.startActivityForResult(intent, REQ_CAPTURE)
        } catch (e: Exception) {
            emitSignal("capture_failed", "launch_failed: ${e.message}")
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_CAPTURE) return false

        if (resultCode != Activity.RESULT_OK) {
            emitSignal("capture_failed", "cancelled")
            return true
        }

        val file = lastPhotoFile
        if (file == null || !file.exists()) {
            emitSignal("capture_failed", "missing_file")
            return true
        }

        return try {
            val bytes = file.readBytes()
            val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
            emitSignal("photo_captured_b64", b64)
            true
        } catch (e: Exception) {
            emitSignal("capture_failed", "read_failed: ${e.message}")
            true
        }
    }
}
