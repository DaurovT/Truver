import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Motion tokens of «Truver — спецификация движения» — port of `Motion.swift`. No bare durations or curves in
/// views: everything comes from here, and «Уменьшить движение» (Android: «Удалить анимацию») picks the replacement.
abstract final class Motion {
  static const instant = Duration.zero;
  static const tick = Duration(milliseconds: 90);
  static const quick = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 240);
  static const move = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 600);
  static const breath = Duration(milliseconds: 2400);

  /// Everything that appears or slides in: cubic-bezier(0.2, 0.8, 0.2, 1).
  static const out = Cubic(0.2, 0.8, 0.2, 1);

  /// Everything that leaves; one step shorter than its appearance: cubic-bezier(0.4, 0, 1, 1).
  static const inCurve = Cubic(0.4, 0, 1, 1);

  /// Needle spring: stiffness 300, critical damping (no overshoot) — values must never lie about pitch.
  static const needleStiffness = 300.0;
  static double get needleDamping => 2 * math.sqrt(needleStiffness);

  /// SwiftUI `.spring(response: 0.35, dampingFraction: 0.8)` — sheets, fretboard position, window handles.
  static const snapSpring = SpringDescription(mass: 1, stiffness: 322.27, damping: 28.72);

  /// SwiftUI `.spring(response: 0.42, dampingFraction: 0.62)` — rewards only.
  static const popSpring = SpringDescription(mass: 1, stiffness: 223.8, damping: 18.55);

  /// Curve approximations of the springs for implicit animations (`AnimatedFoo(curve: ...)`).
  static const snap = _SpringCurve(snapSpring);
  static const pop = _SpringCurve(popSpring);
  static const snapDuration = Duration(milliseconds: 520);
  static const popDuration = Duration(milliseconds: 700);

  /// System «remove animations» switch.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// A spring sampled as a curve over a fixed duration (settles within it).
class _SpringCurve extends Curve {
  const _SpringCurve(this.spring);
  final SpringDescription spring;

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(spring, 0, 1, 0);
    final seconds = t * (spring == Motion.popSpring ? 0.7 : 0.52);
    return t >= 1 ? 1 : sim.x(seconds);
  }
}

/// Critically damped spring integrated per display frame (needle, deviation slider): 30–40 readings per second
/// never stack animations. Port of `SpringFollower`.
class SpringFollower {
  SpringFollower([this.value = 0]);

  double value;
  double _velocity = 0;
  Duration? _last;

  /// Moves towards `target`; with `reduceMotion` jumps straight there. `time` is the frame timestamp.
  double step(double target, Duration time, {required bool reduceMotion}) {
    final last = _last;
    _last = time;
    if (reduceMotion || last == null) {
      value = target;
      _velocity = 0;
      return value;
    }
    var dt = math.min(0.05, math.max(0, (time - last).inMicroseconds / 1e6));
    final k = Motion.needleStiffness, c = Motion.needleDamping;
    while (dt > 0) {
      final h = math.min(dt, 1 / 240);
      final acceleration = -k * (value - target) - c * _velocity;
      _velocity += acceleration * h;
      value += _velocity * h;
      dt -= h;
    }
    return value;
  }

  void reset(double v) {
    value = v;
    _velocity = 0;
    _last = null;
  }
}
