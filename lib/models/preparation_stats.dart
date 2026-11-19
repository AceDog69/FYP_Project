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
