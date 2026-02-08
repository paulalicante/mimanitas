import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app_theme.dart';
import '../../main.dart';
import '../../services/message_notification_service.dart';
import '../../utils/schedule_conflict.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? jobTitle;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.jobTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  RealtimeChannel? _messagesChannel;
  Timer? _pollingTimer;
  String? _jobId;
  String? _helperId;
  int _jobDuration = 60;
  bool _isFlexibleJob = false;

  @override
  void initState() {
    super.initState();
    // Tell notification service we're viewing this conversation
    messageNotificationService.setCurrentConversation(widget.conversationId);
    _loadConversationDetails();
    _loadMessages(showLoading: true);
    _markMessagesAsRead();
    _subscribeToMessages();
    _startPolling();
  }

  @override
  void dispose() {
    // Clear current conversation when leaving
    messageNotificationService.setCurrentConversation(null);
    _pollingTimer?.cancel();
    _messagesChannel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversationDetails() async {
    try {
      final conversation = await supabase
          .from('conversations')
          .select('job_id, helper_id, jobs(is_flexible, scheduled_date, status, estimated_duration_minutes)')
          .eq('id', widget.conversationId)
          .single();

      setState(() {
        _jobId = conversation['job_id'] as String?;
        _helperId = conversation['helper_id'] as String?;
        final job = conversation['jobs'] as Map<String, dynamic>?;
        _isFlexibleJob = job?['is_flexible'] == true && job?['scheduled_date'] == null;
        _jobDuration = (job?['estimated_duration_minutes'] as int?) ?? 60;
      });
    } catch (e) {
      print('Error loading conversation details: $e');
    }
  }

  // Polling fallback - refresh every 3 seconds for reliable real-time
  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadMessages();
      _markMessagesAsRead();
    });
  }

  void _subscribeToMessages() {
    _messagesChannel = supabase
        .channel('chat_${widget.conversationId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            print('New message in chat: ${payload.newRecord}');
            // Reload messages and mark as read
            _loadMessages();
            _markMessagesAsRead();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            // Reload on update (for proposal status changes)
            _loadMessages();
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages({bool showLoading = false}) async {
    if (showLoading || _messages.isEmpty) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final messages = await supabase
          .from('messages')
          .select('''
            *,
            sender:profiles!messages_sender_id_fkey(id, name)
          ''')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(messages);
        _isLoading = false;
      });

      // Scroll to bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase
          .from('messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('conversation_id', widget.conversationId)
          .neq('sender_id', user.id)
          .isFilter('read_at', null);
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final messageText = _messageController.text.trim();
      _messageController.clear();

      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'content': messageText,
        'message_type': 'text',
      });

      // Reload messages
      await _loadMessages();
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar mensaje: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _showScheduleProposalDialog() async {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              'Proponer fecha',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700,
                color: AppColors.navyDark,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Selecciona cuándo te gustaría hacer este trabajo:',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                // Date picker button
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                      locale: const Locale('es', 'ES'),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    selectedDate != null
                        ? _formatDateForDisplay(selectedDate!)
                        : 'Seleccionar fecha',
                    style: GoogleFonts.inter(),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    side: BorderSide(
                      color: selectedDate != null ? AppColors.orange : AppColors.border,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Time picker button
                OutlinedButton.icon(
                  onPressed: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 10, minute: 0),
                    );
                    if (time != null) {
                      setDialogState(() => selectedTime = time);
                    }
                  },
                  icon: const Icon(Icons.access_time),
                  label: Text(
                    selectedTime != null
                        ? selectedTime!.format(context)
                        : 'Seleccionar hora',
                    style: GoogleFonts.inter(),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    side: BorderSide(
                      color: selectedTime != null ? AppColors.orange : AppColors.border,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancelar',
                  style: GoogleFonts.inter(color: AppColors.textMuted),
                ),
              ),
              ElevatedButton(
                onPressed: selectedDate != null && selectedTime != null
                    ? () => Navigator.pop(context, {
                          'date': selectedDate,
                          'time': selectedTime,
                        })
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                ),
                child: Text(
                  'Proponer',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      await _sendScheduleProposal(
        result['date'] as DateTime,
        result['time'] as TimeOfDay,
      );
    }
  }

  String _formatDateForDisplay(DateTime date) {
    const dayNames = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${dayNames[date.weekday % 7]}, ${date.day} ${months[date.month - 1]}';
  }

  Future<void> _sendScheduleProposal(DateTime date, TimeOfDay time) async {
    setState(() {
      _isSending = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

      // Check for scheduling conflict for the helper
      if (_helperId != null) {
        final conflictResult = await ScheduleConflict.checkConflict(
          helperId: _helperId!,
          proposedDate: dateStr,
          proposedTime: timeStr,
          durationMinutes: _jobDuration,
          excludeJobId: _jobId,
        );

        if (conflictResult.hasConflict) {
          setState(() => _isSending = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(conflictResult.message ?? 'El helper ya tiene otro trabajo a esa hora'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'content': 'Propuesta de fecha: ${_formatDateForDisplay(date)} a las ${time.format(context)}',
        'message_type': 'schedule_proposal',
        'metadata': {
          'proposed_date': dateStr,
          'proposed_time': timeStr,
          'status': 'pending',
        },
      });

      await _loadMessages();
    } catch (e) {
      print('Error sending schedule proposal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar propuesta: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _respondToProposal(String messageId, Map<String, dynamic> metadata, bool accept) async {
    try {
      final proposedDate = metadata['proposed_date'] as String;
      final proposedTime = metadata['proposed_time'] as String?;

      // Check for scheduling conflict before accepting
      if (accept && _helperId != null) {
        final conflictResult = await ScheduleConflict.checkConflict(
          helperId: _helperId!,
          proposedDate: proposedDate,
          proposedTime: proposedTime,
          durationMinutes: _jobDuration,
          excludeJobId: _jobId,
        );

        if (conflictResult.hasConflict) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(conflictResult.message ?? 'El helper ya tiene otro trabajo a esa hora'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Update the message status
      await supabase
          .from('messages')
          .update({
            'metadata': {
              ...metadata,
              'status': accept ? 'accepted' : 'declined',
              'responded_at': DateTime.now().toIso8601String(),
            },
          })
          .eq('id', messageId);

      if (accept && _jobId != null) {
        // Update the job with the agreed date
        await supabase
            .from('jobs')
            .update({
              'scheduled_date': proposedDate,
              'scheduled_time': proposedTime,
              'is_flexible': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _jobId!);

        // Send a confirmation message
        final user = supabase.auth.currentUser;
        if (user != null) {
          await supabase.from('messages').insert({
            'conversation_id': widget.conversationId,
            'sender_id': user.id,
            'content': '✅ ¡Fecha confirmada! El trabajo queda programado para el $proposedDate${proposedTime != null ? ' a las $proposedTime' : ''}.',
            'message_type': 'text',
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Fecha acordada! El trabajo ha sido actualizado.'),
              backgroundColor: AppColors.success,
            ),
          );
        }

        // Refresh to update _isFlexibleJob
        await _loadConversationDetails();
      }

      await _loadMessages();
    } catch (e) {
      print('Error responding to proposal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildScheduleProposalMessage(Map<String, dynamic> message, bool isOwnMessage) {
    final metadata = message['metadata'] as Map<String, dynamic>? ?? {};
    final status = metadata['status'] as String? ?? 'pending';
    final proposedDate = metadata['proposed_date'] as String?;
    final proposedTime = metadata['proposed_time'] as String?;
    final createdAt = DateTime.parse(message['created_at'] as String);
    final timeString = DateFormat('HH:mm').format(createdAt);
    final canRespond = !isOwnMessage && status == 'pending';

    // Format the date nicely
    String dateDisplay = '';
    if (proposedDate != null) {
      try {
        final date = DateTime.parse(proposedDate);
        dateDisplay = _formatDateForDisplay(date);
        if (proposedTime != null) {
          dateDisplay += ' a las $proposedTime';
        }
      } catch (_) {
        dateDisplay = proposedDate;
      }
    }

    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case 'accepted':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusText = 'Aceptada';
        break;
      case 'declined':
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        statusText = 'Rechazada';
        break;
      default:
        statusColor = AppColors.warning;
        statusIcon = Icons.schedule;
        statusText = 'Pendiente';
    }

    return Align(
      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.3), width: 2),
          boxShadow: const [
            BoxShadow(
              color: AppColors.navyShadow,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: AppColors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Propuesta de fecha',
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navyDark,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Date/Time
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateDisplay,
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOwnMessage ? 'Tu propuesta' : 'Propuesta de ${widget.otherUserName}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Action buttons (only for pending proposals the user didn't send)
            if (canRespond) ...[
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _respondToProposal(message['id'], metadata, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: Text('Proponer otra', style: GoogleFonts.inter(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _respondToProposal(message['id'], metadata, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                        child: Text(
                          'Aceptar',
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Timestamp
            Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 8),
              child: Text(
                timeString,
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.jobTitle != null)
              Text(
                widget.jobTitle!,
                style: const TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Hint banner for flexible jobs without agreed date
          if (_isFlexibleJob)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.orange.withValues(alpha: 0.15),
                    AppColors.gold.withValues(alpha: 0.1),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: AppColors.orange.withValues(alpha: 0.3)),
                ),
              ),
              child: InkWell(
                onTap: _showScheduleProposalDialog,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_month, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¿Cuándo hacemos el trabajo?',
                            style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.navyDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Toca para proponer una fecha y hora',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.orange),
                  ],
                ),
              ),
            ),

          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _messages.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: AppColors.border,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No hay mensajes todavía',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Envía un mensaje para empezar',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isOwnMessage = message['sender_id'] == user?.id;
                          final messageType = message['message_type'] as String? ?? 'text';

                          // Handle schedule proposal messages
                          if (messageType == 'schedule_proposal') {
                            return _buildScheduleProposalMessage(message, isOwnMessage);
                          }

                          // Regular text message
                          final content = message['content'] as String;
                          final createdAt = DateTime.parse(message['created_at'] as String);
                          final timeString = DateFormat('HH:mm').format(createdAt);

                          return Align(
                            alignment: isOwnMessage
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isOwnMessage
                                    ? AppColors.navyDark
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.navyShadow,
                                    blurRadius: 5,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    content,
                                    style: TextStyle(
                                      color: isOwnMessage
                                          ? AppColors.darkTextPrimary
                                          : AppColors.textDark,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    timeString,
                                    style: TextStyle(
                                      color: isOwnMessage
                                          ? AppColors.darkTextSecondary
                                          : AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Message input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: AppColors.navyShadow,
                  blurRadius: 5,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Schedule button (only show for flexible jobs without agreed date)
                  if (_isFlexibleJob)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.calendar_month, color: AppColors.orange),
                        onPressed: _showScheduleProposalDialog,
                        tooltip: 'Proponer fecha',
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppColors.orange),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
