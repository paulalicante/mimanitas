import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../app_theme.dart';

class DebugSmsScreen extends StatefulWidget {
  const DebugSmsScreen({super.key});

  @override
  State<DebugSmsScreen> createState() => _DebugSmsScreenState();
}

class _DebugSmsScreenState extends State<DebugSmsScreen> {
  String _result = 'Press button to test';
  bool _isLoading = false;
  bool _codeSent = false;
  final _codeController = TextEditingController();

  // Realtime test
  RealtimeChannel? _testChannel;
  String _realtimeStatus = 'Not connected';
  final List<String> _realtimeLog = [];

  @override
  void dispose() {
    _testChannel?.unsubscribe();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _testFunction() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing...';
    });

    try {
      final session = supabase.auth.currentSession;

      setState(() {
        _result = 'Session: ${session != null ? "exists" : "null"}\n';
        if (session != null) {
          _result += 'Access Token: ${session.accessToken.substring(0, 50)}...\n\n';
        }
        _result += 'Calling function...\n';
      });

      final response = await supabase.functions.invoke(
        'send-verification-code',
        body: {'phone': '+34603103122'},
        headers: {
          'Authorization': 'Bearer ${session?.accessToken ?? "NO_TOKEN"}',
        },
      );

      setState(() {
        _result += '\nStatus: ${response.status}\n';
        _result += 'Response: ${response.data.toString()}\n';
        _codeSent = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6) {
      setState(() {
        _result = 'Please enter a 6-digit code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _result = 'Verifying code...';
    });

    try {
      final session = supabase.auth.currentSession;

      final response = await supabase.functions.invoke(
        'verify-sms-code',
        body: {
          'phone': '+34603103122',
          'code': _codeController.text.trim(),
        },
        headers: {
          'Authorization': 'Bearer ${session?.accessToken ?? "NO_TOKEN"}',
        },
      );

      setState(() {
        _result = 'Verify Status: ${response.status}\n';
        _result += 'Response: ${response.data.toString()}\n';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Verify Error: $e';
        _isLoading = false;
      });
    }
  }

  // ============ REALTIME TEST METHODS ============

  void _addRealtimeLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _realtimeLog.add('[$timestamp] $message');
      // Keep only last 20 messages
      if (_realtimeLog.length > 20) {
        _realtimeLog.removeAt(0);
      }
    });
    print('REALTIME TEST: $message');
  }

  Future<void> _startRealtimeTest() async {
    _addRealtimeLog('Starting Realtime test...');

    // Unsubscribe from existing channel
    if (_testChannel != null) {
      await _testChannel!.unsubscribe();
      _testChannel = null;
    }

    try {
      final channelName = 'debug_realtime_test_${DateTime.now().millisecondsSinceEpoch}';
      _addRealtimeLog('Creating channel: $channelName');

      _testChannel = supabase
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (payload) {
              _addRealtimeLog('*** CALLBACK FIRED! ***');
              _addRealtimeLog('Event: ${payload.eventType}');
              _addRealtimeLog('New: ${payload.newRecord}');
              _addRealtimeLog('Old: ${payload.oldRecord}');
            },
          )
          .subscribe((status, [error]) {
        _addRealtimeLog('Channel status: $status');
        setState(() {
          _realtimeStatus = status.toString();
        });
        if (error != null) {
          _addRealtimeLog('Channel error: $error');
        }
      });

      _addRealtimeLog('Subscription initiated');
    } catch (e) {
      _addRealtimeLog('Error: $e');
    }
  }

  Future<void> _checkRealtimeConfig() async {
    _addRealtimeLog('Checking Realtime configuration...');

    try {
      // Query to check if tables are in realtime publication
      final result = await supabase.rpc('check_realtime_tables').select();
      _addRealtimeLog('Realtime tables: $result');
    } catch (e) {
      _addRealtimeLog('RPC not available, trying direct query...');

      // Try a simpler check - just verify we can query messages
      try {
        final messages = await supabase
            .from('messages')
            .select('id')
            .limit(1);
        _addRealtimeLog('Messages table accessible: ${messages.length} rows');
      } catch (e2) {
        _addRealtimeLog('Error querying messages: $e2');
      }
    }
  }

  Future<void> _sendTestMessage() async {
    _addRealtimeLog('Sending test message...');

    final user = supabase.auth.currentUser;
    if (user == null) {
      _addRealtimeLog('Error: No user logged in');
      return;
    }

    try {
      // Find any conversation the user is part of
      final conversations = await supabase
          .from('conversations')
          .select('id')
          .or('seeker_id.eq.${user.id},helper_id.eq.${user.id}')
          .limit(1);

      if (conversations.isEmpty) {
        _addRealtimeLog('No conversations found for user');
        return;
      }

      final conversationId = conversations[0]['id'];
      _addRealtimeLog('Found conversation: $conversationId');

      // Insert a test message
      final result = await supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': user.id,
        'content': '[TEST] Realtime test message - ${DateTime.now()}',
      }).select();

      _addRealtimeLog('Message inserted: ${result[0]['id']}');
      _addRealtimeLog('Now check if callback fires above...');
    } catch (e) {
      _addRealtimeLog('Error sending message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Debug Tools'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Realtime'),
              Tab(text: 'SMS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ===== REALTIME TAB =====
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _realtimeStatus.contains('subscribed')
                          ? AppColors.successLight
                          : AppColors.navyVeryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Status: $_realtimeStatus',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _realtimeStatus.contains('subscribed')
                            ? AppColors.success
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _startRealtimeTest,
                          child: const Text('1. Subscribe'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _sendTestMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.info,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('2. Send Test'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _checkRealtimeConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyLight,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Check Config'),
                  ),
                  const SizedBox(height: 16),

                  // Instructions
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.infoBorder),
                    ),
                    child: const Text(
                      'Instructions:\n'
                      '1. Click "Subscribe" to start listening\n'
                      '2. Click "Send Test" to insert a message\n'
                      '3. If callback fires, you\'ll see "*** CALLBACK FIRED! ***"\n'
                      '4. If no callback, Realtime is NOT configured in Supabase',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Log output
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(
                          _realtimeLog.isEmpty
                              ? 'Realtime log will appear here...'
                              : _realtimeLog.join('\n'),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ===== SMS TAB =====
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : _testFunction,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Test SMS Function'),
                  ),
                  const SizedBox(height: 24),
                  if (_codeSent) ...[
                    TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Enter 6-digit code',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: AppColors.surface,
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _verifyCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Verify Code'),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _result,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
