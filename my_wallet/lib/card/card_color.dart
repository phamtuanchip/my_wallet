import 'dart:math';

import 'package:flutter/painting.dart';

/// Preset swatches offered in the card sheet. The `color` DB column stores
/// either an index into this list (legacy, 0..7) or a full ARGB value.
const List<Color> kCardColors = [
  Color(0xFFE05252), // Coral Red
  Color(0xFFE8677A), // Pink
  Color(0xFFE5844A), // Orange
  Color(0xFFD4A837), // Amber
  Color(0xFF4CAF7D), // Green
  Color(0xFF4A90D9), // Blue
  Color(0xFF7B68D9), // Purple
  Color(0xFF2C2C2E), // Dark (default)
];

Color cardColorFromValue(int value) =>
    (value >= 0 && value < kCardColors.length) ? kCardColors[value] : Color(value);

double _hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// Picks a random, saturated card colour whose hue is as far as possible from
/// every colour already in use, so a new card never repeats an existing one.
/// Returns an opaque ARGB value (always > the preset index range).
int pickDistinctCardColor(Iterable<int> usedValues, {Random? random}) {
  final rnd = random ?? Random();
  final used = usedValues.map(cardColorFromValue).toList();
  final usedHues = used
      .map(HSLColor.fromColor)
      .where((h) => h.saturation > 0.15) // greys/black don't occupy a hue
      .map((h) => h.hue)
      .toList();
  final usedArgb = used.map((c) => c.toARGB32()).toSet();

  int? best;
  var bestScore = -1.0;
  for (var i = 0; i < 64; i++) {
    final color = HSLColor.fromAHSL(
      1,
      rnd.nextDouble() * 360,
      0.55 + rnd.nextDouble() * 0.2,
      0.42 + rnd.nextDouble() * 0.1,
    ).toColor();
    final argb = color.toARGB32();
    if (usedArgb.contains(argb)) continue;
    final hue = HSLColor.fromColor(color).hue;
    final score = usedHues.isEmpty
        ? 360.0
        : usedHues.map((h) => _hueDistance(h, hue)).reduce(min);
    if (score > bestScore) {
      bestScore = score;
      best = argb;
    }
  }
  return best ?? (0xFF000000 | rnd.nextInt(0xFFFFFF));
}
