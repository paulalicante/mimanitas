import '../main.dart';

/// Result of a schedule conflict check
class ConflictCheckResult {
  final bool hasConflict;
  final Map<String, dynamic>? conflictingJob;
  final String? message;

  ConflictCheckResult({
    required this.hasConflict,
    this.conflictingJob,
    this.message,
  });
}

/// Utility for checking schedule conflicts for helpers
class ScheduleConflict {
  /// Check if a helper has a scheduling conflict for a given date/time
  ///
  /// [helperId] - The helper's user ID
  /// [proposedDate] - The proposed job date (YYYY-MM-DD format)
  /// [proposedTime] - The proposed start time (HH:MM or HH:MM:SS format)
  /// [durationMinutes] - The proposed job duration (defaults to 60)
  /// [excludeJobId] - Optional job ID to exclude from conflict check (for updating existing jobs)
  static Future<ConflictCheckResult> checkConflict({
    required String helperId,
    required String proposedDate,
    String? proposedTime,
    int durationMinutes = 60,
    String? excludeJobId,
  }) async {
    try {
      // Fetch all the helper's committed jobs (accepted applications with assigned/in_progress status)
      final acceptedApps = await supabase
          .from('applications')
          .select('''
            job_id,
            jobs!applications_job_id_fkey(
              id, title, scheduled_date, scheduled_time,
              estimated_duration_minutes, status
            )
          ''')
          .eq('applicant_id', helperId)
          .eq('status', 'accepted');

      // Filter to only jobs that are assigned or in_progress
      final committedJobs = <Map<String, dynamic>>[];
      for (final app in acceptedApps) {
        final job = app['jobs'] as Map<String, dynamic>?;
        if (job == null) continue;

        final jobStatus = job['status'] as String?;
        if (jobStatus != 'assigned' && jobStatus != 'in_progress') continue;

        // Skip the job we're updating (if provided)
        if (excludeJobId != null && job['id'] == excludeJobId) continue;

        committedJobs.add(job);
      }

      // If no committed jobs, no conflict possible
      if (committedJobs.isEmpty) {
        return ConflictCheckResult(hasConflict: false);
      }

      // Parse the proposed time slot
      final proposedStart = _parseDateTime(proposedDate, proposedTime);
      if (proposedStart == null) {
        // If we can't parse the proposed time, just check for same-day conflicts
        for (final job in committedJobs) {
          final jobDate = job['scheduled_date'] as String?;
          if (jobDate == proposedDate) {
            return ConflictCheckResult(
              hasConflict: true,
              conflictingJob: job,
              message: 'Ya tienes un trabajo asignado ese día: "${job['title']}"',
            );
          }
        }
        return ConflictCheckResult(hasConflict: false);
      }

      final proposedEnd = proposedStart.add(Duration(minutes: durationMinutes));

      // Check each committed job for overlap
      for (final job in committedJobs) {
        final jobDate = job['scheduled_date'] as String?;
        final jobTime = job['scheduled_time'] as String?;
        final jobDuration = (job['estimated_duration_minutes'] as int?) ?? 60;

        // If the committed job has no date, skip it (flexible job not yet scheduled)
        if (jobDate == null) continue;

        final jobStart = _parseDateTime(jobDate, jobTime);
        if (jobStart == null) {
          // If job has same date but unparseable time, flag as potential conflict
          if (jobDate == proposedDate) {
            return ConflictCheckResult(
              hasConflict: true,
              conflictingJob: job,
              message: 'Ya tienes un trabajo ese día: "${job['title']}"',
            );
          }
          continue;
        }

        final jobEnd = jobStart.add(Duration(minutes: jobDuration));

        // Check for overlap: two time ranges overlap if one starts before the other ends
        // [proposedStart, proposedEnd) overlaps with [jobStart, jobEnd)
        // if proposedStart < jobEnd AND jobStart < proposedEnd
        if (proposedStart.isBefore(jobEnd) && jobStart.isBefore(proposedEnd)) {
          final timeStr = jobTime != null ? ' a las ${jobTime.substring(0, 5)}' : '';
          return ConflictCheckResult(
            hasConflict: true,
            conflictingJob: job,
            message: 'Conflicto de horario con "${job['title']}"$timeStr',
          );
        }
      }

      return ConflictCheckResult(hasConflict: false);
    } catch (e) {
      print('Error checking schedule conflict: $e');
      // On error, don't block the action - just log and continue
      return ConflictCheckResult(hasConflict: false);
    }
  }

  /// Check if a helper is available for a job (convenience method)
  /// Returns true if available (no conflict), false if busy
  static Future<bool> isHelperAvailable({
    required String helperId,
    required String jobDate,
    String? jobTime,
    int durationMinutes = 60,
    String? excludeJobId,
  }) async {
    final result = await checkConflict(
      helperId: helperId,
      proposedDate: jobDate,
      proposedTime: jobTime,
      durationMinutes: durationMinutes,
      excludeJobId: excludeJobId,
    );
    return !result.hasConflict;
  }

  /// Parse date and optional time into DateTime
  static DateTime? _parseDateTime(String date, String? time) {
    try {
      // Parse date (YYYY-MM-DD)
      final dateParts = date.split('-');
      if (dateParts.length != 3) return null;

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      if (time == null || time.isEmpty) {
        // No time specified - return start of day
        return DateTime(year, month, day, 0, 0);
      }

      // Parse time (HH:MM or HH:MM:SS)
      final timeParts = time.split(':');
      if (timeParts.length < 2) return DateTime(year, month, day, 0, 0);

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return null;
    }
  }
}
