# my_wallet — Roadmap

Goal: one private, offline vault for every card I own — **bank cards first** (grouped by
bank, scheme and card type, CVV behind fingerprint/passcode), then access cards, the
chip CCCD (citizen ID) and e-passports.

## 1. Where the app is today (v1.0 → v1.1)

| Area | State |
|---|---|
| Code | Everything lives in `lib/main.dart` (~2,650 lines). It mixes UI, NFC, SQLite and file transfer, so it needs a split before new features go in. |
| NFC scan | Reads the tag **UID** and type (Mifare Classic/Ultralight, NFC-A/B/F/V, NDEF records). It does **not** speak EMV, so bank cards come back as "NFC Type A" with a random UID. |
| Storage | `sqflite` table `cards(id, uid, name, tagType, content, timestamp, color)`, **not encrypted**. |
| HCE | Emulates a custom AID `F0010203040506`. It **cannot** stand in for a Mifare door badge (readers check the UID / Crypto-1) or a bank card (payment needs the issuer's keys and tokenisation). |
| P2P file transfer | Built on NDEF. Android Beam was removed in Android 10, so phone-to-phone transfer is unreliable. Drop it or move it to Nearby Share/QR. |
| Security | No app lock, no `FLAG_SECURE`, `allowBackup` defaults to true, HCE `requireDeviceUnlock=false`, `MANAGE_EXTERNAL_STORAGE` requested (the Play Store will reject it). |
| Release | v1.1.0: `applicationId = com.phamtuanchip.mywallet`, release key, versionCode from the version name, one universal APK per tag (see README). |

Done in v1.9.0: **card themes**, drawn in code (no bitmaps, no licences): Black marble, Carbon, Holographic,
Đông Sơn drum, Lotus, Bamboo, Spring blossom, Summer sea, Autumn leaves, Winter snow, picked in a third row of the
colour sheet and stored as 2000 + index in `color`. The zodiac sign is now **glitter gold** (grains of glitter on
bright honey-to-lemon gold, glow, bokeh, star flares) with its **English name**, small in the card's corner. A
**tilt reflection**: the phone's accelerometer moves a band of light across the gold and flashes the glitter and
stars, like turning a metal card under a lamp (auto sweep without a sensor; off with "Remove animations"; the
sensor runs only while the front card is on screen).

Done in v1.8.0: zodiac signs in **shiny gold** (metallic gradient + soft glow, a light sweep every ~4 s on
the card in front, off with "Remove animations"; dark rim on light cards), drawn **big in the centre** of the
card at 64 % of its height behind the text. **Gradient backgrounds**: 10 presets (Sunset, Ocean, Aurora, Rose
gold, Royal, Emerald, Fire, Midnight, Peach, Galaxy) next to the solid colours, stored as 1000 + index in the
existing `color` column (no migration).

Done in v1.7.0: a **zodiac sign** on every card with an expiry (VALID THRU month → the sign covering most of
that month: 01 Capricorn … 12 Sagittarius), on the card face, the card sheet preview and every colour swatch.
Icons are Tabler Icons (MIT, bundled SVG). The colour is the opposite hue of the card, made lighter or darker
until it reaches WCAG 4.5:1 contrast with the card.

Done in v1.6.0: **access cards** (elevator, door/smart lock, parking, hotel) in Documents. 13.56 MHz cards
are read with the phone's NFC: UID, chip family from SAK/ATQA, and for MIFARE Classic how many sectors still
open with a default key (+ block 0). Tapping such a card from the Wallet scan offers "Save to Documents".
125 kHz cards (EM4100/T5577/HID, most "thẻ từ") **cannot be read by any phone**: the ID comes from a USB OTG
keyboard-type reader or from OCR of the number printed on the card (10-digit decimal and/or Wiegand-26
`fff,ccccc`), converted to the EM4100 hex ID. Magnetic-stripe cards are photo + manual entry only.

Done in v1.5.0: export a document to the phone's **Download/MyWallet** folder as a PDF (both sides on one
A4 page, cards at real 85.6 × 54 mm size for printing), one combined JPEG, or one JPEG per side. Capture now
works like a photo-scan app: ML Kit Document Scanner in full mode (auto edges, adjustable corners, rotate,
filters, shadow/finger clean-up), "scan both sides" in one session, gallery import through the scanner, and
papers (passport page, insurance, other) kept at up to 3000 px in a page-shaped frame.

Done in v1.4.0: a **Documents** tab for personal papers. Tapping a card that is not a bank card but has
the ICAO eMRTD chip asks "CCCD or passport?". The chip is read over NFC with BAC + 3DES secure messaging
(own implementation on `pointycastle`, checked against the ICAO 9303-11 worked example): DG1 (MRZ),
DG2 (face photo) and, for the CCCD, DG13 (name with diacritics, address, parents…, best effort). The BAC
key comes from the MRZ on the back (camera OCR) or from the typed number + dates. Documents without a chip
(car/motorbike licence, vehicle registration, insurance, other) are saved as front/back photos (Document
Scanner crop + OCR prefill). Fields and photos are AES-256-GCM encrypted on the phone, opened only after
fingerprint/passcode; DB v5 adds the `documents` table.

Done in v1.3.0: card number + expiry (and name/label when the card exposes them) read from the
chip over NFC (EMV: PPSE, SELECT, GPO, READ RECORD; read-only, zero amount), cards recognised again
by a keyed fingerprint of the number (bank cards send a random UID per tap), camera scan through
ML Kit Document Scanner (crop + deskew) with multi-pass OCR (original, grey + contrast, 180°)
merged per field, one de-duplicated "add details" prompt that auto-hides and can be closed.

Done in v1.2.0: card details per card (number, cardholder, network, debit/credit, bank, expiry, CVV),
camera / photo scan with on-device ML Kit OCR, number + CVV encrypted with AES-256-GCM (key in Android
Keystore) and unlocked with fingerprint/passcode, DB v3 migration (additive), Google Wallet-style stack
(76 dp tap strip, tap to bring a card forward), a random never-used colour for every new card,
backups disabled for card data.

Fixed in v1.1: crash on devices without NFC (`CardEmulation.getInstance(null)`), broken
`widget_test.dart`, removed the stale Java HCE service, final applicationId, new launcher icon (adaptive), Lucide icon set, release signing, tag-triggered GitHub release.

## 2. Hardware reality check

| Input | Can it read a bank card? | Notes |
|---|---|---|
| **Phone NFC (Android)** | Yes: card number (PAN) + expiry | EMV flow `SELECT PPSE (2PAY.SYS.DDF01) → SELECT AID → GET PROCESSING OPTIONS → READ RECORD`, parse tag `5A`/`57` (PAN), `5F24` (expiry). The cardholder name is usually blank on modern cards. **CVV/CVC2 is never on the chip**, so the user always types it. |
| Phone NFC (iOS) | No | Core NFC blocks payment AIDs. On iOS, add cards manually or via camera. |
| Camera OCR | Yes: number, expiry, sometimes the name | On-device ML Kit text recognition plus Luhn validation. Works for both printed and embossed cards. |
| **Ocrustar IR dongle (`my_remote`)** | **No** | The EKX4S/5S is an IR *transmitter* with **no IR receiver** (see `my_remote/README.md`). Bank/ID cards have no IR interface anyway. |
| USB/BT smart-card reader (e.g. ACR39U, ACR122U) | Yes, via contact chip | Possible later through Android USB host + PC/SC-style APDUs; same EMV parser. |

## 3. Data model (v2)

```
bank      (id, name, short_name, bin_prefixes, logo, color)
card      (id, kind[bank|access|cccd|passport|other], bank_id?, scheme[visa|mastercard|jcb|amex|unionpay|napas|other],
           product[debit|credit|prepaid], tier[classic|gold|platinum|...], label, holder_name,
           pan_enc, last4, expiry_mm_yy, cvv_enc?, nfc_uid?, color, notes, created_at, updated_at, sort_order)
card_tag  (card_id, tag)        -- free tags such as "online", "travel"
```

- Encrypted columns (`pan_enc`, `cvv_enc`) use AES-256-GCM. The data key is wrapped by an Android Keystore / iOS Keychain key.
- `last4` and `scheme` stay in clear text so lists, grouping and search work without decrypting.
- Grouping in the UI: **by bank → by scheme → by product type**, plus filter chips and search.
- The scheme comes from the IIN: Visa `4`, Mastercard `51–55, 2221–2720`, JCB `3528–3589`, Amex `34/37`, UnionPay `62`, NAPAS `9704`.
  Vietnamese bank from the BIN table (e.g. `970436` Vietcombank, `970418` BIDV, `970415` VietinBank, `970407` Techcombank, …).

## 4. Security design (bank-card vault)

1. **App lock**: biometrics or device passcode (`local_auth`) on launch and on every return from background (configurable grace period of 0/30/60 s).
2. **Two-level reveal**: the list shows `•••• 1234` only. The full PAN or CVV needs a fresh **BiometricPrompt with CryptoObject** (class-3 biometrics or device credential), auto-hides after 30 s, and copying clears the clipboard after 30 s.
3. **At rest**: encrypted fields (or SQLCipher for the whole DB), key in Keystore with `setUserAuthenticationRequired`.
4. **Platform**: `FLAG_SECURE` (no screenshots, blank in recents), `android:allowBackup="false"`, no network permission needed for the vault, R8 on.
5. **Backup**: export only as a password-encrypted file (Argon2id/PBKDF2 → AES-GCM), shared through the system share sheet / SAF.
6. Note: PCI DSS forbids merchants from storing CVV. For a personal vault it's your call, so CVV storage is an **opt-in per card**.

## 5. Roadmap

### Phase 0: Foundation (≈1 week)
- [ ] Split `main.dart` into `lib/core` (crypto, db, theme), `lib/data` (repositories), `lib/features/{vault,scan,settings}`.
- [ ] Pick state management (Riverpod suggested) and keep `sqflite` (switch to `sqflite_sqlcipher` for encryption).
- [x] Final `applicationId` `com.phamtuanchip.mywallet` (v1.1.0); every later version updates in place.
- [ ] Remove `MANAGE_EXTERNAL_STORAGE` and the NDEF P2P transfer (or hide it behind a flag).
- [x] Release signing, tag-triggered GitHub Release, new icons.

### Phase 1: Secure bank-card vault MVP (≈2 weeks), **priority**
- [ ] Design system + vault layout from section 6 (theme tokens, card stack, add sheet).
- [x] Fingerprint / passcode before showing saved number or CVV, 60 s grace, re-locks in background, no backup (v1.2.0).
- [ ] Whole-app lock on launch, `FLAG_SECURE`.
- [x] DB v3 migration with encrypted PAN/CVV, additive `onUpgrade` (v1.2.0).
- [x] **Card details form**: number with Luhn check and live scheme logo, expiry, CVV, holder, bank (auto from BIN, editable), product (v1.2.0).
- [ ] Add a card without NFC (manual only), tier, notes.
- [ ] Vault list grouped by **bank / scheme / type**, search, filter chips, reorder.
- [x] Card face with scheme mark, bank, last 4, holder, expiry/expired (v1.2.0).
- [ ] Copy number with clipboard auto-clear.
- [ ] Vietnamese UI strings (i18n with `intl`/ARB), dark mode.
- [x] Unit tests: Luhn, IIN → scheme, BIN → bank, OCR parser, crypto round-trip, colours (v1.2.0).
- [ ] DB migration test (v2 → v3 on a real SQLite file).

### Phase 2: Fast input (≈1–2 weeks)
- [x] **NFC EMV reader** (Android): PAN + expiry (+ name/label when present) saved encrypted; Visa/Mastercard/JCB/NAPAS/Amex/UnionPay/Discover AIDs, PPSE or AID fallback, GPO fallback to record scan (v1.3.0).
- [ ] On-device Gemini Nano (ML Kit GenAI Prompt API) as an optional extra pass on supported phones only (Pixel 10, Galaxy S26…); not available on mid-range devices.
- [x] **Camera scan**: ML Kit on-device OCR, Luhn and expiry parsing, review in the form (v1.2.0).
- [x] Duplicate detection by keyed PAN fingerprint: tapping a saved card updates it instead of adding a new one (v1.3.0).

### Phase 3: Polish & safety net (≈1 week)
- [ ] Encrypted backup/restore file.
- [ ] Expiry reminders (local notifications 30 days before `expiry`).
- [ ] Statistics: cards per bank, cards expiring this year.
- [ ] Play Store prep: privacy policy, Data safety form ("data not collected, stays on device"), AAB build in CI.

### Phase 4: Other card types (later)
- [x] **Access cards**: UID/type/key check over NFC (13.56 MHz), USB reader or printed number for 125 kHz, photos (v1.6.0). Door emulation is still not possible: readers check the UID / Crypto-1, which HCE cannot fake.
- [ ] 125 kHz over Bluetooth (e.g. Chameleon Ultra) so no USB reader is needed.
- [x] **CCCD (chip citizen ID)**: MRZ from the back by camera (or typed), BAC over NFC, DG1 + DG2 photo + DG13 Vietnamese personal data (v1.4.0).
- [x] **E-passport**: same eMRTD flow with the MRZ from the photo page (v1.4.0).
- [x] **Paper documents** (driving licences, vehicle registration, insurance, other): front/back photos, encrypted, OCR prefill (v1.4.0).
- [ ] eMRTD: **PACE** for chips that refuse BAC, **passive authentication** (SOD signature against the CSCA list), JPEG 2000 face photo decoding.
- [ ] Expiry reminders for documents (licence, CCCD, insurance).
- [ ] USB smart-card reader support (contact chip).
- [ ] iOS build on a macOS CI runner (manual/camera input only for bank cards; eMRTD works on iOS with Core NFC).

## 6. Mobile UI optimisation

Findings in the current UI: 67 hard-coded `Color(0x…)`, 36 inline `fontSize`, 48 `setState` calls in one
`State` class (the whole screen rebuilds on every NFC event), **no** `Semantics`/tooltips, English-only
strings, and a `Courier` font for card numbers that isn't bundled on Android.

### Design system
- [ ] One `ThemeData` built from `ColorScheme.fromSeed` + a `ThemeExtension` for wallet tokens (card gradients, radii, spacing 4/8/12/16/24).
      Replace every hard-coded colour and font size, so dark mode and contrast come for free.
- [ ] Typography: bundle one font with Vietnamese diacritics (Inter or Be Vietnam Pro), use `FontFeature.tabularFigures()` for
      card numbers and amounts instead of `Courier`.
- [ ] Icon set: Lucide everywhere (done), plus bank and scheme logos as SVG (`flutter_svg`) for the card face.

### Layout & navigation
- [ ] Bottom nav **Vault · Scan · Settings** with a big central **+ Add** button (manual / NFC / camera in one bottom sheet).
- [ ] Vault screen: Apple-Wallet card stack per bank (collapsed groups), sticky group headers, search on pull-down,
      filter chips (bank / scheme / debit-credit / expiring).
- [ ] Card detail as a `Hero` transition from the stack; actions (copy number, show CVV, edit, delete) in reach of the thumb at the bottom.
- [ ] Respect `SafeArea`, the keyboard (`viewInsets`), small phones (≤360 dp) and tablets/foldables (two-pane list + detail at ≥600 dp).
- [ ] Edge-to-edge with transparent system bars; predictive back gesture (Android 14+).

### Interaction & feedback
- [ ] Haptic feedback on NFC read success/failure, reveal and copy.
- [ ] NFC scan sheet with clear states: *waiting → reading → success / try again*, and a hint for where the antenna is on the phone.
- [ ] Every screen has **loading / empty / error** states (skeleton cards, empty-state illustration with an "Add your first card" CTA).
- [ ] Undo snackbar for delete instead of a blocking dialog; confirmation only for destructive bulk actions.
- [ ] Form UX: numeric keyboard, auto-format `#### #### #### ####` and `MM/YY`, live scheme logo, autofocus on the next field, inline Luhn error.
- [ ] Motion: 200–300 ms, `Curves.easeOutCubic`; honour "Remove animations" (`MediaQuery.disableAnimations`).

### Accessibility & i18n
- [ ] `Semantics` labels for icon-only buttons and card faces ("Vietcombank Visa debit ending 1234"); masked numbers read as "ending 1234", never the full PAN.
- [ ] Text scaling up to 200 % without overflow (test with `textScaler`), touch targets ≥ 48 dp, contrast ≥ 4.5:1.
- [ ] Vietnamese + English via ARB files (`flutter gen-l10n`), Vietnamese by default.

### Performance
- [ ] Split the 2,650-line widget into small widgets with `const` constructors; move state to Riverpod so an NFC event rebuilds only the scan sheet.
- [ ] `ListView.builder`/`SliverList` for the vault, `RepaintBoundary` around animated card stacks, cache decoded bank logos.
- [ ] Startup: open the DB and unlock in parallel behind a native splash (`flutter_native_splash`, matching the new icon); target < 1 s on mid-range phones.
- [ ] APK size: ship split-per-ABI APKs / AAB (arm64 is 18.8 MB versus 50 MB universal), drop unused plugins (`file_picker`, `permission_handler` once P2P is gone).

### Privacy in the UI
- [ ] Blur/hide card faces when the app goes to background (in addition to `FLAG_SECURE`).
- [ ] "Privacy mode" toggle: mask even the last 4 digits and bank name in lists for use in public.
