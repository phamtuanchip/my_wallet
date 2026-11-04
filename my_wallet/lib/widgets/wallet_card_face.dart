import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../card/card_info.dart';
import '../card/card_theme_art.dart';
import '../card/zodiac.dart';
import 'scheme_badge.dart';
import 'zodiac_mark.dart';

/// Keeps white text readable over bright artwork and the glitter sign.
const List<Shadow> _kTextShadows = [Shadow(color: Color(0x73000000), blurRadius: 4, offset: Offset(0, 1))];

/// The front of a card in the wallet. The top [WalletCardFace.headerHeight]
/// pixels carry the identifying info (name, bank, scheme, last 4) because that
/// is the only part visible while the card sits in the stack.
class WalletCardFace extends StatelessWidget {
  const WalletCardFace({
    super.key,
    required this.title,
    required this.color,
    this.subtitle,
    this.last4,
    this.holder,
    this.expiry,
    this.scheme,
    this.footnote,
    this.elevated = false,
    this.height = 200,
    this.gradientColors,
    this.themeArt,
  });

  static const double headerHeight = 76;

  final String title;
  final String? subtitle;
  final Color color;
  final String? last4;
  final String? holder;
  final String? expiry;
  final CardScheme? scheme;
  final String? footnote;
  final bool elevated;
  final double height;

  /// Multi-colour background (gradient presets); [color] is then its average,
  /// used for the shadow and for the logo's contrast check.
  final List<Color>? gradientColors;

  /// Themed artwork (marble, Đông Sơn drum, seasons…), drawn over everything
  /// else in the background.
  final CardThemeArt? themeArt;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final darker = hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
    final lighter = hsl.withLightness((hsl.lightness + 0.06).clamp(0.0, 1.0)).toColor();
    const tabular = [FontFeature.tabularFigures()];
    final hasScheme = scheme != null && scheme != CardScheme.unknown;
    final expired = expiry != null && isExpired(expiry!);
    final sign = ZodiacSign.fromExpiry(expiry);

    final semantic = [
      title,
      ?subtitle,
      if (hasScheme) scheme!.label,
      if (last4 != null && last4!.isNotEmpty) 'ending $last4',
      if (expired) 'expired',
      if (sign != null) sign.label,
    ].join(', ');

    return Semantics(
      label: semantic,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: gradientColors ?? [lighter, darker],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: (elevated ? color : Colors.black).withValues(alpha: elevated ? 0.40 : 0.16),
              blurRadius: elevated ? 24 : 10,
              offset: Offset(0, elevated ? 10 : 4),
            ),
          ],
        ),
        child: ExcludeSemantics(
          child: Stack(children: [
          if (themeArt != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: RepaintBoundary(child: CustomPaint(painter: CardThemePainter(themeArt!))),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: everything here stays visible in the stack.
                SizedBox(
                  height: headerHeight - 16 - 8,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                shadows: _kTextShadows,
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (subtitle != null || (last4 != null && last4!.isNotEmpty))
                              Text(
                                [
                                  ?subtitle,
                                  if (last4 != null && last4!.isNotEmpty) '•• $last4',
                                ].join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                shadows: _kTextShadows,
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                  fontFeatures: tabular,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      hasScheme
                          ? SchemeBadge(scheme!)
                          : const Icon(LucideIcons.nfc, color: Colors.white60, size: 22),
                    ],
                  ),
                ),
                const Spacer(),
                if (last4 != null && last4!.isNotEmpty) ...[
                  Text(
                    '••••  ••••  ••••  $last4',
                    style: const TextStyle(
                                shadows: _kTextShadows,
                      color: Colors.white,
                      fontSize: 19,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          (holder == null || holder!.isEmpty) ? ' ' : holder!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                                shadows: _kTextShadows,color: Colors.white, fontSize: 12.5, letterSpacing: 1),
                        ),
                      ),
                      if (expiry != null && expiry!.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              expired ? 'EXPIRED' : 'VALID THRU',
                              style: TextStyle(
                                shadows: _kTextShadows,
                                color: expired ? const Color(0xFFFFD1D1) : Colors.white60,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              expiry!,
                              style: const TextStyle(
                                shadows: _kTextShadows,
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFeatures: tabular,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ] else if (footnote != null)
                  Text(footnote!, style: const TextStyle(
                                shadows: _kTextShadows,color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          // Zodiac sign of the expiry month with its English name, small in
          // the corner under the header (the background now carries the theme).
          if (sign != null)
            Positioned(
              right: 18,
              top: headerHeight - 10,
              child: ZodiacBadge(sign: sign, background: color, size: 36, animate: elevated),
            ),
        ]),
        ),
      ),
    );
  }
}
