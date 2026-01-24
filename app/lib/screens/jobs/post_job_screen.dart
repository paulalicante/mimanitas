import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../auth/phone_verification_screen.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _priceController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String _priceType = 'fixed';
  String? _selectedSkill;
  List<Map<String, dynamic>> _skills = [];

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _priceController.dispose();
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

    // Check if profile is complete
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('phone')
          .eq('id', user.id)
          .single();

      final phone = profile['phone'] as String?;

      if (phone == null || phone.isEmpty) {
        _showProfileIncompleteDialog();
        return;
      }

      // Profile is complete, proceed with job posting
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
              'Para publicar trabajos necesitas añadir tu número de teléfono.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text(
              'Esto permite que los manitas se pongan en contacto contigo cuando apliquen.',
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
              _showPhoneDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE86A33),
              foregroundColor: Colors.white,
            ),
            child: const Text('Añadir teléfono'),
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
        title: const Text('Añadir teléfono'),
        content: Form(
          key: formKey,
          child: TextFormField(
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
                    .update({'phone': phoneNumber})
                    .eq('id', user.id);

                if (context.mounted) {
                  Navigator.pop(context);

                  // Navigate to phone verification screen
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
                        content: Text('Teléfono verificado'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    // Now post the job
                    await _postJob();
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

      print('DEBUG: Submitting job with data:');
      print('  poster_id: ${user.id}');
      print('  title: ${_titleController.text.trim()}');
      print('  skill_id: $_selectedSkill');
      print('  location: ${_locationController.text.trim()}');
      print('  price_type: $_priceType');
      print('  price_amount: ${_priceController.text}');

      await supabase.from('jobs').insert({
        'poster_id': user.id,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'skill_id': _selectedSkill,
        'location_address': _locationController.text.trim(),
        'price_type': _priceType,
        'price_amount': double.parse(_priceController.text),
        'status': 'open',
      });

      print('DEBUG: Job inserted successfully');

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Trabajo publicado con éxito!'),
            backgroundColor: Colors.green,
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
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Publicar trabajo',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Describe el trabajo que necesitas realizar',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 32),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),

                  // Title
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Título del trabajo',
                      hintText: 'Ej: Pintar mi valla',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa un título';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      hintText: 'Describe el trabajo en detalle',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa una descripción';
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
                        child: Text('${skill['icon'] ?? ''} ${skill['name_es']}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedSkill = value;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Por favor selecciona un tipo de trabajo';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Location
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Ubicación',
                      hintText: 'Ej: Alicante Centro',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa una ubicación';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Price type
                  Text(
                    'Tipo de precio',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Precio fijo'),
                          value: 'fixed',
                          groupValue: _priceType,
                          onChanged: (value) {
                            setState(() {
                              _priceType = value!;
                            });
                          },
                          activeColor: const Color(0xFFE86A33),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Por hora'),
                          value: 'hourly',
                          groupValue: _priceType,
                          onChanged: (value) {
                            setState(() {
                              _priceType = value!;
                            });
                          },
                          activeColor: const Color(0xFFE86A33),
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
                          ? 'Precio (€)'
                          : 'Precio por hora (€)',
                      border: const OutlineInputBorder(),
                      prefixText: '€ ',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa un precio';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Por favor ingresa un número válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Submit button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submitJob,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE86A33),
                      foregroundColor: Colors.white,
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
                        : const Text(
                            'Publicar trabajo',
                            style: TextStyle(
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
