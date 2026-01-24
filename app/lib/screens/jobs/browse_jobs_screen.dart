import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSkills();
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

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;

      // Build query with filters
      var query = supabase
          .from('jobs')
          .select('*, skills(name_es, icon), profiles!jobs_poster_id_fkey(name)')
          .eq('status', 'open');

      // Apply skill filter if selected
      if (_selectedSkillFilter != null) {
        query = query.eq('skill_id', _selectedSkillFilter!);
      }

      // Execute query with ordering
      final jobs = await query.order('created_at', ascending: false);

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
            final applicationStatus = hasApplied ? applications[0]['status'] : null;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Trabajos disponibles',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
        actions: [
          // Filter button
          PopupMenuButton<String>(
            icon: Icon(
              _selectedSkillFilter != null
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
              color: const Color(0xFFE86A33),
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
                    child: Row(
                      children: [
                        const Icon(Icons.clear, size: 20),
                        const SizedBox(width: 8),
                        const Text('Mostrar todos'),
                      ],
                    ),
                    onTap: _clearFilter,
                  ),
                ..._skills.map((skill) {
                  return PopupMenuItem<String>(
                    value: skill['id'].toString(),
                    child: Text('${skill['icon']} ${skill['name_es']}'),
                  );
                }).toList(),
              ];
            },
          ),
        ],
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
                        '📭',
                        style: TextStyle(fontSize: 64),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedSkillFilter != null
                            ? 'No hay trabajos de este tipo'
                            : 'No hay trabajos disponibles',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
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
                  color: const Color(0xFFE86A33),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _jobs.length,
                    itemBuilder: (context, index) {
                      final job = _jobs[index];
                      final skill = job['skills'];
                      final poster = job['profiles'];
                      final skillName = skill != null ? skill['name_es'] : '';
                      final skillIcon = skill != null ? skill['icon'] : '';
                      final posterName = poster != null ? poster['name'] : 'Usuario';
                      final hasApplied = job['has_applied'] ?? false;
                      final applicationStatus = job['application_status'] as String?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => JobDetailScreen(
                                  jobId: job['id'],
                                ),
                              ),
                            );
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
                                    Text(
                                      job['price_type'] == 'fixed'
                                          ? '€${job['price_amount']}'
                                          : '€${job['price_amount']}/h',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFE86A33),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (skillName.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF0E8),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '$skillIcon $skillName',
                                          style: const TextStyle(
                                            color: Color(0xFFE86A33),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    if (hasApplied) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: applicationStatus == 'accepted'
                                              ? Colors.green.withOpacity(0.15)
                                              : applicationStatus == 'rejected'
                                                  ? Colors.red.withOpacity(0.15)
                                                  : Colors.blue.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              applicationStatus == 'accepted'
                                                  ? Icons.check_circle
                                                  : applicationStatus == 'rejected'
                                                      ? Icons.cancel
                                                      : Icons.pending,
                                              size: 14,
                                              color: applicationStatus == 'accepted'
                                                  ? Colors.green
                                                  : applicationStatus == 'rejected'
                                                      ? Colors.red
                                                      : Colors.blue,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              applicationStatus == 'accepted'
                                                  ? 'Aceptado'
                                                  : applicationStatus == 'rejected'
                                                      ? 'Rechazado'
                                                      : 'Aplicado',
                                              style: TextStyle(
                                                color: applicationStatus == 'accepted'
                                                    ? Colors.green
                                                    : applicationStatus == 'rejected'
                                                        ? Colors.red
                                                        : Colors.blue,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
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
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                  maxLines: 3,
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
                                    Expanded(
                                      child: Text(
                                        job['location_address'] ?? 'Sin ubicación',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '• $posterName',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => JobDetailScreen(
                                            jobId: job['id'],
                                          ),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: hasApplied
                                          ? Colors.grey[600]
                                          : const Color(0xFFE86A33),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      hasApplied ? 'Ver detalles' : 'Ver detalles y aplicar',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
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
    );
  }
}
