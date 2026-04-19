# NFC File Transfer - Quick Start Checklist ✅

## Pre-Test Setup (Do This Once)

### Device Requirements
- [ ] Device A has Android 7.0+ with NFC hardware
- [ ] Device B has Android 7.0+ with NFC hardware
- [ ] Both devices have NFC **enabled** in Settings
- [ ] Both devices have My Wallet app installed
- [ ] My Wallet has NFC permissions granted
- [ ] Removed thick phone cases that block NFC signals
- [ ] Both phones have decent battery (>20%)

### App Preparation
- [ ] Close all other apps using NFC
- [ ] Restart both phones (optional but recommended)
- [ ] Open My Wallet on both devices
- [ ] Check that both show "NFC Ready"

---

## Test #1: Image File Transfer (Recommended First Test)

### Setup
- [ ] Device A ready (waiting mode)
- [ ] Device B has a photo/image file

### Step 1: Prepare Receiver (Device A)
1. Open My Wallet
2. Tap the **Download icon** (📥) in top toolbar
3. Status should show: **"Waiting for file transfer... Hold devices together"**
4. ✅ **Leave it on this screen**

### Step 2: Prepare Sender (Device B)
1. Open My Wallet
2. Tap the **Upload icon** (📤) in top toolbar
3. Select a file from your gallery/files
4. Tap **"Send via NFC"** button
5. Status should show: **"Starting file transfer... Hold devices together"**

### Step 3: Connect Devices
1. **Position**: Hold phones back-to-back (NFC antennae facing each other)
2. **Distance**: Keep about 1-5 cm apart
3. **Stability**: Hold steady, don't move around
4. **Duration**: Keep in contact for 2-3 seconds
5. **Wait**: Watch for progress bar on Device B

### Step 4: Verify Success
- [ ] Device B: Progress bar shows (10% → 100%)
- [ ] Device B: Message shows "File sent successfully: [filename]"
- [ ] Device A: Message shows "File received successfully: [filename]"
- [ ] Both: Green checkmark/success indicators appear
- [ ] Check Device A Downloads folder: **File should be there!**

### Troubleshooting This Test
- Not discovering? → Bring phones closer, check NFC is ON
- Transfer slow? → Normal, could take 5-10 seconds for large files
- Transfer failed? → Try again, move to different position
- Still failing? → Restart both apps and try different antenna positions

---

## Test #2: Text File Transfer

### Setup
- [ ] Device A ready (waiting mode)
- [ ] Device B has a .txt file selected

### Run
1. Repeat the same steps as Test #1
2. File should transfer and save
3. ✅ **Verify file opens correctly on Device A**

---

## Test #3: Swap Roles (Device B Receives)

### Setup
- [ ] Device B ready (waiting mode)
- [ ] Device A has a file selected

### Run
1. Start file transfer from Device A
2. Device B receives file
3. ✅ **Verify bidirectional transfer works**

---

## Expected Behavior Chart

```
DEVICE B (Sender)                  DEVICE A (Receiver)
─────────────────────────────────────────────────────

Tap Upload (📤)                    Tap Download (📥)
↓                                  ↓
"Preparing file..."                "Waiting for file..."
↓                                  ↓
"Starting transfer..."             Waiting...
↓                                  ↓
Progress: 10%                      Waiting...
Progress: 30%
Progress: 50%                      [Devices Near]
Progress: 80%                      ↓
Progress: 100%                     "File received!"
↓                                  ↓
"File sent: photo.jpg"             Check Downloads folder
✅ Success                         ✅ File found
```

---

## Monitoring Logs (Advanced)

### View Logs in Terminal
```bash
flutter logs
```

### Look For These Messages
```
✅ [INFO] Starting file transfer session...
✅ [INFO] Device discovered, attempting file transfer
✅ [INFO] Writing file to peer device
✅ [INFO] File transfer completed: [filename]

OR:

✅ [INFO] Starting file reception session
✅ [INFO] Tag discovered during file reception
✅ [INFO] File transfer detected: [filename]
✅ [INFO] File received and saved: [filename]
```

### If You See Errors
```
❌ [ERROR] Error starting file P2P session: ...
❌ [WARNING] Tag is not NDEF writable or is null
❌ [ERROR] Error processing received file: ...
```
These will help debug the issue.

---

## Success Indicators ✅

You'll know the fix is working when:

1. **Visual Indicators**
   - [ ] Status messages update in real-time
   - [ ] Progress bar fills from left to right
   - [ ] No error messages appear
   - [ ] Success dialogs appear on both devices

2. **File Indicators**
   - [ ] File appears in Downloads folder on receiver
   - [ ] File size is correct
   - [ ] File can be opened normally
   - [ ] File is not corrupted

3. **Log Indicators**
   - [ ] Logs show "File transfer completed"
   - [ ] No "ERROR" messages in logs
   - [ ] Clear progression through steps

---

## Failure Scenarios & Solutions

### Scenario: "Waiting for file transfer..." forever
**Solution:**
1. Bring phones closer (within 5cm)
2. Ensure NFC is enabled on both
3. Move to different antenna position
4. Restart the app on receiver device

### Scenario: "Error sending file: ..."
**Solution:**
1. Check file size (should be reasonable, < 100MB)
2. Try with a smaller file
3. Restart both apps
4. Check device storage has space

### Scenario: File appears corrupted
**Solution:**
1. Try with different file type
2. Ensure transfer completes (watch progress bar to 100%)
3. Don't move phones during transfer
4. Check downloaded file location

### Scenario: Transfer starts but stops
**Solution:**
1. Keep phones in contact during entire transfer
2. For large files: keep in contact 5-10 seconds
3. Don't interrupt (don't tap other buttons)
4. Try with smaller file first

---

## Test Results Template

### Test #1 Results
- [ ] Device: ________________
- [ ] File type: ________________
- [ ] Status: ✅ SUCCESS / ❌ FAILED
- [ ] Issue (if any): ________________

### Test #2 Results
- [ ] Device: ________________
- [ ] File type: ________________
- [ ] Status: ✅ SUCCESS / ❌ FAILED
- [ ] Issue (if any): ________________

### Test #3 Results
- [ ] Device: ________________
- [ ] File type: ________________
- [ ] Status: ✅ SUCCESS / ❌ FAILED
- [ ] Issue (if any): ________________

---

## Additional Documentation

For more information, see:

1. **[NFC_FIX_SUMMARY.md](NFC_FIX_SUMMARY.md)**
   - Overview of all changes
   - Key improvements made

2. **[NFC_FIX_CHANGELOG.md](NFC_FIX_CHANGELOG.md)**
   - Detailed technical changes
   - Code comparisons
   - Technical background

3. **[NFC_FILE_TRANSFER_TESTING_GUIDE.md](NFC_FILE_TRANSFER_TESTING_GUIDE.md)**
   - Comprehensive testing guide
   - Troubleshooting detailed solutions
   - Performance tips
   - Device setup guide

---

## Final Checklist

Before testing is complete:

- [ ] Successfully transferred file from Device B to Device A
- [ ] File is in Downloads folder on Device A
- [ ] File can be opened and viewed
- [ ] Successfully transferred in reverse direction (A to B)
- [ ] No error messages in logs
- [ ] Clear status messages appear throughout
- [ ] Transfer works with multiple file types
- [ ] Process is repeatable and consistent

---

## Summary

### If All Tests Pass ✅
**The NFC file transfer issue is FIXED!** 🎉

### If Tests Fail ❌
1. Review troubleshooting section
2. Check detailed logs
3. Refer to [NFC_FILE_TRANSFER_TESTING_GUIDE.md](NFC_FILE_TRANSFER_TESTING_GUIDE.md)
4. Try different positions/devices

---

## Questions?

- **How do I check logs?** → Run `flutter logs` in terminal
- **Where's the Downloads folder?** → Device Settings → Storage → Downloads
- **Can I use emulator?** → Only if it has NFC support (rare)
- **Need more help?** → See detailed testing guide

---

**Ready to test? Start with Test #1 above!** 🚀
