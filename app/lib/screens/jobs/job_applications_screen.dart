import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_theme.dart';
import '../../main.dart';
import '../../services/payment_service.dart';
import '../../utils/schedule_conflict.dart';
import '../messages/chat_screen.dart';

class JobApplicationsScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  final double jobPrice;

  const JobApplicationsScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
    this.jobPrice = 0,
  });

  @override
  State<JobApplicationsScreen> createState() => _JobApplicationsScreenState();
}

class _JobApplicationsScreenState extends State<JobApplicationsScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;
  Map<String, dynamic>? _jobScheduleInfo;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadApplications();

    // Soft pulsing animation for contact banner
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load job scheduling info
      final jobData = await supabase
          .from('jobs')
          .select('scheduled_date, scheduled_time, is_flexible, estimated_duration_minutes')
          .eq('id', widget.jobId)
          .single();

      final applications = await supabase
          .from('applications')
          .select('''
            *,
            profiles!applications_applicant_id_fkey(id, name, phone, bio, barrio, avatar_url, date_of_birth)
          ''')
          .eq('job_id', widget.jobId)
          .order('created_at', ascending: false);

      setState(() {
        _jobScheduleInfo = jobData;
        _applications = List<Map<String, dynamic>>.from(applications);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading applications: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar las aplicaciones: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _navigateToChat(String helperId, String helperName) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Check if conversation already exists
      final existingConv = await supabase
          .from('conversations')
          .select('id')
          .eq('job_id', widget.jobId)
          .eq('seeker_id', user.id)
          .eq('helper_id', helperId)
          .maybeSingle();

      String conversationId;

      if (existingConv != null) {
        conversationId = existingConv['id'];
      } else {
        // Create new conversation
        final newConv = await supabase
            .from('conversations')
            .insert({
              'job_id': widget.jobId,
              'seeker_id': user.id,
              'helper_id': helperId,
            })
            .select('id')
            .single();
        conversationId = newConv['id'];
      }

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversationId,
            otherUserName: helperName,
            jobTitle: widget.jobTitle,
          ),
        ),
      );
    } catch (e) {
      print('Error opening conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir conversación: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _acceptApplication(String applicationId, String helperId) async {
    try {
      print('=== DEBUG: ACCEPTING APPLICATION WITH STRIPE CHECKOUT ===');
      print('DEBUG: Application ID: $applicationId');
      print('DEBUG: Helper ID: $helperId');
      print('DEBUG: Job ID: ${widget.jobId}');

      // Check for scheduling conflict before proceeding
      final scheduledDate = _jobScheduleInfo?['scheduled_date'] as String?;
      final scheduledTime = _jobScheduleInfo?['scheduled_time'] as String?;
      final isFlexible = _jobScheduleInfo?['is_flexible'] == true;
      final duration = (_jobScheduleInfo?['estimated_duration_minutes'] as int?) ?? 60;

      if (scheduledDate != null && !isFlexible) {
        final conflictResult = await ScheduleConflict.checkConflict(
          helperId: helperId,
          proposedDate: scheduledDate,
          proposedTime: scheduledTime,
          durationMinutes: duration,
          excludeJobId: widget.jobId,
        );

        if (conflictResult.hasConflict) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Este helper ya tiene otro trabajo a esa hora: ${conflictResult.conflictingJob?['title'] ?? 'trabajo existente'}',
                ),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Create checkout session
      // URLs for Stripe redirect - in production, use deep links
      const baseUrl = 'https://mimanitas.me';
      final successUrl = '$baseUrl/payment-success?job_id=${widget.jobId}&application_id=$applicationId';
      final cancelUrl = '$baseUrl/payment-cancelled?job_id=${widget.jobId}';

      final checkoutResult = await paymentService.createCheckoutSession(
        jobId: widget.jobId,
        applicationId: applicationId,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (!checkoutResult.success) {
        // Check if helper needs to set up their account
        if (checkoutResult.helperNeedsOnboarding) {
          if (mounted) {
            _showHelperNeedsSetupDialog(helperId);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(checkoutResult.error ?? 'Error al crear el pago'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
        return;
      }

      // Show payment confirmation dialog with redirect info
      if (mounted) {
        final confirmed = await _showPaymentConfirmation(checkoutResult);
        if (confirmed != true) return;
      }

      // Open Stripe Checkout in browser
      if (checkoutResult.checkoutUrl != null) {
        final uri = Uri.parse(checkoutResult.checkoutUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          // Show verification dialog when user returns
          if (mounted && checkoutResult.sessionId != null) {
            await _showPaymentVerificationDialog(
              checkoutResult.sessionId!,
              applicationId,
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo abrir la página de pago'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      }
    } catch (e) {
      // Close any open dialogs
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/job-applications');
      }

      print('Error accepting application: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al aceptar la aplicación: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showPaymentVerificationDialog(String sessionId, String applicationId) async {
    if (!mounted) return;

    // Show dialog asking user to confirm when they've paid
    final shouldVerify = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payment, color: AppColors.orange),
            const SizedBox(width: 12),
            const Expanded(child: Text('Completa el pago')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se ha abierto Stripe en tu navegador.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Completa el pago allí y luego pulsa "Ya he pagado" para verificar.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.info, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Si cerraste el navegador, pulsa "Cancelar" e inténtalo de nuevo.',
                      style: TextStyle(fontSize: 13, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('Ya he pagado'),
          ),
        ],
      ),
    );

    if (shouldVerify != true || !mounted) {
      await _loadApplications();
      return;
    }

    // Now show verifying dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Verificando pago...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );

    // Poll for payment completion (webhook may need a moment to process)
    PaymentConfirmResult? verifyResult;
    for (int attempt = 0; attempt < 6; attempt++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      verifyResult = await paymentService.verifyCheckout(sessionId: sessionId);
      if (verifyResult.success) break;
    }

    // Close loading dialog
    if (mounted) Navigator.of(context).pop();

    if (verifyResult?.success == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verifyResult!.message ?? '¡Pago completado! Trabajo asignado.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadApplications();
      }
    } else {
      // Payment not yet confirmed — might still complete via webhook
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo verificar el pago. Si has pagado, el estado se actualizará en breve.'),
            backgroundColor: AppColors.orange,
            duration: Duration(seconds: 5),
          ),
        );
        await _loadApplications();
      }
    }
  }

  void _showHelperNeedsSetupDialog(String helperId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: AppColors.orange),
            const SizedBox(width: 12),
            const Text('Cuenta no configurada'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Este helper aún no ha configurado su cuenta para recibir pagos.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppColors.info, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Envíale un mensaje para avisarle que quieres contratarle. '
                      'La configuración solo tarda 3 minutos.',
                      style: TextStyle(
                        color: AppColors.info,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Navigate to chat with helper
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Usa Mensajes para contactar con el helper'),
                  backgroundColor: AppColors.info,
                ),
              );
            },
            icon: const Icon(Icons.message, size: 18),
            label: const Text('Enviar mensaje'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showPaymentConfirmation(CheckoutSessionResult checkoutResult) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen del pago:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildPaymentRow('Trabajo', checkoutResult.formattedJobAmount),
            _buildPaymentRow('Comisión plataforma (10%)', checkoutResult.formattedFee),
            const Divider(),
            _buildPaymentRow('Total', checkoutResult.formattedTotal, bold: true),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.info, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Serás redirigido a Stripe para completar el pago de forma segura.',
                      style: TextStyle(
                        color: AppColors.info,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock, color: AppColors.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El dinero se guardará en depósito hasta que marques el trabajo como completado.',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('Pagar ${checkoutResult.formattedTotal}'),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(String label, String amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? AppColors.orange : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectApplication(String applicationId) async {
    try {
      await supabase
          .from('applications')
          .update({'status': 'rejected'})
          .eq('id', applicationId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aplicación rechazada'),
            backgroundColor: AppColors.orange,
          ),
        );
      }

      await _loadApplications();
    } catch (e) {
      print('Error rejecting application: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al rechazar la aplicación: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAcceptConfirmation(String applicationId, String helperId, String helperName) {
    final priceText = widget.jobPrice > 0
        ? '\n\nSe te pedirá pagar €${widget.jobPrice.toStringAsFixed(2)} + 10% comisión.'
        : '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aceptar aplicación'),
        content: Text(
          '¿Quieres aceptar a $helperName para este trabajo?'
          '$priceText\n\n'
          'Esto asignará el trabajo a $helperName y rechazará automáticamente las demás aplicaciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptApplication(applicationId, helperId);
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _showRejectConfirmation(String applicationId, String helperName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar aplicación'),
        content: Text('¿Seguro que quieres rechazar a $helperName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _rejectApplication(applicationId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'accepted':
        return 'Aceptado';
      case 'rejected':
        return 'Rechazado';
      case 'withdrawn':
        return 'Retirado';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.orange;
      case 'accepted':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'withdrawn':
        return AppColors.textMuted;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aplicaciones'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Job title header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.jobTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_applications.length} ${_applications.length == 1 ? 'aplicación' : 'aplicaciones'}',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          // Applications list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _applications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '📭',
                              style: TextStyle(fontSize: 64),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay aplicaciones todavía',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadApplications,
                        color: AppColors.orange,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _applications.length,
                          itemBuilder: (context, index) {
                            final application = _applications[index];
                            final helper = application['profiles'];
                            final helperName = helper != null ? helper['name'] : 'Usuario';
                            final helperId = helper != null ? helper['id'] : '';
                            final helperPhone = helper != null ? helper['phone'] : null;
                            final helperBio = helper != null ? helper['bio'] : null;
                            final helperBarrio = helper != null ? helper['barrio'] : null;
                            final helperAvatar = helper != null ? helper['avatar_url'] : null;
                            final helperDob = helper != null ? helper['date_of_birth'] : null;
                            final status = application['status'] as String;

                            // Calculate age if date of birth is available
                            int? helperAge;
                            if (helperDob != null) {
                              try {
                                final dob = DateTime.parse(helperDob);
                                final today = DateTime.now();
                                helperAge = today.year - dob.year;
                                if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
                                  helperAge--;
                                }
                              } catch (e) {
                                // Invalid date format
                                helperAge = null;
                              }
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Helper avatar
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: const BoxDecoration(
                                            color: AppColors.navyVeryLight,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              helperName.isNotEmpty
                                                  ? helperName[0].toUpperCase()
                                                  : 'U',
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.navyDark,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Helper info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    helperName,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (helperAge != null) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.navyVeryLight,
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        '$helperAge años',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: AppColors.textMuted,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (helperBarrio != null)
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.location_on,
                                                      size: 14,
                                                      color: AppColors.textMuted,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      helperBarrio,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: AppColors.textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              if (helperPhone != null && status == 'accepted')
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.phone,
                                                      size: 14,
                                                      color: AppColors.textMuted,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      helperPhone,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: AppColors.textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                        // Status badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(status).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _getStatusText(status),
                                            style: TextStyle(
                                              color: _getStatusColor(status),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Bio section
                                    if (helperBio != null && helperBio.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Sobre mí',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              helperBio,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: AppColors.textMuted,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // Action buttons for pending applications
                                    if (status == 'pending') ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _showRejectConfirmation(
                                                application['id'],
                                                helperName,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.error,
                                                side: const BorderSide(
                                                  color: AppColors.error,
                                                  width: 1.5,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Text('Rechazar'),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () => _showAcceptConfirmation(
                                                application['id'],
                                                helperId,
                                                helperName,
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Text('Aceptar'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],

                                    // Contact info for accepted applications
                                    if (status == 'accepted') ...[
                                      const SizedBox(height: 16),
                                      AnimatedBuilder(
                                        animation: _pulseAnimation,
                                        builder: (context, child) {
                                          return InkWell(
                                            onTap: () => _navigateToChat(helperId, helperName),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.orangeLight.withValues(
                                                  alpha: 0.5 + (_pulseAnimation.value * 0.5),
                                                ),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: AppColors.orange.withValues(
                                                    alpha: _pulseAnimation.value,
                                                  ),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.message,
                                                    color: AppColors.orange,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'Contacta con $helperName para coordinar',
                                                      style: const TextStyle(
                                                        color: AppColors.orange,
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  const Icon(
                                                    Icons.chevron_right,
                                                    color: AppColors.orange,
                                                    size: 20,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
