// Activity start times are saved as the phone's clock reading marked as UTC
// (for example a ride at 2:14 PM is stored as 14:14 UTC). Challenge dates are
// real moments. These two helpers translate between the two, so a challenge
// that ends at 8:00 PM really ends at 8:00 PM on the phone's clock.
// If activities are ever saved as true UTC, these must become plain
// .toUtc() / .toLocal() conversions.

/// A local DateTime -> the same clock reading marked as UTC, to compare
/// against a stored started_at.
DateTime clockAsUtc(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second);

/// A stored started_at -> the local DateTime with the same clock reading.
DateTime clockOf(DateTime stored) =>
    DateTime(stored.year, stored.month, stored.day, stored.hour, stored.minute, stored.second);
