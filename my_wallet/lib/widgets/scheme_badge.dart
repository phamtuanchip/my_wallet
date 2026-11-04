import 'package:flutter/material.dart';

import '../card/card_info.dart';

/// Small brand mark for a card scheme, drawn with plain widgets (no image assets).
class SchemeBadge extends StatelessWidget {
  const SchemeBadge(this.scheme, {super.key, this.color = Colors.white, this.size = 22});

  final CardScheme scheme;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    TextStyle style({FontStyle fontStyle = FontStyle.normal, double scale = 1}) => TextStyle(
          color: color,
          fontSize: size * scale,
          fontWeight: FontWeight.w900,
          fontStyle: fontStyle,
          letterSpacing: 0.5,
          height: 1,
        );

    final Widget badge = switch (scheme) {
      CardScheme.visa => Text('VISA', style: style(fontStyle: FontStyle.italic)),
      CardScheme.mastercard => SizedBox(
          width: size * 1.7,
          height: size * 1.1,
          child: Stack(children: [
            Positioned(left: 0, child: _dot(const Color(0xFFEB001B))),
            Positioned(right: 0, child: _dot(const Color(0xFFF79E1B).withValues(alpha: 0.9))),
          ]),
        ),
      CardScheme.jcb => Text('JCB', style: style()),
      CardScheme.amex => Text('AMEX', style: style(scale: 0.8)),
      CardScheme.napas => Text('napas', style: style(scale: 0.85)),
      CardScheme.unionpay => Text('UnionPay', style: style(scale: 0.7)),
      CardScheme.discover => Text('DISCOVER', style: style(scale: 0.6)),
      CardScheme.diners => Text('Diners', style: style(scale: 0.75)),
      CardScheme.unknown => const SizedBox.shrink(),
    };
    return Semantics(label: scheme == CardScheme.unknown ? null : scheme.label, child: ExcludeSemantics(child: badge));
  }

  Widget _dot(Color c) => Container(
        width: size * 1.1,
        height: size * 1.1,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}
