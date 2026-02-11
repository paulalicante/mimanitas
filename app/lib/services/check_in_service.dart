import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import '../main.dart';

/// Result of a check-in or check-out operation
class CheckInResult {
  final bool success;
  final String? error;
  final double? distanceMeters;

  CheckInResult({required this.success, this.error, this.distanceMeters});

  factory CheckInResult.success({double? distanceMeters}) =>
      CheckInResult(success: true, distanceMeters: distanceMeters);

  factory CheckInResult.failure(String error) =>
      CheckInResult(success: false, error: error);
}

/// Service for handling helper check-in/check-out at job locations
/// This is a mobile-only feature - web users see a prompt to use the app
class CheckInService {
  /// Check if we're on a mobile platform
  static bool get isMobilePlatform => !kIsWeb;

  /// Maximum distance (meters) from job location to allow check-in
  static const int maxCheckInDistanceMeters = 200;

  /// Get current GPS position
  static Future<Position?> getCurrentPosition() async {
    if (kIsWeb) return null;

    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      // Check location permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // Get current position
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  /// Calculate distance between two coordinates using Haversine formula
  static double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  /// Check in to a job
  /// Verifies helper is near the job location before allowing check-in
  static Future<CheckInResult> checkIn(String jobId) async {
    if (kIsWeb) {
      return CheckInResult.failure('Esta función solo está disponible en la app móvil');
    }

    try {
      // Get current position
      final position = await getCurrentPosition();
      if (position == null) {
        return CheckInResult.failure(
          'No se pudo obtener tu ubicación. Activa el GPS e intenta de nuevo.',
        );
      }

      // Get job details to verify location
      final job = await supabase
          .from('jobs')
          .select('id, location_lat, location_lng, location_address, status, checked_in_at')
          .eq('id', jobId)
          .single();

      // Check job status
      if (job['status'] != 'assigned' && job['status'] != 'in_progress') {
        return CheckInResult.failure(
          'Solo puedes registrar entrada en trabajos asignados.',
        );
      }

      // Check if already checked in
      if (job['checked_in_at'] != null) {
        return CheckInResult.failure('Ya has registrado entrada en este trabajo.');
      }

      // Verify distance from job location (if job has coordinates)
      double? distance;
      final jobLat = job['location_lat'] as double?;
      final jobLng = job['location_lng'] as double?;

      if (jobLat != null && jobLng != null) {
        distance = calculateDistance(
          position.latitude,
          position.longitude,
          jobLat,
          jobLng,
        );

        if (distance > maxCheckInDistanceMeters) {
          return CheckInResult.failure(
            'Estás a ${distance.round()}m del trabajo. '
            'Debes estar a menos de ${maxCheckInDistanceMeters}m para registrar entrada.',
          );
        }
      }

      // Update job with check-in data
      await supabase.from('jobs').update({
        'checked_in_at': DateTime.now().toUtc().toIso8601String(),
        'check_in_lat': position.latitude,
        'check_in_lng': position.longitude,
        'status': 'in_progress',
      }).eq('id', jobId);

      return CheckInResult.success(distanceMeters: distance);
    } catch (e) {
      print('Error checking in: $e');
      return CheckInResult.failure('Error al registrar entrada: $e');
    }
  }

  /// Check out of a job
  /// Records completion location for verification
  static Future<CheckInResult> checkOut(String jobId) async {
    if (kIsWeb) {
      return CheckInResult.failure('Esta función solo está disponible en la app móvil');
    }

    try {
      // Get current position
      final position = await getCurrentPosition();
      if (position == null) {
        return CheckInResult.failure(
          'No se pudo obtener tu ubicación. Activa el GPS e intenta de nuevo.',
        );
      }

      // Get job details
      final job = await supabase
          .from('jobs')
          .select('id, status, checked_in_at, checked_out_at, checkin_approved_at')
          .eq('id', jobId)
          .single();

      // Check job status
      if (job['status'] != 'in_progress') {
        return CheckInResult.failure(
          'Solo puedes registrar salida en trabajos en progreso.',
        );
      }

      // Check if checked in
      if (job['checked_in_at'] == null) {
        return CheckInResult.failure('Primero debes registrar entrada.');
      }

      // Check if arrival was approved by seeker
      if (job['checkin_approved_at'] == null) {
        return CheckInResult.failure(
          'El cliente aún no ha confirmado tu llegada. Espera su confirmación.',
        );
      }

      // Check if already checked out
      if (job['checked_out_at'] != null) {
        return CheckInResult.failure('Ya has registrado salida de este trabajo.');
      }

      // Update job with check-out data
      // Note: We don't change status to 'completed' here - that's the seeker's action
      await supabase.from('jobs').update({
        'checked_out_at': DateTime.now().toUtc().toIso8601String(),
        'check_out_lat': position.latitude,
        'check_out_lng': position.longitude,
      }).eq('id', jobId);

      return CheckInResult.success();
    } catch (e) {
      print('Error checking out: $e');
      return CheckInResult.failure('Error al registrar salida: $e');
    }
  }

  /// Get check-in status for a job
  static Future<Map<String, dynamic>?> getCheckInStatus(String jobId) async {
    try {
      final job = await supabase
          .from('jobs')
          .select('''
            id, status,
            checked_in_at, checked_out_at,
            check_in_lat, check_in_lng,
            check_out_lat, check_out_lng
          ''')
          .eq('id', jobId)
          .single();

      return job;
    } catch (e) {
      print('Error getting check-in status: $e');
      return null;
    }
  }

  /// Calculate work duration from check-in to check-out
  static Duration? calculateWorkDuration(
    String? checkedInAt,
    String? checkedOutAt,
  ) {
    if (checkedInAt == null) return null;

    final checkIn = DateTime.parse(checkedInAt);
    final checkOut = checkedOutAt != null
        ? DateTime.parse(checkedOutAt)
        : DateTime.now().toUtc();

    return checkOut.difference(checkIn);
  }

  /// Format duration as human-readable string
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }
}
