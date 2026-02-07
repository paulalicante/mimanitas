import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import '../../main.dart';
import '../../services/geocoding_service.dart';
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
  bool _dataChanged = false;

  // Travel time for helpers (mode → minutes for each transport mode)
  Map<String, int> _travelTimes = {};
  bool _isLoadingTravelTime = false;

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
      final jobData = await supabase.from('jobs').select('''
            *,
            skills(name_es, icon),
            profiles!jobs_poster_id_fkey(id, name, phone)
          ''').eq('id', widget.jobId).single();

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

      // Load travel time for helpers (non-blocking)
      _loadTravelTime();
    } catch (e) {
      print('Error loading job details: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar el trabajo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _travelModeLabel(String mode) {
    const labels = {
      'car': 'en coche',
      'bike': 'en bici',
      'walk': 'a pie',
      'transit': 'en transporte publico',
      'escooter': 'en patinete',
    };
    return labels[mode] ?? mode;
  }

  IconData _travelModeIcon(String mode) {
    const icons = {
      'car': Icons.directions_car,
      'bike': Icons.directions_bike,
      'walk': Icons.directions_walk,
      'transit': Icons.directions_bus,
      'escooter': Icons.electric_scooter,
    };
    return icons[mode] ?? Icons.directions;
  }

  /// Load accurate travel time from Google Distance Matrix API.
  /// Fetches travel time for ALL of the helper's transport modes.
  Future<void> _loadTravelTime() async {
    final user = supabase.auth.currentUser;
    if (user == null || _job == null) return;

    final jobLat = (_job!['location_lat'] as num?)?.toDouble();
    final jobLng = (_job!['location_lng'] as num?)?.toDouble();
    if (jobLat == null || jobLng == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('user_type, location_lat, location_lng')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null || profile['user_type'] != 'helper') return;

      final homeLat = (profile['location_lat'] as num?)?.toDouble();
      final homeLng = (profile['location_lng'] as num?)?.toDouble();
      if (homeLat == null || homeLng == null) return;

      final prefs = await supabase
          .from('notification_preferences')
          .select('transport_modes')
          .eq('user_id', user.id)
          .maybeSingle();

      final transportModes = List<String>.from(prefs?['transport_modes'] ?? ['car']);
      if (transportModes.isEmpty) transportModes.add('car');

      setState(() => _isLoadingTravelTime = true);

      final origin = '$homeLat,$homeLng';
      final destination = '$jobLat,$jobLng';

      final results = <String, int>{};
      for (final mode in transportModes) {
        final minutes = await geocodingService.getTravelTimeMinutes(
          origin: origin,
          destination: destination,
          mode: mode,
        );
        if (minutes != null) {
          results[mode] = minutes;
        }
      }

      if (mounted) {
        setState(() {
          _travelTimes = results;
          _isLoadingTravelTime = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTravelTime = false);
    }
  }

  String _formatScheduledDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
      const months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
      final dayName = days[date.weekday - 1];
      final monthName = months[date.month - 1];
      return '${dayName[0].toUpperCase()}${dayName.substring(1)}, ${date.day} de $monthName';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatScheduledTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return '${parts[0]}:${parts[1]}';
    } catch (_) {
      return timeStr;
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes == 60) return '1 hora';
    if (minutes == 360) return 'medio día';
    if (minutes == 480) return 'día completo';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours horas';
    return '$hours h $mins min';
  }

  Future<void> _checkProfileAndApply() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Check if profile is complete
    try {
      final profile = await supabase
          .from('profiles')
          .select('phone, bio, phone_verified')
          .eq('id', user.id)
          .single();

      final phone = profile['phone'] as String?;
      final bio = profile['bio'] as String?;
      final phoneVerified = profile['phone_verified'] as bool? ?? false;

      final missingFields = <String>[];
      if (phone == null || phone.isEmpty) missingFields.add('Teléfono');
      if (bio == null || bio.isEmpty) missingFields.add('Biografía');

      if (missingFields.isNotEmpty) {
        _showProfileIncompleteDialog(missingFields);
        return;
      }

      // Check if phone needs verification
      if (!phoneVerified) {
        if (!mounted) return;

        final verified = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => PhoneVerificationScreen(
              phoneNumber: phone!,
              onVerified: () {
                // Phone verified successfully
              },
            ),
          ),
        );

        if (verified == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Teléfono verificado'),
              backgroundColor: AppColors.success,
            ),
          );
          // Now apply to the job
          await _applyToJob();
        }
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
            backgroundColor: AppColors.error,
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
                          size: 20, color: AppColors.orange),
                      const SizedBox(width: 8),
                      Text(field),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            const Text(
              'Esto permite que los clientes se pongan en contacto contigo cuando acepten tu aplicación.',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
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
                          content:
                              Text('Perfil actualizado y teléfono verificado'),
                          backgroundColor: AppColors.success,
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
                        backgroundColor: AppColors.success,
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
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
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

      // Signal to parent screens that data changed
      _dataChanged = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Aplicación enviada con éxito!'),
            backgroundColor: AppColors.success,
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
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_job == null) {
      return Scaffold(
        appBar: AppBar(),
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
                style: GoogleFonts.inter(
                  fontSize: 18,
                  color: AppColors.textMuted,
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_dataChanged);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Detalles del trabajo'),
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
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _job!['price_type'] == 'fixed'
                          ? '€${_job!['price_amount']}'
                          : '€${_job!['price_amount']}/h',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.orange,
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
                    color: AppColors.navyVeryLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$skillIcon $skillName',
                    style: const TextStyle(
                      color: AppColors.navyDark,
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.navyShadow,
                      blurRadius: 10,
                      offset: Offset(0, 2),
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
                        color: AppColors.textMuted,
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.navyShadow,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: AppColors.navyDark,
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
                              color: AppColors.textMuted,
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
              // Travel time (helpers only, shown when available)
              if (_isLoadingTravelTime || _travelTimes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.infoLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.infoBorder,
                    ),
                  ),
                  child: _isLoadingTravelTime
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.info,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Calculando tiempo de viaje...',
                              style: TextStyle(
                                fontSize: 15,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tiempo de viaje estimado',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Sort by travel time (fastest first)
                            ...(_travelTimes.entries.toList()
                                  ..sort((a, b) => a.value.compareTo(b.value)))
                                .map((entry) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _travelModeIcon(entry.key),
                                            color: AppColors.info,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '~${entry.value} min ${_travelModeLabel(entry.key)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.navyDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                          ],
                        ),
                ),
              ],

              // Scheduling info (only show if job has scheduling data)
              if (_job!['is_flexible'] == true ||
                  _job!['scheduled_date'] != null ||
                  _job!['estimated_duration_minutes'] != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.navyShadow,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: AppColors.navyDark,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _job!['is_flexible'] == true
                                  ? 'Horario flexible'
                                  : 'Horario',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                            if (_job!['scheduled_date'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _formatScheduledDate(_job!['scheduled_date']),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (_job!['scheduled_time'] != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                _formatScheduledTime(_job!['scheduled_time']),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                            if (_job!['estimated_duration_minutes'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '~${_formatDuration(_job!['estimated_duration_minutes'])} estimado',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Poster info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.navyShadow,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: AppColors.navyVeryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          posterName.isNotEmpty
                              ? posterName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
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
                              color: AppColors.textMuted,
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
                    onPressed: _hasApplied || _isApplying
                        ? null
                        : _checkProfileAndApply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _hasApplied ? AppColors.textMuted : null,
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
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.orange,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Este es tu trabajo publicado',
                          style: TextStyle(
                            color: AppColors.orange,
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
      ),
    );
  }
}
