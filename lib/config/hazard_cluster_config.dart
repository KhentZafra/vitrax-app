/// Tuning for merging duplicate hazard reports into a single pin, per
/// the panel's recommendation: "if the same road defect is reported
/// multiple times, place duplicate pins in the same area to display one
/// icon with a counter" (e.g. "Reported 12 times").
class HazardClusterConfig {
  /// The panel specified ~10m. This is set slightly wider (15m) to
  /// absorb realistic phone GPS accuracy (commonly 5-15m, worse under
  /// tree cover or between buildings) — two reports of the same physical
  /// pothole can easily land 10-12m apart on raw GPS alone, and a
  /// literal 10m cutoff would wrongly treat them as different hazards.
  static const duplicateThresholdMeters = 15.0;
}
