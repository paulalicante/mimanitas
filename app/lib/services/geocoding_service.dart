import 'dart:convert';
import 'dart:math';
import '../main.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      placeId: json['placeId'] as String? ?? '',
      description: json['description'] as String? ?? '',
      mainText: json['mainText'] as String? ?? '',
      secondaryText: json['secondaryText'] as String? ?? '',
    );
  }
}

class PlaceDetails {
  final double lat;
  final double lng;
  final String address;
  final String? barrio;

  PlaceDetails({
    required this.lat,
    required this.lng,
    required this.address,
    this.barrio,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    return PlaceDetails(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      address: json['address'] as String? ?? '',
      barrio: json['barrio'] as String?,
    );
  }
}

class GeocodingService {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;
  GeocodingService._internal();

  // Session token for billing optimization (one token per autocomplete session)
  String _sessionToken = _generateSessionToken();

  static String _generateSessionToken() {
    final random = Random();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  /// Start a new autocomplete session (call when user starts typing in a new field)
  void newSession() {
    _sessionToken = _generateSessionToken();
  }

  /// Get autocomplete suggestions for an address input
  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    if (input.trim().length < 2) return [];

    try {
      final response = await supabase.functions.invoke(
        'geocode-address',
        body: {
          'action': 'autocomplete',
          'input': input,
          'sessionToken': _sessionToken,
        },
      );

      if (response.status != 200) {
        print('Autocomplete error: ${response.status}');
        return [];
      }

      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final predictions = data['predictions'] as List<dynamic>? ?? [];
      return predictions
          .map((p) => PlaceSuggestion.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Autocomplete error: $e');
      return [];
    }
  }

  /// Get full details (lat/lng/barrio) for a selected place
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    try {
      final response = await supabase.functions.invoke(
        'geocode-address',
        body: {
          'action': 'details',
          'placeId': placeId,
        },
      );

      if (response.status != 200) {
        print('Place details error: ${response.status}');
        return null;
      }

      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      // End the session after getting details
      newSession();
      return PlaceDetails.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      print('Place details error: $e');
      return null;
    }
  }

  /// Calculate Haversine distance in km (for client-side rough filtering)
  static double haversineDistanceKm(
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

  static double _toRadians(double deg) => deg * pi / 180;

  /// Rough travel time estimate in minutes (for client-side filtering)
  /// Uses average urban speeds — not as accurate as Google Distance Matrix
  static double estimateTravelMinutes(
      double distanceKm, String transportMode) {
    const speeds = {
      'car': 30.0, // km/h urban average
      'transit': 20.0,
      'escooter': 15.0,
      'bike': 12.0,
      'walk': 5.0,
    };
    final speed = speeds[transportMode] ?? 15.0;
    return (distanceKm / speed) * 60;
  }

  /// Get accurate travel time from Google Distance Matrix API.
  /// Returns duration in minutes, or null if unavailable.
  /// [origin] and [destination] are "lat,lng" strings.
  /// [mode] is one of: car, bike, walk, transit, escooter.
  Future<int?> getTravelTimeMinutes({
    required String origin,
    required String destination,
    required String mode,
  }) async {
    try {
      // Map app modes to Google API modes
      final googleMode = const {
        'car': 'driving',
        'bike': 'bicycling',
        'walk': 'walking',
        'transit': 'transit',
        'escooter': 'bicycling',
      }[mode] ?? 'driving';

      final response = await supabase.functions.invoke(
        'geocode-address',
        body: {
          'action': 'distance_matrix',
          'origins': [origin],
          'destination': destination,
          'mode': googleMode,
        },
      );

      if (response.status != 200) return null;

      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;

      final first = results[0] as Map<String, dynamic>;
      final durationSeconds = first['durationSeconds'] as num?;
      if (durationSeconds == null) return null;

      return (durationSeconds / 60).round();
    } catch (e) {
      return null;
    }
  }
}

final geocodingService = GeocodingService();
