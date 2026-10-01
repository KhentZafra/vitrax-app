import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../providers/activity_provider.dart';
import '../models/hazard_report.dart';
import '../config/hazard_cluster_config.dart';
import '../models/hazard_cluster.dart';
import '../services/hazard_service.dart';
import '../services/community_impact_service.dart';
import '../services/notification_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';
import '../widgets/report_hazard_sheet.dart';
import 'create_challenge_screen.dart';

/// GPS recording screen — a dedicated map screen reached only after the
/// subtype has already been chosen on SubtypeSelectionScreen. This screen
/// itself has no subtype picker; it's purely: watch for movement -> auto-
/// start -> track -> auto-stop/check-in -> save.
///
/// Map is visible immediately on entering, showing your current position
/// while auto-start watches for movement. The moment sustained movement
/// is detected, recording begins automatically — the timer only starts
/// once you're actually moving; staying stationary keeps it at zero.
/// Community hazards (shared by other users, clustered nearby) are
/// visible on the map even before recording starts.
class RecordScreen extends StatefulWidget {
  final ActivityType activityType;
  final String subtype;

  // Set only when opened via "Track this Route" from a shared route —
  // the original sharer's exact recorded GPS path, drawn as a fixed
  // reference line on the map underneath your own live track, plus
  // whose route it is for the "Retracing ..." banner. Both null for a
  // normal, non-retracing recording (the overwhelmingly common case).
  final List<GpsPoint>? referenceRoute;
  final String? referenceRouteLabel;

  const RecordScreen({
    super.key,
    required this.activityType,
    required this.subtype,
    this.referenceRoute,
    this.referenceRouteLabel,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  StreamSubscription<Position>? _positionSub;
  Timer? _ticker;
  Timer? _undoTimer;

  final MapController _mapController = MapController();

  bool _isRecording = false;
  bool _isStarting = false; // closes the reentrancy window in _start() below
  bool _isLocked = false;
  bool _isSaving = false;
  bool _isPaused =
      false; // duration timer pauses while the exit-confirm dialog is open

  double _distanceMeters = 0;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  Position? _lastPosition;
  DateTime? _lastFixTime;
  // Live, smoothed current speed — separate from avgSpeed (which is
  // a true cumulative average and intentionally slow to react). This
  // uses a light exponential moving average so it responds quickly to
  // real pace changes without jumping wildly on normal GPS noise.
  double _currentSpeedKmh = 0.0;
  final List<LatLng> _routePoints = [];
  final List<GpsPoint> _route = [];

  // Live position, updated whether or not recording has started yet —
  // this is what lets the map show a "you are here" dot immediately,
  // before any movement has triggered auto-start.
  LatLng? _currentLatLng;
  bool _hasCenteredMap = false;

  // Hazards *this session* reported (not yet necessarily shared).
  final List<HazardReport> _hazards = [];
  HazardReport? _pendingUndo;
  int _undoSecondsLeft = 0;

  // ---- Live proximity hazard confirmation ----
  // Hazard ids already prompted this recording session, so passing the
  // same pin repeatedly (e.g. circling back, or GPS fixes lingering
  // nearby) doesn't ask again and again.
  final Set<String> _sessionPromptedHazardIds = {};
  HazardReport? _proximityPrompt;
  bool _proximityBusy = false;
  static const _proximityTriggerMeters = 40.0;

  // Community hazards already shared by other users, clustered for display.
  List<HazardCluster> _communityClusters = [];

  // ---------------------------------------------------------------------
  // Motion detection (auto start / auto stop + safety check-in).
  //
  // These thresholds are a starting point, not a scientifically tuned
  // value — expect to adjust them after real-world testing on foot/bike.
  // Two independent signals:
  //   1. Pre-start: sustained movement above _startThresholdKmh for
  //      _startSustainDuration -> auto-starts the recording.
  //   2. During recording: sustained stillness below _stillThresholdKmh
  //      for _checkInAfter -> shows a "still there?" dialog. If no
  //      response within _autoStopAfter, auto-stops (and auto-saves)
  //      as a safety net. If movement resumes at any point, the check
  //      resets / the dialog auto-dismisses.
  // ---------------------------------------------------------------------
  static const double _startThresholdKmh = 2.5;
  static const Duration _startSustainDuration = Duration(seconds: 6);
  static const double _stillThresholdKmh = 1.5;
  static const Duration _checkInAfter = Duration(seconds: 90);
  static const int _autoStopAfterSeconds = 60;

  StreamSubscription<Position>? _preStartMotionSub;
  DateTime? _movingSince; // pre-start: how long sustained movement has lasted
  DateTime?
  _belowThresholdSince; // pre-start: how long speed has been under threshold, for the reset grace period below

  DateTime?
  _stillSince; // during recording: how long sustained stillness has lasted
  bool _checkInDialogOpen = false;
  String?
  _pendingStopReason; // set when the user actively confirms they're stopping
  BuildContext? _checkInDialogContext;
  Timer? _autoStopTimer;
  final ValueNotifier<int> _autoStopSecondsLeft = ValueNotifier<int>(
    _autoStopAfterSeconds,
  );

  bool get _isCycling => widget.activityType == ActivityType.ride;

  // Computed once — the reference route itself never changes during a
  // recording session, so there's no reason to remap it on every frame.
  late final List<LatLng> _referenceLatLngs =
      (widget.referenceRoute ?? const [])
          .map((p) => LatLng(p.lat, p.lng))
          .toList();
  bool get _isRetracing => _referenceLatLngs.length > 1;

  @override
  void initState() {
    super.initState();
    // Post-frame so context/ScaffoldMessenger is safe to use if a
    // permission snackbar needs to show immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _watchForAutoStart());

    // Ask for microphone permission now, while the user is standing
    // still looking at this screen — not later, mid-run, the first time
    // a hazard proximity prompt tries to listen for a spoken yes/no.
    // VoiceCommandService caches whatever the OS permission result is
    // the first time it checks (success OR failure), so if that first
    // check happens awkwardly during a hazard alert and gets missed or
    // denied, voice responses would silently stop working for the rest
    // of this app install. Calling warmUp() here instead means the
    // permission is already resolved, successfully, well before it's
    // ever actually needed.
    VoiceCommandService.warmUp();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _preStartMotionSub?.cancel();
    _ticker?.cancel();
    _undoTimer?.cancel();
    _autoStopTimer?.cancel();
    _autoStopSecondsLeft.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackWithAction(
        "Location access was denied. Enable it in your phone's Settings to record.",
        actionLabel: 'Open Settings',
        onAction: Geolocator.openAppSettings,
      );
      return false;
    }

    if (permission == LocationPermission.denied) {
      _showSnack('Location permission is required to record this activity.');
      return false;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      _showSnackWithAction(
        'Location services are turned off on this device.',
        actionLabel: 'Open Settings',
        onAction: Geolocator.openLocationSettings,
      );
      return false;
    }

    return true;
  }

  void _showSnackWithAction(
    String message, {
    required String actionLabel,
    required Future<bool> Function() onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Watches for sustained movement while on the pre-start screen and
  /// auto-triggers _start() once detected — this is #13 (automated start).
  /// The manual Start button always remains available as an override, so
  /// a flaky/slow GPS fix can't strand the user waiting.
  Position? _lastPreStartPosition;
  DateTime? _lastPreStartFixTime;

  Future<void> _watchForAutoStart() async {
    if (_isRecording || !mounted) return;

    final ok = await _ensurePermission();
    if (!ok || !mounted || _isRecording) return;

    // distanceFilter: 0 and best accuracy — matches the fix already
    // applied to the live recording stream. The previous medium
    // accuracy + distanceFilter: 3 combination could take a while to
    // get a good first fix and, more importantly, contributed to the
    // noisy readings that were prematurely resetting the sustained-
    // movement timer below (very noticeable at motorbike speeds, where
    // a single bad fix reads as an implausible speed drop).
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
    _preStartMotionSub?.cancel();
    _preStartMotionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
          if (_isRecording) return;

          // Same accuracy filter the live recorder uses — an inaccurate fix
          // can produce a wildly wrong instantaneous speed and reset the
          // sustained-movement timer for no real reason.
          const maxAcceptableAccuracyMeters = 25.0;
          if (pos.accuracy > maxAcceptableAccuracyMeters) return;

          final latLng = LatLng(pos.latitude, pos.longitude);
          setState(() => _currentLatLng = latLng);

          if (!_hasCenteredMap) {
            _hasCenteredMap = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _mapController.move(latLng, 16),
            );
          }

          // Device-reported speed (pos.speed) is often unreliable — zero or
          // erratic on a weak signal, slow starts, or some hardware entirely.
          // Fall back to computing speed from distance/time between the last
          // two fixes (the same technique the live recorder already uses),
          // and trust whichever signal indicates more movement.
          double speedKmh = pos.speed >= 0 ? pos.speed * 3.6 : 0;

          if (_lastPreStartPosition != null) {
            final segment = Geolocator.distanceBetween(
              _lastPreStartPosition!.latitude,
              _lastPreStartPosition!.longitude,
              pos.latitude,
              pos.longitude,
            );
            final secondsSince =
                DateTime.now()
                    .difference(_lastPreStartFixTime ?? DateTime.now())
                    .inMilliseconds /
                1000;
            if (secondsSince > 0) {
              final computedSpeedKmh = (segment / secondsSince) * 3.6;
              if (computedSpeedKmh > speedKmh) speedKmh = computedSpeedKmh;
            }
          }
          _lastPreStartPosition = pos;
          _lastPreStartFixTime = DateTime.now();

          if (speedKmh >= _startThresholdKmh) {
            _belowThresholdSince = null;
            _movingSince ??= DateTime.now();
            if (DateTime.now().difference(_movingSince!) >=
                _startSustainDuration) {
              _start();
            }
          } else {
            // Grace period before actually resetting: a single noisy or
            // momentarily-slow fix (common at any real speed — a bump, a
            // brief GPS glitch, a fix computed over an oddly short time
            // gap) shouldn't wipe out several seconds of already-confirmed
            // movement. Only a genuinely sustained drop (700ms+ below
            // threshold) resets the sustained-movement clock.
            _belowThresholdSince ??= DateTime.now();
            if (DateTime.now().difference(_belowThresholdSince!) >=
                const Duration(milliseconds: 700)) {
              _movingSince = null;
            }
          }
        });
  }

  Future<void> _start() async {
    // _isStarting closes the race that _isRecording alone can't catch:
    // _isRecording isn't set true until after two awaits below, so two
    // near-simultaneous calls (auto-start firing right as you tap the
    // manual start icon, for instance) could both pass an
    // _isRecording-only guard and each end up creating their own
    // Timer.periodic — doubling the duration tick rate, since the
    // first one never gets canceled once _ticker is overwritten by the
    // second. Setting this synchronously, before any await, blocks a
    // second call immediately.
    if (_isRecording || _isStarting) return;
    _isStarting = true;
    _preStartMotionSub?.cancel();
    _movingSince = null;
    _belowThresholdSince = null;
    _lastPreStartPosition = null;
    _lastPreStartFixTime = null;

    final ok = await _ensurePermission();
    if (!ok) {
      _isStarting = false;
      return;
    }

    final current = await Geolocator.getCurrentPosition();

    // A concurrent call may have already finished starting the
    // recording while we were awaiting above — bail out instead of
    // standing up a second ticker/position stream on top of it.
    if (_isRecording) {
      _isStarting = false;
      return;
    }

    final startLatLng = LatLng(current.latitude, current.longitude);

    setState(() {
      _isRecording = true;
      _distanceMeters = 0;
      _elapsed = Duration.zero;
      _currentSpeedKmh = 0.0;
      _lastPosition = current;
      _currentLatLng = startLatLng;
      _startedAt = DateTime.now();
      _routePoints
        ..clear()
        ..add(startLatLng);
      _route.clear();
      _hazards.clear();
      _communityClusters = [];
    });
    _isStarting = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(startLatLng, 16);
    });

    _loadCommunityHazards(startLatLng);

    // Defensive: cancel any stray timer/stream before creating new
    // ones, in case something above still slipped through.
    _ticker?.cancel();
    _positionSub?.cancel();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) setState(() => _elapsed += const Duration(seconds: 1));

      final secondsSinceFix = DateTime.now()
          .difference(_lastFixTime ?? DateTime.now())
          .inSeconds;

      // Safety net for the 90s stillness check-in — keep feeding it zero
      // speed once fixes have been missing for a couple of seconds. This
      // is harmless even during real movement: a genuine fix a moment
      // later immediately clears the stillness clock again (see
      // _trackStillness), so a brief gap here never accumulates toward
      // the 90s trigger while you're actually still moving.
      if (secondsSinceFix >= 2) {
        _trackStillness(0);
      }

      // Only blank out the *displayed* speed after a longer gap. Real
      // GPS fix intervals commonly drift to 2-3 seconds even while
      // moving (device throttling, weak signal, normal batching) —
      // zeroing the display on every such gap made speed flicker
      // between a real reading and 0 every other second. Wait long
      // enough that a stale reading is actually more likely to mean
      // "stopped" than "the next fix just hasn't arrived yet."
      if (secondsSinceFix >= 5 && _currentSpeedKmh != 0) {
        setState(() => _currentSpeedKmh = 0.0);
      }
    });

    // distanceFilter: 0 — get every fix, even while stationary. A
    // nonzero value here means the stream goes completely silent once
    // you stop moving that many meters between updates, which is why
    // speed wasn't reacting and the stillness dialog wasn't firing.
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
          const maxAcceptableAccuracyMeters = 20.0;
          if (pos.accuracy > maxAcceptableAccuracyMeters) return;

          final latLng = LatLng(pos.latitude, pos.longitude);
          _route.add(
            GpsPoint(
              lat: pos.latitude,
              lng: pos.longitude,
              timestamp: DateTime.now(),
            ),
          );

          // Compute everything first, WITHOUT setState — this fires on
          // every GPS fix (potentially several times a second), and each
          // setState() call triggers a full rebuild of the live map view
          // (polylines, hazard markers, clusters). Three separate setState
          // calls per fix — as this used to have — means up to 3x the
          // rebuild work per tick for no benefit, since they all land in
          // the same frame anyway. One setState at the end batches it into
          // a single rebuild instead.
          double? newDistanceMeters;
          LatLng? newRoutePoint;
          double newSpeedKmh = _currentSpeedKmh;

          if (_lastPosition != null) {
            final segment = Geolocator.distanceBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              pos.latitude,
              pos.longitude,
            );

            // Milliseconds, not whole seconds — fixes can arrive faster than
            // once a second, and truncating to inSeconds could floor a
            // sub-second gap to 0 and skip the speed calc entirely.
            final secondsSinceLast =
                DateTime.now()
                    .difference(_lastFixTime ?? DateTime.now())
                    .inMilliseconds /
                1000;
            final impliedSpeedKmh = secondsSinceLast > 0
                ? (segment / secondsSinceLast) * 3.6
                : 0;
            final maxPlausibleSpeedKmh =
                widget.activityType == ActivityType.ride ? 70.0 : 45.0;

            // Feed every fix into stillness tracking (#13/#14), even ones too
            // small to count as real movement — that's exactly the signal
            // that indicates the user has stopped.
            _trackStillness(impliedSpeedKmh.toDouble());

            if (segment > 2 && impliedSpeedKmh < maxPlausibleSpeedKmh) {
              newDistanceMeters = _distanceMeters + segment;
              newRoutePoint = latLng;
              // Light smoothing (70% previous / 30% new reading) so live
              // speed reacts quickly to real pace changes but doesn't jump
              // around on normal GPS jitter between individual fixes.
              newSpeedKmh = (_currentSpeedKmh * 0.7) + (impliedSpeedKmh * 0.3);
            } else if (impliedSpeedKmh < 1) {
              // Genuinely stopped (not just a filtered-out noisy fix) —
              // let the live speed actually reach zero instead of hovering
              // just above it forever from the smoothing alone.
              newSpeedKmh = 0.0;
            }
          }
          _lastPosition = pos;
          _lastFixTime = DateTime.now();

          setState(() {
            if (newDistanceMeters != null) _distanceMeters = newDistanceMeters;
            if (newRoutePoint != null) _routePoints.add(newRoutePoint);
            _currentSpeedKmh = newSpeedKmh;
            _currentLatLng = latLng;
          });
          _mapController.move(latLng, _mapController.camera.zoom);
          _checkHazardProximity(latLng);
        });
  }

  /// Fetches every hazard other users have shared, keeps only ones within
  /// ~5km of where this activity started (no PostGIS bounding-box query
  /// set up, so filtering happens client-side), then clusters same-type
  /// reports that are close together into single pins with a radius.
  Future<void> _loadCommunityHazards(LatLng near) async {
    const searchRadiusMeters = 5000.0;
    final shared = await HazardService.fetchShared();
    if (!mounted) return;

    final nearby = shared.where((h) {
      final distance = Geolocator.distanceBetween(
        near.latitude,
        near.longitude,
        h.position.latitude,
        h.position.longitude,
      );
      return distance <= searchRadiusMeters;
    }).toList();

    setState(() {
      _communityClusters = HazardCluster.cluster(
        nearby,
        thresholdMeters: HazardClusterConfig.duplicateThresholdMeters,
      );
    });
  }

  String _relativeTimeLabel(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Bottom sheet shown when tapping a hazard cluster pin — how many
  /// times it's been reported and how recently, per the panel's
  /// "duplicate pins... display one icon with a counter" recommendation.
  /// Worded as "reported N times" rather than "by N users" since
  /// HazardReport doesn't track a distinct reporter id, only the reports
  /// themselves — the same person could in principle report twice.
  void _showClusterDetails(HazardCluster cluster) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => _LiveClusterDetailSheet(
        cluster: cluster,
        relativeTimeLabel: _relativeTimeLabel,
      ),
    );
  }

  /// Checks whether [current] is close enough to an unconfirmed-by-me
  /// community hazard to prompt "is this still here?" — the automatic,
  /// proximity-triggered version of the confirm flow, as opposed to
  /// _showClusterDetails above (which is always manual: the user has to
  /// tap the pin themselves). Only one prompt is ever shown at a time,
  /// and each hazard is only prompted once per recording session.
  void _checkHazardProximity(LatLng current) {
    if (_proximityPrompt != null)
      return; // a prompt is already up — don't stack another
    if (_pendingUndo != null)
      return; // don't collide with the just-reported-hazard banner

    for (final cluster in _communityClusters) {
      final distance = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        cluster.center.latitude,
        cluster.center.longitude,
      );
      if (distance > _proximityTriggerMeters) continue;

      // Most recent report in the cluster — matches what the manual
      // sheet shows first, and is the single report this prompt acts on.
      final sorted = [...cluster.reports]
        ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      final candidate = sorted.firstWhere(
        (r) => r.id != null,
        orElse: () => sorted.first,
      );
      if (candidate.id == null ||
          _sessionPromptedHazardIds.contains(candidate.id))
        continue;

      setState(() {
        _sessionPromptedHazardIds.add(candidate.id!);
        _proximityPrompt = candidate;
      });
      // Mirrors the in-app banner as a system notification, same reason
      // as the stillness alert above — the banner only renders while
      // this screen is on top and visible.
      NotificationService.showHazardNearby(candidate.type.label.toLowerCase());
      final roundedDistance = (distance / 10).round() * 10;
      TtsService.speakThen(
        'Caution: ${candidate.type.label.toLowerCase()} reported $roundedDistance meters ahead. Is it still here? Say yes or no.',
        () => VoiceCommandService.listenForYesNo(
          onYes: () => _respondToProximityPrompt(stillHere: true),
          onNo: () => _respondToProximityPrompt(stillHere: false),
        ),
      );
      return; // one at a time
    }
  }

  Future<void> _respondToProximityPrompt({required bool stillHere}) async {
    final report = _proximityPrompt;
    if (report?.id == null || _proximityBusy) return;

    setState(() => _proximityBusy = true);
    final success = stillHere
        ? await CommunityImpactService.verifyStillHere(report!.id!)
        : await HazardService.confirmClear(report!.id!);
    if (!mounted) return;

    setState(() {
      _proximityBusy = false;
      _proximityPrompt = null;
    });
    NotificationService.cancelHazardAlert();

    if (!success) {
      TtsService.speak("Sorry, that couldn't be recorded. You may be the original reporter, or already confirmed this one.");
      _showSnack("Couldn't record that, You may be the original reporter, or already confirmed this one.");
    } else {
      TtsService.speak('Thank you for confirming. Your confirmation is greatly appreciated.');
      _showSnack(stillHere ? 'Thanks!, This helps keep reports trustworthy.' : 'Thanks for helping keep the map accurate.');
    }
  }

  void _dismissProximityPrompt() {
    setState(() => _proximityPrompt = null);
    NotificationService.cancelHazardAlert();
  }

  void _toggleLock() => setState(() => _isLocked = !_isLocked);

  /// Stop button in the live view. Deliberately routes through the same
  /// _confirmExitDuringRecording() flow used for back/nav-away — same
  /// "Do you want to stop your activity?" dialog, same Yes -> save +
  /// congratulations modal, same Continue -> resume exactly where it
  /// left off. Locked recordings block this the same way they already
  /// block leaving the screen.
  void _onStopTapped() {
    if (_isLocked) {
      _showSnack('Recording is locked. Tap Lock to unlock before leaving.');
      return;
    }
    _confirmExitDuringRecording();
  }

  /// Tracks sustained stillness during recording — #13/#14 combined.
  /// If speed stays under _stillThresholdKmh for _checkInAfter, shows a
  /// "still there?" dialog. If movement resumes at any point (including
  /// while the dialog is open), the stillness clock resets and the
  /// dialog auto-dismisses as a false alarm.
  void _trackStillness(double speedKmh) {
    if (_isPaused) return; // skip while exit-confirm dialog is already up

    if (speedKmh < _stillThresholdKmh) {
      _stillSince ??= DateTime.now();
      final stillDuration = DateTime.now().difference(_stillSince!);
      if (stillDuration >= _checkInAfter && !_checkInDialogOpen) {
        _showCheckInDialog();
      }
    } else {
      _stillSince = null;
      if (_checkInDialogOpen && _checkInDialogContext != null) {
        // Movement resumed while the dialog was up — false alarm, dismiss it.
        Navigator.of(_checkInDialogContext!).pop(false);
      }
    }
  }

  Future<void> _showCheckInDialog() async {
    _checkInDialogOpen = true;
    _autoStopSecondsLeft.value = _autoStopAfterSeconds;

    // Mirrors the in-app dialog below as a real system notification —
    // showDialog only renders while this screen is actually on top and
    // visible, so if the phone is locked or another app is in front
    // when stillness is detected, the in-app dialog alone would never
    // be seen. The notification is the part that actually reaches the
    // user in that case.
    NotificationService.showStillnessAlert();

    _autoStopTimer?.cancel();
    _autoStopTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _autoStopSecondsLeft.value -= 1;
      if (_autoStopSecondsLeft.value <= 0) {
        timer.cancel();
        if (_checkInDialogContext != null) {
          Navigator.of(
            _checkInDialogContext!,
          ).pop(true); // no response -> auto-stop
        }
      }
    });

    final shouldStop = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _checkInDialogContext = dialogContext;
        return _CheckInDialog(secondsLeft: _autoStopSecondsLeft);
      },
    );

    _autoStopTimer?.cancel();
    _checkInDialogOpen = false;
    _checkInDialogContext = null;
    _stillSince = null; // fresh stillness window either way
    NotificationService.cancelStillnessAlert(); // resolved one way or another — clear it so it doesn't linger

    if (!mounted) return;

    if (shouldStop == true) {
      final wasAutoTimeout = _autoStopSecondsLeft.value <= 0;
      if (wasAutoTimeout) {
        // No response at all — can't ask why, just stop. This is the
        // fully-automated path: if the user has genuinely finished (or
        // can't respond), the activity ends on its own.
        _showSnack('Activity auto-stopped due to inactivity.');
        await _stopAndSave();
      } else {
        // User actively tapped "No" — ask why before actually ending
        // the recording, so the stop reason is captured.
        final reason = await _showStopReasonDialog();
        if (!mounted) return;
        _pendingStopReason = reason;
        if (reason != null) _showSnack('Stopping — $reason');
        await _stopAndSave();
      }
    }
    // shouldStop == false (or null from a race) -> "Yes, I'm okay" or
    // movement-resumed dismissal; recording just continues normally.
  }

  /// Shown after the user actively confirms they've stopped (not on a
  /// silent auto-timeout) — captures why, purely for the rider's own
  /// record. Not persisted to the database in this pass; stored only
  /// long enough to prefill the completion modal's caption suggestion.
  Future<String?> _showStopReasonDialog() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _StopReasonDialog(),
    );
  }

  Future<void> _openReportHazard() async {
    final type = await showReportHazardSheet(context);
    if (type == null || _lastPosition == null) return;
    _reportHazard(type);
  }

  /// Reports a hazard: shows the marker + undo banner immediately
  /// (optimistic UI), then persists it to Supabase in the background.
  /// Stays private (not visible to other users) until the activity this
  /// report belongs to is shared — see _shareToCommunity in the modal.
  Future<void> _reportHazard(HazardType type) async {
    var report = HazardReport(
      type: type,
      position: LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
      reportedAt: DateTime.now(),
    );

    setState(() {
      _hazards.add(report);
      _pendingUndo = report;
      _undoSecondsLeft = 3;
    });

    _undoTimer?.cancel();
    _undoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _undoSecondsLeft--);
      if (_undoSecondsLeft <= 0) {
        timer.cancel();
        setState(() => _pendingUndo = null);
      }
    });

    final saved = await HazardService.report(report);
    if (!mounted) return;

    if (saved != null) {
      setState(() {
        final index = _hazards.indexOf(report);
        if (index != -1) _hazards[index] = saved;
        if (_pendingUndo == report) _pendingUndo = saved;
      });
    } else {
      _showSnack('Hazard shown on your map, but could not be saved online.');
    }
  }

  void _undoHazardReport() {
    if (_pendingUndo == null) return;
    final toRemove = _pendingUndo!;
    _undoTimer?.cancel();
    setState(() {
      _hazards.remove(toRemove);
      _pendingUndo = null;
    });
    if (toRemove.id != null) {
      HazardService.delete(toRemove.id!);
    }
  }

  Future<void> _stopAndSave() async {
    _positionSub?.cancel();
    _ticker?.cancel();

    if (_distanceMeters <= 0 && _elapsed.inSeconds < 5) {
      if (mounted) _resetToPreStart();
      return;
    }

    setState(() => _isSaving = true);

    final provider = context.read<ActivityProvider>();
    final saved = await provider.saveActivity(
      type: widget.activityType,
      subtype: widget.subtype,
      distanceKm: _distanceMeters / 1000,
      duration: _elapsed,
      startedAt: _startedAt ?? DateTime.now(),
      route: _route,
    );

    if (!mounted) return;

    if (saved != null) {
      // Snapshot before _resetToPreStart() clears session state, so the
      // completion modal can still show the route and offer to share
      // this session's hazard reports.
      final routeSnapshot = List<LatLng>.from(_routePoints);
      final hazardIdsSnapshot = _hazards
          .where((h) => h.id != null)
          .map((h) => h.id!)
          .toList();

      // Link (not yet share) these hazards to the saved activity, so
      // they're associated with it for reference even before sharing.
      // AWAITED: the completion modal's "Share to Community" button can
      // fire HazardService.shareHazards() the instant it's shown, and
      // that call can depend on activity_id already being set on the
      // hazard rows (RLS or backend validation) — so this must finish
      // before the modal appears, or a fast tap on Share silently loses
      // the hazard reports even though the activity itself shares fine.
      // Skipped for a pending-sync (offline-queued) activity — its id is
      // a local placeholder, not a real Supabase row, so there's nothing
      // valid to link to yet. Known limitation: hazards reported during
      // an offline session aren't currently re-linked after the activity
      // syncs later — a reasonable follow-up, not covered in this pass.
      if (hazardIdsSnapshot.isNotEmpty && !saved.pendingSync) {
        await HazardService.linkToActivity(hazardIdsSnapshot, saved.id!);
        if (!mounted) return;
      }

      setState(() => _isSaving = false);

      if (saved.pendingSync) {
        // Kick a retry now rather than waiting for some other screen to
        // call loadActivities()/syncPending(). The completion modal is
        // reactive to ActivityProvider (see _CompletionModal below), so
        // if this succeeds while the modal is still open, Share unlocks
        // on its own without the user needing to do anything.
        provider.syncPending();
      }

      _resetToPreStart();
      _showCompletionModal(saved, routeSnapshot, hazardIdsSnapshot);
    } else {
      setState(() => _isSaving = false);
      _showSnack(provider.errorMessage ?? 'Unable to save activity.');
    }
  }

  void _resetToPreStart() {
    _autoStopTimer?.cancel();
    _stillSince = null;
    _checkInDialogOpen = false;
    _checkInDialogContext = null;

    setState(() {
      _isRecording = false;
      _isLocked = false;
      _isPaused = false;
      _distanceMeters = 0;
      _elapsed = Duration.zero;
      _lastPosition = null;
      _lastFixTime = null;
      _currentSpeedKmh = 0.0;
      _routePoints.clear();
      _route.clear();
      _hazards.clear();
      _pendingUndo = null;
      _communityClusters = [];
      _sessionPromptedHazardIds.clear();
      _proximityPrompt = null;
      // Deliberately NOT resetting _currentLatLng/_hasCenteredMap — keeps
      // the map showing your last known position instead of jumping
      // back to an empty/default view between sessions.
    });

    // Ready to auto-detect the next activity starting.
    _watchForAutoStart();
  }

  /// Called whenever the user tries to leave RecordScreen mid-recording
  /// (system back, swipe-back, or tapping another bottom-nav tab) while
  /// NOT locked. Pauses the duration timer, asks "stop your activity?",
  /// then either stops+saves (same flow as tapping Stop, including the
  /// congratulations/share modal) or resumes exactly where it left off.
  Future<void> _confirmExitDuringRecording() async {
    if (!_isRecording) return;

    setState(() => _isPaused = true);

    final shouldStop = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ExitConfirmDialog(),
    );

    if (!mounted) return;

    if (shouldStop == true) {
      await _stopAndSave(); // handles saving + congratulations modal + reset
    } else {
      setState(() => _isPaused = false); // resume duration where it left off
    }
  }

  Future<void> _showCompletionModal(
    Activity activity,
    List<LatLng> route,
    List<String> hazardIds,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CompletionModal(
        activity: activity,
        route: route,
        hazardIds: hazardIds,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept every exit attempt while recording — Lock decides what
      // happens next (hard block vs. confirm dialog), not whether we
      // intercept at all.
      canPop: !_isRecording,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isLocked) {
          _showSnack('Recording is locked. Tap Lock to unlock before leaving.');
          return;
        }
        _confirmExitDuringRecording();
      },
      child: Scaffold(
        backgroundColor: const Color(0xff050505),
        body: SafeArea(
          child: _isRecording ? _buildLiveView() : _buildPreStartView(),
        ),
      ),
    );
  }

  Widget _buildPreStartView() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  title: Text(
                    _isCycling ? 'Cycling' : 'Running',
                    style: const TextStyle(color: Colors.white),
                  ),
                  centerTitle: true,
                ),
                const SizedBox(height: 4),
                // Subtype was already chosen on SubtypeSelectionScreen
                // (see widget.subtype) — just shown here for confirmation,
                // not re-editable on this screen.
                Text(
                  widget.subtype,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
                if (_isRetracing) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.near_me,
                        color: Colors.greenAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Retracing ${widget.referenceRouteLabel ?? "a shared route"}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                // Tapping the icon is a quiet fallback trigger — not a
                // labeled "Start" button — in case GPS is slow to detect
                // movement (e.g. weak signal). See _start()'s guard
                // against double-invocation for why this is safe to
                // combine with auto-detection running at the same time.
                InkWell(
                  onTap: _start,
                  borderRadius: BorderRadius.circular(80),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue.withValues(alpha: .08),
                    ),
                    child: Icon(
                      _isCycling ? Icons.pedal_bike : Icons.directions_run,
                      color: Colors.blue,
                      size: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue.shade200,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Detecting movement to start automatically…',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                const SizedBox(height: 115),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    // Recording hasn't started yet at this point, so
                    // there's nothing to confirm/lose — a direct jump
                    // to Home is fine (matches the same '/home' route
                    // other screens use to get back to the root tab).
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/home', (route) => false),
                    icon: const Icon(Icons.close, size: 22),
                    label: const Text(
                      'Cancel Record',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveView() {
    final km = _distanceMeters / 1000;
    final avgSpeed = _elapsed.inSeconds > 0
        ? km / (_elapsed.inSeconds / 3600)
        : 0.0;
    final current = _routePoints.isNotEmpty
        ? _routePoints.last
        : const LatLng(0, 0);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: current, initialZoom: 16),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.vitrax.app',
                  ),
                  // Reference trail (the original sharer's exact path) —
                  // drawn first so your own live-recorded polyline below
                  // always renders on top of it, staying visible even
                  // where the two overlap.
                  if (_isRetracing)
                    PolylineLayer(
                      // Distinguished from your own live track by color
                      // alone (green vs. blue) rather than a dash pattern —
                      // keeps this compatible regardless of exact
                      // flutter_map version, since dashed-line support
                      // varies across releases.
                      polylines: [
                        Polyline(
                          points: _referenceLatLngs,
                          color: Colors.greenAccent.withValues(alpha: .85),
                          strokeWidth: 5,
                        ),
                      ],
                    ),
                  if (_isRetracing)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _referenceLatLngs.first,
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.greenAccent,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                        Marker(
                          point: _referenceLatLngs.last,
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.greenAccent,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.flag,
                              color: Colors.black,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_routePoints.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: Colors.blue,
                          strokeWidth: 5,
                        ),
                      ],
                    ),

                  // ---- Community hazard cluster radius circles ----
                  // Drawn under the markers so the translucent area shows
                  // roughly where the underlying reports were made.
                  CircleLayer(
                    circles: _communityClusters
                        .map(
                          (c) => CircleMarker(
                            point: c.center,
                            radius: c.radiusMeters,
                            useRadiusInMeter: true,
                            color: c.type.color.withValues(alpha: .15),
                            borderColor: c.type.color.withValues(alpha: .5),
                            borderStrokeWidth: 1.5,
                          ),
                        )
                        .toList(),
                  ),

                  MarkerLayer(
                    markers: [
                      Marker(
                        point: current,
                        width: 26,
                        height: 26,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),

                      // This session's own reports (not yet necessarily shared).
                      ..._hazards.map(
                        (h) => Marker(
                          point: h.position,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: h.type.color,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              h.type.icon,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),

                      // Community clusters — shows a count badge when more
                      // than one report was merged into this pin. Tap for
                      // details (how many times, how recently).
                      ..._communityClusters.map(
                        (c) => Marker(
                          point: c.center,
                          width: 44,
                          height: 44,
                          child: GestureDetector(
                            onTap: () => _showClusterDetails(c),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: c.type.color,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    c.type.icon,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                if (c.count > 1)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        '${c.count}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 12,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.red, size: 10),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'GPS Tracking',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (_isRetracing)
                Positioned(
                  top: 46,
                  left: 60,
                  right: 60,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Retracing ${widget.referenceRouteLabel ?? "a shared route"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                right: 16,
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _StatRow(
                        icon: Icons.map_outlined,
                        iconColor: Colors.blue,
                        value: km.toStringAsFixed(2),
                        unit: 'km',
                        label: 'DISTANCE',
                      ),
                      const Divider(color: Colors.white12, height: 18),
                      _StatRow(
                        icon: Icons.access_time,
                        iconColor: Colors.greenAccent,
                        value: _formatDuration(_elapsed),
                        unit: '',
                        label: 'DURATION',
                      ),
                      const Divider(color: Colors.white12, height: 18),
                      _StatRow(
                        icon: Icons.speed,
                        iconColor: Colors.lightBlueAccent,
                        value: _currentSpeedKmh.toStringAsFixed(1),
                        unit: 'km/h',
                        label: 'SPEED',
                      ),
                      const Divider(color: Colors.white12, height: 18),
                      _StatRow(
                        icon: Icons.bolt,
                        iconColor: Colors.amber,
                        value: avgSpeed.toStringAsFixed(1),
                        unit: 'km/h',
                        label: 'AVG. SPEED',
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 210,
                child: InkWell(
                  onTap: () => _mapController.move(current, 16),
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
                ),
              ),
              if (_pendingUndo != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 190,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff141414),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Hazard reported successfully!',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: _undoHazardReport,
                          child: Text(
                            'Undo ($_undoSecondsLeft)',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_proximityPrompt != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 190,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff141414),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _proximityPrompt!.type.color.withValues(
                          alpha: .5,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _proximityPrompt!.type.icon,
                              color: _proximityPrompt!.type.color,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Is this ${_proximityPrompt!.type.label.toLowerCase()} still here?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: _proximityBusy
                                  ? null
                                  : _dismissProximityPrompt,
                              child: Icon(
                                Icons.close,
                                color: Colors.grey.shade500,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_proximityBusy)
                          const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _respondToProximityPrompt(
                                    stillHere: false,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green,
                                    side: const BorderSide(color: Colors.green),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cleared',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _respondToProximityPrompt(
                                    stillHere: true,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange,
                                    side: const BorderSide(
                                      color: Colors.orange,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'Still Here',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ControlBox(
                            icon: _isLocked ? Icons.lock : Icons.lock_open,
                            label: 'Lock',
                            onTap: _toggleLock,
                            color: const Color(0xff1b1b1b),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xff1b1b1b),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _formatDuration(_elapsed),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Duration',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ControlBox(
                            icon: Icons.stop_rounded,
                            label: 'Stop',
                            onTap: _onStopTapped,
                            color: const Color(0xff3a1414),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openReportHazard,
                        icon: const Icon(Icons.warning_amber_rounded),
                        label: const Text(
                          'Report Hazard',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Saving overlay — shown while an auto-stop (check-in
              // timeout or "I'm Done") or exit-confirm Stop is in
              // progress. No dedicated Stop button exists to show this
              // inline anymore, so it's a full-screen dim + spinner.
              // Also stays up while hazards are being linked to the
              // saved activity, since that now happens before the
              // completion modal is shown.
              if (_isSaving)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: .6),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Saving your activity…',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Post-recording congratulations modal: stats, a static route preview,
/// and actions to share to the community feed (which also shares any
/// hazards reported during this session) or spin the activity into a
/// challenge.
class _CompletionModal extends StatefulWidget {
  final Activity activity;
  final List<LatLng> route;
  final List<String> hazardIds;

  const _CompletionModal({
    required this.activity,
    required this.route,
    required this.hazardIds,
  });

  @override
  State<_CompletionModal> createState() => _CompletionModalState();
}

class _CompletionModalState extends State<_CompletionModal> {
  bool _isSharing = false;
  bool _shared = false;
  bool _isRetryingSync = false;
  bool _challengeTapped =
      false; // disables the Create a Challenge button after use

  String _durationLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) {
      return '$h hour${h == 1 ? '' : 's'}${m > 0 ? ' $m minute${m == 1 ? '' : 's'}' : ''}';
    }
    return '$m minute${m == 1 ? '' : 's'}';
  }

  Future<void> _shareToCommunity() async {
    // Re-resolve here too — this can be called some time after build(),
    // and widget.activity.id is the original local_... placeholder id
    // for an activity that synced after this modal opened. Using that
    // stale id would call markActivityShared on an id Supabase has
    // never heard of.
    final provider = context.read<ActivityProvider>();
    final current = provider.resolveCurrent(widget.activity);
    if (current.id == null || current.pendingSync) return;
    setState(() => _isSharing = true);

    final results = await Future.wait([
      provider.markActivityShared(current.id!),
      HazardService.shareHazards(widget.hazardIds),
    ]);
    final activityShared = results[0];
    final hazardsShared = results[1];

    if (!mounted) return;
    setState(() {
      _isSharing = false;
      _shared = activityShared;
    });

    if (!activityShared) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not share right now, Please try again from Recent Activity later.',
          ),
        ),
      );
    } else if (!hazardsShared && widget.hazardIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Activity shared, but hazard reports could not be shared, Please try again later.',
          ),
        ),
      );
    }
  }

  Future<void> _retrySync() async {
    setState(() => _isRetryingSync = true);
    await context.read<ActivityProvider>().syncPending();
    if (!mounted) return;
    setState(() => _isRetryingSync = false);
    // No need to manually update state beyond this — build() re-resolves
    // the activity from ActivityProvider on every rebuild, so a
    // successful sync here surfaces automatically (see build() below).
  }

  void _createChallenge() {
    setState(() => _challengeTapped = true);
    // resolveCurrent, not widget.activity directly — if this synced in
    // the background since the modal opened (see _retrySync above),
    // widget.activity could still be the stale local_... placeholder,
    // which has no real Supabase id for other participants' attempts
    // to eventually reference.
    final provider = context.read<ActivityProvider>();
    final current = provider.resolveCurrent(widget.activity);
    // Pushed on top, not a replacement — this modal stays underneath and
    // is still here (with this button now disabled) when the user comes
    // back, so Done's enabled state still only depends on sharing.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateChallengeScreen(seedActivity: current),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Re-resolved every rebuild (context.watch triggers a rebuild on
    // every ActivityProvider change) rather than trusting widget.activity
    // directly — that field is a snapshot from the moment this modal was
    // opened, and a background sync retry (see _retrySync and the
    // pendingSync check in _stopAndSave) can flip pendingSync to false
    // after that snapshot was taken. Matched by startedAt, not id — a
    // locally-queued activity's id changes once it syncs.
    final provider = context.watch<ActivityProvider>();
    final a = provider.resolveCurrent(widget.activity);
    final hasHazards = widget.hazardIds.isNotEmpty;

    return Dialog(
      backgroundColor: const Color(0xff111111),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Congratulations! 🎉',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              if (a.pendingSync)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        color: Colors.orange,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Saved on your device, Will sync and become shareable once you\'re back online.',
                          style: TextStyle(
                            color: Colors.orange.shade200,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Text(
                'You made ${a.distanceKm.toStringAsFixed(2)} km in ${_durationLabel(a.duration)} '
                'at an average speed of ${a.avgSpeedKmh.toStringAsFixed(1)} km/h!',
                style: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 15,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              if (widget.route.length > 1)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 160,
                    child: IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCameraFit: CameraFit.coordinates(
                            coordinates: widget.route,
                            padding: const EdgeInsets.all(24),
                          ),
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.vitrax.app',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: widget.route,
                                color: Colors.blue,
                                strokeWidth: 4,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ModalStat(
                    label: 'Distance',
                    value: '${a.distanceKm.toStringAsFixed(2)} km',
                  ),
                  _ModalStat(
                    label: 'Duration',
                    value: _durationLabel(a.duration),
                  ),
                  _ModalStat(
                    label: 'Avg Speed',
                    value: '${a.avgSpeedKmh.toStringAsFixed(1)} km/h',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---- Share explanation ----
              Text(
                hasHazards
                    ? 'Share with the community so everyone can see your reports and stay informed.'
                    : 'Share with the community so everyone can see your progress.',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12.5,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Highlighted (filled, blue) while actionable — sharing is
              // what makes hazard reports from this ride visible to other
              // users, so it's pushed as the primary action. Fades to a
              // muted outline once done, handing prominence to Done.
              SizedBox(
                width: double.infinity,
                child: _shared
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Shared with Community'),
                        style: OutlinedButton.styleFrom(
                          disabledForegroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _isSharing
                            ? null
                            : (a.pendingSync
                                  ? (_isRetryingSync ? null : _retrySync)
                                  : _shareToCommunity),
                        icon: (_isSharing || _isRetryingSync)
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                a.pendingSync ? Icons.refresh : Icons.share,
                                size: 18,
                              ),
                        label: Text(
                          a.pendingSync ? 'Retry Sync' : 'Share to Community',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              // Also highlighted while available, but tapping it never
              // affects Done's enabled state — only sharing does.
              SizedBox(
                width: double.infinity,
                child: _challengeTapped
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Challenge Created'),
                        style: OutlinedButton.styleFrom(
                          disabledForegroundColor: Colors.grey,
                          side: BorderSide(color: Colors.grey.shade700),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _createChallenge,
                        icon: const Icon(Icons.emoji_events_outlined, size: 18),
                        label: const Text('Create a Challenge'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              // Stays disabled/muted until the activity has actually been
              // shared — Create a Challenge does NOT unlock this, only
              // sharing does, since that's what makes this ride's hazard
              // reports visible to other users.
              //
              // Exception: if the activity is still pendingSync (recorded
              // offline, not synced yet), sharing is genuinely impossible
              // right now — Done stays enabled so the user isn't locked out
              // of a barrierDismissible: false dialog with no way out. It'll
              // become shareable later once ActivityProvider syncs it.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_shared || a.pendingSync)
                      ? () => Navigator.pop(context)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: const Color(0xff1a1a1a),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _shared || a.pendingSync ? 'Done' : 'Share to enable Done',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalStat extends StatelessWidget {
  final String label;
  final String value;
  const _ModalStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;
  final String label;

  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    Text(
                      unit,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ControlBox({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation shown when the user tries to leave RecordScreen mid-
/// recording (unlocked). Duration is already paused by the caller before
/// this shows — Yes stops+saves the activity (same as the Stop button),
/// No dismisses and resumes exactly where it left off.
class _ExitConfirmDialog extends StatelessWidget {
  const _ExitConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.withValues(alpha: .15),
              ),
              child: const Icon(
                Icons.pause_circle_outline,
                color: Colors.orange,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Do you want to stop your activity?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your timer is paused. Choose Stop to save what you\'ve recorded, or Continue to keep going.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Stop',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Safety check-in shown when the app detects sustained stillness during
/// a recording (#14). Counts down toward an automatic stop (#13) if
/// there's no response — but auto-dismisses immediately if movement
/// resumes before that happens (handled by the caller, _trackStillness).
class _CheckInDialog extends StatelessWidget {
  final ValueNotifier<int> secondsLeft;
  const _CheckInDialog({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: .15),
              ),
              child: const Icon(
                Icons.help_outline,
                color: Colors.blue,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Are you okay?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We haven't detected movement in a while.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: secondsLeft,
              builder: (context, value, _) => Text(
                'Auto-stopping in ${value}s if no response',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Yes, I\'m okay',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'No',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after the user actively confirms they've stopped moving —
/// captures why, so a mid-ride problem (flat tire, injury, etc.) is
/// distinguishable from simply finishing the activity.
class _StopReasonDialog extends StatelessWidget {
  const _StopReasonDialog();

  static const _reasons = [
    ('Finished my activity', Icons.flag_outlined),
    ('Flat tire / mechanical issue', Icons.build_outlined),
    ('Feeling unwell or injured', Icons.medical_services_outlined),
    ('Weather conditions', Icons.cloud_outlined),
    ('Safety or traffic concern', Icons.warning_amber_outlined),
    ('Other', Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What happened?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "This just helps keep your own record, It isn't shared unless you choose to.",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            ..._reasons.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => Navigator.pop(context, r.$1),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff1a1a1a),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(r.$2, color: Colors.blue, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            r.$1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(
                  'Skip',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Manual version of the hazard confirm flow, shown when the user taps
/// a hazard pin themselves on the live recording map. Mirrors
/// RoutesScreen's _ClusterDetailSheet (same "Still Here?" / "Clear Now
/// (x/3)" pattern, same per-report busy guard) so the two manual entry
/// points behave identically — the only difference from the automatic
/// proximity prompt (_checkHazardProximity) is that this one requires
/// the user to tap the pin instead of triggering on its own.
class _LiveClusterDetailSheet extends StatefulWidget {
  final HazardCluster cluster;
  final String Function(DateTime) relativeTimeLabel;
  const _LiveClusterDetailSheet({
    required this.cluster,
    required this.relativeTimeLabel,
  });

  @override
  State<_LiveClusterDetailSheet> createState() =>
      _LiveClusterDetailSheetState();
}

class _LiveClusterDetailSheetState extends State<_LiveClusterDetailSheet> {
  Map<String, ({int count, bool byMe})> _clearStatus = {};
  Map<String, ({int count, bool byMe})> _verifyStatus = {};
  bool _loadingStatus = true;
  final Set<String> _busyIds = {};

  late final List<HazardReport> _sortedReports = [...widget.cluster.reports]
    ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final ids = _sortedReports
        .where((r) => r.id != null)
        .map((r) => r.id!)
        .toList();
    final clearStatus = await HazardService.fetchClearStatus(ids);
    final verifyStatus = await CommunityImpactService.fetchVerificationStatus(
      ids,
    );
    if (!mounted) return;
    setState(() {
      _clearStatus = clearStatus;
      _verifyStatus = verifyStatus;
      _loadingStatus = false;
    });
  }

  Future<void> _confirmClear(String hazardId) async {
    setState(() => _busyIds.add(hazardId));
    final success = await HazardService.confirmClear(hazardId);
    if (!mounted) return;
    setState(() => _busyIds.remove(hazardId));

    if (success) {
      _loadStatus();
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't confirm, You may be the original reporter, or you've already confirmed this one.",
          ),
        ),
      );
    }
  }

  Future<void> _confirmStillHere(String hazardId) async {
    setState(() => _busyIds.add(hazardId));
    final success = await CommunityImpactService.verifyStillHere(hazardId);
    if (!mounted) return;
    setState(() => _busyIds.remove(hazardId));

    if (success) {
      _loadStatus();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks, This helps keep reports trustworthy.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't confirm, You may be the original reporter, or you've already confirmed this one.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cluster = widget.cluster;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cluster.type.color,
                  ),
                  child: Icon(cluster.type.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cluster.type.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        cluster.count == 1
                            ? 'Reported once'
                            : 'Reported ${cluster.count} times',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _sortedReports.length,
                separatorBuilder: (_, __) =>
                    Divider(color: Colors.white10, height: 20),
                itemBuilder: (context, index) {
                  final r = _sortedReports[index];
                  final clearStatus = r.id != null ? _clearStatus[r.id] : null;
                  final clearCount = clearStatus?.count ?? 0;
                  final clearedByMe = clearStatus?.byMe ?? false;
                  final verifyStatus = r.id != null
                      ? _verifyStatus[r.id]
                      : null;
                  final verifiedByMe = verifyStatus?.byMe ?? false;
                  final busy = r.id != null && _busyIds.contains(r.id);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 6,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.relativeTimeLabel(r.reportedAt),
                            style: TextStyle(
                              color: Colors.grey.shade300,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (r.id != null) ...[
                        const SizedBox(height: 8),
                        if (_loadingStatus)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton(
                                onPressed: (verifiedByMe || busy)
                                    ? null
                                    : () => _confirmStillHere(r.id!),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  side: BorderSide(
                                    color: verifiedByMe
                                        ? Colors.blue
                                        : Colors.white24,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: busy
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        verifiedByMe
                                            ? 'Verified still here'
                                            : 'Still Here?',
                                        style: TextStyle(
                                          color: verifiedByMe
                                              ? Colors.blue
                                              : Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                              ),
                              OutlinedButton(
                                onPressed: (clearedByMe || busy)
                                    ? null
                                    : () => _confirmClear(r.id!),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  side: BorderSide(
                                    color: clearedByMe
                                        ? Colors.green
                                        : Colors.white24,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: busy
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        clearedByMe
                                            ? 'Confirmed $clearCount/3'
                                            : 'Clear Now ($clearCount/3)',
                                        style: TextStyle(
                                          color: clearedByMe
                                              ? Colors.green
                                              : Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Clear Now" if this is gone when you pass by. 3 confirmations from other users removes it automatically.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
