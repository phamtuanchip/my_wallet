package com.example.my_wallet.nfc

import android.content.SharedPreferences
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

/**
 * HCE (Host Card Emulation) service that handles APDU command/response flow.
 * Card data is read from SharedPreferences set by MainActivity.
 */
class CardEmulationService : HostApduService() {

    companion object {
        private const val TAG = "CardEmulationService"

        // SELECT AID command prefix
        private val SELECT_APDU_HEADER = byteArrayOf(
            0x00.toByte(), // CLA
            0xA4.toByte(), // INS: SELECT
            0x04.toByte(), // P1: select by AID
            0x00.toByte()  // P2
        )

        // Our custom AID (must match hce_apdu_service.xml)
        private val CARD_AID = hexStringToByteArray("F0010203040506")

        // Response codes
        private val SW_OK = byteArrayOf(0x90.toByte(), 0x00.toByte())
        private val SW_UNKNOWN_CMD = byteArrayOf(0x6D.toByte(), 0x00.toByte())
        private val SW_FILE_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())

        // Custom INS byte for GET DATA
        private const val INS_GET_DATA = 0xCA.toByte()

        fun hexStringToByteArray(hex: String): ByteArray {
            val len = hex.length
            val data = ByteArray(len / 2)
            var i = 0
            while (i < len) {
                data[i / 2] = ((Character.digit(hex[i], 16) shl 4) +
                        Character.digit(hex[i + 1], 16)).toByte()
                i += 2
            }
            return data
        }
    }

    private lateinit var sharedPreferences: SharedPreferences
    private var isSelected = false

    override fun onCreate() {
        super.onCreate()
        sharedPreferences = getSharedPreferences("hce_prefs", MODE_PRIVATE)
        Log.d(TAG, "CardEmulationService created")
    }

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        Log.d(TAG, "Received APDU: ${commandApdu.toHexString()}")

        // Check if emulation is active
        if (!sharedPreferences.getBoolean("is_emulating", false)) {
            Log.d(TAG, "Not emulating — ignoring APDU")
            return SW_FILE_NOT_FOUND
        }

        // Handle SELECT AID command
        if (commandApdu.size >= SELECT_APDU_HEADER.size + 1) {
            val isSelectHeader = commandApdu.take(SELECT_APDU_HEADER.size)
                .toByteArray()
                .contentEquals(SELECT_APDU_HEADER)

            if (isSelectHeader) {
                val aidLength = commandApdu[SELECT_APDU_HEADER.size].toInt() and 0xFF
                if (commandApdu.size >= SELECT_APDU_HEADER.size + 1 + aidLength) {
                    val receivedAid = commandApdu.copyOfRange(
                        SELECT_APDU_HEADER.size + 1,
                        SELECT_APDU_HEADER.size + 1 + aidLength
                    )
                    if (receivedAid.contentEquals(CARD_AID)) {
                        isSelected = true
                        Log.d(TAG, "AID selected successfully")
                        return SW_OK
                    }
                }
                return SW_FILE_NOT_FOUND
            }
        }

        // Handle GET DATA command after card is selected
        if (isSelected && commandApdu.size >= 2 && commandApdu[1] == INS_GET_DATA) {
            return buildCardDataResponse()
        }

        Log.w(TAG, "Unknown APDU command: ${commandApdu.toHexString()}")
        return SW_UNKNOWN_CMD
    }

    override fun onDeactivated(reason: Int) {
        isSelected = false
        val reasonStr = when (reason) {
            DEACTIVATION_LINK_LOSS -> "LINK_LOSS"
            DEACTIVATION_DESELECTED -> "DESELECTED"
            else -> "UNKNOWN($reason)"
        }
        Log.d(TAG, "Card deactivated: $reasonStr")
    }

    /**
     * Builds a response APDU containing the emulated card's UID as payload,
     * followed by SW_OK (90 00).
     */
    private fun buildCardDataResponse(): ByteArray {
        val cardUid = sharedPreferences.getString("emulating_card_uid", "") ?: ""
        val cardName = sharedPreferences.getString("emulating_card_name", "") ?: ""

        // Payload: card name length (1 byte) + card name bytes + uid bytes
        val nameBytes = cardName.toByteArray(Charsets.UTF_8)
        val uidBytes = cardUid.toByteArray(Charsets.UTF_8)

        val payload = ByteArray(1 + nameBytes.size + uidBytes.size)
        payload[0] = nameBytes.size.toByte()
        nameBytes.copyInto(payload, 1)
        uidBytes.copyInto(payload, 1 + nameBytes.size)

        Log.d(TAG, "Responding with card data for: $cardName")
        return payload + SW_OK
    }

    private fun ByteArray.toHexString(): String =
        joinToString("") { "%02X".format(it) }
}
