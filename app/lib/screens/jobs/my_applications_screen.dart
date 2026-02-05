import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../main.dart';
import 'job_detail_screen.dart';
import '../reviews/submit_review_screen.dart';
import '../messages/chat_screen.dart';

class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;
  String _filterStatus = 'active'; // active, completed, rejected, all

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      var query = supabase
          .from('applications')
          .select('''
            *,
            jobs!applications_job_id_fkey(
              id,
              title,
              description,
              price_type,
              price_amount,
              location_address,
              status,
              poster_id,
              skills(name_es, icon),
              profiles!jobs_poster_id_fkey(id, name, phone)
            )
          ''')
          .eq('applicant_id', user.id)
          .order('created_at', ascending: false);

      final applications = await query;

      // Check review status for completed jobs
      final applicationsWithReviewStatus = await Future.wait(
        applications.map((app) async {
          final job = app['jobs'];
          bool hasReviewed = false;

          if (job != null &&
              job['status'] == 'completed' &&
              app['status'] == 'accepted') {
            final reviews = await supabase
                .from('reviews')
                .select('id')
                .eq('job_id', job['id'])
                .eq('reviewer_id', user.id);
            hasReviewed = reviews.isNotEmpty;
          }

          return {
            ...app,
            'has_reviewed': hasReviewed,
          };
        }).toList(),
      );

      setState(() {
        _applications = applicationsWithReviewStatus;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading applications: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredApplications {
    if (_filterStatus == 'all') return _applications;
    if (_filterStatus == 'active') {
      // Pending + accepted where job is NOT completed
      return _applications.where((app) {
        final status = app['status'] as String;
        final jobStatus = app['jobs']?['status'] as String? ?? '';
        if (status == 'pending') return true;
        if (status == 'accepted' && jobStatus != 'completed') return true;
        return false;
      }).toList();
    }
    if (_filterStatus == 'completed') {
      // Accepted applications where job IS completed
      return _applications.where((app) {
        final status = app['status'] as String;
        final jobStatus = app['jobs']?['status'] as String? ?? '';
        return status == 'accepted' && jobStatus == 'completed';
      }).toList();
    }
    return _applications
        .where((app) => app['status'] == _filterStatus)
        .toList();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'pending':
      default:
        return AppColors.info;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'accepted':
        return 'Aceptado';
      case 'rejected':
        return 'Rechazado';
      case 'pending':
      default:
        return 'Pendiente';
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'accepted':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
      default:
        return Icons.pending;
    }
  }

  Future<void> _promptForReview(String jobId, String posterId, String posterName) async {
    // Check if user has already reviewed this job
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final existingReviews = await supabase
          .from('reviews')
          .select('id')
          .eq('job_id', jobId)
          .eq('reviewer_id', user.id);

      if (existingReviews.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ya has dejado una reseña para este trabajo'),
              backgroundColor: AppColors.orange,
            ),
          );
        }
        return;
      }

      // Show review screen
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SubmitReviewScreen(
            jobId: jobId,
            revieweeId: posterId,
            revieweeName: posterName,
          ),
        ),
      );

      // Reload applications after review
      _loadApplications();
    } catch (e) {
      print('Error checking for existing review: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _openConversation(String jobId, String seekerId, String posterName) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Check if conversation already exists
      final existingConv = await supabase
          .from('conversations')
          .select('id')
          .eq('job_id', jobId)
          .eq('seeker_id', seekerId)
          .eq('helper_id', user.id)
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
              'seeker_id': seekerId,
              'helper_id': user.id,
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
            otherUserName: posterName,
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

  @override
  Widget build(BuildContext context) {
    final filteredApps = _filteredApplications;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis aplicaciones',
        ),
      ),
      body: Column(
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
                    _applications.where((app) {
                      final s = app['status'] as String;
                      final js = app['jobs']?['status'] as String? ?? '';
                      return s == 'pending' || (s == 'accepted' && js != 'completed');
                    }).length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Completados',
                    'completed',
                    _applications.where((app) {
                      final s = app['status'] as String;
                      final js = app['jobs']?['status'] as String? ?? '';
                      return s == 'accepted' && js == 'completed';
                    }).length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Rechazados',
                    'rejected',
                    _applications
                        .where((app) => app['status'] == 'rejected')
                        .length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip('Todos', 'all', _applications.length),
                ],
              ),
            ),
          ),

          // Applications list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : filteredApps.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '📋',
                              style: TextStyle(fontSize: 64),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _filterStatus == 'all'
                                  ? 'No has aplicado a ningún trabajo'
                                  : _filterStatus == 'active'
                                      ? 'No tienes aplicaciones activas'
                                      : _filterStatus == 'completed'
                                          ? 'No tienes trabajos completados'
                                          : 'No hay aplicaciones ${_getStatusText(_filterStatus).toLowerCase()}',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadApplications,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredApps.length,
                          itemBuilder: (context, index) {
                            final application = filteredApps[index];
                            final job = application['jobs'];
                            final status = application['status'] as String;

                            if (job == null) {
                              return const SizedBox.shrink();
                            }

                            final skill = job['skills'];
                            final poster = job['profiles'];
                            final skillName = skill != null ? skill['name_es'] : '';
                            final skillIcon = skill != null ? skill['icon'] : '';
                            final posterName = poster != null ? poster['name'] : 'Usuario';
                            final posterId = poster != null ? poster['id'] : '';
                            final posterPhone = poster != null ? poster['phone'] : null;
                            final jobStatus = job['status'] as String;
                            final hasReviewed = application['has_reviewed'] as bool? ?? false;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () async {
                                  final changed = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (context) => JobDetailScreen(
                                        jobId: job['id'],
                                      ),
                                    ),
                                  );
                                  if (changed == true) _loadApplications();
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Status badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(status).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _getStatusIcon(status),
                                              size: 14,
                                              color: _getStatusColor(status),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _getStatusText(status),
                                              style: TextStyle(
                                                color: _getStatusColor(status),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Job title and price
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
                                          Text(
                                            job['price_type'] == 'fixed'
                                                ? '€${job['price_amount']}'
                                                : '€${job['price_amount']}/h',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Skill
                                      if (skillName.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.navyVeryLight,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '$skillIcon $skillName',
                                            style: const TextStyle(
                                              color: AppColors.navyDark,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 12),

                                      // Description
                                      Text(
                                        job['description'],
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 15,
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),

                                      // Location and poster
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.location_on,
                                            size: 16,
                                            color: AppColors.textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              job['location_address'] ?? 'Sin ubicación',
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '• $posterName',
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Contact info and message button for accepted applications
                                      if (status == 'accepted') ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            // Message button
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => _openConversation(
                                                  job['id'],
                                                  posterId,
                                                  posterName,
                                                ),
                                                icon: const Icon(Icons.message, size: 18),
                                                label: const Text('Mensaje'),
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (posterPhone != null) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: AppColors.successLight,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.successBorder,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.phone,
                                                  size: 18,
                                                  color: AppColors.success,
                                                ),
                                                const SizedBox(width: 8),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Contacta con el cliente',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: AppColors.success,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      posterPhone,
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppColors.success,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],

                                      // Review status and button for completed jobs
                                      if (jobStatus == 'completed' && status == 'accepted') ...[
                                        const SizedBox(height: 12),
                                        // Review status indicator
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
                                                hasReviewed ? Icons.check_circle : Icons.rate_review,
                                                size: 16,
                                                color: hasReviewed ? AppColors.success : AppColors.orange,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                hasReviewed ? 'Reseña enviada' : 'Pendiente de reseña',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: hasReviewed ? AppColors.success : AppColors.orange,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Review button (only if not reviewed yet)
                                        if (!hasReviewed) ...[
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _promptForReview(
                                                job['id'],
                                                posterId,
                                                posterName,
                                              ),
                                              icon: const Icon(Icons.rate_review, size: 18),
                                              label: const Text('Dejar reseña'),
                                              style: ElevatedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
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
      selectedColor: AppColors.navyDark,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.navyDark,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: AppColors.navyVeryLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppColors.navyDark : Colors.transparent,
        ),
      ),
    );
  }
}
