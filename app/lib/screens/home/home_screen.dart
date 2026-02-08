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

            // Helper sees dashboard; seekers see marketing content
            if (_userType == 'helper') ...[
              _buildHelperDashboard(),
            ] else ...[
              _buildSeekerHomePage(),
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

  // --- Seeker Home Page (Marketing) ---

  Widget _buildSeekerHomePage() {
    return Column(
      children: [
        // Navy Hero Section
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navyDark, AppColors.navyDarker],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  // Hero headline
                  Text(
                    'Tu comunidad de',
                    style: GoogleFonts.nunito(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkTextPrimary,
                      height: 1.15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'ayuda ',
                        style: GoogleFonts.nunito(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkTextPrimary,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        'local',
                        style: GoogleFonts.nunito(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Encuentra ayuda de confianza cerca de ti o comparte tu tiempo cuando estés libre. Pago seguro, sin agencias, sin comisiones ocultas.',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      color: AppColors.darkTextSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Hero CTA
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const PostJobScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_circle_outline, size: 20),
                        const SizedBox(width: 8),
                        Text('Publicar un trabajo', style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Gold "Gratis" badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          '⭐ Gratis para todos ⭐',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyDarker,
                          ),
                        ),
                        Text(
                          'hasta 31 julio 2026',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navyDarker.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Gold Stats Strip
        Container(
          width: double.infinity,
          color: AppColors.gold,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Wrap(
                spacing: 32,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _buildStatItem('🚀', 'Lanzamiento Q2 2026'),
                  _buildStatItem('📍', 'Empezamos en Alicante'),
                  _buildStatItem('🔒', 'Pago 100% seguro'),
                  _buildStatItem('💰', 'Sin comisiones ocultas'),
                ],
              ),
            ),
          ),
        ),

        // "No Greedy Rabbit" Section
        Container(
          width: double.infinity,
          color: AppColors.navyDark,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  // Rabbit image placeholder (emoji for now)
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.darkOverlay,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🐰', style: TextStyle(fontSize: 64)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'El ayudante cobra el 100%.',
                    style: GoogleFonts.nunito(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkTextPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Siempre.',
                    style: GoogleFonts.nunito(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Otras plataformas se quedan con el 20-30% de cada trabajo. Nosotros no cobramos comisión por transacción.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: AppColors.darkTextSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Comparison cards
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0x26DC3232), // red tint
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x4DDC3232)),
                          ),
                          child: Column(
                            children: [
                              Text('OTRAS APPS', style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFE85555),
                                letterSpacing: 0.5,
                              )),
                              const SizedBox(height: 4),
                              Text('20-30%', style: GoogleFonts.nunito(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.darkTextPrimary,
                              )),
                              Text('comisión', style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.darkTextMuted,
                              )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              Text('MI MANITAS', style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold,
                                letterSpacing: 0.5,
                              )),
                              const SizedBox(height: 4),
                              Text('0%', style: GoogleFonts.nunito(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.darkTextPrimary,
                              )),
                              Text('para siempre*', style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.darkTextMuted,
                              )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '*Los buscadores de ayuda pagarán una pequeña cuota mensual. Los ayudantes siempre gratis.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.darkTextMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),

        // How It Works Section
        Container(
          width: double.infinity,
          color: AppColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Text(
                    'Cómo funciona',
                    style: GoogleFonts.nunito(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tres pasos sencillos para conseguir ayuda',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildStep('1', 'Publica', 'Describe lo que necesitas y pon tu precio o tarifa por hora.'),
                      _buildStep('2', 'Conecta', 'Recibe solicitudes de manitas verificados de tu zona.'),
                      _buildStep('3', 'Paga seguro', 'El dinero se guarda en depósito hasta que el trabajo esté hecho.'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Features Grid
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Text(
                    'Características',
                    style: GoogleFonts.nunito(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildFeatureCard('🔒', 'Pago en depósito', 'El dinero está seguro hasta que confirmes que el trabajo está bien.'),
                      _buildFeatureCard('📅', 'Calendario', 'Los manitas muestran cuándo están libres.'),
                      _buildFeatureCard('💬', 'Mensajería', 'Chat directo con los candidatos.'),
                      _buildFeatureCard('📱', 'Verificación', 'Todos los usuarios verificados por teléfono.'),
                      _buildFeatureCard('📍', '100% local', 'Hecho para tu barrio, no un marketplace global.'),
                      _buildFeatureCard('💰', 'Precios claros', 'Tú pones el precio. Sin sorpresas.'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Trust Section
        Container(
          width: double.infinity,
          color: AppColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Text(
                    'Confianza garantizada',
                    style: GoogleFonts.nunito(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildTrustItem('🔐', 'Depósito seguro', 'Stripe protege tu dinero'),
                      _buildTrustItem('✓', 'Usuarios verificados', 'Teléfono confirmado'),
                      _buildTrustItem('⚖️', 'Cumplimiento legal', 'GDPR y normativa española'),
                      _buildTrustItem('⭐', 'Reseñas reales', 'De transacciones completadas'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Final CTA Section
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navyDark, AppColors.navyDarker],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  Text(
                    '¿Listo para empezar?',
                    style: GoogleFonts.nunito(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Publica tu primer trabajo gratis y encuentra ayuda en tu barrio.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppColors.darkTextSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const PostJobScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        ),
                        child: Text('Publicar trabajo', style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        )),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const MyJobsScreen(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          side: BorderSide(color: AppColors.darkTextMuted),
                          foregroundColor: AppColors.darkTextPrimary,
                        ),
                        child: Text('Ver mis trabajos', style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Text(text, style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.navyDarker,
        )),
      ],
    );
  }

  Widget _buildFeatureCard(String icon, String title, String description) {
    return Container(
      width: 270,
      padding: const EdgeInsets.all(24),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(height: 16),
          Text(title, style: GoogleFonts.nunito(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.navyDark,
          )),
          const SizedBox(height: 6),
          Text(description, style: GoogleFonts.inter(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.5,
          )),
        ],
      ),
    );
  }

  Widget _buildTrustItem(String icon, String title, String subtitle) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(24),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.navyVeryLight,
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 12),
          Text(title, style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.navyDark,
          ), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.inter(
            fontSize: 13,
            color: AppColors.textMuted,
          ), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String title, String description) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(28),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number, style: GoogleFonts.nunito(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              )),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: GoogleFonts.nunito(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.navyDark,
          )),
          const SizedBox(height: 8),
          Text(description, style: GoogleFonts.inter(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.5,
          ), textAlign: TextAlign.center),
        ],
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
              _buildJobsOverviewCard(),
              const SizedBox(height: 16),
              if (_upcomingJobs.isNotEmpty) ...[
                _buildUpcomingJobsCard(),
                const SizedBox(height: 16),
              ],
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

  Widget _buildUpcomingJobsCard() {
    return _buildDashboardCard(
      icon: Icons.assignment_turned_in,
      title: 'Proximos trabajos',
      trailing: GestureDetector(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const MyApplicationsScreen()),
          );
          _loadDashboardData();
        },
        child: Text('Ver todos',
          style: GoogleFonts.inter(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      child: Column(
        children: _upcomingJobs.take(3).map((app) {
          final job = app['jobs'] as Map<String, dynamic>;
          final scheduledDate = job['scheduled_date'] as String?;
          final scheduledTime = job['scheduled_time'] as String?;
          final barrio = job['barrio'] as String?;
          final locationAddress = job['location_address'] as String?;
          final location = barrio ?? locationAddress;

          return InkWell(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => JobDetailScreen(jobId: job['id']),
                ),
              );
              _loadDashboardData();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job['title'] as String,
                          style: GoogleFonts.nunito(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.navyDark)),
                        const SizedBox(height: 4),
                        // Date and time row
                        if (scheduledDate != null)
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 13, color: AppColors.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                _formatJobDate(scheduledDate, scheduledTime),
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                              ),
                              if (scheduledTime != null) ...[
                                const SizedBox(width: 12),
                                const Icon(Icons.access_time, size: 13, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  scheduledTime.substring(0, 5),
                                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                                ),
                              ],
                            ],
                          ),
                        // Location row
                        if (location != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 13, color: AppColors.textMuted),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
                ],
              ),
            ),
          );
        }).toList(),
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
          color: color.withOpacity(0.08),
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
