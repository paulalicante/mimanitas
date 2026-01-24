import 'package:flutter/material.dart';
import '../../main.dart';
import 'job_detail_screen.dart';

class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;
  String _filterStatus = 'all'; // all, pending, accepted, rejected

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
              skills(name_es, icon),
              profiles!jobs_poster_id_fkey(name, phone)
            )
          ''')
          .eq('applicant_id', user.id)
          .order('created_at', ascending: false);

      final applications = await query;

      setState(() {
        _applications = List<Map<String, dynamic>>.from(applications);
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
    return _applications
        .where((app) => app['status'] == _filterStatus)
        .toList();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.blue;
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

  @override
  Widget build(BuildContext context) {
    final filteredApps = _filteredApplications;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mis aplicaciones',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
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
                  _buildFilterChip('Todos', 'all', _applications.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Pendientes',
                    'pending',
                    _applications
                        .where((app) => app['status'] == 'pending')
                        .length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Aceptados',
                    'accepted',
                    _applications
                        .where((app) => app['status'] == 'accepted')
                        .length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Rechazados',
                    'rejected',
                    _applications
                        .where((app) => app['status'] == 'rejected')
                        .length,
                  ),
                ],
              ),
            ),
          ),

          // Applications list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFE86A33),
                    ),
                  )
                : filteredApps.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '📋',
                              style: TextStyle(fontSize: 64),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _filterStatus == 'all'
                                  ? 'No has aplicado a ningún trabajo'
                                  : 'No hay aplicaciones ${_getStatusText(_filterStatus).toLowerCase()}',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadApplications,
                        color: const Color(0xFFE86A33),
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
                            final posterPhone = poster != null ? poster['phone'] : null;

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
                                              color: Color(0xFFE86A33),
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
                                      const SizedBox(height: 12),

                                      // Description
                                      Text(
                                        job['description'],
                                        style: TextStyle(
                                          color: Colors.grey[700],
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

                                      // Contact info for accepted applications
                                      if (status == 'accepted' && posterPhone != null) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.green.withOpacity(0.3),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.phone,
                                                size: 18,
                                                color: Colors.green[700],
                                              ),
                                              const SizedBox(width: 8),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Contacta con el cliente',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.green[700],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    posterPhone,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.green[900],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
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
