import 'package:flutter/material.dart';
import '../../main.dart';
import '../../app_theme.dart';

const _dayNames = [
  'Lunes',
  'Martes',
  'Miercoles',
  'Jueves',
  'Viernes',
  'Sabado',
  'Domingo',
];

// Map display index (0=Mon) to DB day_of_week (0=Sun, 1=Mon, ..., 6=Sat)
int _displayToDow(int displayIndex) {
  return (displayIndex + 1) % 7; // Mon=1, Tue=2, ..., Sun=0
}

int _dowToDisplay(int dow) {
  return (dow + 6) % 7; // Sun(0)->6, Mon(1)->0, Tue(2)->1, ...
}

class _TimeSlot {
  final String? id; // null for new slots
  final TimeOfDay start;
  final TimeOfDay end;
  final bool isRecurring;

  _TimeSlot({
    this.id,
    required this.start,
    required this.end,
    this.isRecurring = true,
  });
}

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Slots by display day index (0=Mon, 6=Sun)
  final Map<int, List<_TimeSlot>> _slotsByDay = {};

  // IDs to delete on save
  final Set<String> _deletedIds = {};

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await supabase
          .from('availability')
          .select()
          .eq('user_id', userId)
          .eq('is_recurring', true)
          .order('start_time');

      for (int i = 0; i < 7; i++) {
        _slotsByDay[i] = [];
      }

      for (final row in data) {
        final dow = row['day_of_week'] as int;
        final displayIdx = _dowToDisplay(dow);
        final startParts = (row['start_time'] as String).split(':');
        final endParts = (row['end_time'] as String).split(':');

        _slotsByDay[displayIdx]!.add(_TimeSlot(
          id: row['id'] as String,
          start: TimeOfDay(
              hour: int.parse(startParts[0]),
              minute: int.parse(startParts[1])),
          end: TimeOfDay(
              hour: int.parse(endParts[0]),
              minute: int.parse(endParts[1])),
        ));
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading availability: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addSlot(int displayDay) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Hora de inicio',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              const ColorScheme.light(primary: AppColors.navyDark),
        ),
        child: child!,
      ),
    );
    if (start == null || !mounted) return;

    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start.hour + 4, minute: 0),
      helpText: 'Hora de fin',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              const ColorScheme.light(primary: AppColors.navyDark),
        ),
        child: child!,
      ),
    );
    if (end == null || !mounted) return;

    setState(() {
      _slotsByDay[displayDay] ??= [];
      _slotsByDay[displayDay]!.add(_TimeSlot(start: start, end: end));
    });
  }

  void _removeSlot(int displayDay, int slotIndex) {
    final slot = _slotsByDay[displayDay]![slotIndex];
    if (slot.id != null) {
      _deletedIds.add(slot.id!);
    }
    setState(() {
      _slotsByDay[displayDay]!.removeAt(slotIndex);
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Delete removed slots
      for (final id in _deletedIds) {
        await supabase.from('availability').delete().eq('id', id);
      }

      // Upsert all current slots
      for (int displayDay = 0; displayDay < 7; displayDay++) {
        final slots = _slotsByDay[displayDay] ?? [];
        for (final slot in slots) {
          final row = {
            'user_id': userId,
            'day_of_week': _displayToDow(displayDay),
            'start_time':
                '${slot.start.hour.toString().padLeft(2, '0')}:${slot.start.minute.toString().padLeft(2, '0')}:00',
            'end_time':
                '${slot.end.hour.toString().padLeft(2, '0')}:${slot.end.minute.toString().padLeft(2, '0')}:00',
            'is_recurring': true,
          };

          if (slot.id != null) {
            await supabase
                .from('availability')
                .update(row)
                .eq('id', slot.id!);
          } else {
            await supabase.from('availability').insert(row);
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disponibilidad guardada'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error saving availability: $e');
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

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mi disponibilidad',
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
              child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configura tu horario semanal',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Solo te notificaremos de trabajos que coincidan con tu disponibilidad.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(7, (displayDay) {
                    final slots = _slotsByDay[displayDay] ?? [];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.navyShadow,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Day name
                            SizedBox(
                              width: 90,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _dayNames[displayDay],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            // Slots
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (slots.isEmpty)
                                    const Padding(
                                      padding:
                                          EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Sin horario',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ...slots.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final slot = entry.value;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 4),
                                      child: Chip(
                                        label: Text(
                                          '${_formatTime(slot.start)} - ${_formatTime(slot.end)}',
                                          style: const TextStyle(
                                              fontSize: 13),
                                        ),
                                        deleteIcon: const Icon(
                                            Icons.close,
                                            size: 16),
                                        onDeleted: () =>
                                            _removeSlot(displayDay, idx),
                                        backgroundColor:
                                            AppColors.navyVeryLight,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            // Add button
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  color: AppColors.navyDark),
                              onPressed: () => _addSlot(displayDay),
                              tooltip: 'Anadir horario',
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
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
                              'Guardar disponibilidad',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
