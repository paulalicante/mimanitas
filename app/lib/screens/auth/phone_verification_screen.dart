import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../main.dart';
import 'dart:async';

class PhoneVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback? onVerified;

  const PhoneVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.onVerified,
  });

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;
  String? _errorMessage;
  String? _successMessage;
  int _resendCountdown = 0;
  Timer? _timer;
  int? _attemptsRemaining;

  @override
  void dispose() {
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    setState(() {
      _resendCountdown = 60; // 60 seconds cooldown
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendVerificationCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final session = supabase.auth.currentSession;
      if (session == null) {
        throw Exception('Usuario no autenticado');
      }

      final response = await supabase.functions.invoke(
        'send-verification-code',
        body: {'phone': widget.phoneNumber},
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.status == 200) {
        setState(() {
          _codeSent = true;
          _successMessage = 'Código enviado a ${widget.phoneNumber}';
          _isLoading = false;
        });
        _startResendCountdown();
      } else {
        final error = response.data['error'] ?? 'Error al enviar código';
        throw Exception(error);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6) {
      setState(() {
        _errorMessage = 'Ingresa un código de 6 dígitos';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final session = supabase.auth.currentSession;
      if (session == null) {
        throw Exception('Usuario no autenticado');
      }

      final response = await supabase.functions.invoke(
        'verify-sms-code',
        body: {
          'phone': widget.phoneNumber,
          'code': _codeController.text.trim(),
        },
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.status == 200) {
        setState(() {
          _successMessage = '¡Teléfono verificado exitosamente!';
          _isLoading = false;
        });

        // Wait a moment to show success message
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          // Call the callback if provided
          widget.onVerified?.call();

          // Navigate back
          Navigator.of(context).pop(true);
        }
      } else {
        final error = response.data['error'] ?? 'Código inválido';
        final attemptsRemaining = response.data['attemptsRemaining'];

        setState(() {
          _errorMessage = error;
          _attemptsRemaining = attemptsRemaining;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificar teléfono'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon
                const Icon(
                  Icons.phone_android,
                  size: 80,
                  color: AppColors.navyDark,
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Verificación por SMS',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Subtitle
                Text(
                  _codeSent
                      ? 'Hemos enviado un código de verificación a:'
                      : 'Enviaremos un código de verificación a:',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Phone number
                Text(
                  widget.phoneNumber,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Success message
                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.successBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _successMessage!,
                            style: TextStyle(color: AppColors.success),
                          ),
                        ),
                      ],
                    ),
                  ),

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                        if (_attemptsRemaining != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Intentos restantes: $_attemptsRemaining',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                // Send code button (if code not sent yet)
                if (!_codeSent)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _sendVerificationCode,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
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
                            'Enviar código',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),

                // Code input and verify (if code sent)
                if (_codeSent) ...[
                  // Code input
                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'Código de verificación',
                      hintText: '000000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Verify button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
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
                            'Verificar código',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Resend button
                  TextButton(
                    onPressed: _resendCountdown > 0 || _isLoading
                        ? null
                        : _sendVerificationCode,
                    child: Text(
                      _resendCountdown > 0
                          ? 'Reenviar código en $_resendCountdown segundos'
                          : 'Reenviar código',
                      style: const TextStyle(
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Info box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.infoLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.infoBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: AppColors.info, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '¿Por qué verificar?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.info,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'La verificación por SMS garantiza que tenemos un número de contacto real y ayuda a mantener la confianza en la plataforma.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
