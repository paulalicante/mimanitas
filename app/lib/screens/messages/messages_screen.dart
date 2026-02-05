import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app_theme.dart';
import '../../main.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  RealtimeChannel? _messagesChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadConversations(showLoading: true);
    _subscribeToMessages();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  // Polling fallback - refresh every 5 seconds
  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadConversations();
    });
  }

  void _subscribeToMessages() {
    _messagesChannel = supabase
        .channel('messages_screen_updates_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // Reload conversations when new message arrives
            _loadConversations();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // Reload when messages are marked as read
            _loadConversations();
          },
        )
        .subscribe();
  }

  Future<void> _loadConversations({bool showLoading = false}) async {
    if (showLoading || _conversations.isEmpty) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Load conversations where user is either seeker or helper
      final conversations = await supabase
          .from('conversations')
          .select('''
            *,
            job:jobs(id, title, status),
            seeker:profiles!conversations_seeker_id_fkey(id, name),
            helper:profiles!conversations_helper_id_fkey(id, name),
            last_message:messages(content, created_at, sender_id)
          ''')
          .or('seeker_id.eq.${user.id},helper_id.eq.${user.id}')
          .order('last_message_at', ascending: false);

      // Get last message for each conversation
      final conversationsWithMessages = await Future.wait(
        conversations.map((conv) async {
          final messages = await supabase
              .from('messages')
              .select('content, created_at, sender_id')
              .eq('conversation_id', conv['id'])
              .order('created_at', ascending: false)
              .limit(1);

          // Count unread messages
          final unreadMessages = await supabase
              .from('messages')
              .select('id')
              .eq('conversation_id', conv['id'])
              .neq('sender_id', user.id)
              .isFilter('read_at', null);

          return {
            ...conv,
            'last_message': messages.isNotEmpty ? messages[0] : null,
            'unread_count': unreadMessages.length,
          };
        }).toList(),
      );

      setState(() {
        _conversations = conversationsWithMessages;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading conversations: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensajes'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '💬',
                        style: TextStyle(fontSize: 64),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No tienes mensajes todavía',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.orange,
                  onRefresh: _loadConversations,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _conversations[index];
                      final job = conversation['job'] as Map<String, dynamic>?;
                      final isSeeker = conversation['seeker_id'] == user?.id;
                      final otherUser = isSeeker
                          ? conversation['helper'] as Map<String, dynamic>?
                          : conversation['seeker'] as Map<String, dynamic>?;
                      final otherUserName = otherUser?['name'] ?? 'Usuario';

                      final lastMessage = conversation['last_message'] as Map<String, dynamic>?;
                      final lastMessageText = lastMessage?['content'] as String? ?? '';
                      final lastMessageTime = lastMessage?['created_at'] != null
                          ? DateTime.parse(lastMessage!['created_at'] as String)
                          : null;
                      final isOwnMessage = lastMessage?['sender_id'] == user?.id;

                      final unreadCount = conversation['unread_count'] as int? ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.navyDark,
                            child: Text(
                              otherUserName.isNotEmpty
                                  ? otherUserName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  otherUserName,
                                  style: TextStyle(
                                    fontWeight: unreadCount > 0
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (lastMessageTime != null)
                                Text(
                                  DateFormat('HH:mm').format(lastMessageTime),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (job != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  job['title'] ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (lastMessageText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (isOwnMessage)
                                      Text(
                                        'Tú: ',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.textMuted,
                                          fontWeight: unreadCount > 0
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        lastMessageText,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.textMuted,
                                          fontWeight: unreadCount > 0
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: unreadCount > 0
                              ? Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: AppColors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  conversationId: conversation['id'],
                                  otherUserName: otherUserName,
                                  jobTitle: job?['title'],
                                ),
                              ),
                            );
                            // Reload conversations after returning from chat
                            _loadConversations();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
