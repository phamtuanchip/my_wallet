# my_wallet — Handover (for the next agent/session)

Flutter wallet app. Working note. This file is a working note; delete when no longer needed.

## Where things are

- **Repo**: `C:\Users\phamt\project\my_wallet` (git). App lives in the `my_wallet/` subfolder.
- **Branch**: `release/v1.9.0` (pushed to `origin`). The old `release/v1.4.0` remote branch still exists (only its 1.4.0 commit).
- **Everything is committed and pushed** through commit `947db8d` (phone-replacement labels). Working tree is clean except this HANDOVER.md.
- **Current version**: `my_wallet/pubspec.yaml` → `1.9.0+1009000`.
- Version/build rule: build number = `major*1000000 + minor*1000 + patch`. Bump both on every release.

## Phone (physical device) workflow — IMPORTANT

- The user tests on a real phone (MTP name **`A069`**) over USB file-transfer, **not adb**.
- After each build, copy the APK to the phone's **Download** folder **and delete all older `my_wallet-*.apk`**, keeping only the newest. (Standing instruction from the user.)
- Build: `cd my_wallet && powershell -ExecutionPolicy Bypass -File tool\build_release.ps1` → outputs `release/my_wallet-<ver>.apk` (git-ignored). Needs `android/key.properties` (present, git-ignored) and uses JDK 17 automatically.
- Copy+verify+clean via MTP COM (Shell.Application, NameSpace(17), item `A069`, its first storage → `Download`). See prior session commands; verify by `ExtendedProperty('System.Size')` == local bytes, then delete old ones with `InvokeVerb('delete')` and re-list to confirm.
- Builds take ~3–11 min; run in background and read the task output file when notified.

## Conventions

- Chat replies to this user in **Vietnamese**. Code/comments/commits in **English**.
- App UI strings are **English**, with Vietnamese labels for document/theme types (e.g. `vnLabel`, `vnName`).
- Commits use the personal identity `Pham Tuan <phamtuanchip@gmail.com>` (repo-local git config), with no AI co-author or session trailers.
- Don't commit/push unless asked (the user says "commit và push"). Branch first if on `main`.
- Secrets/APKs are git-ignored: `android/key.properties`, `android/keystore/*.jks`, `release/`, `**/pubspec.lock`. Keep it that way.
- Always run `flutter analyze` (expect "No issues found!") and `flutter test` (currently **80 passing**) before building. Run from `my_wallet/`.
- Editing tip: large multi-point edits via a Python script in the scratchpad are fragile with shell quoting — prefer the Edit tool, or write the .py file with the Write tool then run it.

## Feature history (all shipped, committed)

- v1.3.0: EMV chip reader (PAN+expiry), PAN fingerprint dedupe (DB v4), multi-pass OCR.
- v1.4.0: Documents vault — CCCD/passport over NFC (own BAC + 3DES secure messaging on `pointycastle`, DG1/DG2/DG13), paper docs as encrypted front/back photos. DB v5 `documents` table.
- v1.5.0: Export to `Download/MyWallet` (PDF both sides on A4 at real card size / combined JPEG / separate JPEGs) via a native Kotlin MediaStore channel; photo-scan capture (ML Kit Document Scanner full mode, scan both sides, papers up to 3000 px).
- v1.6.0: Access cards — 13.56 MHz read over NFC (UID, SAK type, MIFARE Classic default-key check); 125 kHz EM4100 via USB OTG reader or OCR of printed number.
- v1.7.0 / v1.8.0: zodiac sign from VALID THRU month; metallic gold; 10 gradient backgrounds.
- v1.9.0: 10 **card themes** drawn in code (`lib/card/card_theme_art.dart`); zodiac redrawn as **glitter gold** with English name in the card corner; **tilt reflection** via accelerometer (`lib/widgets/tilt_light.dart`).
- (post-1.9.0, committed `947db8d`, not yet released as an APK): **phone-replacement labels** — honest "can/can't use phone instead" banner per document kind + note under HCE "Hold Near Reader".

### Colour/theme storage (no DB migration — all in the `color` int column)

`lib/card/card_color.dart` + `card_theme_art.dart` decode `color`:
- `0..7` = legacy preset index (`kCardColors`)
- `1000 + i` = gradient (`kGradientBase`, `kCardGradients`)
- `2000 + i` = theme (`kThemeBase`, `kCardThemes`)
- otherwise = raw ARGB
`cardColorFromValue(int)` returns the representative solid colour; `cardGradientFromValue`, `cardThemeFromValue` return null unless in range.

## OUTSTANDING WORK (what the user asked for next — NOT done)

The user's last request (this is the active task):
> "vì load cả background lẫn hiệu ứng logo cung hoàng đạo nên switch/change card bị chậm rõ rệt, tối ưu chỗ này; cung hoàng đạo/logo phải lấp lánh khi nghiêng thẻ; thêm nhiều chủ đề: thiên nhiên, hoa, con vật."

### 1. Performance (main problem) — card switch/swipe is laggy

Root cause: in the Cards tab `PageView` and the wallet stack, card **size animates** each frame (AnimatedContainer margins / stack transforms). That makes both painters redo expensive work every frame:
- `CardThemePainter` (in `card_theme_art.dart`) re-runs hundreds of vector path ops per frame.
- `GlitterGlyphPainter` (in `widgets/zodiac_mark.dart`) recomputes grain/star geometry whenever `size` changes (`_prepare` keys on exact `Size`, which changes every animation frame).

**Planned fix (designed, not yet implemented):**

a) **Rasterize each theme to a `ui.Image` once**, then paint with `canvas.drawImageRect` (cheap blit, scales to any card size).
   - Extract the current bg+art+scrim drawing into a free function `paintThemeVector(Canvas, CardThemeArt, Size)`.
   - Add a `CardThemeRaster` cache: `Map<String themeId, ui.Image>`, a reference size ~`520x328` (or 600x378, ID-1 ratio 1.586), a `preloadAll()` (call from `_NFCScannerScreenState.initState`, next to `ZodiacGlyphs.preload()`), and a `ChangeNotifier ready` that notifies when an image finishes.
   - `CardThemePainter(theme) : super(repaint: CardThemeRaster.ready)`. In `paint`: if image cached → `drawImageRect(img, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium)`; else draw vectors (fallback for the first frame) and kick off async rasterize.
   - Memory check: ref 520×328×4 ≈ 0.68 MB × (themes count). With ~18 themes ≈ 12 MB — acceptable; don't go bigger.

b) **Make `GlitterGlyphPainter` size-independent.** Compute grains + star positions **once in the 24-unit glyph space**, cached statically keyed by `seed` (= `sign.index`). In `paint`, `canvas.scale(size.shortestSide/24)` and draw everything in unit coords. Set stroke widths/point radii as `deviceWidth / s` (cheap scalars computed per paint) so they stay the right pixel size. This removes all per-size recompute. Keep the existing tilt/shine logic (uses `along()` on positions — recompute `along` in unit space or normalise by 24).
   - Current geometry constants to preserve: `_strokeUnits = 2.4`; grain step `max(0.35, w/7)`; across spread `w*1.05`; grain kinds split 0.42/0.74/0.92; 4 star fractions `[0.1,0.38,0.63,0.88]`.

c) Confirm each card's theme/glyph is under a `RepaintBoundary` (theme already is in `wallet_card_face.dart`). Consider wrapping the whole card face in a `RepaintBoundary` in the stack/pageview item builders.

### 2. Tilt sparkle on the sign/logo

Already implemented (`TiltLight` + specular band in `GlitterGlyphPainter`, `animate: elevated`). Verify it still works after the refactor; the user re-listed it, so make sure the corner `ZodiacBadge` visibly shimmers on tilt. `TiltLight.source` is injectable (set to `null` in tests — no sensor plugin under `flutter test`).

### 3. More themes: nature / flowers / animals

Add new `CardThemeArt` entries to `kCardThemes` in `card_theme_art.dart` (each is a `void Function(Canvas, Size)` painter; use the existing helpers `_u`, `_stroke`, `_fill`, `_blossom`, `_leaf`; set `scrim: true` for light artwork). Suggested: mountains, pine forest, starry night, sakura, rose, sunflower, koi fish, butterfly. They're pre-rasterized after fix (1a), so complexity is a one-time cost.
- Each new theme: unique `id`, `name` (EN), `vnName` (VI), a `background` gradient, a painter. IDs must stay unique (there's a test asserting that). Index in the list = stored value `2000 + index`; **append**, never reorder (would change saved cards' themes).

### Tests to update after the work

- `test/zodiac_test.dart`: theme-count/paint test iterates `kCardThemes` at sizes `[Size(340,200), Size(70,44), Size(1,1)]` — new themes auto-covered; keep the unique-`id` assertion.
- `test/render_preview_test.dart`: renders a contact sheet of all themes to a PNG when `PREVIEW_OUT=<path>` is set. Use it to eyeball new themes:
  `PREVIEW_OUT=<scratch>/preview.png flutter test test/render_preview_test.dart` then Read the PNG.
- Add a perf-oriented test only if cheap (e.g. the glyph geometry cache is reused across sizes).

## Key files

- `lib/main.dart` — app shell, tabs (Wallet / Cards / Settings / Documents), NFC scan dispatch (EMV → eMRTD probe → access-card info), DB open/migrate, card sheet with colour/gradient/theme swatches.
- `lib/card/card_color.dart`, `card_theme_art.dart`, `zodiac.dart` — colours, themes, zodiac mapping.
- `lib/widgets/wallet_card_face.dart`, `zodiac_mark.dart` (+ `ZodiacBadge`), `tilt_light.dart`.
- `lib/document/` — `id_document.dart` (kinds, fields, `PhoneReplacement`), `document_store.dart` (encrypted, DB v5), `document_screen.dart`, `document_capture.dart`, `document_ocr.dart`, `document_export.dart`, `documents_view.dart`, `chip_read_sheet.dart`.
- `lib/nfc/emv/` (EMV), `lib/nfc/emrtd/` (BAC/MRZ/DG), `lib/access/` (lf_card_id, nfc_tag_info, access_read_sheets).
- `android/app/src/main/kotlin/.../MainActivity.kt` — HCE channel + `com.phamtuanchip.mywallet/downloads` MediaStore save channel.

## Deps of note
`pointycastle` (eMRTD crypto), `pdf`, `google_mlkit_document_scanner`, `google_mlkit_text_recognition`, `image`, `image_picker`, `sensors_plus` (tilt), `path_drawing` (parse zodiac SVG at runtime), `sqflite`(+`_common_ffi` dev), `cryptography`, `local_auth`, `flutter_secure_storage`. (No `flutter_svg` — removed; SVGs parsed via `path_drawing`.)

## Also pending (non-blocking)
- `pubspec.lock` is git-ignored; for an app it's usually better tracked. Ask the user before changing.
- Optional "phone replacement" HCE feature for user-controlled custom-AID readers (the honest, limited version) — user hasn't chosen to build it yet; labels are in.
