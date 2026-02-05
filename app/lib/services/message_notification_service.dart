import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import '../main.dart';
import '../screens/messages/chat_screen.dart';

class _PendingNotification {
  final String senderName;
  final String message;
  final String? jobTitle;
  final String conversationId;

  _PendingNotification({
    required this.senderName,
    required this.message,
    this.jobTitle,
    required this.conversationId,
  });
}

class MessageNotificationService {
  static final MessageNotificationService _instance = MessageNotificationService._internal();
  factory MessageNotificationService() => _instance;
  MessageNotificationService._internal();

  RealtimeChannel? _channel;
  String? _currentConversationId; // Track which conversation user is viewing
  GlobalKey<NavigatorState>? _navigatorKey;
  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  // Debug log tracking
  List<String> debugLogs = [];

  // Notification queue
  final List<_PendingNotification> _notificationQueue = [];
  bool _isShowingNotification = false;
  _PendingNotification? _currentNotification;

  // Unread message tracking
  final Map<String, int> _unreadByConversation = {};

  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    debugLogs.add(logMessage);
    if (debugLogs.length > 20) {
      debugLogs.removeAt(0);
    }
    print(logMessage);
  }

  void initialize({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
  }) {
    _navigatorKey = navigatorKey;
    _scaffoldMessengerKey = scaffoldMessengerKey;
    // Unsubscribe from any existing channel first (important for hot restart)
    _channel?.unsubscribe();
    _channel = null;
    _subscribeToMessages();
  }

  void dispose() {
    _channel?.unsubscribe();
  }

  // Call this when entering a chat screen
  void setCurrentConversation(String? conversationId) {
    _currentConversationId = conversationId;
    // Clear unread count for this conversation when user opens it
    if (conversationId != null) {
      _unreadByConversation[conversationId] = 0;
    }
  }

  // Get total unread message count
  int getTotalUnreadCount() {
    return _unreadByConversation.values.fold(0, (sum, count) => sum + count);
  }

  // Get unread count for specific conversation
  int getUnreadCountForConversation(String conversationId) {
    return _unreadByConversation[conversationId] ?? 0;
  }

  void _subscribeToMessages() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _addDebugLog('No user, skipping subscription');
      return;
    }

    _addDebugLog('Subscribing to messages for user ${user.id}');

    try {
      _channel = supabase
          .channel('global_message_notifications_${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (payload) async {
              _addDebugLog('*** RECEIVED NEW MESSAGE ***');
              _addDebugLog('Payload: ${payload.newRecord}');

              // Always get current user inside callback (don't use stale closure)
              final currentUser = supabase.auth.currentUser;
              if (currentUser == null) {
                _addDebugLog('Skipping: no current user');
                return;
              }

              final newMessage = payload.newRecord;
              final senderId = newMessage['sender_id'] as String?;
              final conversationId = newMessage['conversation_id'] as String?;

              _addDebugLog('Sender ID: $senderId, Current user: ${currentUser.id}');
              _addDebugLog('Conversation ID: $conversationId, Current: $_currentConversationId');

              // Don't notify for own messages
              if (senderId == currentUser.id) {
                _addDebugLog('Skipping: own message');
                return;
              }

              // Don't notify if user is currently viewing this conversation
              if (conversationId == _currentConversationId) {
                _addDebugLog('Skipping: user is viewing this conversation');
                return;
              }

              // Check if this conversation belongs to the user
              try {
                _addDebugLog('Checking conversation ownership...');
                final conversation = await supabase
                    .from('conversations')
                    .select('id, seeker_id, helper_id, job:jobs(title)')
                    .eq('id', conversationId!)
                    .maybeSingle();

                _addDebugLog('Conv data: $conversation');

                if (conversation == null) {
                  _addDebugLog('Skipping: conversation not found');
                  return;
                }

                final isSeeker = conversation['seeker_id'] == currentUser.id;
                final isHelper = conversation['helper_id'] == currentUser.id;

                _addDebugLog('Seeker: $isSeeker, Helper: $isHelper');

                if (!isSeeker && !isHelper) {
                  _addDebugLog('Skipping: user not in conversation');
                  return;
                }

                // Get sender name
                final senderProfile = await supabase
                    .from('profiles')
                    .select('name')
                    .eq('id', senderId!)
                    .maybeSingle();

                final senderName = senderProfile?['name'] ?? 'Alguien';
                final messageContent = newMessage['content'] as String? ?? '';
                final jobTitle = conversation['job']?['title'] as String?;

                _addDebugLog('SHOWING NOTIFICATION: $senderName - $messageContent');

                // Queue notification and increment unread count
                _queueNotification(
                  senderName: senderName,
                  message: messageContent,
                  jobTitle: jobTitle,
                  conversationId: conversationId,
                );

                // Increment unread count for this conversation
                _unreadByConversation[conversationId] = (_unreadByConversation[conversationId] ?? 0) + 1;
                _addDebugLog('Unread count for conversation: ${_unreadByConversation[conversationId]}');
              } catch (e) {
                _addDebugLog('Error checking conv: $e');
              }
            },
          )
          .subscribe((status, [error]) {
        _addDebugLog('Channel status: $status');
        if (error != null) {
          _addDebugLog('Channel error: $error');
        }
      });
      _addDebugLog('Subscription initiated');
    } catch (e) {
      _addDebugLog('Error subscribing: $e');
    }
  }

  void _queueNotification({
    required String senderName,
    required String message,
    String? jobTitle,
    required String conversationId,
  }) {
    _notificationQueue.add(
      _PendingNotification(
        senderName: senderName,
        message: message,
        jobTitle: jobTitle,
        conversationId: conversationId,
      ),
    );
    _addDebugLog('Queued notification. Queue size: ${_notificationQueue.length}');

    // If a notification is already showing, refresh it to update the queue count
    if (_isShowingNotification && _currentNotification != null) {
      _addDebugLog('Refreshing current notification to show updated queue count');
      final messenger = _scaffoldMessengerKey?.currentState;
      if (messenger != null) {
        messenger.hideCurrentSnackBar();
        _isShowingNotification = false;
        // Put current notification back at front of queue
        _notificationQueue.insert(0, _currentNotification!);
        _currentNotification = null;
      }
    }
    _processNotificationQueue();
  }

  void _processNotificationQueue() {
    if (_isShowingNotification || _notificationQueue.isEmpty) {
      return;
    }

    _isShowingNotification = true;
    _currentNotification = _notificationQueue.removeAt(0);
    _showNotification(
      senderName: _currentNotification!.senderName,
      message: _currentNotification!.message,
      jobTitle: _currentNotification!.jobTitle,
      conversationId: _currentNotification!.conversationId,
    );
  }

  void _showNotification({
    required String senderName,
    required String message,
    String? jobTitle,
    required String conversationId,
  }) {
    _addDebugLog('Showing notification: $senderName');

    // Use post-frame callback to ensure we're on the UI thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = _scaffoldMessengerKey?.currentState;
      if (messenger == null) {
        _addDebugLog('ERROR: ScaffoldMessenger is null!');
        _isShowingNotification = false;
        _processNotificationQueue();
        return;
      }
      _addDebugLog('ScaffoldMessenger OK, showing snackbar...');

      // Truncate message if too long
      final truncatedMessage = message.length > 50
          ? '${message.substring(0, 50)}...'
          : message;

      // Check queue size for indicator
      final queueSize = _notificationQueue.length;

      try {
        messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.orange,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        senderName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (queueSize > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '+$queueSize',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (jobTitle != null)
                    Text(
                      jobTitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  Text(
                    truncatedMessage,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Close button to dismiss without opening chat
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: () {
                messenger.hideCurrentSnackBar();
                _isShowingNotification = false;
                _currentNotification = null;
                _processNotificationQueue();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(days: 365),
        action: SnackBarAction(
          label: 'Ver',
          textColor: AppColors.orange,
          onPressed: () async {
            // Get other user's name for the chat screen
            final user = supabase.auth.currentUser;
            if (user == null) return;

            try {
              final conversation = await supabase
                  .from('conversations')
                  .select('''
                    seeker_id, helper_id,
                    seeker:profiles!conversations_seeker_id_fkey(name),
                    helper:profiles!conversations_helper_id_fkey(name),
                    job:jobs(title)
                  ''')
                  .eq('id', conversationId)
                  .single();

              final isSeeker = conversation['seeker_id'] == user.id;
              final otherUser = isSeeker
                  ? conversation['helper'] as Map<String, dynamic>?
                  : conversation['seeker'] as Map<String, dynamic>?;
              final otherUserName = otherUser?['name'] ?? 'Usuario';
              final chatJobTitle = conversation['job']?['title'] as String?;

              _navigatorKey?.currentState?.push(
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    conversationId: conversationId,
                    otherUserName: otherUserName,
                    jobTitle: chatJobTitle,
                  ),
                ),
              );
            } catch (e) {
              _addDebugLog('Error nav to chat: $e');
            } finally {
              _isShowingNotification = false;
              _currentNotification = null;
              _processNotificationQueue();
            }
          },
        ),
      ),
    );
        _addDebugLog('SnackBar shown!');
      } catch (e) {
        _addDebugLog('ERROR showing snackbar: $e');
        _currentNotification = null;
        _isShowingNotification = false;
        _processNotificationQueue();
      }
    });

    // Notification persists until user dismisses it (swipes or clicks "Ver")
  }

  // Re-subscribe when user logs in
  void resubscribe() {
    _channel?.unsubscribe();
    _subscribeToMessages();
  }
}

// Global instance
final messageNotificationService = MessageNotificationService();
