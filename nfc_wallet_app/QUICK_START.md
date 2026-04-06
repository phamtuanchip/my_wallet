# NFC Wallet App - Quick Start Commands

## Project Location
```
c:\Users\phamt\project\my_wallet\nfc_wallet_app\
```

## Next Steps

### Step 1: Test on Windows Desktop (No Android Device Needed)

Open PowerShell or Command Prompt and run:

```bash
cd c:\Users\phamt\project\my_wallet\nfc_wallet_app
flutter run -d windows
```

This will:
- Build the app for Windows
- Launch it automatically
- Show the NFC Scanner UI
- Let you test button clicks and UI layout

**Note:** NFC scanning won't work on Windows (no NFC hardware), but you can verify the app compiles and the UI displays correctly.

---

### Step 2: Set Up Physical Android Device (For NFC Testing)

While the Windows version runs, prepare your Android device with these steps:

**On Your Computer:**
1. Download Android cmdline-tools from: https://developer.android.com/studio#command-line-tools-only
2. Extract to: `C:\Users\phamt\AppData\Local\Android\sdk\cmdline-tools\latest`
3. Accept licenses:
   ```bash
   flutter doctor --android-licenses
   ```

**On Your Android Device:**
1. Settings → About Phone → Tap "Build Number" 7 times
2. Settings → Developer Options → Enable "USB Debugging"
3. Settings → Wireless & networks → Enable "NFC"
4. Connect via USB cable

**Verify Connection:**
```bash
flutter devices
```

You should see your device listed.

---

### Step 3: Run App on Physical Android Device

Once device is connected:

```bash
cd c:\Users\phamt\project\my_wallet\nfc_wallet_app
flutter run
```

The app will:
- Build for Android
- Install on your physical device
- Launch automatically
- Show "NFC Ready" when device's NFC is detected

### Step 4: Test NFC Scanning

1. Tap the "Tap to Scan NFC Card" button
2. Hold an NFC card/tag near the top of your device
3. The app should detect and display:
   - Card UID (hardware identifier)
   - Card Type (Mifare Classic, Ultralight, etc.)
   - NDEF content if available

---

## Project Structure

```
nfc_wallet_app/
├── lib/
│   └── main.dart                    # NFC Scanner UI (flutter_nfc_expert)
├── android/
│   ├── app/src/main/
│   │   ├── AndroidManifest.xml      # NFC permissions configured
│   │   └── res/xml/
│   │       └── nfc_tech_filter.xml  # NFC tag technology filter
│   └── ...
├── pubspec.yaml                     # Dependencies (nfc_manager, sqflite, logger)
├── DEVICE_SETUP_GUIDE.md            # Detailed setup instructions
└── QUICK_START.md                   # This file
```

---

## Useful Commands

```bash
# Navigate to project
cd c:\Users\phamt\project\my_wallet\nfc_wallet_app

# Check device status
flutter devices

# Run on Windows
flutter run -d windows

# Run on Android device
flutter run

# Run specific device
flutter run -d <device_id>

# View app logs in real-time
flutter logs

# Clean build
flutter clean

# Reinstall dependencies
flutter pub get

# Run in release mode (faster)
flutter run --release

# Debug with verbose output
flutter run -v
```

---

## Troubleshooting

**"No pubspec.yaml found"**
- Make sure you're in the correct directory: `nfc_wallet_app/`
- Run: `cd c:\Users\phamt\project\my_wallet\nfc_wallet_app`

**"No devices found"**
- Connect Android device via USB
- Enable USB Debugging on device
- Accept USB debugging prompt on device
- Run: `flutter doctor --android-licenses`

**"NFC not detected on app"**
- Enable NFC in device settings
- Verify device has NFC (check in About Phone)
- Restart app after enabling NFC

**"cmdline-tools missing"**
- Download from: https://developer.android.com/studio#command-line-tools-only
- Extract to: `C:\Users\phamt\AppData\Local\Android\sdk\cmdline-tools\latest`

---

## Example NFC Test Cards

You can test scanning with:
- Mifare Classic 1K cards (common)
- Mifare Ultralight cards (simpler)
- NDEF-enabled NFC tags
- Public transit/payment cards with NFC
- NFC business cards

---

**See DEVICE_SETUP_GUIDE.md for more detailed troubleshooting.**
