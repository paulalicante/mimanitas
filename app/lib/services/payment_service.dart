import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service to handle all Stripe payment operations via Supabase Edge Functions
class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final _supabase = Supabase.instance.client;

  /// Check if the current helper has a Stripe account and its status
  Future<StripeAccountStatus> checkStripeStatus() async {
    try {
      final response = await _supabase.functions.invoke(
        'check-stripe-status',
        body: {},
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Error desconocido';
        return StripeAccountStatus(
          hasAccount: false,
          error: error,
        );
      }

      final data = response.data as Map<String, dynamic>;
      return StripeAccountStatus(
        hasAccount: data['has_account'] as bool? ?? false,
        stripeAccountId: data['stripe_account_id'] as String?,
        onboardingComplete: data['onboarding_complete'] as bool? ?? false,
        payoutsEnabled: data['payouts_enabled'] as bool? ?? false,
        chargesEnabled: data['charges_enabled'] as bool? ?? false,
        detailsSubmitted: data['details_submitted'] as bool? ?? false,
        needsAction: data['needs_action'] as bool? ?? false,
        message: data['message'] as String?,
      );
    } catch (e) {
      debugPrint('Error checking Stripe status: $e');
      return StripeAccountStatus(
        hasAccount: false,
        error: 'Error al verificar cuenta: $e',
      );
    }
  }

  /// Start the Stripe Connect onboarding process for a helper
  /// Returns the onboarding URL to redirect to
  Future<StripeOnboardingResult> startStripeOnboarding({
    required String returnUrl,
    required String refreshUrl,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-stripe-account',
        body: {
          'return_url': returnUrl,
          'refresh_url': refreshUrl,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Error desconocido';
        return StripeOnboardingResult(
          success: false,
          error: error,
        );
      }

      final data = response.data as Map<String, dynamic>;
      return StripeOnboardingResult(
        success: true,
        onboardingUrl: data['onboarding_url'] as String?,
        stripeAccountId: data['stripe_account_id'] as String?,
      );
    } catch (e) {
      debugPrint('Error starting Stripe onboarding: $e');
      return StripeOnboardingResult(
        success: false,
        error: 'Error al iniciar configuración: $e',
      );
    }
  }

  /// Open Stripe onboarding in browser
  Future<bool> openStripeOnboarding({
    required String returnUrl,
    required String refreshUrl,
  }) async {
    final result = await startStripeOnboarding(
      returnUrl: returnUrl,
      refreshUrl: refreshUrl,
    );

    if (!result.success || result.onboardingUrl == null) {
      return false;
    }

    final uri = Uri.parse(result.onboardingUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  /// Create a payment intent for a job
  /// Called when seeker accepts an application
  Future<PaymentIntentResult> createPaymentIntent({
    required String jobId,
    required String applicationId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-payment-intent',
        body: {
          'job_id': jobId,
          'application_id': applicationId,
        },
      );

      if (response.status != 200) {
        final data = response.data as Map<String, dynamic>?;
        final error = data?['error'] as String? ?? 'Error desconocido';
        final helperNeedsOnboarding = data?['helper_needs_onboarding'] as bool? ?? false;
        return PaymentIntentResult(
          success: false,
          error: error,
          helperNeedsOnboarding: helperNeedsOnboarding,
        );
      }

      final data = response.data as Map<String, dynamic>;
      return PaymentIntentResult(
        success: true,
        clientSecret: data['client_secret'] as String?,
        paymentIntentId: data['payment_intent_id'] as String?,
        amountCents: data['amount_cents'] as int?,
        jobAmountCents: data['job_amount_cents'] as int?,
        platformFeeCents: data['platform_fee_cents'] as int?,
        currency: data['currency'] as String? ?? 'eur',
      );
    } catch (e) {
      debugPrint('Error creating payment intent: $e');
      return PaymentIntentResult(
        success: false,
        error: 'Error al crear pago: $e',
      );
    }
  }

  /// Confirm that payment was successful and update job status
  Future<PaymentConfirmResult> confirmPayment({
    required String paymentIntentId,
    required String jobId,
    required String applicationId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'confirm-payment',
        body: {
          'payment_intent_id': paymentIntentId,
          'job_id': jobId,
          'application_id': applicationId,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Error desconocido';
        return PaymentConfirmResult(
          success: false,
          error: error,
        );
      }

      final data = response.data as Map<String, dynamic>;
      return PaymentConfirmResult(
        success: true,
        message: data['message'] as String?,
        jobStatus: data['job_status'] as String?,
        paymentStatus: data['payment_status'] as String?,
      );
    } catch (e) {
      debugPrint('Error confirming payment: $e');
      return PaymentConfirmResult(
        success: false,
        error: 'Error al confirmar pago: $e',
      );
    }
  }

  /// Create a Stripe Checkout Session for payment
  /// Returns a URL to redirect the user to Stripe's hosted payment page
  Future<CheckoutSessionResult> createCheckoutSession({
    required String jobId,
    required String applicationId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-checkout-session',
        body: {
          'job_id': jobId,
          'application_id': applicationId,
          'success_url': successUrl,
          'cancel_url': cancelUrl,
        },
      );

      if (response.status != 200) {
        final data = response.data as Map<String, dynamic>?;
        final error = data?['error'] as String? ?? 'Error desconocido';
        final helperNeedsOnboarding = data?['helper_needs_onboarding'] as bool? ?? false;
        return CheckoutSessionResult(
          success: false,
          error: error,
          helperNeedsOnboarding: helperNeedsOnboarding,
        );
      }

      final data = response.data as Map<String, dynamic>;
      return CheckoutSessionResult(
        success: true,
        checkoutUrl: data['checkout_url'] as String?,
        sessionId: data['session_id'] as String?,
        amountCents: data['amount_cents'] as int?,
        jobAmountCents: data['job_amount_cents'] as int?,
        platformFeeCents: data['platform_fee_cents'] as int?,
      );
    } on FunctionException catch (e) {
      // Handle FunctionException specifically to extract helper_needs_onboarding flag
      debugPrint('FunctionException creating checkout session: ${e.status} - ${e.details}');
      final details = e.details;
      if (details is Map<String, dynamic>) {
        final error = details['error'] as String? ?? 'Error desconocido';
        final helperNeedsOnboarding = details['helper_needs_onboarding'] as bool? ?? false;
        return CheckoutSessionResult(
          success: false,
          error: error,
          helperNeedsOnboarding: helperNeedsOnboarding,
        );
      }
      return CheckoutSessionResult(
        success: false,
        error: 'Error al crear sesión de pago: ${e.details}',
      );
    } catch (e) {
      debugPrint('Error creating checkout session: $e');
      return CheckoutSessionResult(
        success: false,
        error: 'Error al crear sesión de pago: $e',
      );
    }
  }

  /// Open Stripe Checkout in browser
  Future<bool> openStripeCheckout({
    required String jobId,
    required String applicationId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    final result = await createCheckoutSession(
      jobId: jobId,
      applicationId: applicationId,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
    );

    if (!result.success || result.checkoutUrl == null) {
      return false;
    }

    final uri = Uri.parse(result.checkoutUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  /// Verify a completed checkout session
  Future<PaymentConfirmResult> verifyCheckout({
    required String sessionId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-checkout',
        body: {
          'session_id': sessionId,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Error desconocido';
        return PaymentConfirmResult(
          success: false,
          error: error,
        );
      }

      final data = response.data as Map<String, dynamic>;
      return PaymentConfirmResult(
        success: true,
        message: data['message'] as String?,
        jobStatus: data['job_status'] as String?,
        paymentStatus: data['payment_status'] as String?,
      );
    } catch (e) {
      debugPrint('Error verifying checkout: $e');
      return PaymentConfirmResult(
        success: false,
        error: 'Error al verificar pago: $e',
      );
    }
  }

  /// Get helper's balance information
  Future<HelperBalance?> getHelperBalance() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('helper_balances')
          .select()
          .eq('profile_id', userId)
          .maybeSingle();

      if (response == null) return null;

      return HelperBalance(
        availableBalance: (response['available_balance'] as num?)?.toDouble() ?? 0,
        pendingBalance: (response['pending_balance'] as num?)?.toDouble() ?? 0,
        totalEarned: (response['total_earned'] as num?)?.toDouble() ?? 0,
        ytdEarnings: (response['ytd_earnings'] as num?)?.toDouble() ?? 0,
        ytdTransactionCount: response['ytd_transaction_count'] as int? ?? 0,
      );
    } catch (e) {
      debugPrint('Error getting helper balance: $e');
      return null;
    }
  }

  /// Format amount in cents to EUR string
  static String formatEuros(int cents) {
    final euros = cents / 100;
    return '€${euros.toStringAsFixed(2)}';
  }

  /// Format amount to EUR string
  static String formatEurosFromDouble(double amount) {
    return '€${amount.toStringAsFixed(2)}';
  }
}

/// Status of a helper's Stripe Connect account
class StripeAccountStatus {
  final bool hasAccount;
  final String? stripeAccountId;
  final bool onboardingComplete;
  final bool payoutsEnabled;
  final bool chargesEnabled;
  final bool detailsSubmitted;
  final bool needsAction;
  final String? message;
  final String? error;

  StripeAccountStatus({
    required this.hasAccount,
    this.stripeAccountId,
    this.onboardingComplete = false,
    this.payoutsEnabled = false,
    this.chargesEnabled = false,
    this.detailsSubmitted = false,
    this.needsAction = false,
    this.message,
    this.error,
  });

  bool get isReady => hasAccount && payoutsEnabled;
}

/// Result of starting Stripe onboarding
class StripeOnboardingResult {
  final bool success;
  final String? onboardingUrl;
  final String? stripeAccountId;
  final String? error;

  StripeOnboardingResult({
    required this.success,
    this.onboardingUrl,
    this.stripeAccountId,
    this.error,
  });
}

/// Result of creating a payment intent
class PaymentIntentResult {
  final bool success;
  final String? clientSecret;
  final String? paymentIntentId;
  final int? amountCents;
  final int? jobAmountCents;
  final int? platformFeeCents;
  final String currency;
  final String? error;
  final bool helperNeedsOnboarding;

  PaymentIntentResult({
    required this.success,
    this.clientSecret,
    this.paymentIntentId,
    this.amountCents,
    this.jobAmountCents,
    this.platformFeeCents,
    this.currency = 'eur',
    this.error,
    this.helperNeedsOnboarding = false,
  });

  String get formattedTotal => PaymentService.formatEuros(amountCents ?? 0);
  String get formattedJobAmount => PaymentService.formatEuros(jobAmountCents ?? 0);
  String get formattedFee => PaymentService.formatEuros(platformFeeCents ?? 0);
}

/// Result of confirming payment
class PaymentConfirmResult {
  final bool success;
  final String? message;
  final String? jobStatus;
  final String? paymentStatus;
  final String? error;

  PaymentConfirmResult({
    required this.success,
    this.message,
    this.jobStatus,
    this.paymentStatus,
    this.error,
  });
}

/// Result of creating a Stripe Checkout Session
class CheckoutSessionResult {
  final bool success;
  final String? checkoutUrl;
  final String? sessionId;
  final int? amountCents;
  final int? jobAmountCents;
  final int? platformFeeCents;
  final String? error;
  final bool helperNeedsOnboarding;

  CheckoutSessionResult({
    required this.success,
    this.checkoutUrl,
    this.sessionId,
    this.amountCents,
    this.jobAmountCents,
    this.platformFeeCents,
    this.error,
    this.helperNeedsOnboarding = false,
  });

  String get formattedTotal => PaymentService.formatEuros(amountCents ?? 0);
  String get formattedJobAmount => PaymentService.formatEuros(jobAmountCents ?? 0);
  String get formattedFee => PaymentService.formatEuros(platformFeeCents ?? 0);
}

/// Helper's balance information
class HelperBalance {
  final double availableBalance;
  final double pendingBalance;
  final double totalEarned;
  final double ytdEarnings;
  final int ytdTransactionCount;

  HelperBalance({
    required this.availableBalance,
    required this.pendingBalance,
    required this.totalEarned,
    required this.ytdEarnings,
    required this.ytdTransactionCount,
  });

  String get formattedAvailable => PaymentService.formatEurosFromDouble(availableBalance);
  String get formattedPending => PaymentService.formatEurosFromDouble(pendingBalance);
  String get formattedTotal => PaymentService.formatEurosFromDouble(totalEarned);
  String get formattedYtd => PaymentService.formatEurosFromDouble(ytdEarnings);

  /// Check if helper is approaching DAC7 reporting threshold
  bool get approachingTaxThreshold => ytdEarnings >= 1500 || ytdTransactionCount >= 25;

  /// Check if helper has reached DAC7 reporting threshold
  bool get reachedTaxThreshold => ytdEarnings >= 2000 || ytdTransactionCount >= 30;
}

// Global instance
final paymentService = PaymentService();
