// Renders a contact sheet of card themes + the gold sign to a PNG, for a
// visual check. Skipped unless PREVIEW_OUT is set:
//   PREVIEW_OUT=/path/out.png flutter test test/render_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/card/card_color.dart';
import 'package:my_wallet/card/card_theme_art.dart';
import 'package:my_wallet/card/zodiac.dart';
import 'package:my_wallet/widgets/tilt_light.dart';
import 'package:my_wallet/widgets/wallet_card_face.dart';
import 'package:my_wallet/widgets/zodiac_mark.dart';

void main() {
  TiltLight.source = null; // no sensor plugin under flutter test
  final out = Platform.environment['PREVIEW_OUT'];

  testWidgets('render theme contact sheet', (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(ZodiacGlyphs.preload);
    for (var i = 0; i < 30; i++) {
      TiltLight.instance.update(-0.6, 6.4); // light slightly right of centre
    }

    final key = GlobalKey();
    final months = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12'];
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFF101012),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (var i = 0; i < kCardThemes.length; i++)
                SizedBox(
                  width: 340,
                  child: WalletCardFace(
                    title: kCardThemes[i].name,
                    color: cardColorFromValue(themeValue(i)),
                    themeArt: kCardThemes[i],
                    last4: '4242',
                    holder: 'NGUYEN VAN AN',
                    expiry: '${months[i]}/29',
                    elevated: true,
                  ),
                ),
              SizedBox(
                width: 340,
                child: WalletCardFace(
                  title: 'Gradient',
                  color: kCardGradients[0].average,
                  gradientColors: kCardGradients[0].colors,
                  last4: '4242',
                  expiry: '11/29',
                  elevated: true,
                ),
              ),
              SizedBox(
                width: 340,
                child: WalletCardFace(title: 'Amber', color: kCardColors[3], last4: '4242', expiry: '12/29', elevated: true),
              ),
              // Large sign alone to judge the glitter.
              Container(
                width: 340,
                height: 200,
                color: const Color(0xFF1A1206),
                alignment: Alignment.center,
                child: ZodiacMark(sign: ZodiacSign.leo, background: const Color(0xFF1A1206), size: 180, animate: true),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(out!).writeAsBytes(png!.buffer.asUint8List());
    });
  }, skip: out == null);
}
