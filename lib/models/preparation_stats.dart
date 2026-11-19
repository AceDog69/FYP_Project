import 'package:cloud_firestore/cloud_firestore.dart';

const minimumPreparationSampleMillis = 1000;
const maximumPreparationSampleMillis = 12 * 60 * 60 * 1000;
const maximumPreparationSamples = 2147483647;

/// Private per-stall arithmetic history. The document contains no Student or
/// order history beyond the last id needed to bind a Rules-checked increment.
class PreparationStats {
  const PreparationStats({
    required this.sampleCount,
    required this.totalDurationMillis,
    required this.revision,
    required this.lastOrderId,
    required this.updatedAt,
  });

  final int sampleCount, totalDurationMillis, revision;
  final String lastOrderId;
  final Timestamp updatedAt;

  // Round the arithmetic mean up to an integral millisecond so Rules and the
  // UI share one exact, conservative integer snapshot.
  int get averageDurationMillis =>
      (totalDurationMillis + sampleCount - 1) ~/ sampleCount;

  static bool isValidDuration(int milliseconds) =>
      milliseconds >= minimumPreparationSampleMillis &&
      milliseconds <= maximumPreparationSampleMillis;

  static int estimateMillis({
    required int initialPreparationMinutes,
    PreparationStats? history,
  }) => history == null
      ? initialPreparationMinutes * 60000
      : history.averageDurationMillis;

  /// Public Stalls contains only this sanitized estimate and its revision.
  /// The Security Rules bind both fields to this private aggregate atomically.
  static Map<String, int> publicProjectionFields({
    required int initialPreparationMinutes,
    PreparationStats? history,
  }) => history == null
      ? {
          'estimatedPreparationMillis': initialPreparationMinutes * 60000,
          'preparationStatsRevision': 0,
        }
      : publicProjectionForAggregate(
          sampleCount: history.sampleCount,
          totalDurationMillis: history.totalDurationMillis,
          revision: history.revision,
        );

  static Map<String, int> publicProjectionForAggregate({
    required int sampleCount,
    required int totalDurationMillis,
    required int revision,
  }) {
    if (sampleCount < 1 ||
        sampleCount > maximumPreparationSamples ||
        revision != sampleCount ||
        totalDurationMillis < sampleCount * minimumPreparationSampleMillis ||
        totalDurationMillis > sampleCount * maximumPreparationSampleMillis) {
      throw const FormatException('Preparation projection is invalid.');
    }
    return {
      'estimatedPreparationMillis':
          (totalDurationMillis + sampleCount - 1) ~/ sampleCount,
      'preparationStatsRevision': revision,
    };
  }

  static bool matchesPublicProjection(
    Map<String, dynamic>? listing, {
    required int initialPreparationMinutes,
    PreparationStats? history,
  }) {
    if (listing == null) return false;
    final expected = publicProjectionFields(
      initialPreparationMinutes: initialPreparationMinutes,
      history: history,
    );
    return listing['estimatedPreparationMillis'] ==
            expected['estimatedPreparationMillis'] &&
        listing['preparationStatsRevision'] ==
            expected['preparationStatsRevision'];
  }

  factory PreparationStats.decode(
    String vendorUid,
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      throw const FormatException('Preparation history is unavailable.');
    }
    final count = data['sampleCount'], total = data['totalDurationMillis'];
    final revision = data['revision'], lastOrderId = data['lastOrderId'];
    if (data.length != 7 ||
        data['schemaVersion'] != 1 ||
        data['vendorUid'] != vendorUid ||
        count is! int ||
        count < 1 ||
        count > maximumPreparationSamples ||
        total is! int ||
        total < count * minimumPreparationSampleMillis ||
        total > count * maximumPreparationSampleMillis ||
        revision is! int ||
        revision != count ||
        lastOrderId is! String ||
        !RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(lastOrderId) ||
        data['updatedAt'] is! Timestamp) {
      throw const FormatException('Preparation history could not be verified.');
    }
    return PreparationStats(
      sampleCount: count,
      totalDurationMillis: total,
      revision: revision,
      lastOrderId: lastOrderId,
      updatedAt: data['updatedAt'] as Timestamp,
    );
  }

  Map<String, dynamic> withSample(
    String vendorUid,
    String orderId,
    int durationMillis,
  ) {
    if (!isValidDuration(durationMillis) ||
        sampleCount >= maximumPreparationSamples) {
      throw const FormatException(
        'Preparation sample is outside the supported range.',
      );
    }
    return {
      'schemaVersion': 1,
      'vendorUid': vendorUid,
      'sampleCount': sampleCount + 1,
      'totalDurationMillis': totalDurationMillis + durationMillis,
      'revision': revision + 1,
      'lastOrderId': orderId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Map<String, dynamic> firstSample(
    String vendorUid,
    String orderId,
    int durationMillis,
  ) {
    if (!isValidDuration(durationMillis)) {
      throw const FormatException(
        'Preparation sample is outside the supported range.',
      );
    }
    return {
      'schemaVersion': 1,
      'vendorUid': vendorUid,
      'sampleCount': 1,
      'totalDurationMillis': durationMillis,
      'revision': 1,
      'lastOrderId': orderId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
