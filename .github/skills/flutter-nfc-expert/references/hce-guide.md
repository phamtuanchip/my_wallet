# Android HCE (Host Card Emulation) Implementation Guide

Host Card Emulation allows your Android phone to act as a contactless smart card without using a dedicated secure element. Readers detect your device as if it were a standard credit card or access badge.

## HCE Architecture

### Components

```
┌─────────────────────────┐
│  NFC Reader Terminal    │
└──────────┬──────────────┘
           │ APDU Commands/Responses
           │
┌──────────▼──────────────┐
│  Android NFC Hardware   │ (Peer-to-peer mode)
│  (Reader/Writer)        │
└──────────┬──────────────┘
           │ Intent broadcast
┌──────────▼──────────────────────────┐
│  HOST_APDU_SERVICE Intent Filter   │
│  (Your custom service)              │
│  android.nfc.cardemulation.action   │
└──────────┬──────────────────────────┘
           │
┌──────────▼──────────────┐
│  Your App Logic         │
│  (Process commands)     │
└─────────────────────────┘
```

### APDU (Application Protocol Data Unit)

APDU is the ISO/IEC 7816-4 command/response protocol for smart cards.

**Command APDU (C-APDU):**
```
[CLA] [INS] [P1] [P2] [Lc] [Data] [Le]
Each byte represents:
  CLA: Class of instruction (0x00 = standard)
  INS: Instruction code (0xA4 = SELECT, 0xB0 = READ, etc.)
  P1, P2: Parameters (context-specific)
  Lc: Command data length
  Data: Command payload (variable)
  Le: Expected response length (0x00 or 0xFF for all)
```

**Response APDU (R-APDU):**
```
[Data] [SW1] [SW2]
  Data: Response payload (variable, can be empty)
  SW1, SW2: Status word (result code)
    0x61 XX: More data available (XX bytes)
    0x90 00: Success
    0x61 FE: More data, last chunk (max 254 bytes)
    0x6D 00: Instruction not supported
    0x6E 00: Class not supported
    0x69 85: Conditions not satisfied
    0x6A 82: File not found
```

## Common HCE Workflow

### 1. SELECT Command (Card Activation)

Reader initiates contact by selecting an AID (Application Identifier):

```
Command:  00 A4 04 00 07 F222222222222222
                        └─ Your app's AID (8 bytes max)

Response: 90 00
         Success, application selected
         
or

Response: 6A 82  (File not found - AID not recognized)
```

**AID Format:**
- RID (Registered Application Provider Identifier): 5 bytes
  - First byte typically 0xF2 (testing/proprietary)
- PIX (Proprietary Application Identifier eXtension): 0-3 bytes
  - Your company/app specific identifier

**Example AIDs:**
```
Card emulation app: F2 22 22 22 22 22 22 (7 bytes)
Payment app: A0 00 00 00 04 10 10 (Visa)
Loyalty: F2 11 11 11 11 11 11
```

### 2. Transaction Data (Business Logic)

After SELECT, reader sends commands specific to your app:

```
Command: [CLA] [INS] [P1] [P2] [Len] [Data]
Example: 00 B1 00 00 04 AA BB CC DD

Response: [Response Data] [Status]
Example: 12 34 56 78 90 00
        ┌─ 4 bytes of response data
        └─ Success status
```

### 3. Response Codes

Reference for status words:

| SW1 | SW2 | Meaning |
|-----|-----|---------|
| 0x90 | 0x00 | Success, end of command |
| 0x61 | 0xXX | Success, XX more bytes available |
| 0x62 | 0x00 | Warning: no further info |
| 0x63 | 0x00 | Warning: file full |
| 0x64 | 0x00 | Error: transmission error |
| 0x65 | 0x00 | Error: memory failure |
| 0x67 | 0x00 | Error: wrong length |
| 0x68 | 0x00 | Error: security-related |
| 0x69 | 0x85 | Error: conditions not satisfied |
| 0x6A | 0x82 | Error: file/application not found |
| 0x6D | 0x00 | Error: instruction not supported |
| 0x6E | 0x00 | Error: class not supported |
| 0x6F | 0x00 | Error: unknown error |

## Flutter/Android Implementation

### 1. Define Your Service

**Kotlin Implementation (android/app/src/main/kotlin/):**

```kotlin
package com.example.nfc_wallet

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

class CardEmulationService : HostApduService() {
    private val TAG = "HCE_Service"
    
    // Your app's AID (7-8 bytes)
    private val AID_WALLET = byteArrayOf(0xF2.toByte(), 0x22, 0x22, 0x22, 
                                          0x22, 0x22, 0x22)
    
    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
        commandApdu?.let {
            Log.d(TAG, "Received APDU: ${toHexString(it)}")
            
            // Parse SELECT command
            if (isSelectAid(it, AID_WALLET)) {
                // Card activated, return success
                return byteArrayOf(0x90.toByte(), 0x00)
            }
            
            // Handle business logic commands
            return handleTransaction(it)
        }
        return byteArrayOf(0x6F.toByte(), 0x00) // Error
    }
    
    private fun handleTransaction(apdu: ByteArray): ByteArray {
        val INS = apdu[1]
        return when (INS) {
            0xB0.toByte() -> readData(apdu)
            0xD0.toByte() -> writeData(apdu)
            else -> byteArrayOf(0x6D.toByte(), 0x00) // Instruction not supported
        }
    }
    
    private fun readData(apdu: ByteArray): ByteArray {
        // Fetch wallet balance or card info
        val cardData = byteArrayOf(0x12, 0x34, 0x56, 0x78) // Example
        return cardData + byteArrayOf(0x90.toByte(), 0x00)
    }
    
    private fun writeData(apdu: ByteArray): ByteArray {
        // Persist transaction or update state
        return byteArrayOf(0x90.toByte(), 0x00) // Success
    }
    
    private fun isSelectAid(apdu: ByteArray, targetAid: ByteArray): Boolean {
        if (apdu.size < 10) return false
        val cla = apdu[0]
        val ins = apdu[1]
        val p1 = apdu[2]
        val p2 = apdu[3]
        val len = apdu[4].toInt() and 0xFF
        
        if (cla != 0x00.toByte() || ins != 0xA4.toByte() || 
            p1 != 0x04.toByte() || p2 != 0x00.toByte()) {
            return false
        }
        
        val receivedAid = apdu.sliceArray(5 until 5 + len)
        return receivedAid.contentEquals(targetAid)
    }
    
    private fun toHexString(bytes: ByteArray): String {
        return bytes.joinToString("") { "%02X".format(it) }
    }
    
    override fun onDeactivated(reason: Int) {
        Log.d(TAG, "Card deactivated. Reason: $reason")
    }
}
```

### 2. Register Service in AndroidManifest.xml

```xml
<service android:name=".nfc.CardEmulationService"
         android:exported="true"
         android:permission="android.permission.BIND_NFC_SERVICE">
  <intent-filter>
    <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE" />
  </intent-filter>
  <meta-data 
    android:name="android.nfc.cardemulation.host_apdu_service"
    android:resource="@xml/apdu_service_desc" />
</service>
```

### 3. Define APDU Service Descriptor (res/xml/apdu_service_desc.xml)

```xml
<host-apdu-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:apduServiceDesc="@xml/apdu_service"
    android:category="payment" />
```

### 4. Define AID Profiles (res/xml/apdu_service.xml)

```xml
<apdu-aid-group android:category="payment" android:description="@string/app_name">
  <aid-filter android:name="F222222222222222" />
</apdu-aid-group>
```

## Testing HCE

### Prerequisites
- Device with NFC and HCE support (Android 4.4+)
- NFC reader/terminal simulator app
- Enable Developer Options → Wireless Debugging (for logcat)

### Test Steps

1. **Verify service is registered:**
   ```bash
   adb shell dumpsys nfc | grep "HCE enabled"
   ```

2. **Monitor APDU traffic:**
   ```bash
   adb logcat | grep HCE_Service
   ```

3. **Simulate reader:**
   Use apps like "TagWriter" or "NFC Tools" from Play Store:
   - Tap "Emulate" or "Reader" mode
   - Hold external NFC reader near activated device
   - Verify APDU commands appear in logcat

4. **Send custom APDU:**
   ```bash
   adb shell am broadcast -a com.android.nfc.APDU \
     --es apdu "00A404000708F2222222222222"
   ```

## Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Service never called | Permission missing in manifest | Add `BIND_NFC_SERVICE` permission |
| Only one AID recognized | Multiple services competing | Check category (`payment`, `other`) |
| Data truncated in response | LE field too small | Split into multiple APDUs (chaining) |
| Device doesn't advertise AID | Manifest meta-data broken | Validate XML schema and restart device |
| Reader sees old app's AID | Service not uninstalled | `adb uninstall` before reinstall |

## Performance Tips

- Keep APDU processing < 100ms (reader timeout is 200-500ms)
- Don't do network I/O in `processCommandApdu()` (use background threads)
- Pre-cache wallet balance/card data
- Return status words immediately (defer heavy work to background job)

## Security Best Practices

- Validate all APDU input lengths
- Never return sensitive data without authentication
- Implement rate limiting (max X transactions/minute)
- Log all APDU processing for audit trails
- Use TLS for backend communication (if applicable)
