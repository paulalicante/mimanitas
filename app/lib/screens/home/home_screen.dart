import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app_theme.dart';
import '../../main.dart';
import '../jobs/post_job_screen.dart';
import '../jobs/my_jobs_screen.dart';
import '../jobs/browse_jobs_screen.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/my_applications_screen.dart';
import '../debug/debug_sms_screen.dart';
import '../profile/profile_screen.dart';
import '../messages/messages_screen.dart';
import '../payments/earnings_screen.dart';
import '../profile/notification_preferences_screen.dart';
import '../profile/availability_screen.dart';
import '../../services/message_notification_service.dart';
import '../../services/job_notification_service.dart';
import '../../services/payment_service.dart';
import '../../utils/notification_sound.dart';
import '../../utils/job_matching.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _userType;
  String? _userName;
  bool _isLoading = true;
  bool _phoneVerified = false;
  int _unreadMessageCount = 0;
  RealtimeChannel? _messagesChannel;
  Timer? _pollingTimer;

  // Dashboard data (helpers)
  bool _dashboardLoading = true;
  List<Map<String, dynamic>> _availabilitySlots = [];
  int _matchedJobCount = 0;
  int _nearbyJobCount = 0;
  List<Map<String, dynamic>> _upcomingJobs = [];
  Map<String, dynamic>? _notificationPrefs;
  Map<String, dynamic>? _profileLocation;
  HelperBalance? _balance;

  // Dashboard data (seekers)
  bool _seekerDashboardLoading = true;
  List<Map<String, dynamic>> _seekerJobs = [];
  List<Map<String, dynamic>> _assignedJobsNext7Days = [];
  List<Map<String, dynamic>> _openJobsWithApplications = [];
  List<Map<String, dynamic>> _openJobsNoApplications = [];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadUnreadMessageCount();
    _subscribeToMessages();
    _startPolling();
    _subscribeToNotificationService();
  }

  void _subscribeToNotificationService() {
    // Listen to notification service for real-time unread updates
    // The notification service updates _unreadByConversation when messages arrive
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  // Polling fallback - check for new messages every 2 seconds
  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      // Use notification service's unread count for real-time updates
      final serviceUnreadCount = messageNotificationService.getTotalUnreadCount();
      if (serviceUnreadCount != _unreadMessageCount && mounted) {
        setState(() => _unreadMessageCount = serviceUnreadCount);
      }
      // Also load from DB as fallback
      _loadUnreadMessageCount();
    });
  }

  Future<void> _loadUnreadMessageCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Get all conversations where user is seeker or helper
      final conversations = await supabase
          .from('conversations')
          .select('id')
          .or('seeker_id.eq.${user.id},helper_id.eq.${user.id}');

      if (conversations.isEmpty) {
        if (mounted) setState(() => _unreadMessageCount = 0);
        return;
      }

      // Get unread message count in a SINGLE query (not N+1)
      final conversationIds = conversations.map((c) => c['id'] as String).toList();

      final unreadMessages = await supabase
          .from('messages')
          .select('id')
          .inFilter('conversation_id', conversationIds)
          .neq('sender_id', user.id)
          .isFilter('read_at', null);

      if (mounted) {
        setState(() => _unreadMessageCount = unreadMessages.length);
      }
    } catch (e) {
      print('Error loading unread message count: $e');
    }
  }

  void _subscribeToMessages() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _messagesChannel = supabase
        .channel('home_messages_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            print('New message received: ${payload.newRecord}');
            // Update UI from notification service's real-time tracking
            if (mounted) {
              setState(() {
                _unreadMessageCount = messageNotificationService.getTotalUnreadCount();
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // Reload when messages are marked as read
            _loadUnreadMessageCount();
          },
        )
        .subscribe((status, [error]) {
      print('HomeScreen messages channel status: $status');
      if (error != null) {
        print('HomeScreen messages channel error: $error');
      }
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        print('DEBUG: Loading profile for user ${user.id}');
        final profile = await supabase
            .from('profiles')
            .select('user_type, phone_verified, name')
            .eq('id', user.id)
            .single();

        print('DEBUG: Profile data: $profile');
        print('DEBUG: User type from DB: ${profile['user_type']}');

        setState(() {
          _userType = profile['user_type'] as String?;
          _userName = profile['name'] as String?;
          _phoneVerified = profile['phone_verified'] == true;
          _isLoading = false;
        });
        print('DEBUG: _userType set to: $_userType');

        // Initialize job notifications with user context
        if (_userType != null) {
          jobNotificationService.setUserContext(user.id, _userType!);
          if (_userType == 'helper') {
            _loadDashboardData();
          } else if (_userType == 'seeker') {
            _loadSeekerDashboardData();
          }
        }

        // Ensure audio context is ready (browser autoplay policy)
        NotificationSound.ensureInitialized();
      }
    } catch (e) {
      print('DEBUG: Error loading profile: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Helper Dashboard Data Loading ---

  Future<void> _loadDashboardData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _dashboardLoading = true);

    // Phase 1: Load prefs, profile, availability (needed for job classification)
    final phase1 = await Future.wait<dynamic>([
      _loadAvailabilityData(userId),
      _loadPreferencesData(userId),
    ]);

    if (!mounted) return;
    _availabilitySlots = phase1[0] as List<Map<String, dynamic>>;
    final prefsResult = phase1[1] as Map<String, dynamic>;
    _notificationPrefs = prefsResult['prefs'] as Map<String, dynamic>?;
    _profileLocation = prefsResult['profile'] as Map<String, dynamic>?;

    // Phase 2: Load job counts (uses phase 1 data) + independent loaders
    final phase2 = await Future.wait<dynamic>([
      _loadJobCounts(userId),
      _loadUpcomingJobs(userId),
      _loadBalance(),
    ]);

    if (!mounted) return;
    setState(() {
      final counts = phase2[0] as Map<String, int>;
      _matchedJobCount = counts['matched'] ?? 0;
      _nearbyJobCount = counts['nearby'] ?? 0;
      _upcomingJobs = phase2[1] as List<Map<String, dynamic>>;
      _balance = phase2[2] as HelperBalance?;
      _dashboardLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _loadAvailabilityData(String userId) async {
    try {
      final data = await supabase
          .from('availability')
          .select('day_of_week, start_time, end_time')
          .eq('user_id', userId)
          .eq('is_recurring', true)
          .order('start_time');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, int>> _loadJobCounts(String userId) async {
    try {
      final openJobs = await supabase
          .from('jobs')
          .select('id, skill_id, price_type, price_amount, location_lat, location_lng, '
                  'scheduled_date, scheduled_time, is_flexible')
          .eq('status', 'open');

      final appliedJobs = await supabase
          .from('applications')
          .select('job_id')
          .eq('applicant_id', userId);

      final appliedJobIds = appliedJobs.map((a) => a['job_id']).toSet();

      // Filter out jobs the helper has already applied to AND jobs with past dates
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final unappliedJobs = openJobs.where((j) {
        // Exclude jobs helper has already applied to
        if (appliedJobIds.contains(j['id'])) return false;

        // Exclude jobs with scheduled dates in the past
        final scheduledDate = j['scheduled_date'] as String?;
        if (scheduledDate != null && scheduledDate.compareTo(todayStr) < 0) {
          return false;
        }

        return true;
      }).toList();

      // Extract helper prefs for classification
      final helperLat = (_profileLocation?['location_lat'] as num?)?.toDouble();
      final helperLng = (_profileLocation?['location_lng'] as num?)?.toDouble();
      final transportModes = _notificationPrefs != null
          ? List<String>.from(_notificationPrefs!['transport_modes'] ?? [])
          : <String>[];
      final maxTravelMinutes =
          _notificationPrefs?['max_travel_minutes'] as int? ?? 30;
      final notifySkills = _notificationPrefs != null
          ? List<String>.from(_notificationPrefs!['notify_skills'] ?? [])
          : <String>[];
      final minPriceAmount =
          (_notificationPrefs?['min_price_amount'] as num?)?.toDouble();
      final minHourlyRate =
          (_notificationPrefs?['min_hourly_rate'] as num?)?.toDouble();

      int matched = 0;
      int nearby = 0;

      for (final job in unappliedJobs) {
        final result = classifyJob(
          job: job,
          helperLat: helperLat,
          helperLng: helperLng,
          transportModes: transportModes,
          maxTravelMinutes: maxTravelMinutes,
          notifySkills: notifySkills,
          minPriceAmount: minPriceAmount,
          minHourlyRate: minHourlyRate,
          availabilitySlots: _availabilitySlots,
        );

        switch (result) {
          case JobMatchResult.matched:
            matched++;
            break;
          case JobMatchResult.nearbyOnly:
            nearby++;
            break;
          case JobMatchResult.tooFar:
            break; // excluded entirely
        }
      }

      return {'matched': matched, 'nearby': nearby};
    } catch (e) {
      return {'matched': 0, 'nearby': 0};
    }
  }

  Future<List<Map<String, dynamic>>> _loadUpcomingJobs(String userId) async {
    try {
      final data = await supabase
          .from('applications')
          .select('''
            *,
            jobs!applications_job_id_fkey(
              id, title, scheduled_date, scheduled_time, status, barrio, location_address,
              profiles!jobs_poster_id_fkey(name)
            )
          ''')
          .eq('applicant_id', userId)
          .eq('status', 'accepted');

      return List<Map<String, dynamic>>.from(data)
          .where((app) {
            final job = app['jobs'];
            return job != null && job['status'] == 'assigned';
          })
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> _loadPreferencesData(String userId) async {
    try {
      final prefs = await supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      final profile = await supabase
          .from('profiles')
          .select('location_lat, location_lng, barrio, default_location_address')
          .eq('id', userId)
          .single();

      return {'prefs': prefs, 'profile': profile};
    } catch (e) {
      return {'prefs': null, 'profile': null};
    }
  }

  Future<HelperBalance?> _loadBalance() async {
    try {
      return await paymentService.getHelperBalance();
    } catch (e) {
      return null;
    }
  }

  // --- Seeker Dashboard Data Loading ---

  Future<void> _loadSeekerDashboardData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _seekerDashboardLoading = true);

    try {
      // Load all seeker's jobs with their applications and helper profiles
      final jobsData = await supabase
          .from('jobs')
          .select('''
            *,
            applications(id, status, applicant_id, profiles!applications_applicant_id_fkey(id, name))
          ''')
          .eq('poster_id', userId)
          .order('created_at', ascending: false);

      _seekerJobs = List<Map<String, dynamic>>.from(jobsData);

      // Calculate date range for next 7 days
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekFromNow = today.add(const Duration(days: 7));

      // Categorize jobs
      _assignedJobsNext7Days = [];
      _openJobsWithApplications = [];
      _openJobsNoApplications = [];

      for (final job in _seekerJobs) {
        final status = job['status'] as String?;
        final applications = job['applications'] as List? ?? [];
        final pendingApps = applications.where((a) => a['status'] == 'pending').toList();

        if (status == 'assigned' || status == 'in_progress') {
          // Check if scheduled within next 7 days
          final scheduledDate = job['scheduled_date'] as String?;
          if (scheduledDate != null) {
            try {
              final jobDate = DateTime.parse(scheduledDate);
              if (!jobDate.isBefore(today) && jobDate.isBefore(weekFromNow)) {
                _assignedJobsNext7Days.add(job);
              }
            } catch (_) {}
          } else {
            // Flexible jobs with no date - include them
            _assignedJobsNext7Days.add(job);
          }
        } else if (status == 'open') {
          // Check if job is not past-due
          final scheduledDate = job['scheduled_date'] as String?;
          bool isPastDue = false;
          if (scheduledDate != null) {
            try {
              final jobDate = DateTime.parse(scheduledDate);
              isPastDue = jobDate.isBefore(today);
            } catch (_) {}
          }

          if (!isPastDue) {
            if (pendingApps.isNotEmpty) {
              _openJobsWithApplications.add(job);
            } else {
              _openJobsNoApplications.add(job);
            }
          }
        }
      }

      // Sort assigned jobs by date
      _assignedJobsNext7Days.sort((a, b) {
        final dateA = a['scheduled_date'] as String?;
        final dateB = b['scheduled_date'] as String?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });

    } catch (e) {
      print('Error loading seeker dashboard: $e');
    }

    if (mounted) {
      setState(() => _seekerDashboardLoading = false);
    }
  }

  String _formatJobDate(String dateStr, String? timeStr) {
    try {
      final d = DateTime.parse(dateStr);
      const dayNames = ['dom', 'lun', 'mar', 'mie', 'jue', 'vie', 'sab'];
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun',
        'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      final dayName = dayNames[d.weekday % 7];
      final cap = '${dayName[0].toUpperCase()}${dayName.substring(1)}';
      var result = '$cap, ${d.day} ${months[d.month - 1]}';
      if (timeStr != null) {
        try {
          final tp = timeStr.split(':');
          result += ', ${tp[0]}:${tp[1]}';
        } catch (_) {}
      }
      return result;
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              // Header with MiManitas Logo
              Container(
                constraints: const BoxConstraints(maxWidth: 900),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // MiManitas Logo (matching landing page)
                  Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CustomPaint(
                          painter: _MiManitasLogoPainter(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          children: const [
                            TextSpan(text: 'Mi', style: TextStyle(color: AppColors.orange)),
                            TextSpan(text: 'Manitas', style: TextStyle(color: AppColors.gold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Browse jobs button (helpers)
                      if (_userType == 'helper')
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const BrowseJobsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.search, size: 22),
                          color: AppColors.navyDark,
                          tooltip: 'Buscar trabajos',
                        ),
                      // Messages button with badge
                      IconButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const MessagesScreen(),
                            ),
                          );
                          _loadUnreadMessageCount();
                        },
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.message_outlined, size: 22),
                            if (_unreadMessageCount > 0)
                              Positioned(
                                right: -6,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Text(
                                    _unreadMessageCount > 9 ? '9+' : '$_unreadMessageCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        color: AppColors.navyDark,
                        tooltip: 'Mensajes',
                      ),
                      // Main menu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.menu, color: AppColors.navyDark),
                        tooltip: 'Menú',
                        onSelected: (value) async {
                          switch (value) {
                            case 'profile':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const ProfileScreen(),
                                ),
                              );
                              break;
                            case 'my_jobs':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const MyJobsScreen(),
                                ),
                              );
                              break;
                            case 'browse_jobs':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const BrowseJobsScreen(),
                                ),
                              );
                              break;
                            case 'availability':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const AvailabilityScreen(),
                                ),
                              );
                              break;
                            case 'my_applications':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const MyApplicationsScreen(),
                                ),
                              );
                              break;
                            case 'earnings':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const EarningsScreen(),
                                ),
                              );
                              break;
                            case 'notifications':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const NotificationPreferencesScreen(),
                                ),
                              );
                              break;
                            case 'debug':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const DebugSmsScreen(),
                                ),
                              );
                              break;
                            case 'logout':
                              await supabase.auth.signOut();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'profile',
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline, size: 20, color: AppColors.navyDark),
                                const SizedBox(width: 12),
                                Text('Perfil${_phoneVerified ? ' ✓' : ''}'),
                              ],
                            ),
                          ),
                          if (_userType == 'seeker')
                            const PopupMenuItem(
                              value: 'my_jobs',
                              child: Row(
                                children: [
                                  Icon(Icons.work_outline, size: 20, color: AppColors.navyDark),
                                  SizedBox(width: 12),
                                  Text('Mis trabajos'),
                                ],
                              ),
                            ),
                          if (_userType == 'helper') ...[
                            const PopupMenuItem(
                              value: 'browse_jobs',
                              child: Row(
                                children: [
                                  Icon(Icons.search, size: 20, color: AppColors.navyDark),
                                  SizedBox(width: 12),
                                  Text('Buscar trabajos'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'availability',
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_month, size: 20, color: AppColors.navyDark),
                                  SizedBox(width: 12),
                                  Text('Publicar disponibilidad'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'my_applications',
                              child: Row(
                                children: [
                                  Icon(Icons.assignment_outlined, size: 20, color: AppColors.navyDark),
                                  SizedBox(width: 12),
                                  Text('Mis aplicaciones'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'earnings',
                              child: Row(
                                children: [
                                  Icon(Icons.account_balance_wallet_outlined, size: 20, color: AppColors.navyDark),
                                  SizedBox(width: 12),
                                  Text('Ganancias'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'notifications',
                              child: Row(
                                children: [
                                  Icon(Icons.tune, size: 20, color: AppColors.navyDark),
                                  SizedBox(width: 12),
                                  Text('Preferencias'),
                                ],
                              ),
                            ),
                          ],
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'debug',
                            child: Row(
                              children: [
                                Icon(Icons.bug_report, size: 20, color: AppColors.textMuted),
                                SizedBox(width: 12),
                                Text('Debug SMS'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, size: 20, color: AppColors.navyDark),
                                SizedBox(width: 12),
                                Text('Salir'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Both helpers and seekers now see dashboards
            if (_userType == 'helper') ...[
              _buildHelperDashboard(),
            ] else ...[
              _buildSeekerDashboard(),
            ],

            // Footer
            Container(
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.divider),
                ),
              ),
              child: const Text(
                'Hecho con 🔧 en Alicante',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (context) => Container(
              height: 400,
              color: AppColors.navyDarker,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Notification Debug Logs',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        // Rebuild every 500ms to show live logs
                        Future.delayed(const Duration(milliseconds: 500)).then((_) {
                          if (mounted) setState(() {});
                        });
                        return ListView.builder(
                          itemCount: messageNotificationService.debugLogs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Text(
                                messageNotificationService.debugLogs[index],
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: const Icon(Icons.bug_report),
      ),
    );
  }

  // --- Seeker Dashboard ---

  Widget _buildSeekerDashboard() {
    if (_seekerDashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Build the 7-day calendar data
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next7Days = List.generate(7, (i) => today.add(Duration(days: i)));

    // Group assigned jobs by date
    final jobsByDate = <String, List<Map<String, dynamic>>>{};
    for (final job in _assignedJobsNext7Days) {
      final dateStr = job['scheduled_date'] as String?;
      if (dateStr != null) {
        jobsByDate.putIfAbsent(dateStr, () => []).add(job);
      }
    }

    return Column(
      children: [
        // Navy Header with greeting
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navyDark, AppColors.navyDarker],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  Text(
                    '¡Hola, ${_userName ?? ""}!',
                    style: GoogleFonts.nunito(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gestiona tus trabajos',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Dashboard Cards
        Container(
          constraints: const BoxConstraints(maxWidth: 900),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 7-Day Calendar Card - Expanded with job details
              _buildDashboardCard(
                icon: Icons.calendar_month,
                title: 'Próximos 7 días',
                trailing: const Icon(Icons.chevron_right, color: AppColors.navyLight),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const MyJobsScreen()),
                  );
                  _loadSeekerDashboardData();
                },
                child: Column(
                  children: [
                    // Day headers row
                    Row(
                      children: next7Days.map((date) {
                        final isToday = date == today;
                        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                        final hasJobs = jobsByDate.containsKey(dateStr);

                        return Expanded(
                          child: Column(
                            children: [
                              Text(
                                _getSpanishDayAbbrev(date.weekday),
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: isToday ? AppColors.orange : AppColors.navyDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: hasJobs
                                      ? AppColors.orange
                                      : isToday
                                          ? AppColors.navyVeryLight
                                          : AppColors.background,
                                  shape: BoxShape.circle,
                                  border: isToday && !hasJobs
                                      ? Border.all(color: AppColors.orange, width: 2)
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '${date.day}',
                                    style: GoogleFonts.nunito(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: hasJobs
                                          ? Colors.white
                                          : isToday
                                              ? AppColors.orange
                                              : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    // Job details section
                    if (_assignedJobsNext7Days.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'No tienes trabajos asignados esta semana',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: AppColors.divider),
                      // List all jobs for the next 7 days with full details
                      ...next7Days.map((date) {
                        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                        final dayJobs = jobsByDate[dateStr] ?? [];
                        if (dayJobs.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 8),
                              child: Text(
                                _formatJobDate(dateStr, null),
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ),
                            ...dayJobs.map((job) => _buildSeekerCalendarJobRow(job)),
                          ],
                        );
                      }),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Open jobs with pending applications
              if (_openJobsWithApplications.isNotEmpty) ...[
                _buildDashboardCard(
                  icon: Icons.pending_actions,
                  title: 'Solicitudes pendientes',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_openJobsWithApplications.length}',
                      style: GoogleFonts.nunito(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  child: Column(
                    children: _openJobsWithApplications.take(3).map((job) {
                      final applications = job['applications'] as List? ?? [];
                      final pendingCount = applications.where((a) => a['status'] == 'pending').length;

                      return _buildSeekerJobRow(
                        job: job,
                        subtitle: '$pendingCount ${pendingCount == 1 ? 'solicitud' : 'solicitudes'} pendiente${pendingCount == 1 ? '' : 's'}',
                        subtitleColor: AppColors.orange,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Other open jobs (no applications)
              if (_openJobsNoApplications.isNotEmpty) ...[
                _buildDashboardCard(
                  icon: Icons.work_outline,
                  title: 'Trabajos abiertos',
                  trailing: Text(
                    '${_openJobsNoApplications.length}',
                    style: GoogleFonts.nunito(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  child: Column(
                    children: _openJobsNoApplications.take(3).map((job) {
                      return _buildSeekerJobRow(
                        job: job,
                        subtitle: 'Sin solicitudes aún',
                        subtitleColor: AppColors.textMuted,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Empty state - no jobs at all
              if (_seekerJobs.isEmpty) ...[
                _buildDashboardCard(
                  icon: Icons.add_circle_outline,
                  title: 'Publica tu primer trabajo',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const PostJobScreen()),
                    );
                    _loadSeekerDashboardData();
                  },
                  child: Text(
                    'Describe lo que necesitas y encuentra ayuda cerca de ti.',
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Quick actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const PostJobScreen()),
                        );
                        _loadSeekerDashboardData();
                      },
                      icon: const Icon(Icons.add, size: 20),
                      label: Text('Nuevo trabajo', style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                      )),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const MyJobsScreen()),
                        );
                        _loadSeekerDashboardData();
                      },
                      icon: const Icon(Icons.list_alt, size: 20),
                      label: Text('Ver todos', style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                      )),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.navyLight),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  String _getSpanishDayAbbrev(int weekday) {
    const days = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return days[weekday];
  }

  Widget _buildSeekerJobRow({
    required Map<String, dynamic> job,
    required String subtitle,
    required Color subtitleColor,
  }) {
    final title = job['title'] as String? ?? 'Sin título';
    final scheduledDate = job['scheduled_date'] as String?;
    final scheduledTime = job['scheduled_time'] as String?;
    final isFlexible = job['is_flexible'] == true;

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => JobDetailScreen(jobId: job['id']),
          ),
        );
        _loadSeekerDashboardData();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (scheduledDate != null) ...[
                        const Icon(Icons.calendar_today, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          _formatJobDate(scheduledDate, scheduledTime),
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                        ),
                        const SizedBox(width: 12),
                      ] else if (isFlexible) ...[
                        const Icon(Icons.schedule, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          'Flexible',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  /// Calendar job row for seeker dashboard - shows job title, time, and helper name
  Widget _buildSeekerCalendarJobRow(Map<String, dynamic> job) {
    final title = job['title'] as String? ?? 'Sin título';
    final scheduledTime = job['scheduled_time'] as String?;
    final applications = job['applications'] as List? ?? [];

    // Find the accepted application to get helper name
    String? helperName;
    for (final app in applications) {
      if (app['status'] == 'accepted') {
        final profile = app['profiles'] as Map<String, dynamic>?;
        helperName = profile?['name'] as String?;
        break;
      }
    }

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => JobDetailScreen(jobId: job['id']),
          ),
        );
        _loadSeekerDashboardData();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navyVeryLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Time badge
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                scheduledTime != null ? scheduledTime.substring(0, 5) : '--:--',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Job details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.navyDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (helperName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 13, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          helperName,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  // --- Helper Dashboard Widgets ---

  Widget _buildHelperDashboard() {
    if (_dashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      children: [
        // Helper Hero Header
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navyDark, AppColors.navyDarker],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  Text(
                    '¡Hola, ${_userName ?? "Manitas"}!',
                    style: GoogleFonts.nunito(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aquí tienes tu resumen de hoy',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Dashboard Cards
        Container(
          constraints: const BoxConstraints(maxWidth: 900),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvailabilityCard(),
              const SizedBox(height: 16),
              _buildHelperCalendarCard(),
              const SizedBox(height: 16),
              _buildJobsOverviewCard(),
              const SizedBox(height: 16),
              _buildPreferencesSummaryCard(),
              const SizedBox(height: 16),
              _buildPaymentsSummaryCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: AppColors.navyShadow,
              blurRadius: 16,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.navyDark, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: GoogleFonts.nunito(
                    fontSize: 17, fontWeight: FontWeight.w700,
                    color: AppColors.navyDark,
                  )),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    // Group slots by display day (Mon=0 to Sun=6)
    // DB: 0=Sun, 1=Mon, ..., 6=Sat → Display: Mon=0 → (dbDow+6)%7
    final Map<int, List<String>> slotsByDisplayDay = {};
    for (int i = 0; i < 7; i++) {
      slotsByDisplayDay[i] = [];
    }

    for (final slot in _availabilitySlots) {
      final dbDow = slot['day_of_week'] as int;
      final displayIdx = (dbDow + 6) % 7;
      final start = (slot['start_time'] as String).substring(0, 5);
      final end = (slot['end_time'] as String).substring(0, 5);
      slotsByDisplayDay[displayIdx]!.add('$start-$end');
    }

    const dayAbbrevs = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

    return _buildDashboardCard(
      icon: Icons.calendar_month,
      title: 'Mi disponibilidad',
      trailing: const Icon(Icons.chevron_right, color: AppColors.navyLight),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AvailabilityScreen()),
        );
        _loadDashboardData();
      },
      child: _availabilitySlots.isEmpty
          ? Text(
              'No has configurado tu disponibilidad. Toca para empezar.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (i) {
                final hasSlots = slotsByDisplayDay[i]!.isNotEmpty;
                return Expanded(
                  child: Column(
                    children: [
                      Text(dayAbbrevs[i], style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: hasSlots ? AppColors.navyDark : AppColors.textMuted,
                      )),
                      const SizedBox(height: 4),
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: hasSlots ? AppColors.navyVeryLight : AppColors.background,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: hasSlots
                              ? const Icon(Icons.check, size: 16, color: AppColors.navyDark)
                              : const Text('-', style: TextStyle(color: AppColors.textMuted)),
                        ),
                      ),
                      if (hasSlots) ...[
                        const SizedBox(height: 2),
                        ...slotsByDisplayDay[i]!.take(2).map((s) => Text(
                          s,
                          style: GoogleFonts.inter(fontSize: 9, color: AppColors.textMuted),
                        )),
                        if (slotsByDisplayDay[i]!.length > 2)
                          Text('+${slotsByDisplayDay[i]!.length - 2}',
                            style: GoogleFonts.inter(fontSize: 9, color: AppColors.textMuted)),
                      ],
                    ],
                  ),
                );
              }),
            ),
    );
  }

  Widget _buildJobsOverviewCard() {
    return _buildDashboardCard(
      icon: Icons.work_outline,
      title: 'Trabajos disponibles',
      trailing: const Icon(Icons.chevron_right, color: AppColors.navyLight),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const BrowseJobsScreen()),
        );
        _loadDashboardData();
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$_matchedJobCount',
            style: GoogleFonts.nunito(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: AppColors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'trabajos para ti',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navyDark,
                  ),
                ),
                if (_nearbyJobCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '$_nearbyJobCount más en tu zona',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelperCalendarCard() {
    // Build the 7-day calendar data
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next7Days = List.generate(7, (i) => today.add(Duration(days: i)));

    // Group helper's upcoming jobs by date
    final jobsByDate = <String, List<Map<String, dynamic>>>{};
    for (final app in _upcomingJobs) {
      final job = app['jobs'] as Map<String, dynamic>?;
      if (job == null) continue;
      final dateStr = job['scheduled_date'] as String?;
      if (dateStr != null) {
        jobsByDate.putIfAbsent(dateStr, () => []).add(app);
      }
    }

    // Filter to jobs within next 7 days
    final next7DayStrings = next7Days.map((d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
    ).toSet();
    final jobsNext7Days = _upcomingJobs.where((app) {
      final job = app['jobs'] as Map<String, dynamic>?;
      final dateStr = job?['scheduled_date'] as String?;
      return dateStr != null && next7DayStrings.contains(dateStr);
    }).toList();

    return _buildDashboardCard(
      icon: Icons.calendar_month,
      title: 'Próximos 7 días',
      trailing: const Icon(Icons.chevron_right, color: AppColors.navyLight),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const MyApplicationsScreen()),
        );
        _loadDashboardData();
      },
      child: Column(
        children: [
          // Day headers row
          Row(
            children: next7Days.map((date) {
              final isToday = date == today;
              final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              final hasJobs = jobsByDate.containsKey(dateStr);

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      _getSpanishDayAbbrev(date.weekday),
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: isToday ? AppColors.orange : AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: hasJobs
                            ? AppColors.orange
                            : isToday
                                ? AppColors.navyVeryLight
                                : AppColors.background,
                        shape: BoxShape.circle,
                        border: isToday && !hasJobs
                            ? Border.all(color: AppColors.orange, width: 2)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: hasJobs
                                ? Colors.white
                                : isToday
                                    ? AppColors.orange
                                    : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          // Job details section
          if (jobsNext7Days.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'No tienes trabajos asignados esta semana',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
              ),
            )
          else ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.divider),
            // List all jobs for the next 7 days with full details
            ...next7Days.map((date) {
              final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              final dayJobs = jobsByDate[dateStr] ?? [];
              if (dayJobs.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      _formatJobDate(dateStr, null),
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.navyDark,
                      ),
                    ),
                  ),
                  ...dayJobs.map((app) => _buildHelperCalendarJobRow(app)),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Calendar job row for helper dashboard - shows job title, time, seeker name, and location
  Widget _buildHelperCalendarJobRow(Map<String, dynamic> app) {
    final job = app['jobs'] as Map<String, dynamic>;
    final title = job['title'] as String? ?? 'Sin título';
    final scheduledTime = job['scheduled_time'] as String?;
    final barrio = job['barrio'] as String?;
    final locationAddress = job['location_address'] as String?;
    final location = barrio ?? locationAddress;
    final poster = job['profiles'] as Map<String, dynamic>?;
    final seekerName = poster?['name'] as String? ?? 'Usuario';

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => JobDetailScreen(jobId: job['id']),
          ),
        );
        _loadDashboardData();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navyVeryLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Time badge
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                scheduledTime != null ? scheduledTime.substring(0, 5) : '--:--',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Job details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.navyDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 13, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        seekerName,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (location != null) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            location,
                            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesSummaryCard() {
    final prefs = _notificationPrefs;
    final profile = _profileLocation;
    final barrio = profile?['barrio'] as String?;
    final transportModes = prefs != null
        ? List<String>.from(prefs['transport_modes'] ?? [])
        : <String>[];
    final maxTravel = prefs?['max_travel_minutes'] as int? ?? 30;
    final sms = prefs?['sms_enabled'] == true;
    final email = prefs?['email_enabled'] == true;
    final whatsapp = prefs?['whatsapp_enabled'] == true;
    final paused = prefs?['paused'] == true;

    const transportLabels = {
      'car': 'Coche', 'bike': 'Bici', 'walk': 'A pie',
      'transit': 'Bus/Tram', 'escooter': 'Patinete',
    };

    return _buildDashboardCard(
      icon: Icons.tune,
      title: 'Preferencias',
      trailing: const Icon(Icons.chevron_right, color: AppColors.navyLight),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const NotificationPreferencesScreen()),
        );
        _loadDashboardData();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (paused)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Notificaciones pausadas',
                style: GoogleFonts.inter(color: AppColors.orange, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          if (barrio != null)
            _buildPrefRow(Icons.home, barrio),
          if (transportModes.isNotEmpty)
            _buildPrefRow(Icons.commute,
              '${transportModes.map((m) => transportLabels[m] ?? m).join(', ')} (max $maxTravel min)'),
          _buildPrefRow(Icons.notifications_outlined,
            [
              'App',
              if (sms) 'SMS',
              if (email) 'Email',
              if (whatsapp) 'WhatsApp',
            ].join(', ')),
        ],
      ),
    );
  }

  Widget _buildPrefRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Flexible(child: Text(text,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted))),
        ],
      ),
    );
  }

  Widget _buildPaymentsSummaryCard() {
    return _buildDashboardCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Ganancias',
      trailing: const Icon(Icons.chevron_right, color: AppColors.navyLight),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const EarningsScreen()),
        );
        _loadDashboardData();
      },
      child: _balance == null
          ? Text('Configura tu cuenta de pagos para empezar',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted))
          : Row(
              children: [
                _buildBalancePill('Disponible', _balance!.formattedAvailable, AppColors.success),
                const SizedBox(width: 12),
                _buildBalancePill('Pendiente', _balance!.formattedPending, AppColors.gold),
              ],
            ),
    );
  }

  Widget _buildBalancePill(String label, String amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(
              fontSize: 12, color: color, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(amount, style: GoogleFonts.nunito(
              fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

}

/// Custom painter for the MiManitas logo (orange circle + gold smile)
class _MiManitasLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    // Orange circle (head)
    final circlePaint = Paint()
      ..color = AppColors.orange
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(centerX, size.height * 0.38),
      size.width * 0.22,
      circlePaint,
    );

    // Gold smile curve
    final smilePaint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;

    final smilePath = Path();
    smilePath.moveTo(size.width * 0.18, size.height * 0.7);
    smilePath.quadraticBezierTo(
      centerX, size.height * 0.95,
      size.width * 0.82, size.height * 0.7,
    );
    canvas.drawPath(smilePath, smilePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
