import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../../app_theme.dart';

/// Screen for helpers to edit their skills and category-specific attributes
class EditSkillsScreen extends StatefulWidget {
  const EditSkillsScreen({super.key});

  @override
  State<EditSkillsScreen> createState() => _EditSkillsScreenState();
}

class _EditSkillsScreenState extends State<EditSkillsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _allSkills = [];
  Map<String, Map<String, dynamic>> _userSkills = {}; // skill_id -> user_skill data

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Load all skills and user's skills in parallel
      final results = await Future.wait([
        supabase.from('skills').select().order('name_es'),
        supabase.from('user_skills').select().eq('user_id', user.id),
      ]);

      final skills = results[0] as List<dynamic>;
      final userSkills = results[1] as List<dynamic>;

      // Convert user skills to a map for easy lookup
      final userSkillsMap = <String, Map<String, dynamic>>{};
      for (final us in userSkills) {
        userSkillsMap[us['skill_id'] as String] = Map<String, dynamic>.from(us);
      }

      setState(() {
        _allSkills = List<Map<String, dynamic>>.from(skills);
        _userSkills = userSkillsMap;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading skills: $e');
      setState(() => _isLoading = false);
    }
  }

  bool _hasSkill(String skillId) {
    return _userSkills.containsKey(skillId);
  }

  Map<String, dynamic> _getSkillAttributes(String skillId) {
    final userSkill = _userSkills[skillId];
    if (userSkill == null) return {};
    final attrs = userSkill['skill_attributes'];
    if (attrs == null) return {};
    return Map<String, dynamic>.from(attrs);
  }

  double? _getHourlyRate(String skillId) {
    final userSkill = _userSkills[skillId];
    if (userSkill == null) return null;
    final rate = userSkill['rate_per_hour'];
    if (rate == null) return null;
    return double.tryParse(rate.toString());
  }

  Future<void> _toggleSkill(String skillId, bool enabled) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      if (enabled) {
        // Add skill
        final result = await supabase.from('user_skills').insert({
          'user_id': user.id,
          'skill_id': skillId,
          'skill_attributes': {},
        }).select().single();

        setState(() {
          _userSkills[skillId] = Map<String, dynamic>.from(result);
        });
      } else {
        // Remove skill
        await supabase
            .from('user_skills')
            .delete()
            .eq('user_id', user.id)
            .eq('skill_id', skillId);

        setState(() {
          _userSkills.remove(skillId);
        });
      }
    } catch (e) {
      print('Error toggling skill: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _updateSkillAttribute(
    String skillId,
    String attributeKey,
    dynamic value,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final currentAttrs = _getSkillAttributes(skillId);
    currentAttrs[attributeKey] = value;

    try {
      await supabase
          .from('user_skills')
          .update({'skill_attributes': currentAttrs})
          .eq('user_id', user.id)
          .eq('skill_id', skillId);

      setState(() {
        _userSkills[skillId]!['skill_attributes'] = currentAttrs;
      });
    } catch (e) {
      print('Error updating skill attribute: $e');
    }
  }

  Future<void> _updateHourlyRate(String skillId, double? rate) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('user_skills')
          .update({'rate_per_hour': rate})
          .eq('user_id', user.id)
          .eq('skill_id', skillId);

      setState(() {
        _userSkills[skillId]!['rate_per_hour'] = rate;
      });
    } catch (e) {
      print('Error updating hourly rate: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mis habilidades',
          style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _buildSkillsList(),
    );
  }

  Widget _buildSkillsList() {
    // Group skills by category
    final Map<String, List<Map<String, dynamic>>> skillsByCategory = {};
    for (final skill in _allSkills) {
      final category = skill['category'] as String? ?? 'otros';
      skillsByCategory.putIfAbsent(category, () => []);
      skillsByCategory[category]!.add(skill);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Selecciona las habilidades que ofreces y configura los detalles de cada una.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        ...skillsByCategory.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _categoryLabel(entry.key),
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
              ),
              ...entry.value.map((skill) => _buildSkillCard(skill)),
              const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }

  String _categoryLabel(String category) {
    const labels = {
      'mantenimiento': 'Mantenimiento',
      'jardineria': 'Jardineria',
      'limpieza': 'Limpieza',
      'mudanza': 'Mudanza',
      'profesional': 'Servicios profesionales',
      'cuidados': 'Cuidados',
      'hogar': 'Hogar',
      'tecnologia': 'Tecnologia',
      'educacion': 'Educacion',
      'servicios': 'Servicios',
      'general': 'General',
    };
    return labels[category] ?? category;
  }

  Widget _buildSkillCard(Map<String, dynamic> skill) {
    final skillId = skill['id'] as String;
    final nameEs = skill['name_es'] as String? ?? skill['name'] as String;
    final icon = skill['icon'] as String? ?? '🔧';
    final isEnabled = _hasSkill(skillId);
    final modelType = skill['model_type'] as String? ?? 'bulletin';
    final attributesSchema = skill['attributes_schema'] as Map<String, dynamic>? ?? {};

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isEnabled
            ? const BorderSide(color: AppColors.orange, width: 2)
            : BorderSide.none,
      ),
      child: Column(
        children: [
          // Header with toggle
          ListTile(
            leading: Text(icon, style: const TextStyle(fontSize: 28)),
            title: Text(
              nameEs,
              style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
            ),
            subtitle: modelType == 'service_menu'
                ? Text(
                    'Tarifa por hora',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.orange,
                    ),
                  )
                : null,
            trailing: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: isEnabled,
                    activeColor: AppColors.orange,
                    onChanged: (value) => _toggleSkill(skillId, value),
                  ),
          ),
          // Attributes section (only if enabled)
          if (isEnabled && attributesSchema.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hourly rate for service_menu skills
                  if (modelType == 'service_menu') ...[
                    _buildHourlyRateField(skillId),
                    const SizedBox(height: 16),
                  ],
                  // Dynamic attributes
                  ...attributesSchema.entries.map((attr) {
                    return _buildAttributeField(skillId, attr.key, attr.value);
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHourlyRateField(String skillId) {
    final rate = _getHourlyRate(skillId);
    final controller = TextEditingController(
      text: rate != null ? rate.toStringAsFixed(0) : '',
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            'Tarifa por hora',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(
          width: 100,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              suffixText: '€/h',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            onChanged: (value) {
              final rate = double.tryParse(value);
              _updateHourlyRate(skillId, rate);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAttributeField(
    String skillId,
    String attrKey,
    Map<String, dynamic> attrSchema,
  ) {
    final type = attrSchema['type'] as String? ?? 'text';
    final label = attrSchema['label'] as String? ?? attrKey;
    final options = attrSchema['options'] as List<dynamic>? ?? [];
    final placeholder = attrSchema['placeholder'] as String? ?? '';

    final currentAttrs = _getSkillAttributes(skillId);
    final currentValue = currentAttrs[attrKey];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (type == 'multi')
            _buildMultiSelect(skillId, attrKey, options, currentValue)
          else if (type == 'single')
            _buildSingleSelect(skillId, attrKey, options, currentValue)
          else if (type == 'text')
            _buildTextField(skillId, attrKey, placeholder, currentValue),
        ],
      ),
    );
  }

  Widget _buildMultiSelect(
    String skillId,
    String attrKey,
    List<dynamic> options,
    dynamic currentValue,
  ) {
    final selectedValues = currentValue is List
        ? List<String>.from(currentValue)
        : <String>[];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final value = opt['value'] as String;
        final label = opt['label'] as String;
        final isSelected = selectedValues.contains(value);

        return FilterChip(
          label: Text(label),
          selected: isSelected,
          selectedColor: AppColors.orange.withOpacity(0.2),
          checkmarkColor: AppColors.orange,
          onSelected: (selected) {
            final newValues = List<String>.from(selectedValues);
            if (selected) {
              newValues.add(value);
            } else {
              newValues.remove(value);
            }
            _updateSkillAttribute(skillId, attrKey, newValues);
          },
        );
      }).toList(),
    );
  }

  Widget _buildSingleSelect(
    String skillId,
    String attrKey,
    List<dynamic> options,
    dynamic currentValue,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final value = opt['value'] as String;
        final label = opt['label'] as String;
        final isSelected = currentValue == value;

        return ChoiceChip(
          label: Text(label),
          selected: isSelected,
          selectedColor: AppColors.orange.withOpacity(0.2),
          onSelected: (selected) {
            _updateSkillAttribute(skillId, attrKey, selected ? value : null);
          },
        );
      }).toList(),
    );
  }

  Widget _buildTextField(
    String skillId,
    String attrKey,
    String placeholder,
    dynamic currentValue,
  ) {
    final controller = TextEditingController(
      text: currentValue as String? ?? '',
    );

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: placeholder,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      maxLines: 3,
      onChanged: (value) {
        _updateSkillAttribute(skillId, attrKey, value.isNotEmpty ? value : null);
      },
    );
  }
}
