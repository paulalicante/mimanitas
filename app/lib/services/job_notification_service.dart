import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import '../main.dart';
import '../screens/jobs/job_detail_screen.dart';
import '../screens/jobs/job_applications_screen.dart';
import '../utils/notification_sound.dart';

class _PendingJobNotification {
  final String title;
  final String subtitle;
  final String type; // 'new_job' or 'new_application'
  final String referenceId; // job_id or application_id
  final String? jobId;
  final String? jobTitle;
  final double? jobPrice;

  _PendingJobNotification({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.referenceId,
    this.jobId,
    this.jobTitle,
    this.jobPrice,
  });
}

/// A single availability time slot from the database
class _AvailabilitySlot {
  final int dayOfWeek; // 0=Sun, 1=Mon, ..., 6=Sat (JS convention, matches DB)
  final int startMinutes; // minutes since midnight
  final int endMinutes;
  final bool isRecurring;
  final String? specificDate; // 'YYYY-MM-DD'

  _AvailabilitySlot({
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    this.isRecurring = true,
    this.specificDate,
  });
}

/// Cached notification preferences for filtering
class _NotificationPrefs {
  final bool paused;
  final bool inAppEnabled;
  final bool soundEnabled;
  final List<String> notifySkills; // UUIDs — empty = all
  final double? minPriceAmount;
  final double? minHourlyRate;
  // Smart matching fields
  final List<String> transportModes; // car, bike, walk, transit, escooter
  final int maxTravelMinutes;
  final double? homeLat;
  final double? homeLng;
  // Availability slots for schedule matching
  final List<_AvailabilitySlot> availabilitySlots;

  _NotificationPrefs({
    this.paused = false,
    this.inAppEnabled = true,
    this.soundEnabled = true,
    this.notifySkills = const [],
    this.minPriceAmount,
    this.minHourlyRate,
    this.transportModes = const [],
    this.maxTravelMinutes = 30,
    this.homeLat,
    this.homeLng,
    this.availabilitySlots = const [],
  });

  factory _NotificationPrefs.fromMap(Map<String, dynamic> data,
      {double? homeLat,
      double? homeLng,
      List<_AvailabilitySlot> availabilitySlots = const []}) {
    return _NotificationPrefs(
      paused: data['paused'] as bool? ?? false,
      inAppEnabled: data['in_app_enabled'] as bool? ?? true,
      soundEnabled: data['sound_enabled'] as bool? ?? true,
      notifySkills: List<String>.from(data['notify_skills'] ?? []),
      minPriceAmount: (data['min_price_amount'] as num?)?.toDouble(),
      minHourlyRate: (data['min_hourly_rate'] as num?)?.toDouble(),
      transportModes: List<String>.from(data['transport_modes'] ?? []),
      maxTravelMinutes: data['max_travel_minutes'] as int? ?? 30,
      homeLat: homeLat,
      homeLng: homeLng,
      availabilitySlots: availabilitySlots,
    );
  }

  bool get hasLocation => homeLat != null && homeLng != null;
  bool get hasDistanceFilter => hasLocation && transportModes.isNotEmpty;
  bool get hasAvailability => availabilitySlots.isNotEmpty;
}

// --- Haversine distance helpers ---

double _haversineDistanceKm(
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

/// Rough travel time estimate in minutes using urban speed averages.
/// This is an approximation — the precise check happens server-side
/// in the Edge Function using Google Distance Matrix API.
double _estimateTravelMinutes(double distanceKm, String transportMode) {
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

/// Route buffer multipliers: how much longer real routes are vs straight line.
/// Transit gets a very generous buffer because bus/tram routes are far from
/// direct. This prevents false rejections on the client side — the server
/// will use Google Distance Matrix for accurate times.
const _routeBuffer = {
  'car': 1.5,
  'bike': 1.5,
  'walk': 1.8,
  'transit': 2.5,
  'escooter': 1.5,
};

class JobNotificationService {
  static final JobNotificationService _instance =
      JobNotificationService._internal();
  factory JobNotificationService() => _instance;
  JobNotificationService._internal();

  RealtimeChannel? _jobsChannel;
  RealtimeChannel? _applicationsChannel;
  GlobalKey<NavigatorState>? _navigatorKey;
  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  // User context
  String? _userId;
  String? _userType; // 'helper' or 'seeker'

  // Cached preferences (loaded once, refreshed on resubscribe)
  _NotificationPrefs _prefs = _NotificationPrefs();

  // Notification queue (same pattern as message notifications)
  final List<_PendingJobNotification> _notificationQueue = [];
  bool _isShowingNotification = false;
  _PendingJobNotification? _currentNotification;

  // Unread counts for badges
  int _unreadJobCount = 0;
  int _unreadApplicationCount = 0;

  // Debug logs
  List<String> debugLogs = [];

  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[JOB-$timestamp] $message';
    debugLogs.add(logMessage);
    if (debugLogs.length > 20) {
      debugLogs.removeAt(0);
    }
    print(logMessage);
  }

  void initialize({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
  }) {
    _navigatorKey = navigatorKey;
    _scaffoldMessengerKey = scaffoldMessengerKey;
    // Unsubscribe from any existing channels (important for hot restart)
    _jobsChannel?.unsubscribe();
    _applicationsChannel?.unsubscribe();
    _jobsChannel = null;
    _applicationsChannel = null;
    _addDebugLog('Initialized (waiting for user context)');
  }

  /// Set user context so we know which subscriptions to create.
  /// Call this after loading the user profile.
  void setUserContext(String userId, String userType) async {
    _userId = userId;
    _userType = userType;
    _addDebugLog('User context set: type=$userType');
    await _loadPreferences();
    _subscribe();
  }

  /// Load notification preferences from DB and cache them.
  Future<void> _loadPreferences() async {
    if (_userId == null) return;
    try {
      // Load preferences
      final data = await supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', _userId!)
          .maybeSingle();

      // Load profile for home location
      double? homeLat;
      double? homeLng;
      try {
        final profile = await supabase
            .from('profiles')
            .select('location_lat, location_lng')
            .eq('id', _userId!)
            .maybeSingle();
        if (profile != null) {
          homeLat = (profile['location_lat'] as num?)?.toDouble();
          homeLng = (profile['location_lng'] as num?)?.toDouble();
        }
      } catch (e) {
        _addDebugLog('Error loading profile location: $e');
      }

      // Load availability slots for schedule matching
      List<_AvailabilitySlot> availSlots = [];
      try {
        final availData = await supabase
            .from('availability')
            .select(
                'day_of_week, start_time, end_time, is_recurring, specific_date')
            .eq('user_id', _userId!);
        for (final row in availData) {
          final startParts = (row['start_time'] as String).split(':');
          final endParts = (row['end_time'] as String).split(':');
          availSlots.add(_AvailabilitySlot(
            dayOfWeek: row['day_of_week'] as int,
            startMinutes:
                int.parse(startParts[0]) * 60 + int.parse(startParts[1]),
            endMinutes: int.parse(endParts[0]) * 60 + int.parse(endParts[1]),
            isRecurring: row['is_recurring'] as bool? ?? true,
            specificDate: row['specific_date'] as String?,
          ));
        }
        _addDebugLog('Loaded ${availSlots.length} availability slots');
      } catch (e) {
        _addDebugLog('Error loading availability: $e');
      }

      if (data != null) {
        _prefs = _NotificationPrefs.fromMap(data,
            homeLat: homeLat,
            homeLng: homeLng,
            availabilitySlots: availSlots);
        _addDebugLog(
            'Prefs loaded: inApp=${_prefs.inAppEnabled}, sound=${_prefs.soundEnabled}, '
            'skills=${_prefs.notifySkills.length}, '
            'minPrice=${_prefs.minPriceAmount}, '
            'transport=${_prefs.transportModes}, maxTravel=${_prefs.maxTravelMinutes}min, '
            'home=${_prefs.hasLocation ? "${_prefs.homeLat},${_prefs.homeLng}" : "not set"}, '
            'availability=${availSlots.length} slots');
      } else {
        _prefs = _NotificationPrefs(
            homeLat: homeLat,
            homeLng: homeLng,
            availabilitySlots: availSlots);
        _addDebugLog(
            'No preferences row — using defaults (${availSlots.length} availability slots)');
      }
    } catch (e) {
      _addDebugLog('Error loading preferences: $e');
      _prefs = _NotificationPrefs();
    }
  }

  /// Reload preferences (call after user saves preferences screen).
  Future<void> refreshPreferences() async {
    await _loadPreferences();
  }

  void dispose() {
    _jobsChannel?.unsubscribe();
    _applicationsChannel?.unsubscribe();
    _userId = null;
    _userType = null;
    _unreadJobCount = 0;
    _unreadApplicationCount = 0;
  }

  void resubscribe() {
    _jobsChannel?.unsubscribe();
    _applicationsChannel?.unsubscribe();
    _subscribe();
  }

  int get unreadJobCount => _unreadJobCount;
  int get unreadApplicationCount => _unreadApplicationCount;
  int get totalUnreadCount => _unreadJobCount + _unreadApplicationCount;

  void clearJobUnread() => _unreadJobCount = 0;
  void clearApplicationUnread() => _unreadApplicationCount = 0;

  void _subscribe() {
    if (_userId == null || _userType == null) {
      _addDebugLog('Cannot subscribe: no user context');
      return;
    }

    // Helpers get notified about new jobs
    if (_userType == 'helper') {
      _subscribeToNewJobs();
    }

    // Seekers get notified about new applications to their jobs
    if (_userType == 'seeker') {
      _subscribeToNewApplications();
    }

    // Users with type 'both' would get both subscriptions
    // (not currently supported in schema but future-proof)
  }

  void _subscribeToNewJobs() {
    _addDebugLog('Subscribing to new jobs...');
    try {
      _jobsChannel = supabase
          .channel(
              'job_notifications_${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'jobs',
            callback: (payload) async {
              _addDebugLog('*** NEW JOB POSTED ***');
              final newJob = payload.newRecord;
              final posterId = newJob['poster_id'] as String?;
              final jobId = newJob['id'] as String?;
              final title = newJob['title'] as String? ?? 'Nuevo trabajo';
              final priceAmount =
                  (newJob['price_amount'] as num?)?.toDouble();
              final priceType = newJob['price_type'] as String?;
              final skillId = newJob['skill_id'] as String?;
              final location =
                  newJob['location_address'] as String? ?? newJob['barrio'] as String?;

              // Smart matching fields from job
              final jobLat =
                  (newJob['location_lat'] as num?)?.toDouble();
              final jobLng =
                  (newJob['location_lng'] as num?)?.toDouble();
              final isFlexible = newJob['is_flexible'] == true;
              final scheduledDate = newJob['scheduled_date'] as String?;
              final scheduledTime = newJob['scheduled_time'] as String?;

              // Don't notify about own jobs (shouldn't happen for helpers, but defensive)
              if (posterId == _userId) {
                _addDebugLog('Skipping: own job');
                return;
              }

              // Only notify for open jobs
              if (newJob['status'] != 'open') {
                _addDebugLog('Skipping: job status is ${newJob['status']}');
                return;
              }

              // --- Apply notification preferences ---

              // Helper paused all notifications?
              if (_prefs.paused) {
                _addDebugLog('Skipping: helper is paused (no disponible)');
                return;
              }

              // In-app notifications disabled?
              if (!_prefs.inAppEnabled) {
                _addDebugLog('Skipping: in-app notifications disabled');
                return;
              }

              // Skill filter: if user selected specific skills, only match those
              if (_prefs.notifySkills.isNotEmpty && skillId != null) {
                if (!_prefs.notifySkills.contains(skillId)) {
                  _addDebugLog('Skipping: skill $skillId not in filter');
                  return;
                }
              }

              // Minimum price filter (checks price_type)
              if (priceAmount != null) {
                if (priceType == 'hourly' && _prefs.minHourlyRate != null) {
                  if (priceAmount < _prefs.minHourlyRate!) {
                    _addDebugLog(
                        'Skipping: hourly rate $priceAmount < min ${_prefs.minHourlyRate}/h');
                    return;
                  }
                } else if (priceType == 'fixed' && _prefs.minPriceAmount != null) {
                  if (priceAmount < _prefs.minPriceAmount!) {
                    _addDebugLog(
                        'Skipping: fixed price $priceAmount < min ${_prefs.minPriceAmount}');
                    return;
                  }
                }
              }

              // Distance filter (client-side approximation using Haversine)
              // Uses route buffer multipliers so transit-only helpers aren't
              // falsely rejected — server-side Google API provides final accuracy.
              if (_prefs.hasDistanceFilter &&
                  jobLat != null &&
                  jobLng != null) {
                final distanceKm = _haversineDistanceKm(
                    _prefs.homeLat!, _prefs.homeLng!, jobLat, jobLng);

                // Check against fastest transport mode (with route buffer)
                double bestTravelMinutes = double.infinity;
                String bestMode = '';
                double bestBuffer = 1.5;
                for (final mode in _prefs.transportModes) {
                  final minutes =
                      _estimateTravelMinutes(distanceKm, mode);
                  if (minutes < bestTravelMinutes) {
                    bestTravelMinutes = minutes;
                    bestMode = mode;
                    bestBuffer = _routeBuffer[mode] ?? 1.5;
                  }
                }

                // Only reject if Haversine estimate exceeds buffer * max.
                // This is generous on purpose — better to show a notification
                // for a borderline job than to miss it. The helper can check
                // accurate travel time on the job detail screen.
                final bufferedMax = _prefs.maxTravelMinutes * bestBuffer;
                if (bestTravelMinutes > bufferedMax) {
                  _addDebugLog(
                      'Skipping: ${distanceKm.toStringAsFixed(1)}km, '
                      '~${bestTravelMinutes.toStringAsFixed(0)}min via $bestMode '
                      '> ${bufferedMax.toStringAsFixed(0)}min buffered max '
                      '(${_prefs.maxTravelMinutes}min × ${bestBuffer}x)');
                  return;
                }
                _addDebugLog(
                    'Distance OK: ${distanceKm.toStringAsFixed(1)}km, '
                    '~${bestTravelMinutes.toStringAsFixed(0)}min via $bestMode '
                    '(max ${bufferedMax.toStringAsFixed(0)}min buffered)');
              }

              // Availability filter: if job has a scheduled date (not flexible)
              // and the helper has set availability, check if the day/time matches.
              if (!isFlexible &&
                  scheduledDate != null &&
                  _prefs.hasAvailability) {
                final dateObj = DateTime.parse(scheduledDate);
                // Convert Dart weekday (1=Mon, 7=Sun) to DB convention (0=Sun, 1=Mon, ..., 6=Sat)
                final dayOfWeek = dateObj.weekday % 7;

                // Parse job time if available
                int? jobTimeMinutes;
                if (scheduledTime != null) {
                  try {
                    final parts = scheduledTime.split(':');
                    jobTimeMinutes =
                        int.parse(parts[0]) * 60 + int.parse(parts[1]);
                  } catch (_) {}
                }

                bool matches = false;
                for (final slot in _prefs.availabilitySlots) {
                  // Check specific date match
                  if (slot.specificDate == scheduledDate) {
                    if (jobTimeMinutes == null ||
                        (jobTimeMinutes >= slot.startMinutes &&
                            jobTimeMinutes <= slot.endMinutes)) {
                      matches = true;
                      break;
                    }
                  }
                  // Check recurring day match
                  if (slot.isRecurring && slot.dayOfWeek == dayOfWeek) {
                    if (jobTimeMinutes == null ||
                        (jobTimeMinutes >= slot.startMinutes &&
                            jobTimeMinutes <= slot.endMinutes)) {
                      matches = true;
                      break;
                    }
                  }
                }

                if (!matches) {
                  _addDebugLog(
                      'Skipping: no availability match for $scheduledDate ${scheduledTime ?? "(no time)"}');
                  return;
                }
                _addDebugLog(
                    'Availability OK: match found for $scheduledDate ${scheduledTime ?? "(no time)"}');
              }

              // --- End preference filters ---

              // Fetch skill name for richer notification
              String? skillName;
              if (skillId != null) {
                try {
                  final skill = await supabase
                      .from('skills')
                      .select('name_es')
                      .eq('id', skillId)
                      .maybeSingle();
                  skillName = skill?['name_es'] as String?;
                } catch (e) {
                  _addDebugLog('Error fetching skill: $e');
                }
              }

              // Build notification text
              final priceText = priceAmount != null
                  ? '${priceAmount.toStringAsFixed(0)}${priceType == 'hourly' ? '/h' : ''}'
                  : null;

              final subtitle = [
                if (skillName != null) skillName,
                if (priceText != null) priceText,
                if (location != null) location,
              ].join(' | ');

              _addDebugLog('Showing job notification: $title');

              // Increment unread and play sound (if enabled)
              _unreadJobCount++;
              if (_prefs.soundEnabled) {
                NotificationSound.play();
              }

              // Queue notification
              _queueNotification(_PendingJobNotification(
                title: title,
                subtitle: subtitle.isNotEmpty ? subtitle : 'Nuevo trabajo disponible',
                type: 'new_job',
                referenceId: jobId ?? '',
                jobId: jobId,
              ));
            },
          )
          .subscribe((status, [error]) {
        _addDebugLog('Jobs channel: $status');
        if (error != null) _addDebugLog('Jobs channel error: $error');
      });
      _addDebugLog('Jobs subscription initiated');
    } catch (e) {
      _addDebugLog('Error subscribing to jobs: $e');
    }
  }

  void _subscribeToNewApplications() {
    _addDebugLog('Subscribing to new applications...');
    try {
      _applicationsChannel = supabase
          .channel(
              'application_notifications_${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'applications',
            callback: (payload) async {
              _addDebugLog('*** NEW APPLICATION ***');
              final newApp = payload.newRecord;
              final applicantId = newApp['applicant_id'] as String?;
              final jobId = newApp['job_id'] as String?;
              final applicationId = newApp['id'] as String?;

              // Don't notify about own applications (shouldn't happen for seekers)
              if (applicantId == _userId) {
                _addDebugLog('Skipping: own application');
                return;
              }

              if (jobId == null) {
                _addDebugLog('Skipping: no job_id');
                return;
              }

              // Check this is a job we posted
              try {
                final job = await supabase
                    .from('jobs')
                    .select('id, title, poster_id, price_amount')
                    .eq('id', jobId)
                    .maybeSingle();

                if (job == null || job['poster_id'] != _userId) {
                  _addDebugLog('Skipping: not our job');
                  return;
                }

                // Get applicant name
                String applicantName = 'Alguien';
                if (applicantId != null) {
                  try {
                    final profile = await supabase
                        .from('profiles')
                        .select('name')
                        .eq('id', applicantId)
                        .maybeSingle();
                    applicantName = profile?['name'] as String? ?? 'Alguien';
                  } catch (e) {
                    _addDebugLog('Error fetching applicant: $e');
                  }
                }

                final jobTitle = job['title'] as String? ?? 'tu trabajo';
                final jobPrice = (job['price_amount'] as num?)?.toDouble();

                _addDebugLog(
                    'Showing application notification: $applicantName -> $jobTitle');

                // Increment unread and play sound (if enabled)
                _unreadApplicationCount++;
                if (_prefs.soundEnabled) {
                  NotificationSound.play();
                }

                // Queue notification
                _queueNotification(_PendingJobNotification(
                  title: '$applicantName ha aplicado',
                  subtitle: jobTitle,
                  type: 'new_application',
                  referenceId: applicationId ?? '',
                  jobId: jobId,
                  jobTitle: jobTitle,
                  jobPrice: jobPrice,
                ));
              } catch (e) {
                _addDebugLog('Error processing application: $e');
              }
            },
          )
          .subscribe((status, [error]) {
        _addDebugLog('Applications channel: $status');
        if (error != null) _addDebugLog('Applications channel error: $error');
      });
      _addDebugLog('Applications subscription initiated');
    } catch (e) {
      _addDebugLog('Error subscribing to applications: $e');
    }
  }

  // --- Notification queue (same pattern as MessageNotificationService) ---

  void _queueNotification(_PendingJobNotification notification) {
    _notificationQueue.add(notification);
    _addDebugLog(
        'Queued notification. Queue size: ${_notificationQueue.length}');

    // If a notification is already showing, refresh to show queue count
    if (_isShowingNotification && _currentNotification != null) {
      _addDebugLog('Refreshing current notification for queue update');
      final messenger = _scaffoldMessengerKey?.currentState;
      if (messenger != null) {
        messenger.hideCurrentSnackBar();
        _isShowingNotification = false;
        _notificationQueue.insert(0, _currentNotification!);
        _currentNotification = null;
      }
    }
    _processNotificationQueue();
  }

  void _processNotificationQueue() {
    if (_isShowingNotification || _notificationQueue.isEmpty) return;

    _isShowingNotification = true;
    _currentNotification = _notificationQueue.removeAt(0);
    _showNotification(_currentNotification!);
  }

  void _showNotification(_PendingJobNotification notification) {
    _addDebugLog('Showing notification: ${notification.title}');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = _scaffoldMessengerKey?.currentState;
      if (messenger == null) {
        _addDebugLog('ERROR: ScaffoldMessenger is null!');
        _isShowingNotification = false;
        _processNotificationQueue();
        return;
      }

      final queueSize = _notificationQueue.length;
      final isJob = notification.type == 'new_job';

      try {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                // Icon circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isJob
                        ? AppColors.orange
                        : const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isJob ? Icons.work_outline : Icons.person_add,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              notification.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (queueSize > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '+$queueSize',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        notification.subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Close button
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white70, size: 20),
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    _isShowingNotification = false;
                    _currentNotification = null;
                    _processNotificationQueue();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(days: 1),
            action: SnackBarAction(
              label: 'Ver',
              textColor: AppColors.orange,
              onPressed: () {
                _navigateToNotification(notification);
              },
            ),
          ),
        );
        _addDebugLog('SnackBar shown!');

        // Notification stays until user dismisses or clicks "Ver"
      } catch (e) {
        _addDebugLog('ERROR showing snackbar: $e');
        _currentNotification = null;
        _isShowingNotification = false;
        _processNotificationQueue();
      }
    });
  }

  void _navigateToNotification(_PendingJobNotification notification) {
    try {
      if (notification.type == 'new_job' && notification.jobId != null) {
        _navigatorKey?.currentState?.push(
          MaterialPageRoute(
            builder: (context) => JobDetailScreen(
              jobId: notification.jobId!,
            ),
          ),
        );
      } else if (notification.type == 'new_application' &&
          notification.jobId != null) {
        _navigatorKey?.currentState?.push(
          MaterialPageRoute(
            builder: (context) => JobApplicationsScreen(
              jobId: notification.jobId!,
              jobTitle: notification.jobTitle ?? '',
              jobPrice: notification.jobPrice ?? 0,
            ),
          ),
        );
      }
    } catch (e) {
      _addDebugLog('Error navigating: $e');
    } finally {
      _isShowingNotification = false;
      _currentNotification = null;
      _processNotificationQueue();
    }
  }
}

// Global instance
final jobNotificationService = JobNotificationService();
