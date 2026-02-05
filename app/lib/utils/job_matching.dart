import 'dart:math';

/// Hard area cutoff in kilometers. Jobs beyond this straight-line distance
/// from the helper are excluded entirely from the dashboard count.
/// 100km covers a full Spanish province (Alicante province is ~60km N-S).
/// When launching in Barcelona (400km away), no cross-city leakage.
const double kAreaCutoffKm = 100.0;

// --- Haversine distance helpers ---

double haversineDistanceKm(
    double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0; // Earth radius in km
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

double _toRadians(double deg) => deg * pi / 180;

/// Urban speed averages in km/h per transport mode.
const Map<String, double> urbanSpeeds = {
  'car': 30.0,
  'transit': 20.0,
  'escooter': 15.0,
  'bike': 12.0,
  'walk': 5.0,
};

/// Route buffer multipliers: real routes are longer than straight line.
const Map<String, double> routeBuffer = {
  'car': 1.5,
  'bike': 1.5,
  'walk': 1.8,
  'transit': 2.5,
  'escooter': 1.5,
};

/// Rough travel time estimate in minutes using urban speed averages.
double estimateTravelMinutes(double distanceKm, String transportMode) {
  final speed = urbanSpeeds[transportMode] ?? 15.0;
  return (distanceKm / speed) * 60;
}

/// Parse "HH:MM" or "HH:MM:SS" into minutes since midnight.
int parseTimeMinutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Check if a job matches a helper's availability slots.
/// Returns true if the job is flexible, has no date, or the helper has no slots.
bool jobMatchesAvailability({
  required Map<String, dynamic> job,
  required List<Map<String, dynamic>> availabilitySlots,
}) {
  if (availabilitySlots.isEmpty) return true;

  final isFlexible = job['is_flexible'] == true;
  final scheduledDate = job['scheduled_date'] as String?;
  final scheduledTime = job['scheduled_time'] as String?;

  if (isFlexible || scheduledDate == null) return true;

  final dateObj = DateTime.parse(scheduledDate);
  // Convert Dart weekday (1=Mon, 7=Sun) to DB convention (0=Sun, 1=Mon, ..., 6=Sat)
  final dayOfWeek = dateObj.weekday % 7;

  int? jobTimeMinutes;
  if (scheduledTime != null) {
    try {
      jobTimeMinutes = parseTimeMinutes(scheduledTime);
    } catch (_) {}
  }

  for (final slot in availabilitySlots) {
    // Check specific date match
    if (slot['specific_date'] == scheduledDate) {
      if (jobTimeMinutes == null) return true;
      final start = parseTimeMinutes(slot['start_time'] as String);
      final end = parseTimeMinutes(slot['end_time'] as String);
      if (jobTimeMinutes >= start && jobTimeMinutes <= end) return true;
    }
    // Check recurring day match
    final slotRecurring = slot['is_recurring'] as bool? ?? true;
    final slotDow = slot['day_of_week'] as int;
    if (slotRecurring && slotDow == dayOfWeek) {
      if (jobTimeMinutes == null) return true;
      final start = parseTimeMinutes(slot['start_time'] as String);
      final end = parseTimeMinutes(slot['end_time'] as String);
      if (jobTimeMinutes >= start && jobTimeMinutes <= end) return true;
    }
  }

  return false;
}

/// Result of classifying a job against helper preferences.
enum JobMatchResult {
  matched,    // Passes all preference filters
  nearbyOnly, // Within area cutoff but fails one or more preference filters
  tooFar,     // Beyond the hard area cutoff — excluded entirely
}

/// Classify a job for a helper. Returns matched/nearbyOnly/tooFar.
JobMatchResult classifyJob({
  required Map<String, dynamic> job,
  required double? helperLat,
  required double? helperLng,
  required List<String> transportModes,
  required int maxTravelMinutes,
  required List<String> notifySkills,
  required double? minPriceAmount,
  required double? minHourlyRate,
  required List<Map<String, dynamic>> availabilitySlots,
}) {
  final jobLat = (job['location_lat'] as num?)?.toDouble();
  final jobLng = (job['location_lng'] as num?)?.toDouble();

  // --- Hard area cutoff ---
  if (helperLat != null &&
      helperLng != null &&
      jobLat != null &&
      jobLng != null) {
    final distKm = haversineDistanceKm(helperLat, helperLng, jobLat, jobLng);
    if (distKm > kAreaCutoffKm) return JobMatchResult.tooFar;
  }

  // --- Preference filters (any failure = nearbyOnly) ---

  // Skill filter
  final skillId = job['skill_id'] as String?;
  if (notifySkills.isNotEmpty && skillId != null) {
    if (!notifySkills.contains(skillId)) return JobMatchResult.nearbyOnly;
  }

  // Price filter
  final priceAmount = (job['price_amount'] as num?)?.toDouble();
  final priceType = job['price_type'] as String?;
  if (priceAmount != null) {
    if (priceType == 'hourly' && minHourlyRate != null) {
      if (priceAmount < minHourlyRate) return JobMatchResult.nearbyOnly;
    } else if (priceType == 'fixed' && minPriceAmount != null) {
      if (priceAmount < minPriceAmount) return JobMatchResult.nearbyOnly;
    }
  }

  // Distance / travel time filter
  if (helperLat != null &&
      helperLng != null &&
      transportModes.isNotEmpty &&
      jobLat != null &&
      jobLng != null) {
    final distKm = haversineDistanceKm(helperLat, helperLng, jobLat, jobLng);

    double bestTravelMinutes = double.infinity;
    double bestBuffer = 1.5;
    for (final mode in transportModes) {
      final minutes = estimateTravelMinutes(distKm, mode);
      if (minutes < bestTravelMinutes) {
        bestTravelMinutes = minutes;
        bestBuffer = routeBuffer[mode] ?? 1.5;
      }
    }

    final bufferedMax = maxTravelMinutes * bestBuffer;
    if (bestTravelMinutes > bufferedMax) return JobMatchResult.nearbyOnly;
  }

  // Availability filter
  if (!jobMatchesAvailability(
      job: job, availabilitySlots: availabilitySlots)) {
    return JobMatchResult.nearbyOnly;
  }

  return JobMatchResult.matched;
}
