import 'package:flutter/material.dart';
import '../../main.dart';
import 'post_job_screen.dart';
import 'job_applications_screen.dart';

class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _isLoading = true;

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

      // Load application counts for each job
      final jobsWithCounts = await Future.wait(
        jobs.map((job) async {
          final applications = await supabase
              .from('applications')
              .select('id, status')
              .eq('job_id', job['id']);

          final pendingCount = applications
              .where((app) => app['status'] == 'pending')
              .length;

          return {
            ...job,
            'pending_applications': pendingCount,
            'total_applications': applications.length,
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
      await supabase
          .from('jobs')
          .update({
            'status': 'completed',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', jobId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajo marcado como completado'),
            backgroundColor: Colors.green,
          ),
        );
        _loadMyJobs(); // Reload list
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

  void _confirmCompletion(String jobId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Marcar como completado?'),
        content: Text(
            '¿El trabajo "$title" ha sido completado satisfactoriamente?'),
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
                      Text(
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
              : RefreshIndicator(
                  onRefresh: _loadMyJobs,
                  color: const Color(0xFFE86A33),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _jobs.length,
                    itemBuilder: (context, index) {
                      final job = _jobs[index];
                      final skill = job['skills'];
                      final skillName = skill != null ? skill['name_es'] : '';
                      final skillIcon = skill != null ? skill['icon'] : '';
                      final pendingApps = job['pending_applications'] ?? 0;
                      final totalApps = job['total_applications'] ?? 0;

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
                                          borderRadius: BorderRadius.circular(12),
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
                                      job['location_address'] ?? 'Sin ubicación',
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
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (job['status'] == 'assigned') ...[
                                      TextButton.icon(
                                        onPressed: () => _confirmCompletion(
                                          job['id'],
                                          job['title'],
                                        ),
                                        icon: const Icon(Icons.check_circle, size: 18),
                                        label: const Text('Completar'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.green,
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
}
