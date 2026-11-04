import 'dart:math';

import 'package:flutter/painting.dart';

import 'card_theme_art.dart';

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

/// A multi-colour card background.
class CardGradient {
  const CardGradient(this.name, this.colors);
  final String name;
  final List<Color> colors;

  /// Representative single colour (shadows, contrast checks, hue spreading).
  Color get average {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final c in colors) {
      r += c.r;
      g += c.g;
      b += c.b;
    }
    final n = colors.length;
    return Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
  }
}

/// Gradient presets. Stored in the `color` column as [kGradientBase] + index,
/// a range that can't clash with preset indexes (0..7) or ARGB values (≥ 0xFF000000).
const int kGradientBase = 1000;
const List<CardGradient> kCardGradients = [
  CardGradient('Sunset', [Color(0xFFFF7E5F), Color(0xFFD9467A), Color(0xFF6A3093)]),
  CardGradient('Ocean', [Color(0xFF2BC0E4), Color(0xFF1A73C9), Color(0xFF1B2A6B)]),
  CardGradient('Aurora', [Color(0xFF43E97B), Color(0xFF1FA2A6), Color(0xFF3A3F9E)]),
  CardGradient('Rose gold', [Color(0xFFF4C4B5), Color(0xFFD08C7C), Color(0xFF8E4E5A)]),
  CardGradient('Royal', [Color(0xFF5B2A86), Color(0xFF2E1A6E), Color(0xFF0F0C29)]),
  CardGradient('Emerald', [Color(0xFF56AB2F), Color(0xFF1E7A4C), Color(0xFF0B3D2E)]),
  CardGradient('Fire', [Color(0xFFF9D423), Color(0xFFF26B21), Color(0xFFB0182A)]),
  CardGradient('Midnight', [Color(0xFF434343), Color(0xFF232526), Color(0xFF000000)]),
  CardGradient('Peach', [Color(0xFFFFD3A5), Color(0xFFFD9F8B), Color(0xFFC36A8E)]),
  CardGradient('Galaxy', [Color(0xFFDA22FF), Color(0xFF7A2BD6), Color(0xFF1E1A5A)]),
];

int gradientValue(int index) => kGradientBase + index;

/// The gradient for a stored value, or null for a solid colour.
CardGradient? cardGradientFromValue(int value) {
  final i = value - kGradientBase;
  return i >= 0 && i < kCardGradients.length ? kCardGradients[i] : null;
}

Color cardColorFromValue(int value) {
  if (value >= 0 && value < kCardColors.length) return kCardColors[value];
  final gradient = cardGradientFromValue(value);
  if (gradient != null) return gradient.average;
  final theme = cardThemeFromValue(value);
  if (theme != null) return theme.average;
  return Color(value);
}

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
