---
name: flutter-nfc-expert
description: 'Expert Flutter NFC application development. Use when: building NFC features, implementing Mifare/NDEF scanning, storing card data in SQLite, or setting up Android HCE card emulation. Covers setup, dependencies, coding patterns, testing, and troubleshooting.'
argument-hint: 'Describe your NFC feature or implementation task'
user-invocable: true
---

# Flutter NFC Expert Development Skill

Complete guidance for building NFC-enabled applications in Flutter, with emphasis on reading Mifare and NDEF standards, persisting data to SQLite, and implementing card emulation using Android HCE (Host Card Emulation).

## When to Use This Skill

- Setting up a new Flutter project with NFC capabilities
- Implementing NFC tag reading (Mifare, NDEF formats)
- Storing scanned NFC card data locally with SQLite
- Enabling card emulation so the phone acts as a virtual card
- Debugging NFC connection and data parsing issues
- Testing NFC features across Android devices

## Prerequisites

- Flutter SDK (3.0+)
- Android SDK (min API 19, target 34+)
- Physical Android device with NFC hardware enabled
- VS Code with Flutter extension

## Step-by-Step Development Procedure

### 1. Project Setup & Dependencies

**1.1 Create a new Flutter project:**
```bash
flutter create my_nfc_wallet --template=app
cd my_nfc_wallet
```

**1.2 Add NFC and database dependencies:**

Review [pubspec dependencies](./assets/pubspec-nfc.yaml) and add to `pubspec.yaml`:
```yaml
dependencies:
  nfc_manager: ^3.0.0          # iOS/Android NFC reading
  square_in_app_payments: ^1.11.0  # Payment-grade NFC handling
  sqflite: ^2.3.0              # SQLite database
  path_provider: ^2.0.0        # Local file paths
  uuid: ^4.0.0                 # Unique card IDs
```

**1.3 Configure Android manifest:**
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest>
  <uses-permission android:name="android.permission.NFC" />
  <uses-feature android:name="android.hardware.nfc" android:required="true" />
  <uses-feature android:name="android.hardware.nfc.hce" android:required="false" />
  
  <application>
    <activity>
      <!-- NFC Intent filter for tag discovery -->
      <intent-filter>
        <action android:name="android.nfc.action.TECH_DISCOVERED" />
      </intent-filter>
      <meta-data android:name="android.nfc.action.TECH_DISCOVERED" 
                 android:resource="@xml/nfc_tech_filter" />
    </activity>
    
    <!-- Card Emulation Service for HCE -->
    <service android:name=".nfc.CardEmulationService"
             android:exported="true"
             android:permission="android.permission.BIND_NFC_SERVICE">
      <intent-filter>
        <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE" />
      </intent-filter>
      <meta-data android:name="android.nfc.cardemulation.host_apdu_service"
                 android:resource="@xml/hce_apdu_service" />
    </service>
  </application>
</manifest>
```

### 2. NFC Reader Implementation

**2.1 Create NFC Manager service:**
See [NFC reader example](./assets/nfc-reader-example.dart) for complete implementation patterns including:
- Session initialization with error handling
- Tag detection (Mifare Classic, Ultralight, Plus)
- NDEF message parsing
- Data extraction and validation

**2.2 Handle different tag types:**
- Mifare Classic: 1K/4K blocks with authentication
- Mifare Ultralight C: Simplified format
- NDEF: Standard NFC Data Exchange Format

**2.3 Parse common NDEF payloads:**
- URI records (URLs)
- Text records (custom data)
- Mime type records (structured data)
- Vcard records (contact info)

### 3. Local Data Storage with SQLite

**3.1 Initialize database:**
Use [card storage example](./assets/card-storage-example.dart) pattern:
```dart
final db = await openDatabase(
  join(await getDatabasesPath(), 'nfc_cards.db'),
  version: 1,
  onCreate: (Database database, int version) async {
    await database.execute(
      'CREATE TABLE cards(id TEXT PRIMARY KEY, '
      'uid TEXT, content TEXT, format TEXT, discoveredAt INTEGER)'
    );
  },
);
```

**3.2 Store scanned cards:**
- Generate unique ID per scan (UUID)
- Store raw UID (hardware identifier)
- Persist NDEF content (JSON serialized)
- Track format (Mifare type, NDEF type)
- Record timestamp

**3.3 Query and retrieve cards:**
- List all stored cards with pagination
- Find duplicate UIDs (same physical card scanned multiple times)
- Filter by format or timestamp
- Export card data (CSV, JSON)

### 4. Card Emulation (HCE Setup)

**4.1 Understand HCE architecture:**
Review [HCE implementation guide](./references/hce-guide.md) for:
- APDU (Application Protocol Data Unit) commands
- CID (Card Identifier) selection
- Response codes (success, error handling)

**4.2 Implement card emulation service:**
See [HCE emulation example](./assets/hce-emulation-example.dart):
- Extend `HostApduService`
- Handle SELECT command (card activation)
- Define custom APDU responses
- Return card data as virtual card transactions

**4.3 Test emulation:**
- Enable developer mode on test device
- Use NFC reader app to scan your device-as-card
- Verify APDU command/response flow

### 5. Testing Strategy

**5.1 Unit tests:**
- Parse NDEF test data
- Validate UID extraction
- Database CRUD operations

**5.2 Integration tests:**
- Mock NFC tag sessions
- Full scan-to-storage workflow
- Card retrieval and filtering

**5.3 Device testing (required):**
- Use physical NFC tags (Mifare Classic, Ultralight)
- Test emulation with card reader terminals
- Verify Android HCE service activation
- Stress test: rapid tag scanning

### 6. Common Issues & Troubleshooting

**NFC not detected:**
- Verify `android:required="true"` in manifest
- Check device has NFC hardware (`adb shell pm get-max-users`)
- Enable NFC in device settings
- Restart app after manifest changes

**NDEF parsing errors:**
See [NFC standards reference](./references/nfc-standards.md) for:
- Record type identification
- Encoding validation
- Payload boundary checking

**HCE service not activating:**
- Verify `android.nfc.cardemulation.host_apdu_service` meta-data
- Check reader supports Host Card Emulation (not just Type 2/4 tags)
- Confirm service declared before tag discovery activity

**Database corruption:**
- Use `pragma integrity_check` in SQLite
- Implement migration strategy for table schema changes
- Back up card data before app updates

## Performance Optimization

- Cache frequent tag reads (debounce 500ms)
- Use async/await for NFC operations (prevents UI freeze)
- Limit database queries with WHERE clauses
- Close NFC session immediately after read completion

## Security Considerations

- Never log raw UID or NDEF content to console in production
- Use encrypted storage for sensitive card data
- Validate APDU responses before acting on them
- Implement rate limiting for HCE card transactions

## Project Structure

```
lib/
├── models/
│   ├── nfc_card.dart       # Card data model
│   └── nfc_tag.dart        # Tag format definitions
├── services/
│   ├── nfc_manager.dart    # NFC detection & reading
│   ├── card_storage.dart   # SQLite database layer
│   └── card_emulation.dart # HCE service wrapper
├── screens/
│   ├── scanner_screen.dart # Real-time scan UI
│   └── cards_list_screen.dart
└── utils/
    ├── ndef_parser.dart    # NDEF parsing utilities
    └── error_handler.dart
```

## References & Further Reading

- [NFC Standards (Mifare, NDEF)](./references/nfc-standards.md)
- [Android HCE Implementation](./references/hce-guide.md)
- [Flutter NFC Manager Package](https://pub.dev/packages/nfc_manager)
- [Android NFC API Docs](https://developer.android.com/guide/topics/connectivity/nfc)

---

**Need help?** Use drag-and-drop for your specific task:
- "I'm setting up a new NFC project" → Follow steps 1-2
- "I need to scan Mifare tags" → Follow step 2-3
- "I want to store card data persistently" → Follow step 3
- "Enable virtual card (HCE)" → Follow step 4
- "Debug NFC issues" → Jump to troubleshooting section
