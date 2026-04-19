# NFC File Transfer Testing Guide

## What Was Fixed

The NFC file transfer between two Android devices has been improved with the following changes:

### Key Improvements:
1. **Enhanced Polling Options**: Added support for `NfcPollingOption.nfcA` and `NfcPollingOption.nfcF` in addition to `iso14443` to better detect P2P targets between devices
2. **Better Error Handling**: Improved logging and error messages to help debug connection issues
3. **Device Discovery**: Both sender and receiver now use the same polling options for proper P2P communication
4. **Status Messages**: More informative status messages guide the user through the process

---

## Device Setup Checklist

Before testing, ensure both devices are properly configured:

- [ ] Both devices have Android 7.0 (API 24) or higher
- [ ] **NFC Hardware**: Both devices have NFC capability (check Settings → About)
- [ ] **NFC Enabled**: Enable NFC on both devices:
  - Settings → Wireless & Networks → NFC
  - Toggle NFC ON
- [ ] **My Wallet App**: Install and run the app on both devices
- [ ] **Permissions**: Grant NFC permissions when prompted
- [ ] **No Case Interference**: Remove thick phone cases that might block NFC signals

---

## Testing Procedure

### Step 1: Prepare Device A (Receiver)

1. Open **My Wallet** app
2. Tap the **Download icon** (📥) in the app bar
3. You should see the message: **"Waiting for file transfer... Hold devices together"**
4. **Keep the app on this screen** - the receiver is now listening

### Step 2: Prepare Device B (Sender)

1. Open **My Wallet** app on Device B
2. Tap the **Upload icon** (📤) in the app bar
3. Select a file:
   - Choose: Image (JPG, PNG, GIF), Document (PDF, TXT), or Document (DOC, DOCX)
   - Example: Take a screenshot and save it, then select that file
4. Tap **"Send via NFC"** button
5. You should see: **"Starting file transfer... Hold devices together"**

### Step 3: Bring Devices Together

1. **Hold the two devices back-to-back** with NFC antenna areas close together
   - Most Android phones have NFC antenna at the **top or bottom** of the device
   - Check your device manual for exact location
2. **Keep devices steady** - don't move too quickly
3. **Wait 2-3 seconds** for the connection to establish
4. Watch for:
   - Progress bar on Device B (Sender)
   - Status updates on both devices

---

## Expected Behavior

### Successful Transfer:
- **Device B (Sender)**: 
  - Progress bar fills from 10% → 30% → 50% → 100%
  - Status: "File sent successfully: [filename]"
  - Toast notification appears
- **Device A (Receiver)**:
  - Status: "File received successfully: [filename]"
  - Toast notification: "File '[filename]' received and saved!"
  - File saved to Downloads folder

### Files are saved to:
```
Device Storage → Downloads
```

---

## Troubleshooting

### Issue: "Waiting for file transfer..." but nothing happens

**Solution:**
1. Ensure **both devices** have NFC enabled (Settings → Wireless & Networks → NFC)
2. **Hold devices closer together** - NFC requires very close proximity (typically < 10cm)
3. Try different positions:
   - Back-to-back (recommended)
   - Side-by-side
   - Top-to-top (if NFC antenna is at top)
4. Remove any thick phone cases that might block NFC signals

### Issue: "Error transferring file" or "Error starting transfer"

**Solution:**
1. Check the **app logs** in the console:
   - Look for messages like "Starting P2P file transfer session"
   - Look for "Device discovered"
2. Ensure:
   - File is properly selected
   - File size is reasonable (< 100MB for best compatibility)
   - Both apps are using same app version

### Issue: Device shows "Received invalid data format" or "Incomplete file data"

**Solution:**
1. Check NFC antenna alignment:
   - Both devices must be properly aligned
   - Move devices slightly if needed
2. Try with a different file
3. Restart both apps and try again

### Issue: File transfer starts but doesn't complete

**Solution:**
1. **Hold devices steady** during entire transfer
2. Don't move devices during transfer - let them stay in contact
3. For larger files (> 10MB):
   - Transfer may take 5-10 seconds
   - Keep devices in contact for the entire duration

---

## Testing Multiple Scenarios

### Scenario 1: Small Image File ✅ (Recommended First Test)
1. Take a screenshot on Device B
2. Select this image as the file to send
3. Transfer to Device A
4. Verify file appears in Device A's Downloads

### Scenario 2: Text File
1. Create or select a small text file (.txt)
2. Transfer from Device B to Device A
3. Verify the file content is correct

### Scenario 3: PDF File
1. Select a small PDF file (< 5MB)
2. Transfer from Device B to Device A
3. Verify PDF opens correctly

### Scenario 4: Swap Sender/Receiver
1. Now make Device A the sender and Device B the receiver
2. Repeat the file transfer
3. Verify it works in both directions

---

## Logging for Debugging

If you encounter issues, enable detailed logging:

1. In the console, look for messages:
   ```
   Starting file transfer session...
   Device discovered
   Tag discovered during file reception
   Processing received tag for file content
   File transfer completed successfully
   ```

2. Share these logs with support if needed

---

## Performance Tips

1. **NFC Reception Distance**: Usually 5-10 cm maximum
2. **Optimal Contact Time**: Keep devices together for 2-5 seconds
3. **File Size**: Best results with files under 5MB
4. **Antenna Alignment**: Check your device's NFC antenna location
5. **Metal Interference**: Keep away from metal objects during transfer

---

## Card Sharing via NFC

The same P2P improvements also apply to **Card Sharing**:

1. Select a saved card
2. Tap **Share** button
3. Bring Device B (with receiving app open) close to Device A
4. Card data transfers automatically
5. Receiving device saves the card

---

## Support

If you encounter persistent issues:

1. **Check device logs**: Look for error messages in the console
2. **Verify NFC hardware**: Use Settings → About → Device Status
3. **Test with NFC app**: Try Android's default NFC Reader app
4. **Restart devices**: A full restart may help
5. **Update app**: Ensure you're running the latest version

---

## Questions?

For more details on NFC specifications:
- [NFC Type-A/Type-B Specifications](https://nfcpy.readthedocs.io/)
- [Android NFC Documentation](https://developer.android.com/guide/topics/connectivity/nfc)
- [Flutter NFC Manager Package](https://pub.dev/packages/nfc_manager)
