import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../services/payment_service.dart';

/// Screen shown after returning from Stripe Checkout
/// Verifies the payment and shows success/error message
class PaymentSuccessScreen extends StatefulWidget {
  final String sessionId;
  final String? jobId;

  const PaymentSuccessScreen({
    super.key,
    required this.sessionId,
    this.jobId,
  });

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  bool _isLoading = true;
  bool _success = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verifyPayment();
  }

  Future<void> _verifyPayment() async {
    final result = await paymentService.verifyCheckout(
      sessionId: widget.sessionId,
    );

    setState(() {
      _isLoading = false;
      _success = result.success;
      _message = result.message;
      _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isLoading ? 'Verificando pago...' : (_success ? 'Pago completado' : 'Error'),
        ),
        automaticallyImplyLeading: !_isLoading,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 24),
                    Text(
                      'Verificando tu pago...',
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                )
              : _buildResult(),
        ),
      ),
    );
  }

  Widget _buildResult() {
    if (_success) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.successLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 60,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '¡Pago completado!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _message ?? 'El trabajo ha sido asignado correctamente.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.info_outline, color: AppColors.info),
                const SizedBox(height: 8),
                Text(
                  'El dinero está guardado en depósito. Se liberará al helper cuando marques el trabajo como completado.',
                  style: TextStyle(
                    color: AppColors.info,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // Go back to home/my jobs
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text(
                'Volver al inicio',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 60,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Error en el pago',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? 'No se pudo verificar el pago.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Volver a intentar',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      );
    }
  }
}
