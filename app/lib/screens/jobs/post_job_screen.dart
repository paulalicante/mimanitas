import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../../main.dart';
import '../../widgets/places_autocomplete_field.dart';
import '../auth/phone_verification_screen.dart';

class PostJobScreen extends StatefulWidget {
  final Map<String, dynamic>? jobToEdit;

  const PostJobScreen({super.key, this.jobToEdit});

  bool get isEditing => jobToEdit != null;

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String _priceType = 'fixed';
  String? _selectedSkill;
  List<Map<String, dynamic>> _skills = [];

  // Location from Places autocomplete
  String? _selectedAddress;
  double? _selectedLat;
  double? _selectedLng;
  String? _selectedBarrio;

  // Saved addresses
  List<Map<String, dynamic>> _savedLocations = [];
  String? _selectedSavedLocationId; // null = using autocomplete (new address)
  bool _showAutocomplete = true; // false when a saved address chip is selected
  bool _saveNewAddress = false;
  final _saveAddressLabelController = TextEditingController();

  // Scheduling
  bool _isFlexible = false;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int? _estimatedDuration; // in minutes

  static const List<Map<String, dynamic>> _durationOptions = [
    {'label': '30 min', 'value': 30},
    {'label': '1 hora', 'value': 60},
    {'label': '2 horas', 'value': 120},
    {'label': '3 horas', 'value': 180},
    {'label': '4 horas', 'value': 240},
    {'label': 'Medio dia', 'value': 360},
    {'label': 'Dia completo', 'value': 480},
  ];

  @override
  void initState() {
    super.initState();
    _loadSkills();
    _loadSavedLocations();
    _populateFormIfEditing();
  }

  void _populateFormIfEditing() {
    final job = widget.jobToEdit;
    if (job == null) return;

    _titleController.text = job['title'] ?? '';
    _descriptionController.text = job['description'] ?? '';
    _priceController.text = (job['price_amount'] as num?)?.toString() ?? '';
    _priceType = job['price_type'] ?? 'fixed';
    _selectedSkill = job['skill_id'];
    _selectedAddress = job['location_address'];
    _selectedLat = (job['location_lat'] as num?)?.toDouble();
    _selectedLng = (job['location_lng'] as num?)?.toDouble();
    _selectedBarrio = job['barrio'];
    _isFlexible = job['is_flexible'] ?? false;
    _estimatedDuration = job['estimated_duration_minutes'];

    // Parse scheduled date/time
    final scheduledDate = job['scheduled_date'] as String?;
    if (scheduledDate != null) {
      try {
        _selectedDate = DateTime.parse(scheduledDate);
      } catch (_) {}
    }
    final scheduledTime = job['scheduled_time'] as String?;
    if (scheduledTime != null && scheduledTime.length >= 5) {
      try {
        final parts = scheduledTime.split(':');
        _selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }

    // If we have an address, don't show autocomplete initially
    if (_selectedAddress != null) {
      _showAutocomplete = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _saveAddressLabelController.dispose();
    super.dispose();
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

  Future<void> _loadSavedLocations() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await supabase
          .from('saved_locations')
          .select()
          .eq('user_id', user.id)
          .order('is_default', ascending: false)
          .order('updated_at', ascending: false);
      setState(() {
        _savedLocations = List<Map<String, dynamic>>.from(data);
        // If there are saved locations, start with the default selected
        if (_savedLocations.isNotEmpty) {
          _showAutocomplete = false;
          final defaultLoc = _savedLocations.first;
          _selectSavedLocation(defaultLoc);
        }
      });
    } catch (e) {
      // Table may not exist yet — ignore silently
      print('Error loading saved locations: $e');
    }
  }

  void _selectSavedLocation(Map<String, dynamic> location) {
    setState(() {
      _selectedSavedLocationId = location['id'] as String;
      _selectedAddress = location['address'] as String?;
      _selectedLat = (location['location_lat'] as num?)?.toDouble();
      _selectedLng = (location['location_lng'] as num?)?.toDouble();
      _selectedBarrio = location['barrio'] as String?;
      _showAutocomplete = false;
      _saveNewAddress = false;
    });
  }

  void _useNewAddress() {
    setState(() {
      _selectedSavedLocationId = null;
      _selectedAddress = null;
      _selectedLat = null;
      _selectedLng = null;
      _selectedBarrio = null;
      _showAutocomplete = true;
      _saveNewAddress = false;
      _saveAddressLabelController.clear();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      locale: const Locale('es', 'ES'),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  Future<void> _submitJob() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedSkill == null) {
      setState(() {
        _errorMessage = 'Por favor selecciona una habilidad';
      });
      return;
    }

    if (_selectedLat == null || _selectedLng == null) {
      setState(() {
        _errorMessage = 'Por favor selecciona una direccion del listado';
      });
      return;
    }

    // Require either flexible hours or a specific date
    if (!_isFlexible && _selectedDate == null) {
      setState(() {
        _errorMessage = 'Por favor selecciona una fecha o marca "Horario flexible"';
      });
      return;
    }

    // Check if profile is complete
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('phone, phone_verified')
          .eq('id', user.id)
          .single();

      final phone = profile['phone'] as String?;
      final phoneVerified = profile['phone_verified'] as bool? ?? false;

      if (phone == null || phone.isEmpty) {
        _showProfileIncompleteDialog();
        return;
      }

      // Check if phone needs verification
      if (!phoneVerified) {
        if (!mounted) return;

        final verified = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => PhoneVerificationScreen(
              phoneNumber: phone,
              onVerified: () {},
            ),
          ),
        );

        if (verified == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Telefono verificado'),
              backgroundColor: AppColors.success,
            ),
          );
          await _postJob();
        }
        return;
      }

      await _postJob();
    } catch (e) {
      print('Error checking profile: $e');
      setState(() {
        _errorMessage = 'Error al verificar perfil: $e';
      });
    }
  }

  void _showProfileIncompleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Completa tu perfil'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Para publicar trabajos necesitas anadir tu numero de telefono.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text(
              'Esto permite que los manitas se pongan en contacto contigo cuando apliquen.',
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
              _showPhoneDialog();
            },
            child: const Text('Anadir telefono'),
          ),
        ],
      ),
    );
  }

  void _showPhoneDialog() {
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anadir telefono'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: phoneController,
            decoration: const InputDecoration(
              labelText: 'Telefono',
              hintText: '+34 600 000 000',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa tu telefono';
              }
              final phoneRegex = RegExp(r'^(\+34|0034)?[6-9]\d{8}$');
              final cleaned = value.replaceAll(RegExp(r'\s+'), '');
              if (!phoneRegex.hasMatch(cleaned)) {
                return 'Formato invalido (ej: +34 600 000 000)';
              }
              return null;
            },
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

                final phoneNumber = phoneController.text.trim();

                await supabase
                    .from('profiles')
                    .update({'phone': phoneNumber}).eq('id', user.id);

                if (context.mounted) {
                  Navigator.pop(context);

                  final verified = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PhoneVerificationScreen(
                        phoneNumber: phoneNumber,
                        onVerified: () {},
                      ),
                    ),
                  );

                  if (verified == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Telefono verificado'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    await _postJob();
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

  String? _formatTimeForDb(TimeOfDay? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  Future<void> _postJob() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      final jobData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'skill_id': _selectedSkill,
        'location_address': _selectedAddress,
        'location_lat': _selectedLat,
        'location_lng': _selectedLng,
        'barrio': _selectedBarrio,
        'price_type': _priceType,
        'price_amount': double.parse(_priceController.text),
        'is_flexible': _isFlexible,
        'scheduled_date':
            _isFlexible ? null : _selectedDate?.toIso8601String().split('T')[0],
        'scheduled_time': _isFlexible ? null : _formatTimeForDb(_selectedTime),
        'estimated_duration_minutes': _estimatedDuration,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (widget.isEditing) {
        // Update existing job
        print('DEBUG: Updating job ${widget.jobToEdit!['id']} with data: $jobData');
        await supabase.from('jobs').update(jobData).eq('id', widget.jobToEdit!['id']);
      } else {
        // Insert new job
        jobData['poster_id'] = user.id;
        jobData['status'] = 'open';
        print('DEBUG: Submitting new job with data: $jobData');
        await supabase.from('jobs').insert(jobData);
      }

      // Save new address if requested
      if (_saveNewAddress &&
          _selectedSavedLocationId == null &&
          _selectedAddress != null &&
          _selectedLat != null) {
        try {
          final isFirst = _savedLocations.isEmpty;
          await supabase.from('saved_locations').insert({
            'user_id': user.id,
            'label': _saveAddressLabelController.text.trim(),
            'address': _selectedAddress,
            'barrio': _selectedBarrio,
            'location_lat': _selectedLat,
            'location_lng': _selectedLng,
            'is_default': isFirst, // first saved address becomes default
          });
          print('DEBUG: Saved new address');
        } catch (e) {
          print('DEBUG: Error saving address (non-fatal): $e');
        }
      }

      print('DEBUG: Job inserted successfully');

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing ? 'Trabajo actualizado!' : 'Trabajo publicado con exito!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      print('DEBUG: Error submitting job: $error');
      setState(() {
        _errorMessage = 'Error al publicar el trabajo: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar trabajo' : 'Publicar trabajo'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '¿Qué necesitas?',
                    style: GoogleFonts.nunito(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Describe el trabajo que necesitas realizar',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.errorBorder),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),

                  // Title
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titulo del trabajo',
                      hintText: 'Ej: Pintar mi valla',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa un titulo';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion',
                      hintText: 'Describe el trabajo en detalle',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa una descripcion';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Skill selection
                  DropdownButtonFormField<String>(
                    value: _selectedSkill,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de trabajo',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Selecciona una habilidad'),
                    items: _skills.map((skill) {
                      return DropdownMenuItem<String>(
                        value: skill['id'].toString(),
                        child:
                            Text('${skill['icon'] ?? ''} ${skill['name_es']}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedSkill = value);
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Por favor selecciona un tipo de trabajo';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Location: saved address chips + autocomplete
                  if (_savedLocations.isNotEmpty) ...[
                    Text(
                      'Dirección',
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._savedLocations.map((loc) {
                          final isSelected =
                              _selectedSavedLocationId == loc['id'];
                          final isDefault = loc['is_default'] == true;
                          return ChoiceChip(
                            avatar: Icon(
                              isDefault
                                  ? Icons.star
                                  : Icons.location_on,
                              size: 18,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.navyDark,
                            ),
                            label: Text(loc['label'] as String),
                            selected: isSelected,
                            selectedColor: AppColors.navyDark,
                            labelStyle: TextStyle(
                              color:
                                  isSelected ? Colors.white : AppColors.textDark,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (_) => _selectSavedLocation(loc),
                          );
                        }),
                        ActionChip(
                          avatar: Icon(
                            Icons.add,
                            size: 18,
                            color: _showAutocomplete
                                ? Colors.white
                                : AppColors.navyDark,
                          ),
                          label: const Text('Nueva'),
                          backgroundColor: _showAutocomplete
                              ? AppColors.navyDark
                              : null,
                          labelStyle: TextStyle(
                            color: _showAutocomplete
                                ? Colors.white
                                : AppColors.textDark,
                            fontWeight: _showAutocomplete
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onPressed: _useNewAddress,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Show selected saved address summary
                    if (!_showAutocomplete && _selectedAddress != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.orangeLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: AppColors.orange, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedAddress!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],

                  // Autocomplete field (shown when no saved addresses or "Nueva" selected)
                  if (_showAutocomplete) ...[
                    PlacesAutocompleteField(
                      labelText:
                          _savedLocations.isEmpty ? 'Direccion' : 'Nueva direccion',
                      hintText: 'Calle, numero, ciudad...',
                      onPlaceSelected: (place) {
                        setState(() {
                          _selectedSavedLocationId = null;
                          _selectedAddress = place.address;
                          _selectedLat = place.lat;
                          _selectedLng = place.lng;
                          _selectedBarrio = place.barrio;
                        });
                      },
                      validator: (value) {
                        // Skip validation if a saved address is selected
                        if (!_showAutocomplete) return null;
                        if (value == null || value.trim().isEmpty) {
                          return 'Por favor ingresa una direccion';
                        }
                        if (_selectedLat == null) {
                          return 'Selecciona una direccion del listado';
                        }
                        return null;
                      },
                    ),
                    // Save new address checkbox
                    if (_selectedLat != null &&
                        _selectedSavedLocationId == null) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _saveNewAddress,
                        onChanged: (v) =>
                            setState(() => _saveNewAddress = v ?? false),
                        title: const Text(
                          'Guardar esta direccion',
                          style: TextStyle(fontSize: 14),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      if (_saveNewAddress)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: TextFormField(
                            controller: _saveAddressLabelController,
                            decoration: const InputDecoration(
                              hintText: 'Ej: Mi casa, Oficina...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (value) {
                              if (_saveNewAddress &&
                                  (value == null || value.trim().isEmpty)) {
                                return 'Pon un nombre a esta direccion';
                              }
                              return null;
                            },
                          ),
                        ),
                    ],
                  ],

                  // Validation message for address when using saved location
                  if (!_showAutocomplete && _selectedLat == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 12),
                      child: Text(
                        'Selecciona una direccion',
                        style: TextStyle(fontSize: 12, color: AppColors.error),
                      ),
                    ),

                  if (_selectedBarrio != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Zona: $_selectedBarrio',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Scheduling section
                  Text(
                    '¿Cuándo lo necesitas?',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Horario flexible'),
                    subtitle: const Text(
                        'Sin fecha ni hora fija, a convenir con el manitas'),
                    value: _isFlexible,
                    onChanged: (v) => setState(() => _isFlexible = v),
                    contentPadding: EdgeInsets.zero,
                  ),

                  if (!_isFlexible) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Date picker
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Fecha',
                                border: OutlineInputBorder(),
                                suffixIcon:
                                    Icon(Icons.calendar_today, size: 20),
                              ),
                              child: Text(
                                _selectedDate != null
                                    ? DateFormat('dd/MM/yyyy')
                                        .format(_selectedDate!)
                                    : 'Seleccionar',
                                style: TextStyle(
                                  color: _selectedDate != null
                                      ? AppColors.textDark
                                      : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Time picker
                        Expanded(
                          child: InkWell(
                            onTap: _pickTime,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Hora',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.access_time, size: 20),
                              ),
                              child: Text(
                                _selectedTime != null
                                    ? _selectedTime!.format(context)
                                    : 'Seleccionar',
                                style: TextStyle(
                                  color: _selectedTime != null
                                      ? AppColors.textDark
                                      : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Estimated duration
                  DropdownButtonFormField<int>(
                    value: _estimatedDuration,
                    decoration: const InputDecoration(
                      labelText: 'Duracion estimada (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Seleccionar'),
                    items: _durationOptions.map((opt) {
                      return DropdownMenuItem<int>(
                        value: opt['value'] as int,
                        child: Text(opt['label'] as String),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => _estimatedDuration = value),
                  ),
                  const SizedBox(height: 24),

                  // Price type
                  Text(
                    'Tipo de precio',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Precio fijo'),
                          value: 'fixed',
                          groupValue: _priceType,
                          onChanged: (value) =>
                              setState(() => _priceType = value!),
                          activeColor: AppColors.orange,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Por hora'),
                          value: 'hourly',
                          groupValue: _priceType,
                          onChanged: (value) =>
                              setState(() => _priceType = value!),
                          activeColor: AppColors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Price amount
                  TextFormField(
                    controller: _priceController,
                    decoration: InputDecoration(
                      labelText: _priceType == 'fixed'
                          ? 'Precio (EUR)'
                          : 'Precio por hora (EUR)',
                      border: const OutlineInputBorder(),
                      prefixText: 'EUR ',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa un precio';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Por favor ingresa un numero valido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Submit button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submitJob,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            widget.jobToEdit != null ? 'Guardar cambios' : 'Publicar trabajo',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
