import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Where the "light" falls on a card, from how the phone is tilted: -1 … 1
/// along the card's diagonal. Tilting the phone moves the reflection across
/// the gold, like turning a metal card under a lamp.
///
/// One shared accelerometer subscription, open only while at least one
/// visible card uses it ([acquire]/[release]). [available] stays false on
/// devices or tests without the sensor; callers then animate the light.
class TiltLight extends ChangeNotifier {
  TiltLight._();
  static final TiltLight instance = TiltLight._();

  double _value = 0;
  double get value => _value;

  bool _available = false;
  bool get available => _available;

  StreamSubscription<AccelerometerEvent>? _sub;

  /// Where tilt comes from. Tests (no sensor plugin) set it to null; the
  /// light then sweeps on its own, as on phones without an accelerometer.
  @visibleForTesting
  static Stream<AccelerometerEvent> Function()? source =
      () => accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval);
  int _users = 0;

  void acquire() {
    if (_users++ == 0) _start();
  }

  void release() {
    if (_users == 0) return;
    if (--_users == 0) {
      _sub?.cancel();
      _sub = null;
      _available = false;
    }
  }

  void _start() {
    final open = source;
    if (open == null) return;
    try {
      _sub = open().listen(
        (e) => update(e.x, e.y),
        onError: (Object _) {
          _available = false;
          _sub = null;
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _available = false;
    }
  }

  /// Gravity components (m/s²) → light position, smoothed so the glint glides.
  /// Left/right tilt (x) moves it most; tipping the top towards/away from you
  /// (y, relative to the usual ~40° reading angle) adds the rest.
  @visibleForTesting
  void update(double x, double y) {
    _available = true;
    final target = (-x / 9.81 * 1.6 + (y / 9.81 - 0.65) * 1.2).clamp(-1.4, 1.4);
    _value += (target - _value) * 0.22;
    notifyListeners();
  }
}
