import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_drawing/path_drawing.dart';

import '../card/zodiac.dart';
import 'tilt_light.dart';

/// Bright glitter gold, sampled from the reference: honey → lemon → cream.
const List<Color> kZodiacGold = [
  Color(0xFFB8792F),
  Color(0xFFDDA541),
  Color(0xFFEBB946),
  Color(0xFFF7D15B),
  Color(0xFFFCEE8E),
  Color(0xFFFFF8D6),
  Color(0xFFF7D15B),
  Color(0xFFCD973D),
];

/// Glyph outlines (24 × 24 units) parsed once from the bundled Tabler SVGs.
class ZodiacGlyphs {
  ZodiacGlyphs._();
  static final Map<ZodiacSign, Future<Path>> _cache = {};
  static final Map<ZodiacSign, Path> _ready = {};

  /// Already-parsed glyph, so a card can draw it in its first frame.
  static Path? cached(ZodiacSign sign) => _ready[sign];

  /// Parse all 12 glyphs in the background (called at app start).
  static Future<void> preload() => Future.wait(ZodiacSign.values.map(load));
  static final RegExp _path = RegExp(r'<path\b([^>]*)>');
  static final RegExp _d = RegExp(r'\bd="([^"]+)"');

  static Future<Path> load(ZodiacSign sign) => _cache[sign] ??= () async {
        final svg = await rootBundle.loadString(sign.asset);
        final out = Path();
        for (final m in _path.allMatches(svg)) {
          final attrs = m.group(1)!;
          if (attrs.contains('stroke="none"')) continue; // the invisible 24×24 frame
          final d = _d.firstMatch(attrs)?.group(1);
          if (d != null) out.addPath(parseSvgPathData(d), Offset.zero);
        }
        return _ready[sign] = out;
      }();
}

/// A zodiac sign in sparkling glitter gold: gold strokes covered in grains of
/// glitter, soft glow and bokeh, and star flares that twinkle when [animate]
/// is on (off when the system asks for reduced motion).
class ZodiacMark extends StatefulWidget {
  const ZodiacMark({
    super.key,
    required this.sign,
    required this.background,
    this.size = 40,
    this.animate = false,
    this.opacity = 1,
  });

  final ZodiacSign sign;
  final Color background;
  final double size;
  final bool animate;
  final double opacity;

  @override
  State<ZodiacMark> createState() => _ZodiacMarkState();
}

class _ZodiacMarkState extends State<ZodiacMark> with SingleTickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late Future<Path> _glyph = ZodiacGlyphs.load(widget.sign);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ZodiacMark old) {
    super.didUpdateWidget(old);
    if (old.sign != widget.sign) _glyph = ZodiacGlyphs.load(widget.sign);
    _sync();
  }

  bool _tilting = false;

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final on = widget.animate && !reduce;
    if (on) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock
        ..stop()
        ..value = 0;
    }
    if (on != _tilting) {
      _tilting = on;
      on ? TiltLight.instance.acquire() : TiltLight.instance.release();
    }
  }

  @override
  void dispose() {
    if (_tilting) TiltLight.instance.release();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.sign.label} (${widget.sign.vnLabel})',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder<Path>(
          future: _glyph,
          initialData: ZodiacGlyphs.cached(widget.sign),
          builder: (context, snap) {
            final glyph = snap.data;
            if (glyph == null) return const SizedBox.shrink();
            return RepaintBoundary(
              child: CustomPaint(
                painter: GlitterGlyphPainter(
                  glyph: glyph,
                  seed: widget.sign.index,
                  clock: _clock,
                  light: TiltLight.instance,
                  animated: widget.animate,
                  opacity: widget.opacity,
                  darkRim: contrastRatio(kZodiacGold[4], widget.background) < 1.8,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Grain {
  const _Grain(this.offset, this.kind, this.phase);
  final Offset offset;
  final int kind; // 0 dark, 1 mid, 2 bright, 3 twinkling
  final double phase;
}

/// Paints [glyph] (24-unit space) scaled to the canvas as glitter gold.
class GlitterGlyphPainter extends CustomPainter {
  GlitterGlyphPainter({
    required this.glyph,
    required this.seed,
    required this.clock,
    required this.animated,
    this.opacity = 1,
    this.darkRim = false,
    this.light,
  }) : super(repaint: light == null ? clock : Listenable.merge([clock, light]));

  /// Phone tilt → where the reflection falls. Without the sensor the light
  /// sweeps across on its own every cycle of [clock].
  final TiltLight? light;

  /// Reflection position along the top-left → bottom-right diagonal (0…1),
  /// or null when no light is on the glyph.
  double? _band(double t) {
    if (!animated) return null;
    final l = light;
    if (l != null && l.available) return (l.value + 1) / 2;
    return t < 0.45 ? -0.2 + 1.4 * (t / 0.45) : null;
  }

  final Path glyph;
  final int seed;
  final Animation<double> clock;
  final bool animated;
  final double opacity;
  final bool darkRim;

  Size? _cachedFor;
  late Path _path;
  late List<_Grain> _grains;
  late List<Offset> _stars;
  late List<(Offset, double)> _bokeh;

  static const double _strokeUnits = 2.4;

  void _prepare(Size size) {
    if (_cachedFor == size) return;
    _cachedFor = size;
    final s = size.shortestSide / 24;
    _path = glyph.transform((Matrix4.identity()..scaleByDouble(s, s, 1, 1)).storage);
    final w = _strokeUnits * s;
    final rnd = math.Random(seed * 7919 + 17);

    // Glitter grains sampled along the strokes, spread across their width.
    final grains = <_Grain>[];
    final step = math.max(0.35, w / 7);
    var total = 0.0;
    for (final metric in _path.computeMetrics()) {
      total += metric.length;
      for (var d = 0.0; d < metric.length; d += step) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        final normal = Offset(-t.vector.dy, t.vector.dx);
        final across = (rnd.nextDouble() - 0.5) * w * 1.05;
        final along = (rnd.nextDouble() - 0.5) * step;
        final r = rnd.nextDouble();
        grains.add(_Grain(
          t.position + normal * across + t.vector * along,
          r < 0.42 ? 0 : (r < 0.74 ? 1 : (r < 0.92 ? 2 : 3)),
          rnd.nextDouble(),
        ));
      }
    }
    _grains = grains;

    // Star flares at spread-out points of the glyph.
    _stars = [];
    final fractions = [0.1, 0.38, 0.63, 0.88];
    var target = 0;
    var walked = 0.0;
    for (final metric in _path.computeMetrics()) {
      while (target < fractions.length && fractions[target] * total <= walked + metric.length) {
        final pos = metric.getTangentForOffset(fractions[target] * total - walked)?.position;
        if (pos != null) _stars.add(pos);
        target++;
      }
      walked += metric.length;
    }

    // Soft bokeh around the glyph (only noticeable when large).
    _bokeh = [
      for (var i = 0; i < 6; i++)
        (
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
          size.shortestSide * (0.05 + rnd.nextDouble() * 0.08),
        ),
    ];
  }

  Color _a(Color c, double alpha) => c.withValues(alpha: (c.a * alpha * opacity).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    _prepare(size);
    final s = size.shortestSide / 24;
    final w = _strokeUnits * s;
    final t = animated ? clock.value : 0.0;
    final rect = Offset.zero & size;

    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Bokeh.
    if (size.shortestSide > 60) {
      for (final (c, r) in _bokeh) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = _a(const Color(0xFFFFE9A8), 0.16)
            ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, r * 0.5),
        );
      }
    }

    // Warm glow, plus a dark rim when the card itself is light/gold.
    if (darkRim) {
      canvas.drawPath(
          _path,
          stroke(w * 1.5)
            ..color = _a(const Color(0xFF3A2400), 0.55)
            ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, w * 0.35));
    }
    canvas.drawPath(
        _path,
        stroke(w * 2.4)
          ..color = _a(const Color(0xFFFFD86B), 0.45)
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, w * 0.9));

    // Gold body.
    canvas.drawPath(
      _path,
      stroke(w)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [for (final c in kZodiacGold) _a(c, 1)],
        ).createShader(rect),
    );

    // Glitter grains: dark specks for depth, mid and bright flecks, and a set
    // that twinkles in four phase groups.
    final grain = math.max(0.9, w * 0.16);
    final buckets = List.generate(7, (_) => <Offset>[]);
    for (final g in _grains) {
      if (g.kind < 3) {
        buckets[g.kind].add(g.offset);
      } else {
        buckets[3 + (g.phase * 4).floor().clamp(0, 3)].add(g.offset);
      }
    }
    void dots(List<Offset> pts, Color color, double width) {
      if (pts.isEmpty) return;
      canvas.drawPoints(
        ui.PointMode.points,
        pts,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    dots(buckets[0], _a(const Color(0xFF9A6420), 0.75), grain);
    dots(buckets[1], _a(const Color(0xFFFCEE8E), 0.9), grain);
    dots(buckets[2], _a(const Color(0xFFFFFDF2), 0.95), grain * 0.85);
    for (var k = 0; k < 4; k++) {
      final phase = k / 4;
      final level = animated ? (0.5 + 0.5 * math.sin(2 * math.pi * (t + phase))) : (k.isEven ? 0.9 : 0.4);
      dots(buckets[3 + k], _a(Colors.white, 0.25 + 0.75 * level), grain * (0.9 + 0.8 * level));
    }

    // Specular reflection: a bright band across the gold where the light falls,
    // and the glitter inside it flashing.
    final band = _band(t);
    double along(Offset p) => (p.dx / size.width + p.dy / size.height) / 2;
    if (band != null && band > -0.25 && band < 1.25) {
      double c(double v) => v.clamp(0.0, 1.0);
      canvas.drawPath(
        _path,
        stroke(w * 1.04)
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0x00FFFFFF),
              _a(const Color(0xFFFFF4C2), 0.45),
              _a(Colors.white, 0.95),
              _a(const Color(0xFFFFF4C2), 0.55),
              const Color(0x00FFFFFF),
            ],
            stops: [c(band - 0.17), c(band - 0.05), c(band), c(band + 0.04), c(band + 0.15)],
          ).createShader(rect),
      );
      final glints = <Offset>[];
      for (final g in _grains) {
        if (g.kind >= 1 && (along(g.offset) - band).abs() < 0.07) glints.add(g.offset);
      }
      dots(glints, _a(Colors.white, 1), grain * 1.7);
    }

    // Star flares: they light up as the reflection passes over them.
    for (var i = 0; i < _stars.length; i++) {
      final twinkle = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 1.0 + i * 0.29));
      final k = !animated
          ? (i.isEven ? 0.95 : 0.55)
          : band == null
              ? twinkle * 0.45
              : math.max(twinkle * 0.35, 1 - ((along(_stars[i]) - band).abs() / 0.14).clamp(0.0, 1.0));
      if (k < 0.08) continue;
      _flare(canvas, _stars[i], size.shortestSide, k, (animated ? t * 0.5 : 0) + i * 0.35);
    }
  }

  /// A starburst: bright core, 4 long tapered rays and 4 short diagonal ones.
  void _flare(Canvas canvas, Offset c, double extent, double k, double rotation) {
    final long = extent * 0.34 * (0.55 + 0.45 * k);
    final short = long * 0.42;
    final width = math.max(0.9, extent * 0.021);
    for (var i = 0; i < 8; i++) {
      final a = rotation + i * math.pi / 4;
      final len = i.isEven ? long : short;
      final dir = Offset(math.cos(a), math.sin(a));
      final normal = Offset(-dir.dy, dir.dx) * (width * (i.isEven ? 1 : 0.7));
      final tip = c + dir * len;
      final ray = Path()
        ..moveTo((c + normal).dx, (c + normal).dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo((c - normal).dx, (c - normal).dy)
        ..close();
      canvas.drawPath(
        ray,
        Paint()
          ..shader = ui.Gradient.linear(c, tip, [
            _a(Colors.white, k),
            _a(const Color(0xFFFFF0A8), 0.7 * k),
            _a(const Color(0x00FFE07A), 0),
          ], [0, 0.35, 1]),
      );
    }
    final core = extent * 0.07 * (0.6 + 0.4 * k);
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = ui.Gradient.radial(c, core, [
          _a(Colors.white, k),
          _a(const Color(0xFFFFE27A), 0.8 * k),
          _a(const Color(0x00FFE27A), 0),
        ], [0, 0.4, 1]),
    );
  }

  @override
  bool shouldRepaint(GlitterGlyphPainter old) =>
      old.glyph != glyph || old.opacity != opacity || old.darkRim != darkRim || old.animated != animated;
}

/// The corner badge on a card: the glitter sign with its English name below
/// in gold capitals.
class ZodiacBadge extends StatelessWidget {
  const ZodiacBadge({super.key, required this.sign, required this.background, this.size = 36, this.animate = false});

  final ZodiacSign sign;
  final Color background;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final fontSize = math.max(7.5, size * 0.24);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZodiacMark(sign: sign, background: background, size: size, animate: animate),
        const SizedBox(height: 1),
        ExcludeSemantics(
          child: Text(
            sign.label.toUpperCase(),
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: fontSize * 0.14,
              height: 1.1,
              foreground: Paint()
                ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFF8D6), Color(0xFFF7D15B), Color(0xFFDDA541), Color(0xFFB8792F)],
                ).createShader(Rect.fromLTWH(0, 0, size * 2, fontSize * 1.1)),
              shadows: const [Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
          ),
        ),
      ],
    );
  }
}
