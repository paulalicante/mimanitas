import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  int _openJobCount = 0;
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

    final results = await Future.wait<dynamic>([
      _loadAvailabilityData(userId),
      _loadOpenJobCount(userId),
      _loadUpcomingJobs(userId),
      _loadPreferencesData(userId),
      _loadBalance(),
    ]);

    if (!mounted) return;
    setState(() {
      _availabilitySlots = results[0] as List<Map<String, dynamic>>;
      _openJobCount = results[1] as int;
      _upcomingJobs = results[2] as List<Map<String, dynamic>>;
      final prefsResult = results[3] as Map<String, dynamic>;
      _notificationPrefs = prefsResult['prefs'] as Map<String, dynamic>?;
      _profileLocation = prefsResult['profile'] as Map<String, dynamic>?;
      _balance = results[4] as HelperBalance?;
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

  Future<int> _loadOpenJobCount(String userId) async {
    try {
      final openJobs = await supabase
          .from('jobs')
          .select('id')
          .eq('status', 'open');

      final appliedJobs = await supabase
          .from('applications')
          .select('job_id')
          .eq('applicant_id', userId);

      final appliedJobIds = appliedJobs.map((a) => a['job_id']).toSet();
      return openJobs.where((j) => !appliedJobIds.contains(j['id'])).length;
    } catch (e) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _loadUpcomingJobs(String userId) async {
    try {
      final data = await supabase
          .from('applications')
          .select('''
            *,
            jobs!applications_job_id_fkey(
              id, title, scheduled_date, scheduled_time, status,
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
        backgroundColor: Color(0xFFFFFBF5),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFE86A33),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              // Header
              Container(
                constraints: const BoxConstraints(maxWidth: 900),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        '🔧',
                        style: TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mi Manitas',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE86A33),
                            ),
                          ),
                          if (_userName != null && _userName!.isNotEmpty)
                            Text(
                              'Hola, $_userName',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
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
                          color: const Color(0xFFE86A33),
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
                                    color: Colors.red,
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
                        color: const Color(0xFFE86A33),
                        tooltip: 'Mensajes',
                      ),
                      // Main menu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.menu, color: Color(0xFFE86A33)),
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
                                const Icon(Icons.person_outline, size: 20, color: Color(0xFFE86A33)),
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
                                  Icon(Icons.work_outline, size: 20, color: Color(0xFFE86A33)),
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
                                  Icon(Icons.search, size: 20, color: Color(0xFFE86A33)),
                                  SizedBox(width: 12),
                                  Text('Buscar trabajos'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'availability',
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_month, size: 20, color: Color(0xFFE86A33)),
                                  SizedBox(width: 12),
                                  Text('Publicar disponibilidad'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'my_applications',
                              child: Row(
                                children: [
                                  Icon(Icons.assignment_outlined, size: 20, color: Color(0xFFE86A33)),
                                  SizedBox(width: 12),
                                  Text('Mis aplicaciones'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'earnings',
                              child: Row(
                                children: [
                                  Icon(Icons.account_balance_wallet_outlined, size: 20, color: Color(0xFFE86A33)),
                                  SizedBox(width: 12),
                                  Text('Ganancias'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'notifications',
                              child: Row(
                                children: [
                                  Icon(Icons.tune, size: 20, color: Color(0xFFE86A33)),
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
                                Icon(Icons.bug_report, size: 20, color: Colors.grey),
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
                                Icon(Icons.logout, size: 20, color: Color(0xFFE86A33)),
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
              // Hero Section
              Container(
                constraints: const BoxConstraints(maxWidth: 900),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
                child: Column(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '🚀 Próximamente en Alicante',
                        style: TextStyle(
                          color: Color(0xFFE86A33),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Encuentra ayuda local.',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Comparte tu ',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'tiempo',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFFE86A33),
                            height: 1.1,
                          ),
                        ),
                        Text(
                          '.',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Conecta con vecinos que necesitan una mano — o ofrece tus habilidades cuando tengas tiempo libre. Sin agencias, sin intermediarios.',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // How it works
              Container(
                constraints: const BoxConstraints(maxWidth: 900),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: Column(
                  children: [
                    const Text(
                      'Cómo funciona',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildStep(
                          '1',
                          'Publica lo que necesitas',
                          '"Necesito ayuda para pintar mi valla este sábado" — pon tu precio o tarifa por hora.',
                        ),
                        _buildStep(
                          '2',
                          'O comparte tu tiempo',
                          'Muestra cuándo estás disponible. Deja que te encuentren cuando necesiten ayuda.',
                        ),
                        _buildStep(
                          '3',
                          'Conecta y listo',
                          'Mensajea, acuerda las condiciones, completa el trabajo. El pago se guarda seguro hasta que ambos estéis contentos.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // CTA Section - Seeker UI
              Container(
                constraints: const BoxConstraints(maxWidth: 900),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE86A33).withOpacity(0.1),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      '¿Necesitas ayuda?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Publica un trabajo y encuentra manitas en tu barrio',
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const PostJobScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE86A33),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Publicar un trabajo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Features
              Container(
                constraints: const BoxConstraints(maxWidth: 900),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  children: [
                    const Text(
                      '¿Qué hace diferente a Mi Manitas?',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildFeature(
                          '📅',
                          'Horarios flexibles',
                          'Muestra tu disponibilidad real. Perfecto para trabajadores por turnos y estudiantes.',
                        ),
                        _buildFeature(
                          '🔒',
                          'Pago seguro',
                          'El dinero se guarda en depósito hasta que el trabajo esté bien hecho.',
                        ),
                        _buildFeature(
                          '📍',
                          'Hiperlocal',
                          'Hecho para tu barrio, no un marketplace global sin alma.',
                        ),
                        _buildFeature(
                          '🚗',
                          'Opción de recogida',
                          'Los manitas pueden ofrecerte recogerte si estás a las afueras.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Footer
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Text(
                'Hecho con 🔧 en Alicante',
                style: TextStyle(
                  color: Colors.grey[600],
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
              color: Colors.black87,
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
        backgroundColor: const Color(0xFFE86A33),
        child: const Icon(Icons.bug_report),
      ),
    );
  }

  // --- Helper Dashboard Widgets ---

  Widget _buildHelperDashboard() {
    if (_dashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFE86A33)),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 900),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE86A33).withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFFE86A33), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold,
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
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFE86A33)),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AvailabilityScreen()),
        );
        _loadDashboardData();
      },
      child: _availabilitySlots.isEmpty
          ? Text(
              'No has configurado tu disponibilidad. Toca para empezar.',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (i) {
                final hasSlots = slotsByDisplayDay[i]!.isNotEmpty;
                return Expanded(
                  child: Column(
                    children: [
                      Text(dayAbbrevs[i], style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: hasSlots ? const Color(0xFFE86A33) : Colors.grey[400],
                      )),
                      const SizedBox(height: 4),
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: hasSlots ? const Color(0xFFFFF0E8) : Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: hasSlots
                              ? const Icon(Icons.check, size: 16, color: Color(0xFFE86A33))
                              : Text('-', style: TextStyle(color: Colors.grey[400])),
                        ),
                      ),
                      if (hasSlots) ...[
                        const SizedBox(height: 2),
                        ...slotsByDisplayDay[i]!.take(2).map((s) => Text(
                          s,
                          style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                        )),
                        if (slotsByDisplayDay[i]!.length > 2)
                          Text('+${slotsByDisplayDay[i]!.length - 2}',
                            style: TextStyle(fontSize: 9, color: Colors.grey[500])),
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
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFE86A33)),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const BrowseJobsScreen()),
        );
        _loadDashboardData();
      },
      child: Row(
        children: [
          Text(
            '$_openJobCount',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE86A33),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _openJobCount == 1
                  ? 'trabajo disponible'
                  : 'trabajos disponibles',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
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
        child: const Text('Ver todos',
          style: TextStyle(color: Color(0xFFE86A33), fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      child: Column(
        children: _upcomingJobs.take(3).map((app) {
          final job = app['jobs'] as Map<String, dynamic>;
          final posterName = job['profiles']?['name'] as String? ?? 'Cliente';
          final scheduledDate = job['scheduled_date'] as String?;
          final scheduledTime = job['scheduled_time'] as String?;

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
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            posterName,
                            if (scheduledDate != null)
                              _formatJobDate(scheduledDate, scheduledTime),
                          ].join(' — '),
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
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
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFE86A33)),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Notificaciones pausadas',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Flexible(child: Text(text,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
        ],
      ),
    );
  }

  Widget _buildPaymentsSummaryCard() {
    return _buildDashboardCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Ganancias',
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFE86A33)),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const EarningsScreen()),
        );
        _loadDashboardData();
      },
      child: _balance == null
          ? Text('Configura tu cuenta de pagos para empezar',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]))
          : Row(
              children: [
                _buildBalancePill('Disponible', _balance!.formattedAvailable, Colors.green),
                const SizedBox(width: 12),
                _buildBalancePill('Pendiente', _balance!.formattedPending, Colors.orange),
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
            Text(label, style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(amount, style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  // --- Marketing Page Widgets ---

  Widget _buildStep(String number, String title, String description) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE86A33).withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFE86A33),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(String icon, String title, String description) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
