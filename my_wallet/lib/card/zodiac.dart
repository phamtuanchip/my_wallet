import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Zodiac sign drawn on a card face from its expiry month. Icons: Tabler Icons
/// (MIT, `assets/zodiac/`). A card only has a month, so each month maps to
/// the sign that covers most of its days (e.g. January: Capricorn until the
/// 19th, Aquarius from the 20th → Capricorn).
enum ZodiacSign {
  capricorn('Capricorn', 'Ma Kết', '♑'),
  aquarius('Aquarius', 'Bảo Bình', '♒'),
  pisces('Pisces', 'Song Ngư', '♓'),
  aries('Aries', 'Bạch Dương', '♈'),
  taurus('Taurus', 'Kim Ngưu', '♉'),
  gemini('Gemini', 'Song Tử', '♊'),
  cancer('Cancer', 'Cự Giải', '♋'),
  leo('Leo', 'Sư Tử', '♌'),
  virgo('Virgo', 'Xử Nữ', '♍'),
  libra('Libra', 'Thiên Bình', '♎'),
  scorpio('Scorpio', 'Bọ Cạp', '♏'),
  sagittarius('Sagittarius', 'Nhân Mã', '♐');

  const ZodiacSign(this.label, this.vnLabel, this.symbol);

  final String label;
  final String vnLabel;
  final String symbol;

  String get asset => 'assets/zodiac/$name.svg';

  /// Month 1–12 → sign (enum order starts at January = Capricorn).
  static ZodiacSign forMonth(int month) {
    if (month < 1 || month > 12) throw RangeError.range(month, 1, 12, 'month');
    return ZodiacSign.values[month - 1];
  }

  /// From `MM/YY` (or `MM/YYYY`); null when there is no usable month.
  static ZodiacSign? fromExpiry(String? expiry) {
    final m = RegExp(r'^\s*(\d{1,2})\s*/').firstMatch(expiry ?? '');
    if (m == null) return null;
    final month = int.parse(m.group(1)!);
    return month >= 1 && month <= 12 ? forMonth(month) : null;
  }
}

/// WCAG relative-luminance contrast ratio (1 … 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
