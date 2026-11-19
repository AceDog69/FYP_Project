import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/preparation_stats.dart';
import 'package:my_fyp_app/models/queue_progress.dart';
import 'support/fake_order_repository.dart';

void main() {
  const orderId = '00000000000000000001';
  final now = DateTime.utc(2026, 1, 1);
  Timestamp ts(DateTime value) => Timestamp.fromDate(value);
  final base = receiptFor(
    CheckoutRequest(
      id: orderId,
      studentUid: 'student',
      vendorUid: 'stall-a',
      stallName: 'Stall A',
      paymentMethod: 'ewallet',
      items: [
        const OrderItem(
          foodId: 'rice',
          name: 'Rice',
          description: 'Rice meal',
          categoryId: 'main',
          pictureId: 'nasi_lemak',
          priceSen: 500,
          quantity: 1,
          foodRevision: 1,
        ),
      ],
    ),
    1,
  ).order;

  Map<String, dynamic> statsMap(
    String uid, {
    int count = 2,
    int total = 10001,
  }) => {
    'schemaVersion': 1,
    'vendorUid': uid,
    'sampleCount': count,
    'totalDurationMillis': total,
    'revision': count,
    'lastOrderId': orderId,
    'updatedAt': Timestamp.fromDate(now),
  };

  test(
    'configured initial allowance is used without history and mean is rounded up per stall',
    () {
      expect(
        PreparationStats.estimateMillis(initialPreparationMinutes: 15),
        900000,
      );
      final a = PreparationStats.decode('stall-a', statsMap('stall-a'));
      final b = PreparationStats.decode(
        'stall-b',
        statsMap('stall-b', total: 18000),
      );
      expect(a.averageDurationMillis, 5001);
      expect(
        PreparationStats.estimateMillis(
          initialPreparationMinutes: 15,
          history: a,
        ),
        5001,
      );
      expect(
        PreparationStats.estimateMillis(
          initialPreparationMinutes: 15,
          history: b,
        ),
        9000,
      );
      expect(a.averageDurationMillis, isNot(b.averageDurationMillis));
    },
  );

  test(
    'history rejects malformed aggregates and only accepts bounded actual durations',
    () {
      final valid = statsMap('stall-a');
      for (final bad in [
        {...valid, 'sampleCount': 0},
        {...valid, 'totalDurationMillis': 1},
        {...valid, 'totalDurationMillis': 90000000},
        {...valid, 'revision': 9},
        {...valid, 'lastOrderId': 'private/id'},
        {...valid, 'updatedAt': 'client time'},
        {...valid, 'unexpected': true},
      ]) {
        expect(
          () => PreparationStats.decode('stall-a', bad),
          throwsFormatException,
        );
      }
      expect(PreparationStats.isValidDuration(999), isFalse);
      expect(PreparationStats.isValidDuration(1000), isTrue);
      expect(PreparationStats.isValidDuration(12 * 60 * 60 * 1000), isTrue);
      expect(
        PreparationStats.isValidDuration(12 * 60 * 60 * 1000 + 1),
        isFalse,
      );
    },
  );

  test(
    'Preparing ETA uses its frozen estimate, subtracts elapsed time, and becomes uncertain',
    () {
      final start = ts(now);
      final preparing = ConfirmedOrder(
        id: base.id,
        studentUid: base.studentUid,
        vendorUid: base.vendorUid,
        stallName: base.stallName,
        ticket: base.ticket,
        totalSen: base.totalSen,
        itemCount: base.itemCount,
        preparationMinutes: 15,
        paymentMethod: base.paymentMethod,
        createdAt: base.createdAt,
        firstItem: base.firstItem,
        status: 'Preparing',
        statusRevision: 1,
        preparingAt: start,
        preparationEstimateMillis: 60000,
      );
      final progress = QueueProgress('stall-a', 2, 1, 1, start);
      final partial = estimateQueue(
        preparing,
        progress,
        now.add(const Duration(seconds: 25)),
      );
      expect(partial.minutes, 1); // 35 seconds remaining, rounded up.
      expect(partial.message, contains('not a countdown'));
      final elapsed = estimateQueue(
        preparing,
        progress,
        now.add(const Duration(minutes: 1)),
      );
      expect(elapsed.minutes, isNull);
      expect(elapsed.overdue, isTrue);
      expect(elapsed.message, contains('currently unknown'));

      final pending = estimateQueue(
        base,
        QueueProgress('stall-a', 1, 0, 0, start),
        now,
      );
      expect(pending.ahead, 0);
      expect(pending.minutes, isNull);
      expect(pending.message, 'Waiting for preparation to begin.');
    },
  );

  test(
    'Ready and Completed never show an ETA even when a snapshot estimate exists',
    () {
      final started = ts(now),
          readyAt = ts(now.add(const Duration(minutes: 4)));
      final ready = ConfirmedOrder(
        id: base.id,
        studentUid: base.studentUid,
        vendorUid: base.vendorUid,
        stallName: base.stallName,
        ticket: base.ticket,
        totalSen: base.totalSen,
        itemCount: base.itemCount,
        preparationMinutes: 15,
        paymentMethod: base.paymentMethod,
        createdAt: base.createdAt,
        firstItem: base.firstItem,
        status: 'Ready',
        statusRevision: 2,
        preparingAt: started,
        readyAt: readyAt,
        preparationEstimateMillis: 60000,
      );
      final completed = ConfirmedOrder(
        id: base.id,
        studentUid: base.studentUid,
        vendorUid: base.vendorUid,
        stallName: base.stallName,
        ticket: base.ticket,
        totalSen: base.totalSen,
        itemCount: base.itemCount,
        preparationMinutes: 15,
        paymentMethod: base.paymentMethod,
        createdAt: base.createdAt,
        firstItem: base.firstItem,
        status: 'Completed',
        statusRevision: 3,
        preparingAt: started,
        readyAt: readyAt,
        completedAt: readyAt,
      );
      for (final order in [ready, completed]) {
        final estimate = estimateQueue(order, null, now);
        expect(estimate.minutes, isNull);
        expect(estimate.ahead, 0);
      }
    },
  );
}
