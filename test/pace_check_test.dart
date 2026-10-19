import 'package:flutter_test/flutter_test.dart';
import 'package:vitrax_app/models/activity.dart';
import 'package:vitrax_app/services/challenge_service.dart';

/// The challenge anti-cheat: an attempt faster than a person can really go
/// (for example someone riding in a car) is rejected.
void main() {
  group('cycling', () {
    test('normal and fast riding is accepted', () {
      expect(ChallengeService.isPlausiblePace(ActivityType.ride, 18), isTrue);
      expect(ChallengeService.isPlausiblePace(ActivityType.ride, 45), isTrue);
    });
    test('exactly 70 km/h is the limit', () {
      expect(ChallengeService.isPlausiblePace(ActivityType.ride, 70), isTrue);
      expect(ChallengeService.isPlausiblePace(ActivityType.ride, 70.1), isFalse);
    });
    test('car speeds are rejected', () {
      expect(ChallengeService.isPlausiblePace(ActivityType.ride, 90), isFalse);
    });
  });

  group('running and walking', () {
    test('normal running is accepted', () {
      expect(ChallengeService.isPlausiblePace(ActivityType.run, 10), isTrue);
      expect(ChallengeService.isPlausiblePace(ActivityType.walk, 5), isTrue);
    });
    test('exactly 45 km/h is the limit', () {
      expect(ChallengeService.isPlausiblePace(ActivityType.run, 45), isTrue);
      expect(ChallengeService.isPlausiblePace(ActivityType.run, 45.1), isFalse);
    });
    test('a cycling speed is not believable for a run', () {
      expect(ChallengeService.isPlausiblePace(ActivityType.run, 60), isFalse);
      expect(ChallengeService.isPlausiblePace(ActivityType.walk, 60), isFalse);
      // ...but the same speed is fine on a bike
      expect(ChallengeService.isPlausiblePace(ActivityType.ride, 60), isTrue);
    });
  });
}
