package com.example.nfc_wallet_app.nfc;

import android.content.SharedPreferences;
import android.nfc.cardemulation.HostApduService;
import android.os.Bundle;
import android.util.Log;

import java.util.Arrays;

public class CardEmulationService extends HostApduService {
    private static final String TAG = "CardEmulationService";

    // APDU commands
    private static final String SELECT_APDU_HEADER = "00A40400";
    private static final String CARD_AID_1 = "F0010203040506";
    private static final String CARD_AID_2 = "F0010203040507";

    private SharedPreferences sharedPreferences;

    @Override
    public void onCreate() {
        super.onCreate();
        sharedPreferences = getSharedPreferences("hce_prefs", MODE_PRIVATE);
        Log.d(TAG, "CardEmulationService created");
    }

    @Override
    public byte[] processCommandApdu(byte[] commandApdu, Bundle extras) {
        Log.d(TAG, "Received APDU: " + bytesToHex(commandApdu));

        // Check if we're currently emulating a card
        boolean isEmulating = sharedPreferences.getBoolean("is_emulating", false);
        if (!isEmulating) {
            Log.d(TAG, "Not emulating any card, returning error");
            return hexStringToByteArray("6A82"); // File not found
        }

        // Check if this is a SELECT command
        if (commandApdu.length >= 2) {
            String command = bytesToHex(Arrays.copyOf(commandApdu, Math.min(commandApdu.length, 4)));

            if (command.startsWith(SELECT_APDU_HEADER)) {
                // This is a SELECT AID command
                String aid = bytesToHex(commandApdu).substring(10, 26); // Extract AID from APDU
                Log.d(TAG, "SELECT AID: " + aid);

                if (aid.equals(CARD_AID_1) || aid.equals(CARD_AID_2)) {
                    // Valid AID selected, return card data
                    String cardName = sharedPreferences.getString("emulating_card_name", "Unknown Card");
                    String cardUid = sharedPreferences.getString("emulating_card_uid", "");
                    String cardData = sharedPreferences.getString("emulating_card_data", "");

                    Log.d(TAG, "Valid AID selected, returning data for card: " + cardName);

                    // Create response with card information
                    String responseData = cardName + "|" + cardUid + "|" + cardData;
                    String hexResponse = "9000" + stringToHex(responseData);

                    return hexStringToByteArray(hexResponse);
                } else {
                    // Invalid AID
                    Log.d(TAG, "Invalid AID selected");
                    return hexStringToByteArray("6A82"); // File not found
                }
            }
        }

        // For other commands, return success with card info
        String cardName = sharedPreferences.getString("emulating_card_name", "Unknown Card");
        Log.d(TAG, "Unknown command, returning card info for: " + cardName);
        return hexStringToByteArray("9000" + stringToHex(cardName));
    }

    @Override
    public void onDeactivated(int reason) {
        Log.d(TAG, "Card emulation deactivated, reason: " + reason);
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02X", b));
        }
        return sb.toString();
    }

    private byte[] hexStringToByteArray(String s) {
        int len = s.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(s.charAt(i), 16) << 4)
                    + Character.digit(s.charAt(i+1), 16));
        }
        return data;
    }

    private String stringToHex(String str) {
        StringBuilder sb = new StringBuilder();
        for (char c : str.toCharArray()) {
            sb.append(String.format("%02X", (int) c));
        }
        // Truncate if too long for APDU response
        if (sb.length() > 100) {
            sb.setLength(100);
        }
        return sb.toString();
    }
}