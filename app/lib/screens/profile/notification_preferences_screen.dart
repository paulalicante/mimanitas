import 'package:flutter/material.dart';
import '../../main.dart';
import '../../services/job_notification_service.dart';
import '../../widgets/places_autocomplete_field.dart';
import '../../app_theme.dart';
import 'availability_screen.dart';

/// Transport mode definitions
const List<Map<String, dynamic>> _transportModes = [
  {'id': 'car', 'label': 'Coche', 'icon': Icons.directions_car},
  {'id': 'bike', 'label': 'Bici', 'icon': Icons.pedal_bike},
  {'id': 'walk', 'label': 'A pie', 'icon': Icons.directions_walk},
  {'id': 'transit', 'label': 'Bus/Tram', 'icon': Icons.directions_bus},
  {'id': 'escooter', 'label': 'Patinete', 'icon': Icons.electric_scooter},
];

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPremium = true;

  // Pause toggle
  bool _paused = false;

  // Preferences
  bool _inAppEnabled = true;
  bool _soundEnabled = true;
  bool _smsEnabled = false;
  bool _emailEnabled = false;
  bool _whatsappEnabled = false;
  double? _minPrice;
  double? _minHourlyRate;
  List<String> _selectedSkillIds = [];

  // New: transport & travel
  List<String> _selectedTransportModes = [];
  int _maxTravelMinutes = 30;

  // New: home location
  double? _homeLocationLat;
  double? _homeLocationLng;
  String? _homeLocationAddress;
  String? _homeBarrio;

  // Available skills
  List<Map<String, dynamic>> _skills = [];

  // Text controllers for price filters
  final _minPriceController = TextEditingController();
  final _minHourlyRateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _minHourlyRateController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Load skills, preferences, and profile in parallel
      final skillsFuture = supabase
          .from('skills')
          .select('id, name_es, icon')
          .order('name_es');

      final prefsFuture = supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      final profileFuture = supabase
          .from('profiles')
          .select('subscription_status, location_lat, location_lng, barrio, default_location_address')
          .eq('id', userId)
          .single();

      final results =
          await Future.wait([skillsFuture, prefsFuture, profileFuture]);
      final skills = results[0] as List<dynamic>;
      final prefs = results[1] as Map<String, dynamic>?;
      final profile = results[2] as Map<String, dynamic>;
      final subStatus = profile['subscription_status'] as String?;
      _isPremium = (subStatus == 'free_trial' || subStatus == 'active');

      // Load home location from profile
      _homeLocationLat = (profile['location_lat'] as num?)?.toDouble();
      _homeLocationLng = (profile['location_lng'] as num?)?.toDouble();
      _homeBarrio = profile['barrio'] as String?;
      _homeLocationAddress =
          profile['default_location_address'] as String?;

      setState(() {
        _skills = List<Map<String, dynamic>>.from(skills);

        if (prefs != null) {
          _paused = prefs['paused'] as bool? ?? false;
          _inAppEnabled = prefs['in_app_enabled'] as bool? ?? true;
          _soundEnabled = prefs['sound_enabled'] as bool? ?? true;
          _smsEnabled = prefs['sms_enabled'] as bool? ?? false;
          _emailEnabled = prefs['email_enabled'] as bool? ?? false;
          _whatsappEnabled = prefs['whatsapp_enabled'] as bool? ?? false;
          _minPrice = (prefs['min_price_amount'] as num?)?.toDouble();
          _minHourlyRate = (prefs['min_hourly_rate'] as num?)?.toDouble();
          _selectedSkillIds =
              List<String>.from(prefs['notify_skills'] ?? []);
          _selectedTransportModes =
              List<String>.from(prefs['transport_modes'] ?? []);
          _maxTravelMinutes =
              (prefs['max_travel_minutes'] as int?) ?? 30;
        }

        if (_minPrice != null) {
          _minPriceController.text = _minPrice!.toStringAsFixed(0);
        }
        if (_minHourlyRate != null) {
          _minHourlyRateController.text = _minHourlyRate!.toStringAsFixed(0);
        }

        _isLoading = false;
      });
    } catch (e) {
      print('Error loading notification preferences: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar preferencias: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Parse price filters
      final minPriceText = _minPriceController.text.trim();
      final minPrice =
          minPriceText.isNotEmpty ? double.tryParse(minPriceText) : null;
      final minHourlyText = _minHourlyRateController.text.trim();
      final minHourlyRate =
          minHourlyText.isNotEmpty ? double.tryParse(minHourlyText) : null;

      // Save notification preferences
      await supabase.from('notification_preferences').upsert({
        'user_id': userId,
        'paused': _paused,
        'in_app_enabled': _inAppEnabled,
        'sound_enabled': _soundEnabled,
        'sms_enabled': _smsEnabled,
        'email_enabled': _emailEnabled,
        'whatsapp_enabled': _whatsappEnabled,
        'min_price_amount': minPrice,
        'min_hourly_rate': minHourlyRate,
        'notify_skills': _selectedSkillIds,
        'notify_barrios': [],
        'transport_modes': _selectedTransportModes,
        'max_travel_minutes': _maxTravelMinutes,
      }, onConflict: 'user_id');

      // Save home location to profile if set
      if (_homeLocationLat != null && _homeLocationLng != null) {
        await supabase.from('profiles').update({
          'location_lat': _homeLocationLat,
          'location_lng': _homeLocationLng,
          'barrio': _homeBarrio,
          'default_location_address': _homeLocationAddress,
        }).eq('id', userId);
      }

      // Refresh cached preferences in the notification service
      await jobNotificationService.refreshPreferences();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferencias guardadas'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error saving notification preferences: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Preferencias',
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Guardar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pause toggle — prominent at top
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _paused ? AppColors.orange : Colors.transparent,
                        width: _paused ? 2 : 0,
                      ),
                    ),
                    color: _paused ? AppColors.orangeLight : null,
                    child: SwitchListTile(
                      title: Text(
                        _paused ? 'No disponible' : 'Disponible',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _paused ? AppColors.orange : AppColors.success,
                        ),
                      ),
                      subtitle: Text(
                        _paused
                            ? 'No recibirás notificaciones de nuevos trabajos'
                            : 'Recibirás notificaciones según tus preferencias',
                        style: TextStyle(
                          fontSize: 13,
                          color: _paused ? AppColors.orange : AppColors.textMuted,
                        ),
                      ),
                      value: !_paused,
                      onChanged: (value) => setState(() => _paused = !value),
                      activeColor: AppColors.success,
                      secondary: Icon(
                        _paused ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: _paused ? AppColors.orange : AppColors.success,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Home location section
                  _buildSectionCard(
                    title: 'Mi ubicacion',
                    icon: Icons.home,
                    subtitle: 'Tu direccion base para calcular distancias',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PlacesAutocompleteField(
                              labelText: 'Direccion de casa',
                              hintText: 'Escribe tu direccion...',
                              initialValue: _homeLocationAddress,
                              onPlaceSelected: (place) {
                                setState(() {
                                  _homeLocationAddress = place.address;
                                  _homeLocationLat = place.lat;
                                  _homeLocationLng = place.lng;
                                  _homeBarrio = place.barrio;
                                });
                              },
                            ),
                            if (_homeLocationLat != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle,
                                        color: AppColors.success, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ubicacion guardada${_homeBarrio != null ? ' ($_homeBarrio)' : ''}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Transport mode section
                  _buildSectionCard(
                    title: 'Modo de transporte',
                    icon: Icons.commute,
                    subtitle:
                        'Como llegas a los trabajos? (selecciona todos los que uses)',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _transportModes.map((mode) {
                            final id = mode['id'] as String;
                            final label = mode['label'] as String;
                            final icon = mode['icon'] as IconData;
                            final selected =
                                _selectedTransportModes.contains(id);
                            return FilterChip(
                              avatar: Icon(icon,
                                  size: 18,
                                  color: selected
                                      ? AppColors.navyDark
                                      : AppColors.textMuted),
                              label: Text(label),
                              selected: selected,
                              selectedColor: AppColors.navyVeryLight,
                              checkmarkColor: AppColors.navyDark,
                              onSelected: (v) {
                                setState(() {
                                  if (v) {
                                    _selectedTransportModes.add(id);
                                  } else {
                                    _selectedTransportModes.remove(id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Max travel time section
                  if (_selectedTransportModes.isNotEmpty)
                    _buildSectionCard(
                      title: 'Tiempo maximo de viaje',
                      icon: Icons.timer,
                      subtitle:
                          'Solo notificar para trabajos a los que puedas llegar en este tiempo',
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('5 min',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                                  Text(
                                    '$_maxTravelMinutes min',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.navyDark,
                                    ),
                                  ),
                                  const Text('60 min',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                                ],
                              ),
                              Slider(
                                value: _maxTravelMinutes.toDouble(),
                                min: 5,
                                max: 60,
                                divisions: 11,
                                activeColor: AppColors.orange,
                                onChanged: (v) {
                                  setState(() =>
                                      _maxTravelMinutes = v.round());
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (_selectedTransportModes.isNotEmpty)
                    const SizedBox(height: 16),

                  // In-app section
                  _buildSectionCard(
                    title: 'En la app',
                    icon: Icons.notifications,
                    children: [
                      SwitchListTile(
                        title: const Text('Notificaciones en la app'),
                        subtitle: const Text(
                            'Popups cuando hay nuevos trabajos o aplicaciones'),
                        value: _inAppEnabled,
                        activeColor: AppColors.orange,
                        onChanged: (v) =>
                            setState(() => _inAppEnabled = v),
                      ),
                      SwitchListTile(
                        title: const Text('Sonido'),
                        subtitle: const Text(
                            'Reproducir un sonido con cada notificacion'),
                        value: _soundEnabled,
                        activeColor: AppColors.orange,
                        onChanged: _inAppEnabled
                            ? (v) => setState(() => _soundEnabled = v)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // External channels section
                  _buildSectionCard(
                    title: 'Cuando no estes conectado',
                    icon: Icons.phone_android,
                    children: [
                      SwitchListTile(
                        title: const Text('SMS'),
                        subtitle: Text(_isPremium
                            ? 'Recibir SMS para trabajos nuevos'
                            : 'Disponible con suscripcion premium'),
                        value: _smsEnabled,
                        activeColor: AppColors.orange,
                        onChanged: _isPremium
                            ? (v) => setState(() => _smsEnabled = v)
                            : null,
                      ),
                      SwitchListTile(
                        title: const Text('Email'),
                        subtitle: Text(_isPremium
                            ? 'Recibir emails para trabajos nuevos'
                            : 'Disponible con suscripcion premium'),
                        value: _emailEnabled,
                        activeColor: AppColors.orange,
                        onChanged: _isPremium
                            ? (v) => setState(() => _emailEnabled = v)
                            : null,
                      ),
                      SwitchListTile(
                        title: const Text('WhatsApp'),
                        subtitle: Text(_isPremium
                            ? 'Recibir mensajes de WhatsApp'
                            : 'Disponible con suscripcion premium'),
                        value: _whatsappEnabled,
                        activeColor: AppColors.orange,
                        onChanged: _isPremium
                            ? (v) => setState(() => _whatsappEnabled = v)
                            : null,
                      ),
                      if (!_isPremium)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.orangeLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline,
                                    color: AppColors.navyDark, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: const Text(
                                    'Las notificaciones por SMS, email y WhatsApp son una funcion premium.',
                                    style: TextStyle(
                                      color: AppColors.orange,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Skill filters
                  _buildSectionCard(
                    title: 'Habilidades',
                    icon: Icons.handyman,
                    subtitle:
                        'Solo notificar para estas habilidades (vacio = todas)',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _skills.map((skill) {
                            final id = skill['id'] as String;
                            final name =
                                skill['name_es'] as String? ?? '';
                            final selected =
                                _selectedSkillIds.contains(id);
                            return FilterChip(
                              label: Text(name),
                              selected: selected,
                              selectedColor: AppColors.navyVeryLight,
                              checkmarkColor: AppColors.navyDark,
                              onSelected: (v) {
                                setState(() {
                                  if (v) {
                                    _selectedSkillIds.add(id);
                                  } else {
                                    _selectedSkillIds.remove(id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Availability calendar link
                  _buildSectionCard(
                    title: 'Disponibilidad',
                    icon: Icons.calendar_month,
                    subtitle:
                        'Configura tus horarios para recibir trabajos que encajen',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AvailabilityScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit_calendar),
                            label: const Text('Editar mi calendario'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Price filters
                  _buildSectionCard(
                    title: 'Precio minimo',
                    icon: Icons.euro,
                    subtitle:
                        'Solo notificar para trabajos que paguen al menos esto',
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: TextField(
                          controller: _minPriceController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Precio fijo minimo',
                            hintText: 'Sin minimo',
                            prefixText: '\u20AC ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: TextField(
                          controller: _minHourlyRateController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Tarifa minima por hora',
                            hintText: 'Sin minimo',
                            prefixText: '\u20AC ',
                            suffixText: '/h',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Guardar preferencias',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(icon, color: AppColors.navyDark, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}
