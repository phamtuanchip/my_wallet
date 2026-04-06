package com.example.nfc_wallet_app

import android.content.SharedPreferences
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.nfc_wallet_app/hce"
    private lateinit var sharedPreferences: SharedPreferences
    private var nfcAdapter: NfcAdapter? = null
    private var cardEmulation: CardEmulation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sharedPreferences = getSharedPreferences("hce_prefs", MODE_PRIVATE)

        // Initialize NFC components
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        cardEmulation = CardEmulation.getInstance(nfcAdapter)

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
}
