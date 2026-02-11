import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import '../../main.dart';
import '../../services/payment_service.dart';
import '../../utils/job_matching.dart';
import '../jobs/my_jobs_screen.dart';
import '../jobs/browse_helpers_screen.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/my_applications_screen.dart';
import '../profile/notification_preferences_screen.dart';
import '../payments/earnings_screen.dart';

/// Home tab content - dashboard for both helpers and seekers
/// Extracted from HomeScreen for use with bottom navigation
class HomeTab extends StatefulWidget {
  final String? userType;
  final String? userName;
  final void Function(int)? onNavigateToTab;

  const HomeTab({
    super.key,
    this.userType,
    this.userName,
    this.onNavigateToTab,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
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
  List<Map<String, dynamic>> _serviceMenuSkills = [];

  @override
  void initState() {
    super.initState();
    if (widget.userType == 'helper') {
      _loadDashboardData();
    } else if (widget.userType == 'seeker') {
      _loadSeekerDashboardData();
    }
  }

  // --- Helper Dashboard Data Loading ---

  Future<void> _loadDashboardData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _dashboardLoading = true);

    // Phase 1: Load prefs, profile, availability
    final phase1 = await Future.wait<dynamic>([
      _loadAvailabilityData(userId),
      _loadPreferencesData(userId),
    ]);

    if (!mounted) return;
    _availabilitySlots = phase1[0] as List<Map<String, dynamic>>;
    final prefsResult = phase1[1] as Map<String, dynamic>;
    _notificationPrefs = prefsResult['prefs'] as Map<String, dynamic>?;
    _profileLocation = prefsResult['profile'] as Map<String, dynamic>?;

    // Phase 2: Load job counts + independent loaders
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

      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final unappliedJobs = openJobs.where((j) {
        if (appliedJobIds.contains(j['id'])) return false;
        final scheduledDate = j['scheduled_date'] as String?;
        if (scheduledDate != null && scheduledDate.compareTo(todayStr) < 0) {
          return false;
        }
        return true;
      }).toList();

      final helperLat = (_profileLocation?['location_lat'] as num?)?.toDouble();
      final helperLng = (_profileLocation?['location_lng'] as num?)?.toDouble();
      final transportModes = _notificationPrefs != null
          ? List<String>.from(_notificationPrefs!['transport_modes'] ?? [])
          : <String>[];
      final maxTravelMinutes = _notificationPrefs?['max_travel_minutes'] as int? ?? 30;
      final notifySkills = _notificationPrefs != null
          ? List<String>.from(_notificationPrefs!['notify_skills'] ?? [])
          : <String>[];
      final minPriceAmount = (_notificationPrefs?['min_price_amount'] as num?)?.toDouble();
      final minHourlyRate = (_notificationPrefs?['min_hourly_rate'] as num?)?.toDouble();

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
            break;
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
      final results = await Future.wait([
        supabase
            .from('jobs')
            .select('''
              *,
              applications(id, status, applicant_id, profiles!applications_applicant_id_fkey(id, name))
            ''')
            .eq('poster_id', userId)
            .order('created_at', ascending: false),
        supabase
            .from('skills')
            .select()
            .eq('model_type', 'service_menu')
            .order('name_es'),
      ]);

      final jobsData = results[0] as List<dynamic>;
      _serviceMenuSkills = List<Map<String, dynamic>>.from(results[1] as List);
      _seekerJobs = List<Map<String, dynamic>>.from(jobsData);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekFromNow = today.add(const Duration(days: 7));

      _assignedJobsNext7Days = [];
      _openJobsWithApplications = [];
      _openJobsNoApplications = [];

      for (final job in _seekerJobs) {
        final status = job['status'] as String?;
        final applications = job['applications'] as List? ?? [];
        final pendingApps = applications.where((a) => a['status'] == 'pending').toList();

        if (status == 'assigned' || status == 'in_progress') {
          final scheduledDate = job['scheduled_date'] as String?;
          if (scheduledDate != null) {
            try {
              final jobDate = DateTime.parse(scheduledDate);
              if (!jobDate.isBefore(today) && jobDate.isBefore(weekFromNow)) {
                _assignedJobsNext7Days.add(job);
              }
            } catch (_) {}
          } else {
            _assignedJobsNext7Days.add(job);
          }
        } else if (status == 'open') {
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
    return SingleChildScrollView(
      child: Center(
        child: Column(
          children: [
            // Header with MiManitas Logo (simplified - no menu buttons)
            Container(
              constraints: const BoxConstraints(maxWidth: 900),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CustomPaint(
                      painter: MiManitasLogoPainter(),
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
            ),

            // Dashboard content based on user type
            if (widget.userType == 'helper')
              _buildHelperDashboard()
            else
              _buildSeekerDashboard(),

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
    );
  }

  // --- Seeker Dashboard ---

  Widget _buildSeekerDashboard() {
    if (_seekerDashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next7Days = List.generate(7, (i) => today.add(Duration(days: i)));

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
                    '¡Hola, ${widget.userName ?? ""}!',
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
              // 7-Day Calendar Card
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
                  onTap: () {
                    // Navigate to Publicar tab
                    widget.onNavigateToTab?.call(2);
                  },
                  child: Text(
                    'Describe lo que necesitas y encuentra ayuda cerca de ti.',
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Service menu categories - browse helpers directly
              if (_serviceMenuSkills.isNotEmpty) ...[
                _buildDashboardCard(
                  icon: Icons.people_outline,
                  title: 'Buscar ayudantes',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contacta directamente con ayudantes por categoría',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _serviceMenuSkills.map((skill) {
                          final icon = skill['icon'] as String? ?? '🔧';
                          final name = skill['name_es'] as String? ?? skill['name'] as String;
                          return ActionChip(
                            avatar: Text(icon, style: const TextStyle(fontSize: 16)),
                            label: Text(name),
                            backgroundColor: AppColors.navyVeryLight,
                            side: BorderSide.none,
                            labelStyle: GoogleFonts.nunito(
                              fontWeight: FontWeight.w600,
                              color: AppColors.navyDark,
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => BrowseHelpersScreen(
                                    skillId: skill['id'] as String,
                                    skillName: name,
                                  ),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Quick actions - simplified since we have bottom nav
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

  Widget _buildSeekerCalendarJobRow(Map<String, dynamic> job) {
    final title = job['title'] as String? ?? 'Sin título';
    final scheduledTime = job['scheduled_time'] as String?;
    final applications = job['applications'] as List? ?? [];

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

  // --- Helper Dashboard ---

  Widget _buildHelperDashboard() {
    if (_dashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
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
                    '¡Hola, ${widget.userName ?? "Manitas"}!',
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
      onTap: () {
        // Navigate to Calendario tab
        widget.onNavigateToTab?.call(2);
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
      onTap: () {
        // Navigate to Trabajos tab
        widget.onNavigateToTab?.call(1);
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next7Days = List.generate(7, (i) => today.add(Duration(days: i)));

    final jobsByDate = <String, List<Map<String, dynamic>>>{};
    for (final app in _upcomingJobs) {
      final job = app['jobs'] as Map<String, dynamic>?;
      if (job == null) continue;
      final dateStr = job['scheduled_date'] as String?;
      if (dateStr != null) {
        jobsByDate.putIfAbsent(dateStr, () => []).add(app);
      }
    }

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
class MiManitasLogoPainter extends CustomPainter {
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
