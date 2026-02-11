import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../app_theme.dart';
import '../services/message_notification_service.dart';
import '../services/job_notification_service.dart';
import '../utils/notification_sound.dart';
import 'bottom_nav_bar.dart';

// Import all tab screens
import '../screens/home/home_tab.dart';
import '../screens/jobs/browse_jobs_screen.dart';
import '../screens/jobs/my_jobs_screen.dart';
import '../screens/jobs/post_job_screen.dart';
import '../screens/profile/availability_screen.dart';
import '../screens/messages/messages_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/debug/debug_sms_screen.dart';

/// Main scaffold with bottom navigation bar
/// Contains IndexedStack for tab preservation and handles global state
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  String? _userType;
  String? _userName;
  bool _isLoading = true;
  int _unreadMessageCount = 0;
  RealtimeChannel? _messagesChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadUnreadMessageCount();
    _subscribeToMessages();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase
            .from('profiles')
            .select('user_type, name')
            .eq('id', user.id)
            .single();

        setState(() {
          _userType = profile['user_type'] as String?;
          _userName = profile['name'] as String?;
          _isLoading = false;
        });

        // Initialize job notifications with user context
        if (_userType != null) {
          jobNotificationService.setUserContext(user.id, _userType!);
        }

        // Ensure audio context is ready (browser autoplay policy)
        NotificationSound.ensureInitialized();
      }
    } catch (e) {
      print('Error loading profile in MainScaffold: $e');
      setState(() => _isLoading = false);
    }
  }

  // Polling fallback - check for new messages every 2 seconds
  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final serviceUnreadCount = messageNotificationService.getTotalUnreadCount();
      if (serviceUnreadCount != _unreadMessageCount && mounted) {
        setState(() => _unreadMessageCount = serviceUnreadCount);
      }
      _loadUnreadMessageCount();
    });
  }

  Future<void> _loadUnreadMessageCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final conversations = await supabase
          .from('conversations')
          .select('id')
          .or('seeker_id.eq.${user.id},helper_id.eq.${user.id}');

      if (conversations.isEmpty) {
        if (mounted) setState(() => _unreadMessageCount = 0);
        return;
      }

      final conversationIds = conversations.map((c) => c['id'] as String).toList();

      final unreadMessages = await supabase
          .from('messages')
          .select('id')
          .inFilter('conversation_id', conversationIds)
          .neq('sender_id', user.id)
          .isFilter('read_at', null);

      if (mounted) {
        setState(() => _unreadMessageCount = unreadMessages.length);
      }
    } catch (e) {
      print('Error loading unread message count: $e');
    }
  }

  void _subscribeToMessages() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _messagesChannel = supabase
        .channel('main_messages_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (mounted) {
              setState(() {
                _unreadMessageCount = messageNotificationService.getTotalUnreadCount();
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            _loadUnreadMessageCount();
          },
        )
        .subscribe();
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  /// Navigate to a specific tab programmatically
  void navigateToTab(int index) {
    if (index >= 0 && index < 5) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.orange),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _buildTabs(),
      ),
      bottomNavigationBar: MiManitasBottomNav(
        currentIndex: _currentIndex,
        userType: _userType,
        unreadMessageCount: _unreadMessageCount,
        onTap: _onTabTapped,
      ),
      // Debug FAB during development
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: AppColors.navyDark,
        onPressed: () => _showDebugSheet(context),
        child: const Icon(Icons.bug_report, size: 20),
      ),
    );
  }

  List<Widget> _buildTabs() {
    if (_userType == 'helper') {
      return [
        HomeTab(
          userType: 'helper',
          userName: _userName,
          onNavigateToTab: navigateToTab,
        ),
        const BrowseJobsScreen(embedded: true),
        const AvailabilityScreen(embedded: true),
        const MessagesScreen(embedded: true),
        const ProfileScreen(embedded: true),
      ];
    } else {
      // Seeker tabs
      return [
        HomeTab(
          userType: 'seeker',
          userName: _userName,
          onNavigateToTab: navigateToTab,
        ),
        const MyJobsScreen(embedded: true),
        const PostJobScreen(embedded: true),
        const MessagesScreen(embedded: true),
        const ProfileScreen(embedded: true),
      ];
    }
  }

  void _showDebugSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 400,
        color: AppColors.navyDarker,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Debug',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const DebugSmsScreen(),
                            ),
                          );
                        },
                        child: const Text('SMS Test', style: TextStyle(color: Colors.white)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: StatefulBuilder(
                builder: (context, setState) {
                  Future.delayed(const Duration(milliseconds: 500)).then((_) {
                    if (mounted) setState(() {});
                  });
                  return ListView.builder(
                    itemCount: messageNotificationService.debugLogs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text(
                          messageNotificationService.debugLogs[index],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
