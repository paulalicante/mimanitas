import 'package:flutter/material.dart';
import '../../main.dart';
import '../auth/phone_verification_screen.dart';

class JobDetailScreen extends StatefulWidget {
  final String jobId;

  const JobDetailScreen({
    super.key,
    required this.jobId,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  Map<String, dynamic>? _job;
  bool _isLoading = true;
  bool _hasApplied = false;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _loadJobDetails();
  }

  Future<void> _loadJobDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;

      // Load job with related data
      final jobData = await supabase
          .from('jobs')
          .select('''
            *,
            skills(name_es, icon),
            profiles!jobs_poster_id_fkey(id, name, phone)
          ''')
          .eq('id', widget.jobId)
          .single();

      // Check if current user has already applied
      if (user != null) {
        final applications = await supabase
            .from('applications')
            .select('id')
            .eq('job_id', widget.jobId)
            .eq('applicant_id', user.id);

        setState(() {
          _hasApplied = applications.isNotEmpty;
        });
      }

      setState(() {
        _job = jobData;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading job details: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar el trabajo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkProfileAndApply() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Check if profile is complete
    try {
      final profile = await supabase
          .from('profiles')
          .select('phone, bio')
          .eq('id', user.id)
          .single();

      final phone = profile['phone'] as String?;
      final bio = profile['bio'] as String?;

      final missingFields = <String>[];
      if (phone == null || phone.isEmpty) missingFields.add('Teléfono');
      if (bio == null || bio.isEmpty) missingFields.add('Biografía');

      if (missingFields.isNotEmpty) {
        _showProfileIncompleteDialog(missingFields);
        return;
      }

      // Profile is complete, proceed with application
      await _applyToJob();
    } catch (e) {
      print('Error checking profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al verificar perfil: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showProfileIncompleteDialog(List<String> missingFields) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Completa tu perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Para aplicar a trabajos necesitas completar tu perfil con:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...missingFields.map((field) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 20, color: Color(0xFFE86A33)),
                      const SizedBox(width: 8),
                      Text(field),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            const Text(
              'Esto permite que los clientes se pongan en contacto contigo cuando acepten tu aplicación.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showProfileCompletionDialog(missingFields);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE86A33),
              foregroundColor: Colors.white,
            ),
            child: const Text('Completar perfil'),
          ),
        ],
      ),
    );
  }

  void _showProfileCompletionDialog(List<String> missingFields) {
    final phoneController = TextEditingController();
    final bioController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Completa tu perfil'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (missingFields.contains('Teléfono'))
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      hintText: '+34 600 000 000',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa tu teléfono';
                      }
                      // Spanish phone format: +34 followed by 9 digits, or just 9 digits
                      final phoneRegex = RegExp(r'^(\+34|0034)?[6-9]\d{8}$');
                      final cleaned = value.replaceAll(RegExp(r'\s+'), '');
                      if (!phoneRegex.hasMatch(cleaned)) {
                        return 'Formato inválido (ej: +34 600 000 000)';
                      }
                      return null;
                    },
                  ),
                if (missingFields.contains('Teléfono') &&
                    missingFields.contains('Biografía'))
                  const SizedBox(height: 16),
                if (missingFields.contains('Biografía'))
                  TextFormField(
                    controller: bioController,
                    decoration: const InputDecoration(
                      labelText: 'Biografía',
                      hintText: 'Cuéntanos sobre tu experiencia...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa una breve biografía';
                      }
                      return null;
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              try {
                final user = supabase.auth.currentUser;
                if (user == null) return;

                final updates = <String, dynamic>{};
                final phoneNumber = missingFields.contains('Teléfono')
                    ? phoneController.text.trim()
                    : null;

                if (phoneNumber != null) {
                  updates['phone'] = phoneNumber;
                }
                if (missingFields.contains('Biografía')) {
                  updates['bio'] = bioController.text.trim();
                }

                await supabase
                    .from('profiles')
                    .update(updates)
                    .eq('id', user.id);

                if (context.mounted) {
                  Navigator.pop(context);

                  // If phone was updated, navigate to verification
                  if (phoneNumber != null) {
                    final verified = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PhoneVerificationScreen(
                          phoneNumber: phoneNumber,
                          onVerified: () {
                            // Phone verified successfully
                          },
                        ),
                      ),
                    );

                    if (verified == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Perfil actualizado y teléfono verificado'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      // Now apply to the job
                      await _applyToJob();
                    }
                  } else {
                    // No phone update, just bio
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Perfil actualizado'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    await _applyToJob();
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE86A33),
              foregroundColor: Colors.white,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyToJob() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _isApplying = true;
    });

    try {
      // Create application
      await supabase.from('applications').insert({
        'job_id': widget.jobId,
        'applicant_id': user.id,
        'status': 'pending',
      });

      setState(() {
        _hasApplied = true;
        _isApplying = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Aplicación enviada con éxito!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error applying to job: $e');
      setState(() {
        _isApplying = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al aplicar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFFBF5),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFE86A33),
          ),
        ),
      );
    }

    if (_job == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFFBF5),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '😕',
                style: TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 16),
              Text(
                'Trabajo no encontrado',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final skill = _job!['skills'];
    final poster = _job!['profiles'];
    final skillName = skill != null ? skill['name_es'] : '';
    final skillIcon = skill != null ? skill['icon'] : '';
    final posterName = poster != null ? poster['name'] : 'Usuario';
    final user = supabase.auth.currentUser;
    final isOwnJob = user != null && poster != null && poster['id'] == user.id;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Detalles del trabajo',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and Price
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _job!['title'],
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _job!['price_type'] == 'fixed'
                          ? '€${_job!['price_amount']}'
                          : '€${_job!['price_amount']}/h',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE86A33),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Skill badge
              if (skillName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$skillIcon $skillName',
                    style: const TextStyle(
                      color: Color(0xFFE86A33),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Description
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Descripción',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _job!['description'],
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Location
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: const Color(0xFFE86A33),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ubicación',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _job!['location_address'] ?? 'Sin ubicación',
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Poster info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF0E8),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          posterName.isNotEmpty ? posterName[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE86A33),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Publicado por',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            posterName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Apply button (only for helpers who haven't applied and don't own the job)
              if (!isOwnJob)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _hasApplied || _isApplying ? null : _checkProfileAndApply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasApplied
                          ? Colors.grey
                          : const Color(0xFFE86A33),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isApplying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _hasApplied
                                ? 'Ya has aplicado a este trabajo'
                                : 'Aplicar a este trabajo',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

              // Message for own jobs
              if (isOwnJob)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFE86A33),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Este es tu trabajo publicado',
                          style: TextStyle(
                            color: Color(0xFFE86A33),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
