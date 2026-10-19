import 'dart:math';

import 'package:badrgo_ops_console/core/realtime/backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('jitter never pushes a delay past max', () {
    final backoff = Backoff(jitter: 0.5, random: Random(1));
    for (var i = 0; i < 2000; i++) {
      if (i % 50 == 0) backoff.reset();
      expect(backoff.next(), lessThanOrEqualTo(backoff.max));
    }
  });

  test('without jitter the curve is unchanged: 1s, 2s, 4s … 30s', () {
    final backoff = Backoff(jitter: 0);
    final delays = [for (var i = 0; i < 7; i++) backoff.next().inSeconds];
    expect(delays, [1, 2, 4, 8, 16, 30, 30]);
  });
}
