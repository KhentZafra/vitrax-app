import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum HazardType { pothole, roadConstruction, flooding, accident, aggressiveDogs, crime, heavyTraffic, noSignal }

extension HazardTypeX on HazardType {
  String get label {
    switch (this) {
      case HazardType.pothole:
        return 'Pothole';
      case HazardType.roadConstruction:
        return 'Road Construction';
      case HazardType.flooding:
        return 'Flooding';
      case HazardType.accident:
        return 'Accident';
      case HazardType.aggressiveDogs:
        return 'Aggressive Dogs';
      case HazardType.crime:
        return 'Crime';
      case HazardType.heavyTraffic:
        return 'Heavy Traffic';
      case HazardType.noSignal:
        return 'No Signal';
    }
  }

  String get value => name;

  static HazardType fromString(String value) {
    return HazardType.values.firstWhere((t) => t.value == value, orElse: () => HazardType.pothole);
  }

  IconData get icon {
    switch (this) {
      case HazardType.pothole:
        return Icons.warning_rounded;
      case HazardType.roadConstruction:
        return Icons.construction_rounded;
      case HazardType.flooding:
        return Icons.waves_rounded;
      case HazardType.accident:
        return Icons.car_crash_rounded;
      case HazardType.aggressiveDogs:
        return Icons.pets_rounded;
      case HazardType.crime:
        return Icons.shield_rounded;
      case HazardType.heavyTraffic:
        return Icons.traffic_rounded;
      case HazardType.noSignal:
        return Icons.signal_cellular_connected_no_internet_0_bar_rounded;
    }
  }

  Color get color {
    switch (this) {
      case HazardType.pothole:
        return const Color(0xffE53935);
      case HazardType.roadConstruction:
        return const Color(0xffFB8C00);
      case HazardType.flooding:
        return const Color(0xff2F6FED);
      case HazardType.accident:
        return const Color(0xff8E5CE8);
      case HazardType.aggressiveDogs:
        return const Color(0xffF2B705);
      case HazardType.crime:
        return const Color(0xff2ECC71);
      case HazardType.heavyTraffic:
        return const Color(0xffFF7043);
      case HazardType.noSignal:
        return const Color(0xff607D8B);
    }
  }
}

/// A hazard pin. `shared` controls community visibility — false (the
/// default) means only the reporter can see it; true means it shows on
/// everyone's map. See HazardService for the Supabase calls that read/
/// write this.
class HazardReport {
  final String? id;
  final HazardType type;
  final LatLng position;
  final DateTime reportedAt;
  final String? activityId;
  final bool shared;

  /// Only for a "No Signal" stretch found automatically: where the signal
  /// came back, how many meters were without signal, and that the app (not a
  /// person) recorded it. [position] is where the signal was lost.
  final LatLng? endPosition;
  final double? lengthMeters;
  final bool autoDetected;

  // Client-side display fields — not persisted on this row itself, only
  // populated when fetched alongside confirmation counts (see
  // HazardService.fetchClearStatus). Not part of toInsertMap/fromMap's
  // normal round-trip.
  final int clearConfirmationCount;
  final bool confirmedClearByMe;

  HazardReport({
    this.id,
    required this.type,
    required this.position,
    required this.reportedAt,
    this.activityId,
    this.shared = false,
    this.endPosition,
    this.lengthMeters,
    this.autoDetected = false,
    this.clearConfirmationCount = 0,
    this.confirmedClearByMe = false,
  });

  HazardReport copyWith({String? id, bool? shared, String? activityId, int? clearConfirmationCount, bool? confirmedClearByMe}) {
    return HazardReport(
      id: id ?? this.id,
      type: type,
      position: position,
      reportedAt: reportedAt,
      activityId: activityId ?? this.activityId,
      shared: shared ?? this.shared,
      endPosition: endPosition,
      lengthMeters: lengthMeters,
      autoDetected: autoDetected,
      clearConfirmationCount: clearConfirmationCount ?? this.clearConfirmationCount,
      confirmedClearByMe: confirmedClearByMe ?? this.confirmedClearByMe,
    );
  }

  Map<String, dynamic> toInsertMap({required String userId, String? activityId}) {
    return {
      'user_id': userId,
      'activity_id': activityId,
      'type': type.value,
      'lat': position.latitude,
      'lng': position.longitude,
      'reported_at': reportedAt.toIso8601String(),
      if (endPosition != null) 'end_lat': endPosition!.latitude,
      if (endPosition != null) 'end_lng': endPosition!.longitude,
      if (lengthMeters != null) 'length_m': lengthMeters,
      if (autoDetected) 'auto_detected': true,
    };
  }

  /// Row -> Dart, used when fetching community hazards to display on
  /// other users' maps.
  factory HazardReport.fromMap(Map<String, dynamic> map) {
    return HazardReport(
      id: map['id'] as String?,
      type: HazardTypeX.fromString(map['type'] as String),
      position: LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble()),
      reportedAt: DateTime.parse(map['reported_at'] as String),
      activityId: map['activity_id'] as String?,
      shared: map['shared'] as bool? ?? false,
      endPosition: (map['end_lat'] is num && map['end_lng'] is num)
          ? LatLng((map['end_lat'] as num).toDouble(), (map['end_lng'] as num).toDouble())
          : null,
      lengthMeters: (map['length_m'] as num?)?.toDouble(),
      autoDetected: map['auto_detected'] as bool? ?? false,
    );
  }
}