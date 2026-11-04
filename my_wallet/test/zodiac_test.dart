import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/card/card_color.dart';
import 'package:my_wallet/card/zodiac.dart';
import 'package:my_wallet/widgets/wallet_card_face.dart';
import 'package:my_wallet/widgets/tilt_light.dart';
import 'package:my_wallet/widgets/zodiac_mark.dart';
import 'package:my_wallet/card/card_theme_art.dart';

void main() {
  TiltLight.source = null; // no sensor plugin under flutter test
  test('expiry month → the sign covering most of that month', () {
    expect(ZodiacSign.fromExpiry('01/29'), ZodiacSign.capricorn);
    expect(ZodiacSign.fromExpiry('04/30'), ZodiacSign.aries);
    expect(ZodiacSign.fromExpiry('8/27'), ZodiacSign.leo);
    expect(ZodiacSign.fromExpiry('12/2031'), ZodiacSign.sagittarius);
    expect(ZodiacSign.fromExpiry('13/29'), isNull);
    expect(ZodiacSign.fromExpiry(''), isNull);
    expect(ZodiacSign.fromExpiry(null), isNull);
    expect({for (var m = 1; m <= 12; m++) ZodiacSign.forMonth(m)}, hasLength(12));
  });

  test('every sign has its SVG asset bundled', () {
    for (final s in ZodiacSign.values) {
      expect(File(s.asset).existsSync(), isTrue, reason: s.asset);
    }
    expect(File('assets/zodiac/LICENSE-tabler-icons.txt').existsSync(), isTrue);
  });

  test('gradient presets are stored as 1000+i and never clash with old values', () {
    for (var i = 0; i < kCardGradients.length; i++) {
      final v = gradientValue(i);
      expect(cardGradientFromValue(v), same(kCardGradients[i]));
      expect(cardColorFromValue(v).a, 1.0); // opaque average, not Color(1000)
    }
    // Legacy presets and ARGB colours are untouched.
    expect(cardGradientFromValue(3), isNull);
    expect(cardColorFromValue(3), kCardColors[3]);
    expect(cardGradientFromValue(0xFF4A90D9), isNull);
    expect(cardColorFromValue(0xFF4A90D9), const Color(0xFF4A90D9));
    // A card with a gradient still spreads new random colours away from it.
    final picked = Color(pickDistinctCardColor([gradientValue(1)], random: Random(1)));
    expect(picked.a, 1.0);
  });

  test('gold is readable: dark rim only where gold is weak', () {
    // Bright gold vs. a dark card is strong; vs. a light/amber card it needs the rim.
    expect(contrastRatio(kZodiacGold[4], kCardColors[7]), greaterThan(1.8));
    expect(contrastRatio(kZodiacGold[4], const Color(0xFFF4C4B5)), lessThan(1.8));
  });

  testWidgets('glyphs parse from every bundled SVG', (tester) async {
    await tester.runAsync(() async {
      for (final s in ZodiacSign.values) {
        final path = await ZodiacGlyphs.load(s);
        final b = path.getBounds();
        expect(b.isEmpty, isFalse, reason: s.name);
        expect(b.left >= -1 && b.top >= -1 && b.right <= 25 && b.bottom <= 25, isTrue, reason: '${s.name} $b');
      }
    });
  });

  testWidgets('card face: small gold sign + name in the corner, only with an expiry', (tester) async {
    Future<void> pump(String? expiry, {bool elevated = false, List<Color>? gradient}) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: WalletCardFace(
                  title: 'Visa',
                  color: kCardColors[5],
                  last4: '1111',
                  expiry: expiry,
                  elevated: elevated,
                  gradientColors: gradient,
                ),
              ),
            ),
          ),
        ));
    await tester.runAsync(() => ZodiacGlyphs.load(ZodiacSign.aries));
    await pump('04/30');
    await tester.pump();
    expect(find.byType(ZodiacMark), findsOneWidget);
    final painter = tester
        .widgetList<CustomPaint>(find.descendant(of: find.byType(ZodiacMark), matching: find.byType(CustomPaint)))
        .map((w) => w.painter)
        .whereType<GlitterGlyphPainter>()
        .single;
    expect(painter.darkRim, isFalse); // gold on a blue card needs no dark rim
    expect(find.bySemanticsLabel(RegExp('Aries')), findsOneWidget);
    final mark = tester.getRect(find.byType(ZodiacMark));
    final card = tester.getRect(find.byType(WalletCardFace));
    // Small, in the right corner under the header, with the English name.
    expect(mark.height, 36);
    final badge = tester.getRect(find.byType(ZodiacBadge));
    expect(card.right - badge.right, closeTo(18, 1));
    expect(mark.center.dx, closeTo(badge.center.dx, 0.5));
    expect(mark.top - card.top, closeTo(WalletCardFace.headerHeight - 10, 1));
    expect(find.text('ARIES'), findsOneWidget);

    // In front: the shine animates (frames keep coming), and stops when removed.
    await pump('04/30', elevated: true, gradient: kCardGradients.first.colors);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);

    await pump(null);
    expect(find.byType(ZodiacMark), findsNothing);
  });

  testWidgets('reduced motion: no shine animation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: WalletCardFace(title: 'Visa', color: kCardColors[5], last4: '1111', expiry: '04/30', elevated: true),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ZodiacMark), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('tilt moves the light and is smoothed', () {
    final light = TiltLight.instance;
    for (var i = 0; i < 40; i++) {
      light.update(-6, 6.4); // tilted to the right, held at reading angle
    }
    expect(light.available, isTrue);
    expect(light.value, greaterThan(0.8));
    final before = light.value;
    light.update(6, 6.4); // one sample the other way: glides, doesn't jump
    expect(light.value, lessThan(before));
    expect(light.value, greaterThan(before - 0.7));
  });

  test('every theme paints at card and swatch sizes, and maps to 2000+i', () {
    for (var i = 0; i < kCardThemes.length; i++) {
      final theme = kCardThemes[i];
      expect(cardThemeFromValue(themeValue(i)), same(theme));
      expect(cardColorFromValue(themeValue(i)).a, 1.0);
      for (final size in const [Size(340, 200), Size(70, 44), Size(1, 1)]) {
        final recorder = ui.PictureRecorder();
        CardThemePainter(theme).paint(Canvas(recorder), size);
        recorder.endRecording().dispose();
      }
    }
    expect(kCardThemes.map((t) => t.id).toSet(), hasLength(kCardThemes.length));
    expect(cardThemeFromValue(gradientValue(0)), isNull);
  });
}
