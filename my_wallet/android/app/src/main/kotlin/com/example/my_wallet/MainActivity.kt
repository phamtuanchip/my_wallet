package com.example.my_wallet

import android.Manifest
import android.content.ContentValues
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: required by local_auth (BiometricPrompt).
class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.my_wallet/hce"
    private lateinit var sharedPreferences: SharedPreferences
    private var nfcAdapter: NfcAdapter? = null
    private var cardEmulation: CardEmulation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Exports (PDF / JPEG of documents) into the public Download/MyWallet folder.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.phamtuanchip.mywallet/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") return@setMethodCallHandler result.notImplemented()
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime")
                val bytes = call.argument<ByteArray>("bytes")
                if (name == null || mime == null || bytes == null) {
                    return@setMethodCallHandler result.error("INVALID_ARGUMENTS", "name, mime and bytes are required", null)
                }
                try {
                    result.success(saveToDownloads(name, mime, bytes))
                } catch (e: SecurityException) {
                    result.error("PERMISSION", e.message, null)
                } catch (e: Exception) {
                    result.error("WRITE_FAILED", e.message, null)
                }
            }

        sharedPreferences = getSharedPreferences("hce_prefs", MODE_PRIVATE)

        // Initialize NFC components
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        // NfcAdapter is null on devices without NFC (and on emulators); getInstance(null) throws.
        cardEmulation = nfcAdapter?.let { CardEmulation.getInstance(it) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCardEmulation" -> {
                    val cardId = call.argument<String>("cardId")
                    val cardName = call.argument<String>("cardName")
                    val cardUid = call.argument<String>("cardUid")
                    val cardData = call.argument<String>("cardData")

                    if (cardId != null && cardName != null) {
                        startCardEmulation(cardId, cardName, cardUid ?: "", cardData ?: "")
                        result.success("HCE started for card: $cardName")
                    } else {
                        result.error("INVALID_ARGUMENTS", "Card ID and name are required", null)
                    }
                }
                "stopCardEmulation" -> {
                    stopCardEmulation()
                    result.success("HCE stopped")
                }
                "isHceSupported" -> {
                    val supported = nfcAdapter?.isEnabled == true && cardEmulation?.isDefaultServiceForCategory(
                        componentName,
                        CardEmulation.CATEGORY_OTHER
                    ) == true
                    result.success(supported)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startCardEmulation(cardId: String, cardName: String, cardUid: String, cardData: String) {
        try {
            // Store card information in shared preferences for the HCE service to access
            with(sharedPreferences.edit()) {
                putString("emulating_card_id", cardId)
                putString("emulating_card_name", cardName)
                putString("emulating_card_uid", cardUid)
                putString("emulating_card_data", cardData)
                putBoolean("is_emulating", true)
                apply()
            }

            Log.d("MainActivity", "Started HCE for card: $cardName")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error starting HCE: ${e.message}")
        }
    }

    private fun stopCardEmulation() {
        try {
            // Clear card information from shared preferences
            with(sharedPreferences.edit()) {
                remove("emulating_card_id")
                remove("emulating_card_name")
                remove("emulating_card_uid")
                remove("emulating_card_data")
                putBoolean("is_emulating", false)
                apply()
            }

            Log.d("MainActivity", "Stopped HCE")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error stopping HCE: ${e.message}")
        }
    }

    /** Returns the user-visible location, e.g. "Download/MyWallet/x.pdf". */
    private fun saveToDownloads(name: String, mime: String, bytes: ByteArray): String {
        val folder = "MyWallet"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Scoped storage: MediaStore, no permission needed. Android renames on a name clash.
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$folder")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert failed")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Cannot open output stream")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            return "${Environment.DIRECTORY_DOWNLOADS}/$folder/$name"
        }
        // Android 7–9: plain file + media scan; needs WRITE_EXTERNAL_STORAGE (asked by Dart).
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("WRITE_EXTERNAL_STORAGE not granted")
        }
        @Suppress("DEPRECATION")
        val dir = java.io.File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), folder)
        dir.mkdirs()
        var file = java.io.File(dir, name)
        var n = 1
        while (file.exists()) {
            file = java.io.File(dir, name.substringBeforeLast('.') + " ($n)." + name.substringAfterLast('.'))
            n++
        }
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime), null)
        return "${Environment.DIRECTORY_DOWNLOADS}/$folder/${file.name}"
    }
}
