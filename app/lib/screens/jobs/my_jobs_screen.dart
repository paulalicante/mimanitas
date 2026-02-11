import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import '../../main.dart';
import 'post_job_screen.dart';
import 'job_applications_screen.dart';
import '../reviews/submit_review_screen.dart';
import '../messages/chat_screen.dart';

class MyJobsScreen extends StatefulWidget {
  final bool embedded;

  const MyJobsScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _isLoading = true;
  String _filterStatus = 'active'; // active, completed, all

  @override
  void initState() {
    super.initState();
    _loadMyJobs();
  }

  Future<void> _loadMyJobs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final jobs = await supabase
          .from('jobs')
          .select('*, skills(name_es, icon)')
          .eq('poster_id', user.id)
          .order('created_at', ascending: false);

      // Load application counts and review status for each job
      final jobsWithCounts = await Future.wait(
        jobs.map((job) async {
          final applications = await supabase
              .from('applications')
              .select('id, status')
              .eq('job_id', job['id']);

          final pendingCount =
              applications.where((app) => app['status'] == 'pending').length;

          // Get helper info for assigned/completed jobs
          bool hasReviewed = false;
          Map<String, dynamic>? helperProfile;

          if (job['assigned_to'] != null) {
            // Get helper profile
            try {
              final helperData = await supabase
                  .from('profiles')
                  .select('id, name')
                  .eq('id', job['assigned_to'])
                  .single();
              helperProfile = helperData;
            } catch (e) {
              print('Error loading helper profile: $e');
            }

            // Check review status for completed jobs
            if (job['status'] == 'completed') {
              final reviews = await supabase
                  .from('reviews')
                  .select('id')
                  .eq('job_id', job['id'])
                  .eq('reviewer_id', user.id);
              hasReviewed = reviews.isNotEmpty;
            }
          }

          return {
            ...job,
            'pending_applications': pendingCount,
            'total_applications': applications.length,
            'has_reviewed': hasReviewed,
            'helper_profile': helperProfile,
          };
        }).toList(),
      );

      setState(() {
        _jobs = jobsWithCounts;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading jobs: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredJobs {
    if (_filterStatus == 'all') return _jobs;
    if (_filterStatus == 'active') {
      return _jobs.where((job) {
        final status = job['status'] as String;
        final isActive = status == 'open' || status == 'assigned' || status == 'in_progress';
        // Exclude past-due open jobs from active (they go to archived)
        if (status == 'open' && _isJobPastDue(job)) return false;
        return isActive;
      }).toList();
    }
    if (_filterStatus == 'open') {
      // Only open jobs that are NOT past-due
      return _jobs.where((job) {
        final status = job['status'] as String;
        return status == 'open' && !_isJobPastDue(job);
      }).toList();
    }
    if (_filterStatus == 'assigned') {
      return _jobs.where((job) {
        final status = job['status'] as String;
        return status == 'assigned' || status == 'in_progress';
      }).toList();
    }
    if (_filterStatus == 'archived') {
      // Past-due open jobs that haven't been assigned yet
      return _jobs.where((job) {
        final status = job['status'] as String;
        return status == 'open' && _isJobPastDue(job);
      }).toList();
    }
    if (_filterStatus == 'completed') {
      return _jobs.where((job) {
        final status = job['status'] as String;
        return status == 'completed' || status == 'cancelled';
      }).toList();
    }
    return _jobs;
  }

  int get _archivedCount {
    return _jobs.where((job) {
      final status = job['status'] as String;
      return status == 'open' && _isJobPastDue(job);
    }).length;
  }

  int get _openCount {
    return _jobs.where((job) {
      final status = job['status'] as String;
      return status == 'open' && !_isJobPastDue(job);
    }).length;
  }

  int get _assignedCount {
    return _jobs.where((job) {
      final status = job['status'] as String;
      return status == 'assigned' || status == 'in_progress';
    }).length;
  }

  String _getEmptyMessage() {
    switch (_filterStatus) {
      case 'active':
        return 'No tienes trabajos activos';
      case 'open':
        return 'No tienes trabajos abiertos';
      case 'assigned':
        return 'No tienes trabajos asignados';
      case 'archived':
        return 'No tienes trabajos archivados';
      case 'completed':
        return 'No tienes trabajos completados';
      default:
        return 'No tienes trabajos';
    }
  }

  Future<void> _deleteJob(String jobId) async {
    try {
      // Delete related applications first (foreign key constraint)
      await supabase.from('applications').delete().eq('job_id', jobId);

      // Delete related conversations
      await supabase.from('conversations').delete().eq('job_id', jobId);

      // Now delete the job
      await supabase.from('jobs').delete().eq('id', jobId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajo eliminado'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMyJobs(); // Reload list
      }
    } catch (e) {
      print('Error deleting job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showReactivateDialog(Map<String, dynamic> job) async {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    bool isFlexible = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Reactivar trabajo', style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este trabajo tiene una fecha pasada. Elige una nueva fecha o marca como horario flexible.',
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              // Flexible toggle
              SwitchListTile(
                title: Text('Horario flexible', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                subtitle: Text('Sin fecha específica', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                value: isFlexible,
                activeColor: AppColors.orange,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  setDialogState(() {
                    isFlexible = value;
                    if (value) {
                      selectedDate = null;
                      selectedTime = null;
                    }
                  });
                },
              ),
              if (!isFlexible) ...[
                const SizedBox(height: 12),
                // Date picker
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    selectedDate != null
                        ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                        : 'Seleccionar fecha',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 8),
                // Time picker
                OutlinedButton.icon(
                  onPressed: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      setDialogState(() => selectedTime = time);
                    }
                  },
                  icon: const Icon(Icons.access_time),
                  label: Text(
                    selectedTime != null
                        ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                        : 'Seleccionar hora (opcional)',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: (isFlexible || selectedDate != null)
                  ? () => Navigator.pop(context, {
                        'isFlexible': isFlexible,
                        'date': selectedDate,
                        'time': selectedTime,
                      })
                  : null,
              child: const Text('Reactivar'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _reactivateJob(job['id'], result);
    }
  }

  Future<void> _reactivateJob(String jobId, Map<String, dynamic> options) async {
    try {
      final isFlexible = options['isFlexible'] as bool;
      final date = options['date'] as DateTime?;
      final time = options['time'] as TimeOfDay?;

      final updateData = <String, dynamic>{
        'is_flexible': isFlexible,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (isFlexible) {
        updateData['scheduled_date'] = null;
        updateData['scheduled_time'] = null;
      } else if (date != null) {
        updateData['scheduled_date'] = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        if (time != null) {
          updateData['scheduled_time'] = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
        } else {
          updateData['scheduled_time'] = null;
        }
      }

      await supabase.from('jobs').update(updateData).eq('id', jobId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajo reactivado'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMyJobs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reactivar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _completeJob(String jobId) async {
    try {
      // Get job details to find the assigned helper
      final jobData = await supabase
          .from('jobs')
          .select('assigned_to')
          .eq('id', jobId)
          .single();

      final assignedTo = jobData['assigned_to'] as String?;

      // Update job status and release payment
      await supabase.from('jobs').update({
        'status': 'completed',
        'payment_status': 'released',
        'payment_released_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', jobId);

      // Release the held transaction
      await supabase.from('transactions').update({
        'status': 'released',
        'released_at': DateTime.now().toIso8601String(),
      }).eq('job_id', jobId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajo completado. Pago liberado al ayudante.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMyJobs();

        // Prompt to leave a review if there was an assigned helper
        if (assignedTo != null) {
          _promptForReview(jobId, assignedTo);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al completar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _promptForReview(String jobId, String helperId,
      {bool showConfirmation = true}) async {
    try {
      // Check if already reviewed
      final existingReviews = await supabase
          .from('reviews')
          .select('id')
          .eq('job_id', jobId)
          .eq('reviewer_id', supabase.auth.currentUser!.id);
      if (existingReviews.isNotEmpty) return;

      // Get helper details
      final helperData = await supabase
          .from('profiles')
          .select('name')
          .eq('id', helperId)
          .single();

      final helperName = helperData['name'] as String? ?? 'el trabajador';

      if (!mounted) return;

      bool shouldReview = !showConfirmation;

      if (showConfirmation) {
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Dejar una reseña?'),
            content: Text(
              '¿Te gustaría dejar una reseña sobre tu experiencia con $helperName?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Más tarde'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Dejar reseña'),
              ),
            ],
          ),
        );
        shouldReview = result == true;
      }

      if (shouldReview && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SubmitReviewScreen(
              jobId: jobId,
              revieweeId: helperId,
              revieweeName: helperName,
            ),
          ),
        );
        // Reload jobs to update review status
        _loadMyJobs();
      }
    } catch (e) {
      print('Error prompting for review: $e');
    }
  }

  void _confirmCompletion(String jobId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Marcar como completado?'),
        content:
            Text('¿El trabajo "$title" ha sido completado satisfactoriamente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _completeJob(jobId);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            child: const Text('Completar'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String jobId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar trabajo?'),
        content: Text('¿Estás seguro de que quieres eliminar "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteJob(jobId);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openConversation(String jobId, String helperId, String helperName) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Check if conversation already exists
      final existingConv = await supabase
          .from('conversations')
          .select('id')
          .eq('job_id', jobId)
          .eq('seeker_id', user.id)
          .eq('helper_id', helperId)
          .maybeSingle();

      String conversationId;

      if (existingConv != null) {
        conversationId = existingConv['id'];
      } else {
        // Create new conversation
        final newConv = await supabase
            .from('conversations')
            .insert({
              'job_id': jobId,
              'seeker_id': user.id,
              'helper_id': helperId,
            })
            .select('id')
            .single();
        conversationId = newConv['id'];
      }

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversationId,
            otherUserName: helperName,
          ),
        ),
      );
    } catch (e) {
      print('Error opening conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir conversación: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'open':
        return 'Abierto';
      case 'assigned':
        return 'Asignado';
      case 'in_progress':
        return 'En progreso';
      case 'completed':
        return 'Completado';
      case 'disputed':
        return 'En disputa';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return AppColors.info;
      case 'assigned':
      case 'in_progress':
        return AppColors.orange;
      case 'completed':
        return AppColors.success;
      case 'disputed':
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textMuted;
    }
  }

  String _formatScheduledDate(String? dateStr, String? timeStr) {
    if (dateStr == null) return 'Sin fecha';
    try {
      final date = DateTime.parse(dateStr);
      final dayNames = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
      final monthNames = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      final dayName = dayNames[date.weekday % 7];
      final monthName = monthNames[date.month - 1];
      final dateFormatted = '$dayName, ${date.day} $monthName';

      if (timeStr != null && timeStr.length >= 5) {
        return '$dateFormatted a las ${timeStr.substring(0, 5)}';
      }
      return dateFormatted;
    } catch (e) {
      return dateStr;
    }
  }

  bool _isJobPastDue(Map<String, dynamic> job) {
    final scheduledDate = job['scheduled_date'] as String?;
    if (scheduledDate == null) return false;
    if (job['is_flexible'] == true) return false;

    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return scheduledDate.compareTo(todayStr) < 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis trabajos',
        ),
        automaticallyImplyLeading: !widget.embedded,
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
                        '📝',
                        style: TextStyle(fontSize: 64),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No has publicado trabajos todavía',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const PostJobScreen(),
                            ),
                          );
                          _loadMyJobs(); // Reload after posting
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                        child: const Text('Publicar trabajo'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Filter chips
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              'Activos',
                              'active',
                              _jobs.where((j) {
                                final s = j['status'] as String;
                                final isActive = s == 'open' || s == 'assigned' || s == 'in_progress';
                                if (s == 'open' && _isJobPastDue(j)) return false;
                                return isActive;
                              }).length,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              'Abiertos',
                              'open',
                              _openCount,
                              color: AppColors.info,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              'Asignados',
                              'assigned',
                              _assignedCount,
                              color: AppColors.orange,
                            ),
                            const SizedBox(width: 8),
                            if (_archivedCount > 0) ...[
                              _buildFilterChip(
                                'Archivados',
                                'archived',
                                _archivedCount,
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                            ],
                            _buildFilterChip(
                              'Completados',
                              'completed',
                              _jobs.where((j) {
                                final s = j['status'] as String;
                                return s == 'completed' || s == 'cancelled';
                              }).length,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip('Todos', 'all', _jobs.length),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filteredJobs.isEmpty
                          ? Center(
                              child: Text(
                                _getEmptyMessage(),
                                style: GoogleFonts.inter(fontSize: 16, color: AppColors.textMuted),
                              ),
                            )
                          : RefreshIndicator(
                  onRefresh: _loadMyJobs,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredJobs.length,
                    itemBuilder: (context, index) {
                      final job = _filteredJobs[index];
                      final skill = job['skills'];
                      final skillName = skill != null ? skill['name_es'] : '';
                      final skillIcon = skill != null ? skill['icon'] : '';
                      final pendingApps = job['pending_applications'] ?? 0;
                      final hasReviewed = job['has_reviewed'] as bool? ?? false;
                      final assignedHelper =
                          job['helper_profile'] as Map<String, dynamic>?;
                      final jobStatus = job['status'] as String;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            // TODO: Navigate to edit screen
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        job['title'],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (pendingApps > 0) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.success.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.notifications_active,
                                              size: 14,
                                              color: AppColors.success,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$pendingApps',
                                              style: const TextStyle(
                                                color: AppColors.success,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(job['status'])
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _getStatusText(job['status']),
                                        style: TextStyle(
                                          color: _getStatusColor(job['status']),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (skillName.isNotEmpty)
                                  Text(
                                    '$skillIcon $skillName',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                // Scheduled date/time display
                                if (job['scheduled_date'] != null || job['is_flexible'] == true) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        job['is_flexible'] == true ? Icons.event_available : Icons.calendar_today,
                                        size: 14,
                                        color: AppColors.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        job['is_flexible'] == true
                                            ? 'Horario flexible'
                                            : _formatScheduledDate(job['scheduled_date'], job['scheduled_time']),
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  job['description'],
                                  style: const TextStyle(
                                    color: AppColors.textDark,
                                    fontSize: 15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      size: 16,
                                      color: AppColors.textMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      job['location_address'] ??
                                          'Sin ubicación',
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      job['price_type'] == 'fixed'
                                          ? '€${job['price_amount']}'
                                          : '€${job['price_amount']}/hora',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.orange,
                                      ),
                                    ),
                                  ],
                                ),

                                // Archived indicator for past-due jobs
                                if (jobStatus == 'open' && _isJobPastDue(job)) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningLight,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.warning.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.schedule,
                                          size: 16,
                                          color: AppColors.warning,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Fecha pasada - Reactivar para publicar',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.warning,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // Review status indicator for completed jobs
                                if (jobStatus == 'completed' &&
                                    assignedHelper != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hasReviewed
                                          ? AppColors.successLight
                                          : AppColors.orangeLight,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: hasReviewed
                                            ? AppColors.successBorder
                                            : AppColors.orange.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          hasReviewed
                                              ? Icons.check_circle
                                              : Icons.rate_review,
                                          size: 16,
                                          color: hasReviewed
                                              ? AppColors.success
                                              : AppColors.orange,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          hasReviewed
                                              ? 'Reseña enviada'
                                              : 'Pendiente de reseña',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: hasReviewed
                                                ? AppColors.success
                                                : AppColors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // Reactivate button for archived (past-due) jobs
                                    if (jobStatus == 'open' && _isJobPastDue(job)) ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _showReactivateDialog(job),
                                        icon: const Icon(Icons.refresh, size: 18),
                                        label: const Text('Reactivar'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.warning,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    // Message button for assigned jobs
                                    if ((job['status'] == 'assigned' || job['status'] == 'completed') &&
                                        assignedHelper != null) ...[
                                      TextButton.icon(
                                        onPressed: () => _openConversation(
                                          job['id'],
                                          assignedHelper['id'],
                                          assignedHelper['name'] ?? 'Trabajador',
                                        ),
                                        icon: const Icon(Icons.message, size: 18),
                                        label: const Text('Mensaje'),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (job['status'] == 'assigned') ...[
                                      TextButton.icon(
                                        onPressed: () => _confirmCompletion(
                                          job['id'],
                                          job['title'],
                                        ),
                                        icon: const Icon(Icons.check_circle,
                                            size: 18),
                                        label: const Text('Completar'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.success,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (jobStatus == 'completed' &&
                                        assignedHelper != null &&
                                        !hasReviewed) ...[
                                      TextButton.icon(
                                        onPressed: () => _promptForReview(
                                          job['id'],
                                          assignedHelper['id'],
                                          showConfirmation: false,
                                        ),
                                        icon: const Icon(Icons.rate_review,
                                            size: 18),
                                        label: const Text('Dejar reseña'),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                JobApplicationsScreen(
                                              jobId: job['id'],
                                              jobTitle: job['title'],
                                              jobPrice: (job['price_amount'] as num?)?.toDouble() ?? 0,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.people, size: 18),
                                      label: const Text('Aplicaciones'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => PostJobScreen(jobToEdit: job),
                                          ),
                                        ).then((_) => _loadMyJobs());
                                      },
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Editar'),
                                    ),
                                    // Only show delete for open jobs (not assigned/completed)
                                    if (jobStatus == 'open') ...[
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () => _confirmDelete(
                                          job['id'],
                                          job['title'],
                                        ),
                                        icon: const Icon(Icons.delete, size: 18),
                                        label: const Text('Eliminar'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                    ),
                  ],
                ),
      floatingActionButton: _jobs.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PostJobScreen(),
                  ),
                );
                _loadMyJobs(); // Reload after posting
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo trabajo'),
            )
          : null,
    );
  }

  Widget _buildFilterChip(String label, String value, int count, {Color? color}) {
    final isSelected = _filterStatus == value;
    final chipColor = color ?? AppColors.navyDark;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = value;
        });
      },
      selectedColor: chipColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : chipColor,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: color != null ? color.withValues(alpha: 0.1) : AppColors.navyVeryLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? chipColor : Colors.transparent,
        ),
      ),
    );
  }
}
