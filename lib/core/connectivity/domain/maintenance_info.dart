import 'package:equatable/equatable.dart';

/// What the server told us while it is in maintenance. Comes from either a
/// 503 `MAINTENANCE` error body or a 503 `/api/health` response.
class MaintenanceInfo extends Equatable {
  const MaintenanceInfo({
    required this.message,
    this.reason,
    this.since,
    this.retryAfter,
  });

  final String message;

  /// `planned` or `unavailable`.
  final String? reason;
  final DateTime? since;
  final Duration? retryAfter;

  bool get isPlanned => reason == 'planned';

  factory MaintenanceInfo.fromJson(Map<String, dynamic> json, {Duration? retryAfter}) {
    final error = json['error'];
    final source = error is Map<String, dynamic> ? error : json;
    final details = source['details'] is Map<String, dynamic>
        ? source['details'] as Map<String, dynamic>
        : source;
    final retrySeconds = details['retryAfterSeconds'];
    return MaintenanceInfo(
      message: (source['message'] ?? details['message'] ?? 'The service is under maintenance.')
          as String,
      reason: details['reason'] as String?,
      since: DateTime.tryParse('${details['since'] ?? ''}')?.toLocal(),
      retryAfter: retryAfter ??
          (retrySeconds is num ? Duration(seconds: retrySeconds.round()) : null),
    );
  }

  @override
  List<Object?> get props => [message, reason, since, retryAfter];
}
