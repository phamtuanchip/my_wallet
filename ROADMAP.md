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
- [ ] App lock (biometric / passcode) and auto-lock on background, `FLAG_SECURE`, no backup.
- [ ] DB v3 migration to the model above, with encrypted PAN/CVV. Migrate existing `cards` rows in `onUpgrade`; updates must never lose data.
- [ ] **Add card manually**: number with Luhn check and live scheme logo, expiry, CVV, holder, bank (auto from BIN, editable), product, tier, colour, notes.
- [ ] Vault list grouped by **bank / scheme / type**, search, filter chips, reorder.
- [ ] Card detail: realistic card face (scheme logo, bank colour), reveal PAN/CVV with re-auth, copy with auto-clear.
- [ ] Vietnamese UI strings (i18n with `intl`/ARB), dark mode.
- [ ] Unit tests: Luhn, IIN → scheme, BIN → bank, crypto round-trip, DB migration.

### Phase 2: Fast input (≈1–2 weeks)
- [ ] **NFC EMV reader** (Android): read PAN + expiry and prefill the form; the user types the CVV. Handle Visa/Mastercard/JCB/NAPAS AIDs and cards that hide the PAN.
- [ ] **Camera scan**: ML Kit on-device OCR, Luhn and expiry regex, confirm screen.
- [ ] Duplicate detection (same PAN hash) offers an update instead of a new card.

### Phase 3: Polish & safety net (≈1 week)
- [ ] Encrypted backup/restore file.
- [ ] Expiry reminders (local notifications 30 days before `expiry`).
- [ ] Statistics: cards per bank, cards expiring this year.
- [ ] Play Store prep: privacy policy, Data safety form ("data not collected, stays on device"), AAB build in CI.

### Phase 4: Other card types (later)
- [ ] **Access cards**: save UID/type/photo of the card. Note that real door emulation only works with readers that accept a custom AID; Mifare Classic UID cloning is not possible with HCE.
- [ ] **CCCD (chip citizen ID)**: ICAO 9303 eMRTD. Read the MRZ on the back with the camera, then BAC/PACE over NFC to read DG1 (data) + DG2 (photo) and verify the SOD signature (`dmrtd` package).
- [ ] **E-passport**: same eMRTD flow with the MRZ from the photo page.
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
