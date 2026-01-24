import 'package:flutter/material.dart';
import '../../main.dart';

class JobApplicationsScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;

  const JobApplicationsScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
  });

  @override
  State<JobApplicationsScreen> createState() => _JobApplicationsScreenState();
}

class _JobApplicationsScreenState extends State<JobApplicationsScreen> {
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;

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
      final applications = await supabase
          .from('applications')
          .select('''
            *,
            profiles!applications_applicant_id_fkey(id, name, phone, bio, barrio, avatar_url, date_of_birth)
          ''')
          .eq('job_id', widget.jobId)
          .order('created_at', ascending: false);

      setState(() {
        _applications = List<Map<String, dynamic>>.from(applications);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading applications: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar las aplicaciones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _acceptApplication(String applicationId, String helperId) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFE86A33),
          ),
        ),
      );

      // Accept the application
      await supabase
          .from('applications')
          .update({'status': 'accepted'})
          .eq('id', applicationId);

      // Update job status to assigned and set the helper
      await supabase
          .from('jobs')
          .update({
            'status': 'assigned',
            'assigned_to': helperId,
          })
          .eq('id', widget.jobId);

      // Reject all other applications for this job
      await supabase
          .from('applications')
          .update({'status': 'rejected'})
          .eq('job_id', widget.jobId)
          .neq('id', applicationId);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Aplicación aceptada! El trabajo ha sido asignado.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload applications
      await _loadApplications();

      // Go back to my jobs screen
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      print('Error accepting application: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al aceptar la aplicación: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectApplication(String applicationId) async {
    try {
      await supabase
          .from('applications')
          .update({'status': 'rejected'})
          .eq('id', applicationId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aplicación rechazada'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      await _loadApplications();
    } catch (e) {
      print('Error rejecting application: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al rechazar la aplicación: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAcceptConfirmation(String applicationId, String helperId, String helperName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aceptar aplicación'),
        content: Text(
          '¿Quieres aceptar a $helperName para este trabajo?\n\n'
          'Esto asignará el trabajo a $helperName y rechazará automáticamente las demás aplicaciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptApplication(applicationId, helperId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE86A33),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _showRejectConfirmation(String applicationId, String helperName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar aplicación'),
        content: Text('¿Seguro que quieres rechazar a $helperName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _rejectApplication(applicationId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'accepted':
        return 'Aceptado';
      case 'rejected':
        return 'Rechazado';
      case 'withdrawn':
        return 'Retirado';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'withdrawn':
        return Colors.grey;
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
          'Aplicaciones',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Job title header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.jobTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_applications.length} ${_applications.length == 1 ? 'aplicación' : 'aplicaciones'}',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
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
                : _applications.isEmpty
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
                              'No hay aplicaciones todavía',
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
                          itemCount: _applications.length,
                          itemBuilder: (context, index) {
                            final application = _applications[index];
                            final helper = application['profiles'];
                            final helperName = helper != null ? helper['name'] : 'Usuario';
                            final helperId = helper != null ? helper['id'] : '';
                            final helperPhone = helper != null ? helper['phone'] : null;
                            final helperBio = helper != null ? helper['bio'] : null;
                            final helperBarrio = helper != null ? helper['barrio'] : null;
                            final helperAvatar = helper != null ? helper['avatar_url'] : null;
                            final helperDob = helper != null ? helper['date_of_birth'] : null;
                            final status = application['status'] as String;

                            // Calculate age if date of birth is available
                            int? helperAge;
                            if (helperDob != null) {
                              try {
                                final dob = DateTime.parse(helperDob);
                                final today = DateTime.now();
                                helperAge = today.year - dob.year;
                                if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
                                  helperAge--;
                                }
                              } catch (e) {
                                // Invalid date format
                                helperAge = null;
                              }
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Helper avatar
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFFF0E8),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              helperName.isNotEmpty
                                                  ? helperName[0].toUpperCase()
                                                  : 'U',
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFE86A33),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Helper info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    helperName,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (helperAge != null) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey[200],
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        '$helperAge años',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey[700],
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (helperBarrio != null)
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.location_on,
                                                      size: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      helperBarrio,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              if (helperPhone != null && status == 'accepted')
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.phone,
                                                      size: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      helperPhone,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                        // Status badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(status).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _getStatusText(status),
                                            style: TextStyle(
                                              color: _getStatusColor(status),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Bio section
                                    if (helperBio != null && helperBio.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFFBF5),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Sobre mí',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              helperBio,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // Action buttons for pending applications
                                    if (status == 'pending') ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _showRejectConfirmation(
                                                application['id'],
                                                helperName,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red,
                                                side: const BorderSide(
                                                  color: Colors.red,
                                                  width: 1.5,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Text('Rechazar'),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () => _showAcceptConfirmation(
                                                application['id'],
                                                helperId,
                                                helperName,
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFE86A33),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Text('Aceptar'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],

                                    // Contact info for accepted applications
                                    if (status == 'accepted' && helperPhone != null) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF0E8),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.phone,
                                              color: Color(0xFFE86A33),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Contacta con $helperName para coordinar',
                                              style: const TextStyle(
                                                color: Color(0xFFE86A33),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
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
}
