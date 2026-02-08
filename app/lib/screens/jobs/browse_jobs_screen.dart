import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import '../../main.dart';
import 'job_detail_screen.dart';

class BrowseJobsScreen extends StatefulWidget {
  const BrowseJobsScreen({super.key});

  @override
  State<BrowseJobsScreen> createState() => _BrowseJobsScreenState();
}

class _BrowseJobsScreenState extends State<BrowseJobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _isLoading = true;
  String? _selectedSkillFilter;
  List<Map<String, dynamic>> _skills = [];

  // Schedule filter
  bool _filterBySchedule = false;
  List<Map<String, dynamic>> _availabilitySlots = [];
  bool _hasAvailability = false; // true if helper has set any availability

  @override
  void initState() {
    super.initState();
    _loadSkills();
    _loadAvailability();
    _loadJobs();
  }

  Future<void> _loadSkills() async {
    try {
      final skills = await supabase.from('skills').select().order('name_es');
      setState(() {
        _skills = List<Map<String, dynamic>>.from(skills);
      });
    } catch (e) {
      print('Error loading skills: $e');
    }
  }

  Future<void> _loadAvailability() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await supabase
          .from('availability')
          .select('day_of_week, start_time, end_time, is_recurring, specific_date')
          .eq('user_id', user.id);
      setState(() {
        _availabilitySlots = List<Map<String, dynamic>>.from(data);
        _hasAvailability = _availabilitySlots.isNotEmpty;
      });
    } catch (e) {
      print('Error loading availability: $e');
    }
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;

      // Build query with filters
      var query = supabase
          .from('jobs')
          .select(
              '*, skills(name_es, icon), profiles!jobs_poster_id_fkey(name)')
          .eq('status', 'open');

      // Apply skill filter if selected
      if (_selectedSkillFilter != null) {
        query = query.eq('skill_id', _selectedSkillFilter!);
      }

      // Execute query with ordering
      final allJobs = await query.order('created_at', ascending: false);

      // Filter out jobs with past scheduled dates
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final jobs = allJobs.where((job) {
        final scheduledDate = job['scheduled_date'] as String?;
        // Keep jobs without a date, or with today or future dates
        if (scheduledDate == null) return true;
        return scheduledDate.compareTo(todayStr) >= 0;
      }).toList();

      // Check which jobs the current user has applied to
      final jobsWithStatus = await Future.wait(
        jobs.map((job) async {
          if (user != null) {
            final applications = await supabase
                .from('applications')
                .select('status')
                .eq('job_id', job['id'])
                .eq('applicant_id', user.id);

            final hasApplied = applications.isNotEmpty;
            final applicationStatus =
                hasApplied ? applications[0]['status'] : null;

            return {
              ...job,
              'has_applied': hasApplied,
              'application_status': applicationStatus,
            };
          } else {
            return job;
          }
        }).toList(),
      );

      setState(() {
        _jobs = jobsWithStatus;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading jobs: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _selectedSkillFilter = null;
    });
    _loadJobs();
  }

  /// Check if a job matches the helper's availability.
  /// Flexible jobs and jobs without a date always match.
  bool _jobMatchesAvailability(Map<String, dynamic> job) {
    if (!_hasAvailability) return true;

    final isFlexible = job['is_flexible'] == true;
    final scheduledDate = job['scheduled_date'] as String?;
    final scheduledTime = job['scheduled_time'] as String?;

    // Flexible jobs or jobs without a date match everything
    if (isFlexible || scheduledDate == null) return true;

    final dateObj = DateTime.parse(scheduledDate);
    // Convert Dart weekday (1=Mon, 7=Sun) to DB convention (0=Sun, 1=Mon, ..., 6=Sat)
    final dayOfWeek = dateObj.weekday % 7;

    // Parse job time if available
    int? jobTimeMinutes;
    if (scheduledTime != null) {
      try {
        final parts = scheduledTime.split(':');
        jobTimeMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } catch (_) {}
    }

    for (final slot in _availabilitySlots) {
      // Check specific date match
      if (slot['specific_date'] == scheduledDate) {
        if (jobTimeMinutes == null) return true;
        final startMinutes = _parseTimeMinutes(slot['start_time'] as String);
        final endMinutes = _parseTimeMinutes(slot['end_time'] as String);
        if (jobTimeMinutes >= startMinutes && jobTimeMinutes <= endMinutes) {
          return true;
        }
      }
      // Check recurring day match
      final slotRecurring = slot['is_recurring'] as bool? ?? true;
      final slotDow = slot['day_of_week'] as int;
      if (slotRecurring && slotDow == dayOfWeek) {
        if (jobTimeMinutes == null) return true;
        final startMinutes = _parseTimeMinutes(slot['start_time'] as String);
        final endMinutes = _parseTimeMinutes(slot['end_time'] as String);
        if (jobTimeMinutes >= startMinutes && jobTimeMinutes <= endMinutes) {
          return true;
        }
      }
    }

    return false;
  }

  int _parseTimeMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Get visible jobs (filtered by schedule if toggle is on)
  List<Map<String, dynamic>> get _visibleJobs {
    if (!_filterBySchedule || !_hasAvailability) return _jobs;
    return _jobs.where(_jobMatchesAvailability).toList();
  }

  /// Count of jobs hidden by the schedule filter
  int get _hiddenJobsCount {
    if (!_filterBySchedule || !_hasAvailability) return 0;
    return _jobs.length - _visibleJobs.length;
  }

  String _formatScheduleCompact(Map<String, dynamic> job) {
    final isFlexible = job['is_flexible'] == true;
    final date = job['scheduled_date'] as String?;
    final time = job['scheduled_time'] as String?;
    final duration = job['estimated_duration_minutes'] as int?;

    if (isFlexible) {
      if (duration != null) return 'Horario flexible (~${_formatDuration(duration)})';
      return 'Horario flexible';
    }

    final parts = <String>[];
    if (date != null) {
      try {
        final d = DateTime.parse(date);
        const dayNames = ['dom', 'lun', 'mar', 'mie', 'jue', 'vie', 'sab'];
        const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun',
          'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
        final dayName = dayNames[d.weekday % 7];
        parts.add('${dayName[0].toUpperCase()}${dayName.substring(1)}, ${d.day} ${months[d.month - 1]}');
      } catch (_) {
        parts.add(date);
      }
    }
    if (time != null) {
      try {
        final tp = time.split(':');
        parts.add('${tp[0]}:${tp[1]}');
      } catch (_) {
        parts.add(time);
      }
    }
    if (duration != null) parts.add('(~${_formatDuration(duration)})');
    return parts.join(', ');
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes == 60) return '1h';
    if (minutes == 360) return 'medio dia';
    if (minutes == 480) return 'dia completo';
    final hours = minutes ~/ 60;
    return '${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    final visibleJobs = _visibleJobs;
    final hiddenCount = _hiddenJobsCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trabajos disponibles',
        ),
        actions: [
          // Schedule filter toggle (only if helper has availability set)
          if (_hasAvailability)
            IconButton(
              icon: Icon(
                _filterBySchedule
                    ? Icons.calendar_month
                    : Icons.calendar_month_outlined,
                color: _filterBySchedule
                    ? AppColors.gold
                    : Colors.white70,
              ),
              tooltip: _filterBySchedule
                  ? 'Mostrando solo mi horario'
                  : 'Filtrar por mi horario',
              onPressed: () {
                setState(() {
                  _filterBySchedule = !_filterBySchedule;
                });
              },
            ),
          // Skill filter button
          PopupMenuButton<String>(
            icon: Icon(
              _selectedSkillFilter != null
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
            ),
            tooltip: 'Filtrar por tipo de trabajo',
            onSelected: (skillId) {
              setState(() {
                _selectedSkillFilter = skillId;
              });
              _loadJobs();
            },
            itemBuilder: (context) {
              return [
                if (_selectedSkillFilter != null)
                  PopupMenuItem<String>(
                    value: '',
                    onTap: _clearFilter,
                    child: const Row(
                      children: [
                        Icon(Icons.clear, size: 20),
                        SizedBox(width: 8),
                        Text('Mostrar todos'),
                      ],
                    ),
                  ),
                ..._skills.map((skill) {
                  return PopupMenuItem<String>(
                    value: skill['id'].toString(),
                    child: Text('${skill['icon']} ${skill['name_es']}'),
                  );
                }),
              ];
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _jobs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '📭',
                        style: TextStyle(fontSize: 64),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedSkillFilter != null
                            ? 'No hay trabajos de este tipo'
                            : 'No hay trabajos disponibles',
                        style: const TextStyle(
                          fontSize: 18,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (_selectedSkillFilter != null) ...[
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _clearFilter,
                          child: const Text('Ver todos los trabajos'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadJobs,
                  child: Column(
                    children: [
                      // Hidden jobs notice
                      if (_filterBySchedule && hiddenCount > 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          color: AppColors.orangeLight,
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 18, color: AppColors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$hiddenCount trabajo${hiddenCount == 1 ? '' : 's'} no coincide${hiddenCount == 1 ? '' : 'n'} con tu horario',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.orange,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _filterBySchedule = false;
                                  });
                                },
                                child: const Text(
                                  'Ver todos',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.orange,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Schedule filter active chip
                      if (_filterBySchedule && hiddenCount == 0 && _hasAvailability)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: AppColors.successLight,
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 18, color: AppColors.success),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Todos los trabajos coinciden con tu horario',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Job list
                      Expanded(
                        child: visibleJobs.isEmpty && _filterBySchedule
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.calendar_month,
                                        size: 64, color: AppColors.border),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Ningun trabajo coincide con tu horario',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _filterBySchedule = false;
                                        });
                                      },
                                      child: const Text('Ver todos los trabajos'),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: visibleJobs.length,
                                itemBuilder: (context, index) {
                                  final job = visibleJobs[index];
                                  final skill = job['skills'];
                                  final poster = job['profiles'];
                                  final skillName =
                                      skill != null ? skill['name_es'] : '';
                                  final skillIcon =
                                      skill != null ? skill['icon'] : '';
                                  final posterName =
                                      poster != null ? poster['name'] : 'Usuario';
                                  final hasApplied =
                                      job['has_applied'] ?? false;
                                  final applicationStatus =
                                      job['application_status'] as String?;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: InkWell(
                                      onTap: () async {
                                        final changed =
                                            await Navigator.of(context)
                                                .push<bool>(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                JobDetailScreen(
                                              jobId: job['id'],
                                            ),
                                          ),
                                        );
                                        if (changed == true) _loadJobs();
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    job['title'],
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.navyDark,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  job['price_type'] == 'fixed'
                                                      ? '${job['price_amount']}€'
                                                      : '${job['price_amount']}€/h',
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.orange,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                if (skillName.isNotEmpty)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.navyVeryLight,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                    child: Text(
                                                      '$skillIcon $skillName',
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.navyDark,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                if (hasApplied) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: applicationStatus ==
                                                              'accepted'
                                                          ? AppColors.successLight
                                                          : applicationStatus ==
                                                                  'rejected'
                                                              ? AppColors.errorLight
                                                              : AppColors.infoLight,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          applicationStatus ==
                                                                  'accepted'
                                                              ? Icons
                                                                  .check_circle
                                                              : applicationStatus ==
                                                                      'rejected'
                                                                  ? Icons.cancel
                                                                  : Icons
                                                                      .pending,
                                                          size: 14,
                                                          color: applicationStatus ==
                                                                  'accepted'
                                                              ? AppColors.success
                                                              : applicationStatus ==
                                                                      'rejected'
                                                                  ? AppColors.error
                                                                  : AppColors.info,
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Text(
                                                          applicationStatus ==
                                                                  'accepted'
                                                              ? 'Aceptado'
                                                              : applicationStatus ==
                                                                      'rejected'
                                                                  ? 'Rechazado'
                                                                  : 'Aplicado',
                                                          style: TextStyle(
                                                            color: applicationStatus ==
                                                                    'accepted'
                                                                ? AppColors.success
                                                                : applicationStatus ==
                                                                        'rejected'
                                                                    ? AppColors.error
                                                                    : AppColors.info,
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              job['description'],
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 15,
                                                height: 1.4,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            // Scheduling info
                                            if (job['is_flexible'] == true ||
                                                job['scheduled_date'] != null ||
                                                job['estimated_duration_minutes'] !=
                                                    null) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.calendar_today,
                                                    size: 14,
                                                    color: AppColors.textMuted,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _formatScheduleCompact(job),
                                                    style: const TextStyle(
                                                      color: AppColors.textMuted,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.location_on,
                                                  size: 16,
                                                  color: AppColors.textMuted,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    job['location_address'] ??
                                                        'Sin ubicacion',
                                                    style: const TextStyle(
                                                      color: AppColors.textMuted,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  posterName,
                                                  style: const TextStyle(
                                                    color: AppColors.textMuted,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  final changed =
                                                      await Navigator.of(
                                                              context)
                                                          .push<bool>(
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          JobDetailScreen(
                                                        jobId: job['id'],
                                                      ),
                                                    ),
                                                  );
                                                  if (changed == true) {
                                                    _loadJobs();
                                                  }
                                                },
                                                style: hasApplied
                                                    ? ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            AppColors.textMuted,
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            vertical: 12),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                      )
                                                    : ElevatedButton.styleFrom(
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            vertical: 12),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                      ),
                                                child: Text(
                                                  hasApplied
                                                      ? 'Ver detalles'
                                                      : 'Ver detalles y aplicar',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
