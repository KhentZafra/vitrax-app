enum ActivityType { ride, run, walk }

extension ActivityTypeX on ActivityType {
  String get value => name; // 'ride' | 'run' | 'walk'

  static ActivityType fromString(String value) {
    return ActivityType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => ActivityType.ride,
    );
  }

  String get label {
    switch (this) {
      case ActivityType.ride:
        return 'Ride';
      case ActivityType.run:
        return 'Run';
      case ActivityType.walk:
        return 'Walk';
    }
  }
}

class GpsPoint {
  final double lat;
  final double lng;
  final DateTime timestamp;

  GpsPoint({required this.lat, required this.lng, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp.toIso8601String(),
      };

  factory GpsPoint.fromJson(Map<String, dynamic> json) => GpsPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Mirrors a row in the Supabase `activities` table.
class Activity {
  final String? id; // null until Supabase assigns one on insert
  final String userId;
  final ActivityType type;
  final String? subtype; // e.g. "Road cycling", "Easy run"
  final double distanceKm;
  final Duration duration;
  final DateTime startedAt;
  final List<GpsPoint> route;
  final bool shared; // true once shared as a route (Routes tab)
  final bool sharedToFeed; // true once also posted on the Community feed
  final String? caption; // optional note written when sharing
  final String? photoUrl; // optional photo attached when sharing
  // Human-readable place name (e.g. "Panglao, Bohol"), reverse-geocoded
  // once from the route's starting point at save time — see
  // ActivityProvider.saveActivity and services/location_service.dart.
  // Null if geocoding wasn't available (no connectivity, no result) or
  // for activities saved before this field existed — always optional,
  // never required to display an activity.
  final String? location;

  /// If this was recorded by retracing someone's shared route, that route's
  /// activity id (so its owner can be told).
  final String? retracedFrom;

  // Client-side only — never sent to or read from Supabase. True for an
  // activity that was recorded offline and is queued locally, waiting
  // for connectivity to sync. See OfflineActivityQueue.
  final bool pendingSync;

  Activity({
    this.id,
    required this.userId,
    required this.type,
    this.subtype,
    required this.distanceKm,
    required this.duration,
    required this.startedAt,
    this.route = const [],
    this.shared = false,
    this.sharedToFeed = false,
    this.caption,
    this.photoUrl,
    this.location,
    this.retracedFrom,
    this.pendingSync = false,
  });

  /// Shown in Recent Activity — prefers the specific subtype if chosen,
  /// falls back to a generic label per main type.
  String get title {
    if (subtype != null && subtype!.isNotEmpty) return subtype!;
    switch (type) {
      case ActivityType.ride:
        return 'Ride';
      case ActivityType.run:
        return 'Run';
      case ActivityType.walk:
        return 'Walk';
    }
  }

  double get avgSpeedKmh =>
      duration.inSeconds > 0 ? distanceKm / (duration.inSeconds / 3600) : 0;

  /// Row -> Dart. Use when reading from `select()`.
  factory Activity.fromMap(Map<String, dynamic> map) {
    return Activity(
      id: map['id'] as String?,
      userId: map['user_id'] as String,
      type: ActivityTypeX.fromString(map['type'] as String? ?? 'ride'),
      subtype: map['subtype'] as String?,
      distanceKm: (map['distance_km'] as num).toDouble(),
      duration: Duration(seconds: map['duration_seconds'] as int),
      startedAt: DateTime.parse(map['started_at'] as String),
      route: (map['route'] as List<dynamic>?)
              ?.map((p) => GpsPoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      shared: map['shared'] as bool? ?? false,
      sharedToFeed: map['shared_to_feed'] as bool? ?? false,
      caption: map['caption'] as String?,
      photoUrl: map['photo_url'] as String?,
      // Missing key (older rows, or before the `location` column
      // existed) just comes back null here — never a parse error.
      location: map['location'] as String?,
    );
  }

  /// Dart -> row. Use when calling `insert()`. Omits `id` so Supabase
  /// generates it, and omits `user_id` — the caller sets that explicitly
  /// from the authenticated session (RLS also enforces this server-side).
  Map<String, dynamic> toInsertMap() {
    return {
      'user_id': userId,
      'type': type.value,
      'subtype': subtype,
      'distance_km': distanceKm,
      'duration_seconds': duration.inSeconds,
      'started_at': startedAt.toIso8601String(),
      'route': route.map((p) => p.toJson()).toList(),
      'location': location,
      if (retracedFrom != null) 'retraced_from': retracedFrom,
    };
  }

  Activity copyWith({
    bool? shared,
    bool? sharedToFeed,
    String? caption,
    String? photoUrl,
    String? id,
    bool? pendingSync,
    String? location,
  }) {
    return Activity(
      id: id ?? this.id,
      userId: userId,
      type: type,
      subtype: subtype,
      distanceKm: distanceKm,
      duration: duration,
      startedAt: startedAt,
      route: route,
      shared: shared ?? this.shared,
      sharedToFeed: sharedToFeed ?? this.sharedToFeed,
      caption: caption ?? this.caption,
      photoUrl: photoUrl ?? this.photoUrl,
      location: location ?? this.location,
      retracedFrom: retracedFrom,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  /// Serializes everything needed to later insert this activity, for the
  /// offline queue (see OfflineActivityQueue). Deliberately separate from
  /// toInsertMap(): this includes fields toInsertMap omits (id, caption,
  /// photoUrl aren't relevant pre-sync — a freshly-recorded activity has
  /// none of those yet) and is meant for local JSON storage, not Supabase.
  Map<String, dynamic> toLocalJson() {
    return {
      'user_id': userId,
      'type': type.value,
      'subtype': subtype,
      'distance_km': distanceKm,
      'duration_seconds': duration.inSeconds,
      'started_at': startedAt.toIso8601String(),
      'route': route.map((p) => p.toJson()).toList(),
      'location': location,
      'retraced_from': retracedFrom,
    };
  }

  factory Activity.fromLocalJson(Map<String, dynamic> json, {required String localId}) {
    return Activity(
      id: localId,
      userId: json['user_id'] as String,
      type: ActivityTypeX.fromString(json['type'] as String? ?? 'ride'),
      subtype: json['subtype'] as String?,
      distanceKm: (json['distance_km'] as num).toDouble(),
      duration: Duration(seconds: json['duration_seconds'] as int),
      startedAt: DateTime.parse(json['started_at'] as String),
      route: (json['route'] as List<dynamic>? ?? [])
          .map((p) => GpsPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      location: json['location'] as String?,
      retracedFrom: json['retraced_from'] as String?,
      pendingSync: true,
    );
  }
}
