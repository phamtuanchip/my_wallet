import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Google Wallet–style card stack.
///
/// * Collapsed: cards overlap vertically and each shows a [peek]-high header
///   strip (name, bank, last 4), which is a comfortable tap target.
/// * Tap a card: it slides to the top and opens fully; the other cards drop
///   into a short pile underneath.
/// * Tap the open card again: [onOpen] (details / actions).
///   Tap the pile, or press Back: collapse to the full stack.
class WalletCardStack<T> extends StatefulWidget {
  const WalletCardStack({
    super.key,
    required this.items,
    required this.idOf,
    required this.faceBuilder,
    required this.onOpen,
    this.cardHeight = 200,
    this.peek = 76,
  });

  final List<T> items;
  final Object Function(T item) idOf;
  final Widget Function(BuildContext context, T item, bool focused) faceBuilder;
  final ValueChanged<T> onOpen;
  final double cardHeight;
  final double peek;

  @override
  State<WalletCardStack<T>> createState() => _WalletCardStackState<T>();
}

class _WalletCardStackState<T> extends State<WalletCardStack<T>> {
  static const _duration = Duration(milliseconds: 380);
  static const _curve = Curves.easeOutCubic;
  static const _pileGap = 20.0; // space between the open card and the pile
  static const _pileStep = 12.0; // visible edge of each card in the pile
  static const _pileMax = 4; // deeper cards hide under the last visible one
  static const _pileTail = 56.0; // how much of the last pile card shows

  Object? _focusedId;

  int get _focusedIndex =>
      _focusedId == null ? -1 : widget.items.indexWhere((e) => widget.idOf(e) == _focusedId);

  void _tap(T item) {
    HapticFeedback.selectionClick();
    final id = widget.idOf(item);
    if (widget.items.length == 1 || _focusedId == id) {
      widget.onOpen(item);
      return;
    }
    setState(() => _focusedId = _focusedId == null ? id : null);
  }

  void _collapse() {
    if (_focusedId == null) return;
    HapticFeedback.selectionClick();
    setState(() => _focusedId = null);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final n = items.length;
    final focused = _focusedIndex;
    if (focused < 0 && _focusedId != null) _focusedId = null; // card was deleted

    final double height;
    if (focused < 0) {
      height = widget.cardHeight + max(0, n - 1) * widget.peek;
    } else {
      final pile = min(n - 1, _pileMax);
      height = widget.cardHeight + (pile > 0 ? _pileGap + (pile - 1) * _pileStep + _pileTail : 0);
    }

    // Paint order: collapsed = natural (each next card covers the previous one's
    // body, leaving its header visible); focused = pile first, open card on top.
    final order = [
      for (var i = 0; i < n; i++)
        if (i != focused) i,
      if (focused >= 0) focused,
    ];

    final children = <Widget>[];
    var pileSlot = 0;
    for (final i in order) {
      final item = items[i];
      final isFocused = i == focused;
      double top;
      if (focused < 0) {
        top = i * widget.peek;
      } else if (isFocused) {
        top = 0;
      } else {
        final slot = min(pileSlot++, _pileMax - 1);
        top = widget.cardHeight + _pileGap + slot * _pileStep;
      }
      children.add(AnimatedPositioned(
        key: ValueKey(widget.idOf(item)),
        duration: _duration,
        curve: _curve,
        top: top,
        left: 0,
        right: 0,
        height: widget.cardHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (focused >= 0 && !isFocused) ? _collapse : () => _tap(item),
          child: AnimatedScale(
            duration: _duration,
            curve: _curve,
            // Pile cards shrink slightly so the open card reads as "lifted".
            scale: (focused >= 0 && !isFocused) ? 0.94 : 1,
            alignment: Alignment.topCenter,
            child: widget.faceBuilder(context, item, isFocused || (focused < 0 && i == n - 1)),
          ),
        ),
      ));
    }

    return PopScope(
      canPop: _focusedId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _collapse();
      },
      child: AnimatedContainer(
        duration: _duration,
        curve: _curve,
        height: height,
        // Pile cards are full height; cut them at the stack's bottom edge so they
        // don't cover what follows, but leave room for shadows on the other sides.
        child: ClipRect(
          clipper: const _BottomEdgeClipper(overflow: 32),
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      ),
    );
  }
}

class _BottomEdgeClipper extends CustomClipper<Rect> {
  const _BottomEdgeClipper({required this.overflow});

  final double overflow;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-overflow, -overflow, size.width + overflow, size.height + 12);

  @override
  bool shouldReclip(_BottomEdgeClipper oldClipper) => oldClipper.overflow != overflow;
}
