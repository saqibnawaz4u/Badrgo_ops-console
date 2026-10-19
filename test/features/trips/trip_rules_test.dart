import 'package:badrgo_ops_console/core/domain/shared_entities.dart';
import 'package:badrgo_ops_console/core/permissions/permissions.dart';
import 'package:badrgo_ops_console/features/trips/domain/entities/trip.dart';
import 'package:badrgo_ops_console/features/trips/domain/usecases/trip_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/roles.dart';
import '../../fixtures/trips.dart';

void main() {
  group('TripActions.resolve: permission AND trip status', () {
    test('viewer gets no actions on any trip', () {
      for (final status in TripStatus.values) {
        final actions = TripActions.resolve(tripWith(status: status), permissionsFor('viewer'));
        expect(actions.any, isFalse, reason: status.name);
      }
    });

    test('dispatcher can assign and cancel a waiting trip, but never refund', () {
      final waiting = TripActions.resolve(tripWith(), permissionsFor('dispatcher'));
      expect(waiting.canAssign, isTrue);
      expect(waiting.canCancel, isTrue);
      expect(waiting.canRefund, isFalse);

      final completed = TripActions.resolve(tripWith(status: TripStatus.completed), permissionsFor('dispatcher'));
      expect(completed.any, isFalse);
    });

    test('support can refund a completed trip and is never offered assign', () {
      final completed = TripActions.resolve(tripWith(status: TripStatus.completed), permissionsFor('support'));
      expect(completed.canRefund, isTrue);
      expect(completed.canAssign, isFalse);
      expect(completed.canCancel, isFalse);

      final waiting = TripActions.resolve(tripWith(), permissionsFor('support'));
      expect(waiting.canAssign, isFalse);
    });

    test('assign only while requested or assigned (reassign)', () {
      final ops = permissionsFor('ops_manager');
      expect(TripActions.resolve(tripWith(status: TripStatus.assigned), ops).canAssign, isTrue);
      expect(TripActions.resolve(tripWith(status: TripStatus.inProgress), ops).canAssign, isFalse);
    });

    test('cancel only while the trip is still active', () {
      final ops = permissionsFor('ops_manager');
      expect(TripActions.resolve(tripWith(status: TripStatus.inProgress), ops).canCancel, isTrue);
      expect(TripActions.resolve(tripWith(status: TripStatus.completed), ops).canCancel, isFalse);
      expect(TripActions.resolve(tripWith(status: TripStatus.cancelled), ops).canCancel, isFalse);
    });

    test('no refund once the fare is fully refunded', () {
      final trip = tripWith(status: TripStatus.completed, fare: 30, refunded: 30);
      expect(TripActions.resolve(trip, permissionsFor('support')).canRefund, isFalse);
    });

    test('decided by permissions, not by the role name', () {
      // A custom grant with only trip:refund behaves like support.
      final custom = Permissions.fromJson({
        'trip': ['read', 'refund'],
      });
      final actions = TripActions.resolve(tripWith(status: TripStatus.completed), custom);
      expect(actions.canRefund, isTrue);
      expect(actions.canAssign, isFalse);
    });
  });

  group('refund amount validation', () {
    const refundable = Money(12.5, 'QAR');

    test('accepts up to the remaining amount, with a comma or a dot', () {
      expect(TripInputRules.refundAmount('12.5', refundable), isNull);
      expect(TripInputRules.refundAmount('12,50', refundable), isNull);
      expect(TripInputRules.refundAmount('0.01', refundable), isNull);
    });

    test('accepts two-decimal amounts that are inexact in floating point', () {
      // 0.29 * 100 == 28.999999999999996, which a naive check rejects.
      for (final value in ['0.29', '1.15', '0.57', '4.35']) {
        expect(TripInputRules.refundAmount(value, refundable), isNull, reason: value);
      }
    });

    test('rejects more than what is left, naming the limit', () {
      expect(TripInputRules.refundAmount('12.51', refundable), contains('12.50 QAR'));
    });

    test('rejects empty, zero, negative and over-precise amounts', () {
      expect(TripInputRules.refundAmount('', refundable), isNotNull);
      expect(TripInputRules.refundAmount('abc', refundable), isNotNull);
      expect(TripInputRules.refundAmount('0', refundable), isNotNull);
      expect(TripInputRules.refundAmount('-1', refundable), isNotNull);
      expect(TripInputRules.refundAmount('1.005', refundable), isNotNull);
    });

    test('remaining amount accounts for earlier refunds', () {
      final trip = tripWith(status: TripStatus.completed, fare: 30, refunded: 17.5);
      expect(trip.refundable, refundable);
    });
  });

  group('reason', () {
    test('needs 3 to 200 characters after trimming', () {
      expect(TripInputRules.reason('  ab  '), isNotNull);
      expect(TripInputRules.reason('Rider no-show'), isNull);
      expect(TripInputRules.reason('x' * 201), isNotNull);
    });
  });
}
