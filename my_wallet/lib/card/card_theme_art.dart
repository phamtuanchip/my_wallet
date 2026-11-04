import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Themed card backgrounds, drawn in code (no bitmap assets): they stay sharp
/// at any card size, add nothing to the APK and carry no licence questions.
/// Every painter is deterministic (fixed seed), so a card looks the same on
/// every rebuild.
class CardThemeArt {
  const CardThemeArt(this.id, this.name, this.vnName, this.background, this.paint, {this.scrim = false});

  final String id;
  final String name;
  final String vnName;

  /// Base gradient under the artwork.
  final List<Color> background;

  /// Draws the artwork over [background] in a rect of the given size.
  final void Function(Canvas canvas, Size size) paint;

  /// Light artwork: darken behind the white text.
  final bool scrim;

  Color get average {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final c in background) {
      r += c.r;
      g += c.g;
      b += c.b;
    }
    final n = background.length;
    return Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
  }
}

/// Stored in the `color` column as [kThemeBase] + index.
const int kThemeBase = 2000;

int themeValue(int index) => kThemeBase + index;

CardThemeArt? cardThemeFromValue(int value) {
  final i = value - kThemeBase;
  return i >= 0 && i < kCardThemes.length ? kCardThemes[i] : null;
}

final List<CardThemeArt> kCardThemes = [
  const CardThemeArt('marble', 'Black marble', 'Đá cẩm thạch', [Color(0xFF2A2A2C), Color(0xFF161617), Color(0xFF232325)], _marble),
  const CardThemeArt('carbon', 'Carbon', 'Sợi carbon', [Color(0xFF242424), Color(0xFF151515)], _carbon),
  const CardThemeArt('holo', 'Holographic', 'Hologram',
      [Color(0xFF8E9BFF), Color(0xFF8FE3E8), Color(0xFFF7A6C8), Color(0xFFB9F3C7)], _holo,
      scrim: true),
  const CardThemeArt('dongson', 'Dong Son drum', 'Trống đồng', [Color(0xFFB98A43), Color(0xFF7A5220), Color(0xFF4A3012)], _dongSon),
  const CardThemeArt('lotus', 'Lotus', 'Hoa sen', [Color(0xFF145C5E), Color(0xFF0F3D3E), Color(0xFF0A2A2B)], _lotus),
  const CardThemeArt('bamboo', 'Bamboo', 'Tre xanh', [Color(0xFF2F5D31), Color(0xFF1E3B20), Color(0xFF122614)], _bamboo),
  const CardThemeArt('spring', 'Spring blossom', 'Xuân · hoa đào', [Color(0xFFC2385A), Color(0xFF8E1B3A), Color(0xFF5E0E26)], _spring),
  const CardThemeArt('summer', 'Summer sea', 'Hạ · biển', [Color(0xFF1C8DD6), Color(0xFF0E5FA8), Color(0xFF0A3D73)], _summer),
  const CardThemeArt('autumn', 'Autumn leaves', 'Thu · lá phong', [Color(0xFFB5541C), Color(0xFF7A2E0E), Color(0xFF4D1C08)], _autumn),
  const CardThemeArt('winter', 'Winter snow', 'Đông · tuyết', [Color(0xFF1B3A6B), Color(0xFF0B1E3F), Color(0xFF08152D)], _winter),
];

/// Paints a theme (background + artwork) into [rect]; used by the card face,
/// the colour sheet preview and the swatches.
class CardThemePainter extends CustomPainter {
  const CardThemePainter(this.theme);
  final CardThemeArt theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: theme.background,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRect(rect);
    theme.paint(canvas, size);
    canvas.restore();
    if (theme.scrim) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x59000000), Color(0x14000000), Color(0x66000000)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(CardThemePainter old) => old.theme != theme;
}

// ── Helpers ─────────────────────────────────────────────────────────────

double _u(Size s) => s.height / 200; // 1 unit = 1 px on a 200-px-high card

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..isAntiAlias = true;

Paint _fill(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

/// Five-petal blossom.
void _blossom(Canvas c, Offset at, double r, Color petal, Color heart, double turn) {
  for (var i = 0; i < 5; i++) {
    final a = turn + i * 2 * math.pi / 5;
    final p = at + Offset(math.cos(a), math.sin(a)) * r * 0.62;
    c.drawCircle(p, r * 0.5, _fill(petal));
  }
  c.drawCircle(at, r * 0.28, _fill(heart));
}

/// Pointed leaf along [angle].
Path _leaf(Offset base, double length, double width, double angle) {
  final dir = Offset(math.cos(angle), math.sin(angle));
  final normal = Offset(-dir.dy, dir.dx);
  final tip = base + dir * length;
  final mid = base + dir * (length * 0.45);
  return Path()
    ..moveTo(base.dx, base.dy)
    ..quadraticBezierTo((mid + normal * width).dx, (mid + normal * width).dy, tip.dx, tip.dy)
    ..quadraticBezierTo((mid - normal * width).dx, (mid - normal * width).dy, base.dx, base.dy)
    ..close();
}

// ── Themes ──────────────────────────────────────────────────────────────

void _marble(Canvas c, Size s) {
  final rnd = math.Random(11);
  final u = _u(s);
  // Soft clouding.
  for (var i = 0; i < 7; i++) {
    final center = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
    c.drawCircle(
      center,
      (40 + rnd.nextDouble() * 70) * u,
      _fill(const Color(0x14FFFFFF))..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, 30 * u),
    );
  }
  // Veins: long wandering curves, gold and pale grey.
  for (var i = 0; i < 9; i++) {
    final gold = i % 3 != 2;
    final path = Path();
    var p = Offset(-20 * u, rnd.nextDouble() * s.height);
    path.moveTo(p.dx, p.dy);
    while (p.dx < s.width + 20 * u) {
      final next = p + Offset((30 + rnd.nextDouble() * 50) * u, (rnd.nextDouble() - 0.5) * 70 * u);
      final ctrl = Offset((p.dx + next.dx) / 2 + (rnd.nextDouble() - 0.5) * 30 * u, p.dy + (rnd.nextDouble() - 0.5) * 60 * u);
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, next.dx, next.dy);
      p = next;
    }
    final color = gold
        ? Color.fromARGB((120 + rnd.nextInt(100)), 0xD9, 0xB2, 0x5C)
        : Color.fromARGB(60 + rnd.nextInt(50), 0xE8, 0xE8, 0xE8);
    final w = (0.5 + rnd.nextDouble() * (gold ? 2.2 : 1.2)) * u;
    c.drawPath(path, _stroke(color.withValues(alpha: color.a * 0.5), w * 3)..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, 2 * u));
    c.drawPath(path, _stroke(color, w));
  }
}

void _carbon(Canvas c, Size s) {
  final cell = 9 * _u(s);
  for (var y = 0.0, row = 0; y < s.height; y += cell, row++) {
    for (var x = 0.0, col = 0; x < s.width; x += cell, col++) {
      final r = Rect.fromLTWH(x, y, cell, cell);
      final horizontal = (row + col).isEven;
      c.drawRect(
        r.deflate(0.4),
        Paint()
          ..shader = LinearGradient(
            begin: horizontal ? Alignment.topCenter : Alignment.centerLeft,
            end: horizontal ? Alignment.bottomCenter : Alignment.centerRight,
            colors: const [Color(0xFF3C3C3C), Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
          ).createShader(r),
      );
    }
  }
  // Glossy diagonal sheen.
  final rect = Offset.zero & s;
  c.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-1, -1),
        end: Alignment(1, 1),
        colors: [Color(0x00FFFFFF), Color(0x24FFFFFF), Color(0x00FFFFFF)],
        stops: [0.3, 0.45, 0.6],
      ).createShader(rect),
  );
}

void _holo(Canvas c, Size s) {
  final rect = Offset.zero & s;
  final u = _u(s);
  c.drawRect(
    rect,
    Paint()
      ..blendMode = BlendMode.softLight
      ..shader = SweepGradient(
        center: const Alignment(0.6, -0.4),
        colors: const [
          Color(0xFFFF9AD5), Color(0xFF9AE6FF), Color(0xFFB9FF9A), Color(0xFFFFF59A), Color(0xFFD29AFF), Color(0xFFFF9AD5),
        ],
      ).createShader(rect),
  );
  // Diagonal light streaks.
  for (var i = 0; i < 6; i++) {
    final x = (i * 0.22 - 0.2) * s.width;
    final band = Path()
      ..moveTo(x, 0)
      ..lineTo(x + 22 * u, 0)
      ..lineTo(x - 60 * u + 22 * u, s.height)
      ..lineTo(x - 60 * u, s.height)
      ..close();
    c.drawPath(band, _fill(Color.fromARGB(i.isEven ? 46 : 26, 255, 255, 255)));
  }
  // Fine diffraction lines.
  for (var y = 0.0; y < s.height; y += 3 * u) {
    c.drawLine(Offset(0, y), Offset(s.width, y + 8 * u), _stroke(const Color(0x10FFFFFF), 0.6 * u));
  }
}

void _dongSon(Canvas c, Size s) {
  final u = _u(s);
  final center = Offset(s.width / 2, s.height / 2);
  final dark = const Color(0x8C3A240C);
  final light = const Color(0x59F0CF8A);
  // Sun star with 14 rays.
  final star = Path();
  const rays = 14;
  for (var i = 0; i < rays * 2; i++) {
    final r = (i.isEven ? 34 : 12) * u;
    final a = i * math.pi / rays - math.pi / 2;
    final p = center + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
  }
  star.close();
  c.drawPath(star, _fill(light));
  c.drawPath(star, _stroke(dark, 1.2 * u));

  // Concentric bands, each with its own motif.
  final bands = [44.0, 58, 74, 96, 118, 142, 170, 200];
  for (final r in bands) {
    c.drawCircle(center, r * u, _stroke(dark, 1.4 * u));
    c.drawCircle(center, (r + 2.5) * u, _stroke(light, 0.8 * u));
  }
  void around(double radius, int count, void Function(Offset p, double angle) draw) {
    for (var i = 0; i < count; i++) {
      final a = i * 2 * math.pi / count;
      draw(center + Offset(math.cos(a), math.sin(a)) * radius * u, a);
    }
  }

  // Small circles with dots.
  around(51, 22, (p, _) {
    c.drawCircle(p, 3.6 * u, _stroke(dark, 1 * u));
    c.drawCircle(p, 1 * u, _fill(dark));
  });
  // Hatching ticks.
  around(66, 64, (p, a) {
    final d = Offset(math.cos(a), math.sin(a)) * 5 * u;
    c.drawLine(p - d, p + d, _stroke(dark, 1 * u));
  });
  // Flying birds (chevrons) along the wide band.
  around(85, 18, (p, a) {
    final t = Offset(-math.sin(a), math.cos(a)); // tangent
    final n = Offset(math.cos(a), math.sin(a));
    final bird = Path()
      ..moveTo((p - t * 7 * u + n * 3 * u).dx, (p - t * 7 * u + n * 3 * u).dy)
      ..lineTo(p.dx, p.dy)
      ..lineTo((p + t * 2 * u - n * 6 * u).dx, (p + t * 2 * u - n * 6 * u).dy);
    c.drawPath(bird, _stroke(dark, 1.6 * u));
  });
  // Zigzag band.
  final zig = Path();
  const zigCount = 70;
  for (var i = 0; i <= zigCount; i++) {
    final a = i * 2 * math.pi / zigCount;
    final r = (i.isEven ? 100 : 114) * u;
    final p = center + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? zig.moveTo(p.dx, p.dy) : zig.lineTo(p.dx, p.dy);
  }
  c.drawPath(zig, _stroke(dark, 1.1 * u));
  // Outer dotted rings.
  around(130, 90, (p, _) => c.drawCircle(p, 1.4 * u, _fill(dark)));
  around(156, 110, (p, _) => c.drawCircle(p, 1.4 * u, _fill(light)));
}

void _lotus(Canvas c, Size s) {
  final u = _u(s);
  // Lily pads.
  void pad(Offset at, double r, double notch) {
    final path = Path()
      ..moveTo(at.dx, at.dy)
      ..arcTo(Rect.fromCircle(center: at, radius: r), notch + 0.25, 2 * math.pi - 0.5, false)
      ..close();
    c.drawPath(path, _fill(const Color(0xB32E7D5B)));
    for (var i = 0; i < 9; i++) {
      final a = notch + 0.5 + i * (2 * math.pi - 1) / 8;
      c.drawLine(at, at + Offset(math.cos(a), math.sin(a)) * r * 0.92, _stroke(const Color(0x664FB286), 1 * u));
    }
  }

  pad(Offset(s.width * 0.12, s.height * 0.86), 46 * u, -0.6);
  pad(Offset(s.width * 0.92, s.height * 0.95), 54 * u, 3.6);
  pad(Offset(s.width * 0.62, s.height * 1.02), 30 * u, 4.2);

  // Lotus flowers: layered teardrop petals around a base point.
  void flower(Offset base, double size, double alpha) {
    const petals = [(-1.15, 0.78), (1.15, 0.78), (-0.7, 0.92), (0.7, 0.92), (-0.3, 1.0), (0.3, 1.0), (0.0, 1.06)];
    for (final (angle, len) in petals) {
      final a = -math.pi / 2 + angle;
      final petal = _leaf(base, size * len, size * 0.24, a);
      final r = petal.getBounds();
      c.drawPath(
        petal,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color.fromRGBO(210, 85, 126, alpha), Color.fromRGBO(255, 205, 225, alpha)],
          ).createShader(r),
      );
      c.drawPath(petal, _stroke(Color.fromRGBO(255, 230, 240, alpha * 0.6), 0.8 * u));
    }
    c.drawCircle(base + Offset(0, -size * 0.12), size * 0.09, _fill(Color.fromRGBO(255, 214, 102, alpha)));
  }

  flower(Offset(s.width * 0.82, s.height * 0.78), 62 * u, 0.92);
  flower(Offset(s.width * 0.2, s.height * 0.72), 40 * u, 0.75);
  // Stem bud.
  final stem = Path()
    ..moveTo(s.width * 0.48, s.height * 1.05)
    ..quadraticBezierTo(s.width * 0.5, s.height * 0.7, s.width * 0.45, s.height * 0.5);
  c.drawPath(stem, _stroke(const Color(0x994FB286), 2 * u));
  c.drawPath(_leaf(Offset(s.width * 0.45, s.height * 0.52), 24 * u, 7 * u, -math.pi / 2 - 0.15),
      _fill(const Color(0xCCF29CBE)));
}

void _bamboo(Canvas c, Size s) {
  final u = _u(s);
  final rnd = math.Random(5);
  final stalks = [0.08, 0.2, 0.74, 0.88, 0.97];
  for (var i = 0; i < stalks.length; i++) {
    final x = s.width * stalks[i];
    final w = (9 + rnd.nextDouble() * 6) * u;
    final tilt = (rnd.nextDouble() - 0.5) * 0.08;
    c.save();
    c.translate(x, s.height);
    c.rotate(tilt);
    final alpha = i.isEven ? 0.85 : 0.6;
    final rect = Rect.fromLTWH(-w / 2, -s.height * 1.2, w, s.height * 1.2);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w / 2)),
      Paint()
        ..shader = LinearGradient(colors: [
          Color.fromRGBO(70, 140, 70, alpha),
          Color.fromRGBO(140, 200, 110, alpha),
          Color.fromRGBO(60, 120, 60, alpha),
        ]).createShader(rect),
    );
    // Nodes.
    for (var y = -18.0 * u - rnd.nextDouble() * 20 * u; y > -s.height * 1.2; y -= (38 + rnd.nextDouble() * 14) * u) {
      c.drawLine(Offset(-w / 2, y), Offset(w / 2, y), _stroke(Color.fromRGBO(30, 70, 30, alpha), 2 * u));
      c.drawLine(Offset(-w / 2, y - 2 * u), Offset(w / 2, y - 2 * u), _stroke(Color.fromRGBO(190, 230, 150, alpha * 0.5), 1 * u));
    }
    c.restore();
  }
  // Leaf sprays.
  void spray(Offset at, double dir) {
    for (var k = 0; k < 5; k++) {
      final a = dir + (k - 2) * 0.32;
      c.drawPath(_leaf(at, (34 + rnd.nextDouble() * 16) * u, 6 * u, a), _fill(Color.fromRGBO(120, 190, 100, 0.75 - k * 0.06)));
    }
  }

  spray(Offset(s.width * 0.2, s.height * 0.3), -0.3);
  spray(Offset(s.width * 0.76, s.height * 0.18), math.pi + 0.3);
  spray(Offset(s.width * 0.9, s.height * 0.62), math.pi + 0.1);
  spray(Offset(s.width * 0.08, s.height * 0.7), 0.1);
}

void _spring(Canvas c, Size s) {
  final u = _u(s);
  // Mirrored: the branch comes in from the top-right, away from the card title.
  c.translate(s.width, 0);
  c.scale(-1, 1);
  final rnd = math.Random(3);
  // A plum/peach branch from the top-left.
  final branch = Path()
    ..moveTo(-10 * u, s.height * 0.12)
    ..cubicTo(s.width * 0.2, s.height * 0.05, s.width * 0.35, s.height * 0.35, s.width * 0.62, s.height * 0.22)
    ..cubicTo(s.width * 0.75, s.height * 0.16, s.width * 0.85, s.height * 0.3, s.width * 1.05, s.height * 0.18);
  c.drawPath(branch, _stroke(const Color(0xE63B1A12), 5 * u));
  final twig1 = Path()
    ..moveTo(s.width * 0.3, s.height * 0.2)
    ..quadraticBezierTo(s.width * 0.34, s.height * 0.45, s.width * 0.22, s.height * 0.58);
  final twig2 = Path()
    ..moveTo(s.width * 0.7, s.height * 0.2)
    ..quadraticBezierTo(s.width * 0.78, s.height * 0.5, s.width * 0.92, s.height * 0.55);
  for (final t in [twig1, twig2]) {
    c.drawPath(t, _stroke(const Color(0xCC3B1A12), 2.5 * u));
  }
  // Blossoms along the branch and twigs.
  for (final path in [branch, twig1, twig2]) {
    for (final metric in path.computeMetrics()) {
      for (var d = 12 * u; d < metric.length; d += (16 + rnd.nextDouble() * 22) * u) {
        final tangent = metric.getTangentForOffset(d)!;
        final off = Offset((rnd.nextDouble() - 0.5) * 14 * u, (rnd.nextDouble() - 0.5) * 14 * u);
        final r = (6 + rnd.nextDouble() * 6) * u;
        final white = rnd.nextDouble() < 0.3;
        _blossom(c, tangent.position + off, r, white ? const Color(0xF2FFF1F5) : const Color(0xE6FFB3CB),
            const Color(0xFFE8A33D), rnd.nextDouble() * math.pi);
      }
    }
  }
  // Falling petals.
  for (var i = 0; i < 16; i++) {
    final p = Offset(rnd.nextDouble() * s.width, s.height * (0.45 + rnd.nextDouble() * 0.55));
    c.drawOval(Rect.fromCenter(center: p, width: 5 * u, height: 3 * u), _fill(const Color(0x99FFC9DA)));
  }
}

void _summer(Canvas c, Size s) {
  final u = _u(s);
  // Sun with glow.
  final sun = Offset(s.width * 0.82, s.height * 0.24);
  c.drawCircle(sun, 46 * u, _fill(const Color(0x33FFD36E))..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, 18 * u));
  c.drawCircle(sun, 22 * u, _fill(const Color(0xE6FFD36E)));
  // Layered waves.
  final layers = [
    (0.58, 10.0, const Color(0x5590D8FF)),
    (0.68, 12.0, const Color(0x7756B8F0)),
    (0.78, 9.0, const Color(0x99308FD6)),
    (0.88, 11.0, const Color(0xCC1567B0)),
  ];
  for (var li = 0; li < layers.length; li++) {
    final (level, amp, color) = layers[li];
    final path = Path()..moveTo(0, s.height);
    final phase = li * 1.3;
    for (var x = 0.0; x <= s.width + 1; x += 4 * u) {
      final y = s.height * level + math.sin(x / (34 * u) + phase) * amp * u + math.sin(x / (13 * u) + phase * 2) * 2 * u;
      path.lineTo(x, y);
    }
    path
      ..lineTo(s.width, s.height)
      ..close();
    c.drawPath(path, _fill(color));
    // Foam line on the crest.
    final crest = Path();
    for (var x = 0.0; x <= s.width + 1; x += 4 * u) {
      final y = s.height * level + math.sin(x / (34 * u) + phase) * amp * u + math.sin(x / (13 * u) + phase * 2) * 2 * u;
      x == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
    }
    c.drawPath(crest, _stroke(const Color(0x66FFFFFF), 1.2 * u));
  }
}

void _autumn(Canvas c, Size s) {
  final u = _u(s);
  final rnd = math.Random(8);
  const colors = [Color(0xD9FF8A3D), Color(0xD9E0442B), Color(0xD9FFC24A), Color(0xB3A8321C)];
  void maple(Offset at, double r, double rot, Color color) {
    // 5-lobed leaf from three overlapping pointed leaves + stem.
    for (final a in [-1.1, -0.55, 0.0, 0.55, 1.1]) {
      final len = r * (a == 0 ? 1.0 : (a.abs() < 0.6 ? 0.85 : 0.6));
      c.drawPath(_leaf(at, len, r * 0.26, rot - math.pi / 2 + a), _fill(color));
    }
    final stemEnd = at + Offset(math.cos(rot + math.pi / 2), math.sin(rot + math.pi / 2)) * r * 0.45;
    c.drawLine(at, stemEnd, _stroke(color, 1.4 * u));
  }

  for (var i = 0; i < 22; i++) {
    final at = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
    maple(at, (10 + rnd.nextDouble() * 18) * u, rnd.nextDouble() * 2 * math.pi, colors[rnd.nextInt(colors.length)]);
  }
}

void _winter(Canvas c, Size s) {
  final u = _u(s);
  final rnd = math.Random(4);
  // Snowy hills.
  final hill = Path()
    ..moveTo(0, s.height)
    ..lineTo(0, s.height * 0.82)
    ..quadraticBezierTo(s.width * 0.3, s.height * 0.68, s.width * 0.55, s.height * 0.84)
    ..quadraticBezierTo(s.width * 0.8, s.height * 0.72, s.width, s.height * 0.8)
    ..lineTo(s.width, s.height)
    ..close();
  c.drawPath(hill, _fill(const Color(0x33FFFFFF)));
  // Snowflakes.
  void flake(Offset at, double r, double alpha) {
    final p = _stroke(Color.fromRGBO(255, 255, 255, alpha), math.max(0.8, r / 9) * u);
    for (var k = 0; k < 6; k++) {
      final a = k * math.pi / 3;
      final d = Offset(math.cos(a), math.sin(a));
      final end = at + d * r * u;
      c.drawLine(at, end, p);
      final mid = at + d * r * 0.55 * u;
      for (final side in [-0.6, 0.6]) {
        final b = Offset(math.cos(a + side), math.sin(a + side));
        c.drawLine(mid, mid + b * r * 0.32 * u, p);
      }
    }
  }

  for (var i = 0; i < 12; i++) {
    flake(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * 0.85), 5 + rnd.nextDouble() * 12,
        0.35 + rnd.nextDouble() * 0.5);
  }
  for (var i = 0; i < 70; i++) {
    c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height), (0.6 + rnd.nextDouble() * 1.6) * u,
        _fill(Color.fromRGBO(255, 255, 255, 0.25 + rnd.nextDouble() * 0.5)));
  }
}
