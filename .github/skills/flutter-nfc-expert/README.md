# Flutter NFC Expert Skill

A complete, production-ready Flutter skill for building NFC-enabled wallet and card management applications. Covers Mifare card reading, NDEF parsing, SQLite storage, and Android HCE card emulation.

## Quick Start

**Type `/flutter-nfc-expert` in VS Code chat** to invoke this skill with guidance tailored to your task.

### Common Workflows

| Task | Start Here |
|------|-----------|
| Set up new NFC project | [SKILL.md](./SKILL.md#1-project-setup--dependencies) |
| Scan NFC tags (Mifare/NDEF) | [SKILL.md](./SKILL.md#2-nfc-reader-implementation) + [nfc-reader-example.dart](./assets/nfc-reader-example.dart) |
| Store card data persistently | [SKILL.md](./SKILL.md#3-local-data-storage-with-sqlite) + [card-storage-example.dart](./assets/card-storage-example.dart) |
| Enable phone-as-card (HCE) | [SKILL.md](./SKILL.md#4-card-emulation-hce-setup) + [hce-emulation-example.dart](./assets/hce-emulation-example.dart) + [HCE guide](./references/hce-guide.md) |
| Troubleshoot NFC issues | [SKILL.md](./SKILL.md#6-common-issues--troubleshooting) |

## What's Inside

```
.github/skills/flutter-nfc-expert/
├── SKILL.md                        # Main skill: steps 1-6 for complete workflow
├── README.md                       # This file
├── references/
│   ├── nfc-standards.md           # Mifare + NDEF format reference
│   └── hce-guide.md               # Android card emulation architecture
└── assets/
    ├── pubspec-nfc.yaml           # Dependencies to add
    ├── nfc-reader-example.dart    # Complete NFC scanning service
    ├── card-storage-example.dart  # SQLite database layer
    └── hce-emulation-example.dart # Card emulation example (Dart side)
```

## Key Features

✅ **Full NFC Stack**: Mifare Classic/Ultralight reading, NDEF parsing, card detection  
✅ **SQLite Storage**: Persistent card database with transaction history  
✅ **HCE Support**: Turn your phone into a virtual card (Android 4.4+)  
✅ **Production Ready**: Error handling, logging, validation, security patterns  
✅ **Well Documented**: Inline code comments + detailed reference guides  

## Technologies

- **Flutter**: 3.0+
- **Android**: API 19+ (NFC), API 21+ (HCE)
- **Packages**: nfc_manager, sqflite, uuid, logger
- **Formats**: Mifare Classic/Ultralight, NDEF, APDU

## Use Cases

- 💳 **Wallet Apps**: Scan transit/payment cards, store data locally
- 🏢 **Access Control**: Read office badges, emit as virtual card at entry
- 🎟️ **Loyalty Programs**: Store customer card data with balance tracking
- 🔐 **Secure Data**: HCE allows card emulation without microSD secure element

## Next Steps After Setup

1. Choose your primary use case (reading vs. emulation)
2. Review [nfc-standards.md](./references/nfc-standards.md) to understand your target card format
3. Copy relevant code from `assets/` folder into your project
4. Configure `AndroidManifest.xml` with NFC permissions (see SKILL.md step 1.3)
5. Test on physical device with NFC tags

## Troubleshooting

**Can't find the skill?**
- Ensure `.github/skills/flutter-nfc-expert/` is in your workspace root
- Reload VS Code (`Ctrl+Shift+P` → "Developer: Reload Window")

**Code examples have errors?**
- They're production patterns, not copy-paste. Adjust for your project structure.
- Verify all dependencies from `pubspec-nfc.yaml` are added to your `pubspec.yaml`

**NFC not working on device?**
- See [SKILL.md troubleshooting section](./SKILL.md#6-common-issues--troubleshooting)
- Check `adb logcat` for NFC activity
- Ensure Android manifest is correctly configured

---

**Full guidance:** Use the skill by typing `/flutter-nfc-expert` in VS Code chat, or read through [SKILL.md](./SKILL.md) sequentially.
