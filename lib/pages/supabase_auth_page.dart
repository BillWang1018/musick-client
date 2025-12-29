import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/socket_service.dart';
import 'echo_page.dart';
import 'supabase_signup_page.dart';

class SupabaseAuthPage extends StatefulWidget {
  final SocketService socketService;
  final int jwtRouteId;

  const SupabaseAuthPage({
    super.key,
    required this.socketService,
    this.jwtRouteId = 10,
  });

  @override
  State<SupabaseAuthPage> createState() => _SupabaseAuthPageState();
}

class _SupabaseAuthPageState extends State<SupabaseAuthPage> {
  final Logger _logger = Logger();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _status = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInAndSendJwt() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _status = 'Enter email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Signing in...';
    });

    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final session = response.session ?? supabase.auth.currentSession;
      final accessToken = session?.accessToken;

      if (accessToken == null || accessToken.isEmpty) {
        setState(() => _status = 'Signed in, but no access token found.');
        return;
      }

      final payload = jsonEncode({'token': accessToken});
      widget.socketService.rememberAuthPayload(widget.jwtRouteId, payload);
      widget.socketService.sendToRoute(widget.jwtRouteId, payload);

      setState(
        () => _status =
            'JWT sent to server (route ${widget.jwtRouteId}). Waiting for response...',
      );

      final raw = await _waitForLoginResponse(timeout: const Duration(seconds: 8));
      if (!mounted) return;

      if (raw == null) {
        setState(() => _status = 'No login response received from server.');
        return;
      }

      final parsed = _tryParseLoginResponse(raw);
      if (parsed == null) {
        setState(() => _status = 'Invalid login response: $raw');
        return;
      }

      if (parsed.success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EchoPage(
              socketService: widget.socketService,
              title: 'welcome! ${parsed.userName}',
              userId: parsed.userId,
              userName: parsed.userName,
            ),
          ),
        );
      } else {
        setState(() => _status = parsed.message.isEmpty ? 'Login failed.' : parsed.message);
      }
    } on AuthException catch (e) {
      _logger.w('Supabase auth error: ${e.message}');
      setState(() => _status = e.message);
    } catch (e) {
      _logger.e('Unexpected sign-in error: $e');
      setState(() => _status = 'Sign-in failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _waitForLoginResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for login response: $e');
      return null;
    }
  }

  _LoginResponse? _tryParseLoginResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      final message = decoded['message'] ?? decoded['message_text'];
      final userId = decoded['user_id'] ?? decoded['UserID'] ?? decoded['userId'] ?? decoded['userid'];
      final userName = decoded['user_name'];

      if (success is! bool) return null;

      return _LoginResponse(
        success: success,
        message: message is String ? message : '',
        userId: userId is String ? userId : '',
        userName: userName is String ? userName : '',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supabase Login'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !_isLoading,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _signInAndSendJwt,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final result = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => SupabaseSignUpPage(
                            socketService: widget.socketService,
                          ),
                        ),
                      );

                      if (!mounted) return;
                      if (result != null && result.isNotEmpty) {
                        _emailController.text = result;
                        setState(
                          () => _status =
                              'Account created. Please sign in (and confirm email if required).',
                        );
                      }
                    },
              child: const Text('Create an account'),
            ),
            const SizedBox(height: 12),
            if (_status.isNotEmpty)
              Text(
                _status,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

class _LoginResponse {
  final bool success;
  final String message;
  final String userId;
  final String userName;

  const _LoginResponse({
    required this.success,
    required this.message,
    required this.userId,
    required this.userName,
  });
}
