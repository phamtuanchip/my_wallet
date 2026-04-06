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

### 📤 Card Sharing (P2P)
- **Peer-to-Peer Transfer**: Send card data between Android devices via NFC
- **JSON Serialization**: Secure data exchange with structured card information
- **Cross-Device Sync**: Share cards instantly without cloud services
- **Automatic Detection**: Smart recognition of incoming card transfers
- **Seamless Integration**: Works alongside reading and emulation features

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
- **NDEF Messaging**: Structured data exchange protocol
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

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Android**
   - Enable NFC in device settings
   - Grant NFC permissions when prompted
   - Enable Developer Options for HCE testing

4. **Run the app**
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

### Emulating Cards
1. **Select Card**: Choose a saved card from the list
2. **Start Emulation**: Tap the play button (▶️)
3. **Present Phone**: Hold phone near NFC reader
4. **Authentication**: Reader receives virtual card data
5. **Stop Emulation**: Tap stop button when finished

### Sharing Cards (P2P)
1. **Select Card**: Choose a saved card from the list
2. **Tap Share**: Press the share button (📤) next to the card
3. **Start Sending**: App enters P2P mode waiting for receiver
4. **Present Devices**: Hold sending device near receiving device
5. **Auto-Transfer**: Card data transfers automatically via NFC
6. **Confirmation**: Both devices show success messages

### Receiving Cards (P2P)
1. **Normal Operation**: Use app normally for reading or emulation
2. **Auto-Detection**: App automatically detects incoming card transfers
3. **Accept Transfer**: Card data is received and saved automatically
4. **View New Card**: Check the updated cards list for received cards
5. **No User Action**: Receiving happens seamlessly in background

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

## 🔧 Configuration

### NFC Permissions
The app requires the following Android permissions:
```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="true" />
<uses-feature android:name="android.hardware.nfc.hce" android:required="false" />
```

### HCE Service Configuration
Custom AIDs for card emulation:
```xml
<aid-group android:description="@string/hce_aid_group_description" android:category="other">
    <aid-filter android:name="F0010203040506"/>
    <aid-filter android:name="F0010203040507"/>
</aid-group>
```

## 🧪 Testing

### Unit Tests
```bash
flutter test
```

### Integration Tests
```bash
flutter test integration_test/
```

### Device Testing Requirements
- Physical NFC cards (Mifare, NDEF)
- NFC reader terminals for HCE testing
- Android device with NFC hardware
- Developer mode enabled

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines
- Follow Flutter best practices
- Add tests for new features
- Update documentation
- Ensure NFC compatibility across devices

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Flutter NFC Manager package developers
- Android NFC API documentation
- Material Design guidelines
- Open source NFC community

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/phamtuanchip/my_wallet/issues)
- **Discussions**: [GitHub Discussions](https://github.com/phamtuanchip/my_wallet/discussions)
- **Documentation**: [Flutter NFC Expert Skill](./.github/skills/flutter-nfc-expert/)

---

**Made with ❤️ using Flutter and NFC technology**

*Transform your smartphone into a comprehensive NFC card wallet!* 🚀
