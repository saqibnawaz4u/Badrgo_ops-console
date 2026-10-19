import 'dart:math';

/// Exponential backoff with jitter: 1s, 2s, 4s … capped at [max].
/// Jitter spreads reconnects so many tabs don't hit the server in lockstep.
class Backoff {
  Backoff({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(seconds: 30),
    this.factor = 2.0,
    this.jitter = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final double factor;

  /// Fraction of the delay added or removed at random (0.2 = ±20%).
  final double jitter;
  final Random _random;

  int _attempt = 0;

  int get attempt => _attempt;

  Duration next() {
    final raw = initial.inMilliseconds * pow(factor, _attempt);
    final capped = min(raw, max.inMilliseconds.toDouble());
    final spread = capped * jitter * (_random.nextDouble() * 2 - 1);
    _attempt++;
    // Clamp after jitter too, so [max] is a hard ceiling.
    final jittered = min(capped + spread, max.inMilliseconds.toDouble());
    return Duration(milliseconds: max0(jittered).round());
  }

  void reset() => _attempt = 0;

  static double max0(double v) => v < 0 ? 0 : v;
}
