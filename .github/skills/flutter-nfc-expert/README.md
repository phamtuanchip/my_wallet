# Flutter NFC Expert Skill

A complete, production-ready Flutter skill for building NFC-enabled wallet and card management applications. This skill provides step-by-step guidance for implementing Mifare card reading, NDEF parsing, SQLite storage, and Android HCE card emulation.

## How to Use This Skill

**Type `/flutter-nfc-expert` in VS Code chat** to invoke this skill with guidance tailored to your NFC development task.

### Quick Implementation Flow

1. **Project Setup** → Add dependencies and configure Android manifest
2. **NFC Reading** → Implement tag scanning and data extraction
3. **Data Storage** → Set up SQLite database for card persistence
4. **Card Emulation** → Enable HCE for virtual card functionality
5. **Testing** → Validate on physical devices with NFC hardware

### Common Development Tasks

| Task | Skill Section | Key Files |
|------|---------------|-----------|
| Set up new NFC project | [Step 1: Setup](./SKILL.md#1-project-setup--dependencies) | [pubspec-nfc.yaml](./assets/pubspec-nfc.yaml) |
| Scan NFC tags (Mifare/NDEF) | [Step 2: Reader](./SKILL.md#2-nfc-reader-implementation) | [nfc-reader-example.dart](./assets/nfc-reader-example.dart) |
| Store card data persistently | [Step 3: Storage](./SKILL.md#3-local-data-storage-with-sqlite) | [card-storage-example.dart](./assets/card-storage-example.dart) |
| Enable phone-as-card (HCE) | [Step 4: Emulation](./SKILL.md#4-card-emulation-hce-setup) | [hce-emulation-example.dart](./assets/hce-emulation-example.dart) |
| Troubleshoot NFC issues | [Step 6: Issues](./SKILL.md#6-common-issues--troubleshooting) | [NFC standards](./references/nfc-standards.md) |

## Skill Contents

```
.github/skills/flutter-nfc-expert/
├── SKILL.md                        # Complete implementation workflow (6 steps)
├── README.md                       # This usage guide
├── references/
│   ├── nfc-standards.md           # Mifare + NDEF format specifications
│   └── hce-guide.md               # Android card emulation architecture
└── assets/
    ├── pubspec-nfc.yaml           # Required dependencies
    ├── nfc-reader-example.dart    # NFC scanning implementation
    ├── card-storage-example.dart  # SQLite database layer
    └── hce-emulation-example.dart # Card emulation example
```

## Implementation Checklist

### ✅ Phase 1: Foundation
- [ ] Flutter project created with NFC dependencies
- [ ] Android manifest configured for NFC permissions
- [ ] Basic NFC session management implemented

### ✅ Phase 2: Reading
- [ ] Mifare Classic/Ultralight tag detection
- [ ] NDEF message parsing and record extraction
- [ ] UID extraction and format identification
- [ ] Error handling for different tag types

### ✅ Phase 3: Storage
- [ ] SQLite database schema for cards
- [ ] CRUD operations (Create, Read, Update, Delete)
- [ ] Duplicate detection and conflict resolution
- [ ] Data serialization and migration support

### ✅ Phase 4: Emulation
- [ ] Android HCE service implementation
- [ ] APDU command handling
- [ ] AID (Application Identifier) configuration
- [ ] Virtual card data mapping

### ✅ Phase 5: Testing
- [ ] Physical NFC tag testing
- [ ] Card reader compatibility verification
- [ ] HCE service activation testing
- [ ] Performance and stress testing

## Getting Started with the Skill

1. **Invoke the skill**: Type `/flutter-nfc-expert` in VS Code chat
2. **Describe your task**: "I need to scan Mifare tags" or "Set up HCE card emulation"
3. **Follow the guidance**: The skill provides step-by-step implementation instructions
4. **Use code examples**: Copy and adapt code from the `assets/` folder
5. **Test thoroughly**: Always validate on physical NFC hardware

## Troubleshooting

**Can't find the skill?**
- Ensure `.github/skills/flutter-nfc-expert/` exists in your workspace
- Reload VS Code window (`Ctrl+Shift+P` → "Developer: Reload Window")

**Code examples don't work?**
- They're production patterns, not copy-paste code
- Adapt them to your specific project structure and requirements
- Check that all dependencies are properly installed

**NFC features not working?**
- Review [SKILL.md troubleshooting](./SKILL.md#6-common-issues--troubleshooting)
- Check Android manifest configuration
- Verify device has NFC hardware and permissions
- Use `adb logcat` to monitor NFC activity

---

**Full documentation:** Read [SKILL.md](./SKILL.md) for complete implementation guidance with code examples and best practices.
