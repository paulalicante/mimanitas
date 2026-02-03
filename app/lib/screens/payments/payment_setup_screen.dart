import 'package:flutter/material.dart';
import '../../services/payment_service.dart';

/// Screen for helpers to set up their Stripe Connect account
/// This is required before they can receive payments for jobs
class PaymentSetupScreen extends StatefulWidget {
  const PaymentSetupScreen({super.key});

  @override
  State<PaymentSetupScreen> createState() => _PaymentSetupScreenState();
}

class _PaymentSetupScreenState extends State<PaymentSetupScreen> {
  bool _isLoading = true;
  bool _isStartingOnboarding = false;
  StripeAccountStatus? _status;
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
    });

    final status = await paymentService.checkStripeStatus();

    setState(() {
      _status = status;
      _lastChecked = DateTime.now();
      _isLoading = false;
    });
  }

  String _formatLastChecked() {
    if (_lastChecked == null) return '';
    final diff = DateTime.now().difference(_lastChecked!);
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds} seg';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    return 'hace ${diff.inHours} h';
  }

  Future<void> _startOnboarding() async {
    setState(() {
      _isStartingOnboarding = true;
    });

    // URLs for Stripe redirect - using deep links
    // In production, these should be real deep links to your app
    const returnUrl = 'https://mimanitas.me/stripe-return';
    const refreshUrl = 'https://mimanitas.me/stripe-refresh';

    // First call the Edge Function to get the onboarding URL
    final result = await paymentService.startStripeOnboarding(
      returnUrl: returnUrl,
      refreshUrl: refreshUrl,
    );

    setState(() {
      _isStartingOnboarding = false;
    });

    if (!result.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Error desconocido'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Try to open the URL
    if (result.onboardingUrl != null) {
      final opened = await paymentService.openStripeOnboarding(
        returnUrl: returnUrl,
        refreshUrl: refreshUrl,
      );

      if (mounted) {
        if (opened) {
          // Show dialog explaining a new window opened
          _showWindowOpenedDialog();
        } else {
          // If can't open URL, show it to user so they can copy it
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Abre este enlace: ${result.onboardingUrl}',
                style: const TextStyle(color: Colors.white),
              ),
              duration: const Duration(seconds: 10),
              backgroundColor: Colors.orange[700],
            ),
          );
        }
      }
    }
  }

  void _showWindowOpenedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.open_in_new, color: Colors.green[700]),
            const SizedBox(width: 12),
            const Text('Ventana abierta'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se ha abierto una nueva ventana para configurar tu cuenta de Stripe.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.looks_one, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Completa la configuración en la otra ventana',
                          style: TextStyle(color: Colors.blue[800], fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.looks_two, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Vuelve aquí y pulsa "Actualizar" para verificar',
                          style: TextStyle(color: Colors.blue[800], fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _checkStatus();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE86A33),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
            label: const Text('Actualizar estado', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Configurar pagos',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _checkStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFE86A33),
              ),
            )
          : RefreshIndicator(
              onRefresh: _checkStatus,
              color: const Color(0xFFE86A33),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status card
                    _buildStatusCard(),
                    const SizedBox(height: 24),

                    // Action button or status message
                    _buildActionSection(),
                    const SizedBox(height: 32),

                    // Info section
                    _buildInfoSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final status = _status;
    if (status == null) return const SizedBox.shrink();

    IconData icon;
    Color color;
    String title;
    String subtitle;

    if (status.error != null) {
      icon = Icons.error_outline;
      color = Colors.red;
      title = 'Error';
      subtitle = status.error!;
    } else if (!status.hasAccount) {
      icon = Icons.account_balance_wallet_outlined;
      color = const Color(0xFFE86A33);
      title = 'Opcional por ahora';
      subtitle = 'Puedes configurarlo cuando alguien quiera pagarte. Solo tarda 3 minutos.';
    } else if (status.needsAction) {
      icon = Icons.pending_actions;
      color = Colors.orange;
      title = 'Requiere acción';
      subtitle = status.message ?? 'Completa la configuración de Stripe';
    } else if (!status.payoutsEnabled) {
      icon = Icons.hourglass_top;
      color = Colors.blue;
      title = 'En revisión';
      subtitle = status.message ?? 'Stripe está verificando tu información';
    } else {
      icon = Icons.check_circle;
      color = Colors.green;
      title = 'Listo';
      subtitle = status.message ?? '¡Tu cuenta está lista para recibir pagos!';
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 40,
              color: color,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionSection() {
    final status = _status;
    if (status == null) return const SizedBox.shrink();

    // Show setup button if no account or needs action
    if (!status.hasAccount || status.needsAction) {
      return ElevatedButton.icon(
        onPressed: _isStartingOnboarding ? null : _startOnboarding,
        icon: _isStartingOnboarding
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.open_in_new),
        label: Text(
          status.hasAccount ? 'Completar configuración' : 'Configurar ahora (3 min)',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE86A33),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    // Show waiting message if in review
    if (!status.payoutsEnabled) {
      return Column(
        children: [
          // Progress timeline
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                // Timeline steps
                Row(
                  children: [
                    _buildTimelineStep(
                      icon: Icons.check_circle,
                      label: 'Datos enviados',
                      isComplete: true,
                      isActive: false,
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: Colors.blue,
                      ),
                    ),
                    _buildTimelineStep(
                      icon: Icons.hourglass_top,
                      label: 'En verificación',
                      isComplete: false,
                      isActive: true,
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: Colors.grey[300],
                      ),
                    ),
                    _buildTimelineStep(
                      icon: Icons.check_circle_outline,
                      label: 'Listo',
                      isComplete: false,
                      isActive: false,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Estimated time
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.schedule, color: Colors.blue[700], size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Tiempo estimado: 1-2 días laborables',
                            style: TextStyle(
                              color: Colors.blue[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (_lastChecked != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Última comprobación: ${_formatLastChecked()}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Refresh button
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _checkStatus,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Comprobar estado'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue[700],
            ),
          ),
        ],
      );
    }

    // Account is ready
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Puedes aceptar trabajos y recibir pagos.',
              style: TextStyle(color: Colors.green[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cómo funciona',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            icon: Icons.security,
            title: 'Pagos seguros',
            description: 'Usamos Stripe, la plataforma de pagos más segura del mundo.',
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            icon: Icons.lock_clock,
            title: 'Escrow protegido',
            description:
                'El dinero se guarda hasta que el trabajo esté completado.',
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            icon: Icons.account_balance,
            title: 'Transferencia directa',
            description:
                'El pago llega a tu cuenta bancaria española automáticamente.',
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            icon: Icons.receipt_long,
            title: 'Sin comisiones ocultas',
            description: 'El cliente paga una pequeña comisión. Tú recibes el 100%.',
          ),
          const SizedBox(height: 24),
          // Why Stripe needs info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '¿Por qué necesitan mis datos?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'La normativa bancaria europea (PSD2) exige verificar la identidad de quien recibe pagos. '
                  'Es el mismo proceso que harías al abrir una cuenta en cualquier banco. '
                  'Stripe es utilizado por millones de autónomos en España.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Necesitarás:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Tu nombre y fecha de nacimiento\n'
                  '• Tu dirección en España\n'
                  '• Tu número de cuenta (IBAN)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '⏱️ Solo tarda 2-3 minutos',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0E8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: const Color(0xFFE86A33),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineStep({
    required IconData icon,
    required String label,
    required bool isComplete,
    required bool isActive,
  }) {
    final color = isComplete
        ? Colors.blue
        : isActive
            ? Colors.blue
            : Colors.grey[400];

    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isComplete || isActive
                ? Colors.blue.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: color!,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
