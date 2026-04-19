# NFC Wallet App 📱💳

A comprehensive Flutter application that serves as a digital wallet for NFC cards, featuring both **NFC card reading** and **Host Card Emulation (HCE)** capabilities. Transform your smartphone into a virtual NFC card reader and emulator!

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white)
![NFC](https://img.shields.io/badge/NFC-000000?style=for-the-badge&logo=nfc&logoColor=white)

## ✨ Features

### 🔍 NFC Card Reading
- **Multi-format Support**: Read Mifare Classic, Ultralight, NDEF, and other NFC card types
- **Auto-Save**: Automatically save scanned cards with serializable naming (nfc_1, nfc_2, etc.)
- **Duplicate Detection**: Update existing cards instead of creating duplicates
- **Real-time Feedback**: Live scan results with detailed card information
- **Persistent Storage**: SQLite database for reliable card storage

### � File Transfer (P2P)
- **Device Storage Access**: Select files and images from device storage
- **Bidirectional Transfer**: Send and receive files between Android devices
- **App Bar Actions**: Quick access via upload/download icons in toolbar
- **Multi-format Support**: Images (JPG, PNG, GIF), Documents (PDF, DOC, TXT)
- **Automatic Reception**: Smart detection of incoming file transfers
- **Download Folder**: Received files saved to device Downloads directory
- **Progress Tracking**: Real-time transfer status and file information
- **Cancel Support**: Ability to cancel ongoing transfers

### 🎭 Card Emulation (HCE)
- **Virtual Card Creation**: Turn your phone into a virtual NFC card
- **Office Access Badge**: Perfect replacement for physical access cards
- **APDU Protocol**: Full APDU command handling for professional applications
- **Custom AIDs**: Configurable Application Identifiers for different use cases
- **Secure Emulation**: Isolated card data with proper access controls

### 🎨 User Interface
- **Material Design 3**: Modern, intuitive interface
- **Dark/Light Themes**: Adaptive theming support
- **Visual Status Indicators**: Clear feedback for all operations
- **Responsive Layout**: Optimized for various screen sizes
- **Accessibility**: Screen reader support and high contrast options

### 🔧 Technical Features
- **Cross-platform**: Android-first with iOS expansion potential
- **Method Channels**: Native Android integration for HCE
- **Background Services**: Efficient NFC session management
- **P2P Communication**: Direct device-to-device NFC data transfer
- **File System Access**: Device storage integration for file selection
- **NDEF Messaging**: Structured data exchange protocol
- **Multi-format Support**: Handles various file types and sizes
- **Error Handling**: Comprehensive error reporting and recovery
- **Logging**: Detailed operation logs for debugging

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: 3.11.3 or higher
- **Android SDK**: API 19+ (target 34+)
- **Android Device**: With NFC hardware enabled
- **Development Environment**: VS Code with Flutter extension

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/phamtuanchip/my_wallet.git
   cd my_wallet/nfc_wallet_app
   ```

2. **Add app icon** (optional)
   - Replace `assets/icon/nfc_wallet_icon.png` with your 512x512 PNG icon
   - Run `flutter pub run flutter_launcher_icons` to generate icons

3. **Install dependencies**
   ```bash
   flutter pub get
   ```

4. **Configure Android**
   - Enable NFC in device settings
   - Grant NFC permissions when prompted
   - Enable Developer Options for HCE testing

5. **Run the app**
   ```bash
   flutter run --debug -d <device-id>
   ```

### Building for Production
```bash
flutter build apk --release
```

## 📖 Usage Guide

### Reading NFC Cards
1. **Launch App**: Open the NFC Wallet app
2. **Tap Scan**: Press "Tap to Scan NFC Card"
3. **Present Card**: Hold NFC card near device
4. **Auto-Save**: Card is automatically saved with unique name
5. **View Details**: Check card information in the saved cards list

### Transferring Files (P2P)
1. **Select File**: Tap the upload icon (📤) in the app bar or "Select File" button
2. **Choose File**: Pick an image, document, or text file to transfer
3. **Start Transfer**: Press "Send via NFC" or use the send icon in app bar
4. **Present Devices**: Hold sending device near receiving device
5. **Auto-Transfer**: File transfers automatically with progress updates
6. **Confirmation**: Both devices show successful transfer messages

### Receiving Files (P2P)
1. **Start Reception**: Tap the download icon (📥) in the app bar
2. **Wait for Transfer**: App shows "Waiting for file transfer..." status
3. **Auto-Detection**: App automatically detects incoming file transfers
4. **Accept Transfer**: Files are received and saved to Downloads folder
5. **View Details**: Check transfer status and file information
6. **Cancel Anytime**: Use "Cancel Reception" button if needed

### Emulating Cards
1. **Select Card**: Choose a saved card from the list
2. **Start Emulation**: Tap the play button (▶️)
3. **Present Phone**: Hold phone near NFC reader
4. **Authentication**: Reader receives virtual card data
5. **Stop Emulation**: Tap stop button when finished

### Managing Cards
- **View Cards**: Scroll through saved cards list
- **Delete Cards**: Use trash icon to remove unwanted cards
- **Card Details**: Tap cards to view full information
- **Emulation Status**: Visual indicators show active emulation
- **Share Status**: Real-time feedback during P2P transfers

## 🏗️ Architecture

```
lib/
├── main.dart                 # Main application entry point
├── models/
│   └── nfc_card.dart        # Card data model
├── services/
│   ├── nfc_manager.dart     # NFC reading service
│   ├── card_storage.dart    # SQLite database service
│   └── card_emulation.dart  # HCE service wrapper
├── screens/
│   ├── scanner_screen.dart  # Main NFC scanner UI
│   └── cards_list_screen.dart # Saved cards management
└── utils/
    ├── ndef_parser.dart     # NDEF data parsing
    └── error_handler.dart   # Error handling utilities

android/
├── MainActivity.kt          # Flutter activity with method channels
├── CardEmulationService.java # HCE APDU service
├── AndroidManifest.xml      # NFC permissions & HCE service
└── res/xml/
    ├── nfc_tech_filter.xml  # NFC technology filters
    └── hce_apdu_service.xml # HCE service configuration
```

## 🛠️ Technologies Used

### Core Framework
- **Flutter**: Cross-platform UI framework
- **Dart**: Programming language

### NFC & Hardware
- **NFC Manager**: Flutter NFC reading library
- **Host Card Emulation**: Android native HCE API
- **NDEF Protocol**: NFC Data Exchange Format for P2P
- **APDU Protocol**: Smart card communication standard

### Data & Storage
- **SQLite**: Local database for card persistence
- **SharedPreferences**: Configuration and HCE state storage
- **sqflite**: Flutter SQLite wrapper

### Utilities
- **Logger**: Comprehensive logging system
- **UUID**: Unique identifier generation
- **Path Provider**: File system path management
- **File Picker**: Device storage file selection
- **Image/File Handling**: Multi-format file processing

## 🔧 Configuration

### NFC Permissions
The app requires the following Android permissions:
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="true" />
<uses-feature android:name="android.hardware.nfc.hce" android:required="false" />
```

### HCE Service Configuration
```xml
<!-- android/app/src/main/res/xml/hce_apdu_service.xml -->
<host-apdu-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/hce_service_description"
    android:requireDeviceUnlock="false">
    <aid-group android:description="@string/aid_group_description"
        android:category="other">
        <aid-filter android:name="F0010203040506"/>
    </aid-group>
</host-apdu-service>
```

## 📱 Use Cases

- 💳 **Wallet Apps**: Scan transit/payment cards, store data locally
- 🏢 **Access Control**: Read office badges, emit as virtual card at entry
- 🎟️ **Loyalty Programs**: Store customer card data with balance tracking
- 🔐 **Secure Data**: HCE allows card emulation without microSD secure element

## 🤝 Contributing

Built with the Flutter NFC Expert skill. For development guidance, see the [skill documentation](../.github/skills/flutter-nfc-expert/README.md).

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
