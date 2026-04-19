# NFC Wallet App - Device Setup Guide

## Current Status
✅ Flutter project created  
✅ NFC dependencies added  
✅ AndroidManifest.xml configured  
✅ App UI created  
⚠️ Android SDK cmdline-tools missing (blocking device build)

## Quick Fix: Android SDK Setup

### Step 1: Download Android cmdline-tools
1. Go to [https://developer.android.com/studio](https://developer.android.com/studio)
2. Scroll to "Command line tools only"
3. Accept and download `cmdline-tools-windows-*.zip`
4. Extract the zip and note the path

### Step 2: Move cmdline-tools to Android SDK
```bash
# Extract to: C:\Users\phamt\AppData\Local\Android\sdk\cmdline-tools\latest
# The structure should be:
# C:\Users\phamt\AppData\Local\Android\sdk\
#   └── cmdline-tools/
#       └── latest/
#           ├── bin/
#           ├── lib/
#           └── ...
```

### Step 3: Accept Android Licenses
```bash
flutter doctor --android-licenses
# You'll be prompted to accept multiple licenses - type 'y' for each
```

### Step 4: Connect Your Android Device
1. **Enable USB Debugging on Device:**
   - Go to Settings → About Phone
   - Tap "Build Number" 7 times to enable Developer Options
   - Go to Settings → Developer Options
   - Enable "USB Debugging"
   - Enable "USB Debugging (Security settings)" if available

2. **Connect via USB:**
   - Connect device to PC with USB cable
   - Select "File Transfer" (or "MTP") mode when prompted on device
   - Verify with: `flutter devices`

3. **Verify NFC is Enabled:**
   - Go to Settings → Wireless & networks
   - Enable NFC toggle
   - Check that your device supports NFC (in Device Info)

### Step 5: Run the App on Device
```bash
cd c:\Users\phamt\project\my_wallet\nfc_wallet_app
flutter run -v  # -v shows verbose output for debugging
```

## Alternative: Run on Windows Desktop First

While you set up the Android device, you can test the app on Windows:

```bash
cd c:\Users\phamt\project\my_wallet\nfc_wallet_app
flutter run -d windows
```

**Note:** NFC scanning won't work on Windows (NFC hardware unavailable), but you can:
- Test the UI layout
- Verify app builds correctly
- Check app logic before device testing

## Troubleshooting

**Device not showing in `flutter devices`:**
```bash
# Check ADB can see device
adb devices

# If device shows "unauthorized", accept USB debugging prompt on phone

# Force reconnect:
adb kill-server
adb start-server
flutter devices
```

**"No Android device found" after USB Debugging enabled:**
- Try different USB port
- Try different USB cable
- Restart ADB: `adb kill-server && adb start-server`
- Restart device

**App won't scan NFC:**
- Verify `android:required="true"` in AndroidManifest.xml
- Check device has NFC hardware in Settings → About Phone
- Toggle NFC off/on in device settings
- Restart app after enabling NFC

**Build fails with cryptic errors:**
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run -d <device_id> -v
```

## When Physical Device is Ready

Once device is connected:

```bash
# List devices
flutter devices

# Run on specific device (if multiple connected)
flutter run -d <device_id>

# Run in release mode (better performance)
flutter run --release

# View live logs
flutter logs
```

## Testing NFC Features

Once app launches on device:

1. Open the app
2. You should see "NFC Ready - Tap card to scan"
3. Tap "Tap to Scan NFC Card" button
4. Bring NFC card/tag near device's NFC antenna (top of phone)
5. Scan results will appear with UID and content

### Test Cards
- Mifare Classic 1K/4K
- Mifare Ultralight
- NDEF-enabled tags
- Public transit cards
- NFC business cards

---

**Need help?** See the Flutter NFC Expert Skill (.github/skills/flutter-nfc-expert/) for detailed NFC implementation guidance.
