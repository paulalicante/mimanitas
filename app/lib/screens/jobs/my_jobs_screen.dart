import 'package:flutter/material.dart';
import '../../main.dart';
import 'post_job_screen.dart';
import 'job_applications_screen.dart';
import '../reviews/submit_review_screen.dart';
import '../messages/chat_screen.dart';

class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

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
        return status == 'open' || status == 'assigned' || status == 'in_progress';
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

  Future<void> _deleteJob(String jobId) async {
    try {
      await supabase.from('jobs').delete().eq('id', jobId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajo eliminado'),
            backgroundColor: Colors.green,
          ),
        );
        _loadMyJobs(); // Reload list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: Colors.red,
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
            backgroundColor: Colors.green,
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
            backgroundColor: Colors.red,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE86A33),
                  foregroundColor: Colors.white,
                ),
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
            style: TextButton.styleFrom(foregroundColor: Colors.green),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            backgroundColor: Colors.red,
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
        return Colors.blue;
      case 'assigned':
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'disputed':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mis trabajos',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFE86A33),
              ),
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
                      Text(
                        'No has publicado trabajos todavía',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
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
                          backgroundColor: const Color(0xFFE86A33),
                          foregroundColor: Colors.white,
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
                                return s == 'open' || s == 'assigned' || s == 'in_progress';
                              }).length,
                            ),
                            const SizedBox(width: 8),
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
                                _filterStatus == 'active'
                                    ? 'No tienes trabajos activos'
                                    : 'No tienes trabajos completados',
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            )
                          : RefreshIndicator(
                  onRefresh: _loadMyJobs,
                  color: const Color(0xFFE86A33),
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
                                          color: Colors.green.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.notifications_active,
                                              size: 14,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$pendingApps',
                                              style: const TextStyle(
                                                color: Colors.green,
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
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  job['description'],
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 16,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      job['location_address'] ??
                                          'Sin ubicación',
                                      style: TextStyle(
                                        color: Colors.grey[600],
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
                                        color: Color(0xFFE86A33),
                                      ),
                                    ),
                                  ],
                                ),

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
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: hasReviewed
                                            ? Colors.green.withOpacity(0.3)
                                            : Colors.orange.withOpacity(0.3),
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
                                              ? Colors.green[700]
                                              : Colors.orange[700],
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
                                                ? Colors.green[700]
                                                : Colors.orange[700],
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
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFFE86A33),
                                        ),
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
                                          foregroundColor: Colors.green,
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
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFFE86A33),
                                        ),
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
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFE86A33),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        // TODO: Edit functionality
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Función de edición próximamente'),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Editar'),
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFE86A33),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _confirmDelete(
                                        job['id'],
                                        job['title'],
                                      ),
                                      icon: const Icon(Icons.delete, size: 18),
                                      label: const Text('Eliminar'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
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
              backgroundColor: const Color(0xFFE86A33),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo trabajo'),
            )
          : null,
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = value;
        });
      },
      selectedColor: const Color(0xFFE86A33),
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFFE86A33),
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: const Color(0xFFFFF0E8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? const Color(0xFFE86A33) : Colors.transparent,
        ),
      ),
    );
  }
}
