import 'package:flutter/material.dart';
import '../../main.dart';
import '../../services/payment_service.dart';
import 'payment_setup_screen.dart';

/// Screen showing helper's earnings and balance
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  bool _isLoading = true;
  HelperBalance? _balance;
  StripeAccountStatus? _stripeStatus;
  List<Map<String, dynamic>> _recentTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    // Load balance and stripe status in parallel
    final results = await Future.wait([
      paymentService.getHelperBalance(),
      paymentService.checkStripeStatus(),
      _loadRecentTransactions(),
    ]);

    setState(() {
      _balance = results[0] as HelperBalance?;
      _stripeStatus = results[1] as StripeAccountStatus?;
      _isLoading = false;
    });
  }

  Future<void> _loadRecentTransactions() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('transactions')
          .select('''
            *,
            job:jobs(title, poster:profiles!jobs_poster_id_fkey(name))
          ''')
          .eq('job.assigned_to', userId)
          .order('created_at', ascending: false)
          .limit(10);

      _recentTransactions = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mis ganancias',
          style: TextStyle(color: Color(0xFFE86A33)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE86A33)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PaymentSetupScreen(),
                ),
              );
            },
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
              onRefresh: _loadData,
              color: const Color(0xFFE86A33),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Stripe status warning if not ready
                    if (_stripeStatus != null && !_stripeStatus!.isReady)
                      _buildStripeWarning(),

                    // Balance cards
                    _buildBalanceCards(),
                    const SizedBox(height: 24),

                    // Tax info if approaching threshold
                    if (_balance != null && _balance!.approachingTaxThreshold)
                      _buildTaxWarning(),

                    // Recent transactions
                    _buildTransactionsSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStripeWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configura tu cuenta de pagos',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                Text(
                  _stripeStatus?.message ?? 'Necesitas configurar Stripe para recibir pagos',
                  style: TextStyle(
                    color: Colors.orange[800],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PaymentSetupScreen(),
                ),
              );
            },
            child: const Text('Configurar'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCards() {
    final balance = _balance;

    return Row(
      children: [
        Expanded(
          child: _buildBalanceCard(
            title: 'Disponible',
            amount: balance?.formattedAvailable ?? '€0.00',
            icon: Icons.account_balance_wallet,
            color: Colors.green,
            subtitle: 'Listo para retirar',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildBalanceCard(
            title: 'Pendiente',
            amount: balance?.formattedPending ?? '€0.00',
            icon: Icons.hourglass_top,
            color: Colors.orange,
            subtitle: 'En espera',
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard({
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
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
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxWarning() {
    final balance = _balance!;
    final isOver = balance.reachedTaxThreshold;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOver
            ? Colors.red.withOpacity(0.1)
            : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOver
              ? Colors.red.withOpacity(0.3)
              : Colors.blue.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: isOver ? Colors.red : Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOver
                      ? 'Umbral fiscal alcanzado'
                      : 'Acercándote al umbral fiscal',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isOver ? Colors.red : Colors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isOver
                      ? 'Has ganado ${balance.formattedYtd} este año (${balance.ytdTransactionCount} transacciones). '
                          'Debes declarar estos ingresos a Hacienda.'
                      : 'Llevas ${balance.formattedYtd} este año (${balance.ytdTransactionCount} transacciones). '
                          'El límite para declarar es €2.000 o 30 transacciones.',
                  style: TextStyle(
                    color: isOver ? Colors.red[800] : Colors.blue[800],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Historial',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_balance != null)
              Text(
                'Total: ${_balance!.formattedTotal}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        if (_recentTransactions.isEmpty)
          Container(
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Sin transacciones todavía',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cuando completes trabajos, verás tus ganancias aquí',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          Container(
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
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentTransactions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final transaction = _recentTransactions[index];
                return _buildTransactionItem(transaction);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final status = transaction['status'] as String? ?? 'pending';
    final job = transaction['job'] as Map<String, dynamic>?;
    final jobTitle = job?['title'] as String? ?? 'Trabajo';
    final posterName = job?['poster']?['name'] as String? ?? 'Cliente';
    final createdAt = DateTime.tryParse(transaction['created_at'] ?? '');

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'held':
        statusColor = Colors.orange;
        statusText = 'En espera';
        statusIcon = Icons.hourglass_top;
        break;
      case 'released':
        statusColor = Colors.green;
        statusText = 'Completado';
        statusIcon = Icons.check_circle;
        break;
      case 'disputed':
        statusColor = Colors.red;
        statusText = 'Disputado';
        statusIcon = Icons.warning;
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Pendiente';
        statusIcon = Icons.pending;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(statusIcon, color: statusColor, size: 24),
      ),
      title: Text(
        jobTitle,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(posterName),
          if (createdAt != null)
            Text(
              _formatDate(createdAt),
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '+€${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: statusColor,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Hoy';
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      return 'Hace ${diff.inDays} días';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
