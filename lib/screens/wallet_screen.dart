// lib/screens/wallet/wallet_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:paystack_for_flutter/paystack_for_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malak/config/api_config.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _paystackSecretKey = 'sk_test_f5faaf8b06c41bc54016378dfa88964e479d33a6';
const _paystackPublicKey = 'pk_test_326283a4813bb26a9b6372c90c393ea21a46aff4';

// ─── Theme ────────────────────────────────────────────────────────────────────

const _bg = Color(0xFFF9FAFB);
const _surface = Colors.white;
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF6B7280);
const _divider = Color(0xFFF3F4F6);
const _green = Color(0xFF059669);
const _greenLight = Color(0xFFECFDF5);
const _blue = Color(0xFF2563EB);
const _blueLight = Color(0xFFEFF6FF);
const _red = Color(0xFFEF4444);
const _redLight = Color(0xFFFEF2F2);
const _amber = Color(0xFFD97706);
const _amberLight = Color(0xFFFFFBEB);

// ─── Screen ───────────────────────────────────────────────────────────────────

class WalletPage extends StatefulWidget {
  const WalletPage({Key? key}) : super(key: key);

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _wallet;
  bool _loading = true;

  // tab: fund | pay | withdraw
  String _activeTab = 'fund';

  // fund
  final _fundAmountCtrl = TextEditingController();

  // pay
  final _payAmountCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // action loading states
  bool _fundLoading = false;
  bool _payLoading = false;

  // animation
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _fetchWallet();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _fundAmountCtrl.dispose();
    _payAmountCtrl.dispose();
    _recipientCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── API ────────────────────────────────────────────────────────────────────

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _fetchWallet() async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/wallet'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _wallet = json.decode(res.body));
        _animCtrl.forward(from: 0);
      }
    } catch (e) {
      debugPrint('Fetch wallet error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Paystack charge ────────────────────────────────────────────────────────

  Future<String> _chargeWithPaystack(double amount) async {
    final completer = Completer<String>();

    final email = _wallet?['userEmail'] as String? ?? 'user@malak.app';
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString('fullName') ?? '';
    final nameParts = fullName
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final reference = 'WALLET-${DateTime.now().millisecondsSinceEpoch}';

    // Paystack expects kobo (amount × 100)
    final amountInKobo = amount * 100;

    PaystackFlutter().pay(
      context: context,
      secretKey: _paystackSecretKey,
      amount: amountInKobo,
      email: email,
      firstName: firstName,
      lastName: lastName,
      currency: Currency.NGN,
      reference: reference,
      callbackUrl: 'https://malak.app/payment/callback',
      onSuccess: (response) {
        final ref = response.reference ?? reference;
        debugPrint('✅ Wallet fund SUCCESS: $ref');
        if (!completer.isCompleted) completer.complete(ref);
      },
      onCancelled: (response) {
        debugPrint('❌ Wallet fund CANCELLED');
        if (!completer.isCompleted) {
          completer.completeError(Exception('Payment window closed'));
        }
      },
    );

    return completer.future;
  }

  // ── Fund ───────────────────────────────────────────────────────────────────

  Future<void> _handleFund() async {
    final raw = double.tryParse(_fundAmountCtrl.text.trim());
    if (raw == null || raw <= 0) {
      _snack('Enter a valid amount', error: true);
      return;
    }

    setState(() => _fundLoading = true);

    try {
      final ref = await _chargeWithPaystack(raw);

      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$API_BASE_URL/wallet/fund/confirm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'amount': raw, 'reference': ref}),
      );
      final data = json.decode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        _snack(data['message'] ?? 'Wallet funded successfully!');
        _fundAmountCtrl.clear();
        _fetchWallet();
      } else {
        _snack(data['message'] ?? 'Failed to confirm payment', error: true);
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _fundLoading = false);
    }
  }

  // ── Pay ────────────────────────────────────────────────────────────────────

  Future<void> _handlePay() async {
    final amount = double.tryParse(_payAmountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Enter a valid amount', error: true);
      return;
    }
    if (_recipientCtrl.text.trim().isEmpty) {
      _snack('Enter recipient email or ID', error: true);
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Enter a description', error: true);
      return;
    }

    setState(() => _payLoading = true);

    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$API_BASE_URL/wallet/pay'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'amount': amount,
          'recipient': _recipientCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
        }),
      );
      final data = json.decode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        _snack(data['message'] ?? 'Payment successful!');
        _payAmountCtrl.clear();
        _recipientCtrl.clear();
        _descCtrl.clear();
        _fetchWallet();
      } else {
        _snack(data['message'] ?? 'Payment failed', error: true);
      }
    } catch (e) {
      _snack('Error processing payment', error: true);
    } finally {
      if (mounted) setState(() => _payLoading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatCurrency(num? value) {
    if (value == null) return '₦0.00';
    final formatted = value
        .toStringAsFixed(2)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return '₦$formatted';
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr).toLocal();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m';
    } catch (_) {
      return '';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _loading ? _buildSkeleton() : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: const Color(0x14000000),
      backgroundColor: _surface,
      toolbarHeight: 60,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: _textPrimary,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Wallet',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.refresh_rounded,
            color: _textSecondary,
            size: 22,
          ),
          onPressed: () {
            setState(() => _loading = true);
            _fetchWallet();
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        color: _green,
        onRefresh: _fetchWallet,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildBalanceCard(),
              const SizedBox(height: 16),
              _buildTabBar(),
              const SizedBox(height: 16),
              _buildTabContent(),
              const SizedBox(height: 24),
              _buildTransactionHistory(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Balance Card ───────────────────────────────────────────────────────────

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Wallet Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _formatCurrency(_wallet?['balance']),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Nigerian Naira (NGN)',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Tab Bar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _tabBtn('fund', Icons.arrow_upward_rounded, 'Fund', _green),
          _tabBtn('pay', Icons.credit_card_rounded, 'Pay', _blue),
          _tabBtn('withdraw', Icons.arrow_downward_rounded, 'Withdraw', _red),
        ],
      ),
    );
  }

  Widget _tabBtn(String id, IconData icon, String label, Color activeColor) {
    final isActive = _activeTab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.white : _textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : _textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab Content ────────────────────────────────────────────────────────────

  Widget _buildTabContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_activeTab),
        child: _activeTab == 'fund'
            ? _buildFundTab()
            : _activeTab == 'pay'
            ? _buildPayTab()
            : _buildWithdrawTab(),
      ),
    );
  }

  // ── Fund Tab ───────────────────────────────────────────────────────────────

  Widget _buildFundTab() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tabHeader(
            icon: Icons.arrow_upward_rounded,
            iconColor: _green,
            iconBg: _greenLight,
            title: 'Fund Wallet',
            subtitle: 'Add money to your wallet using Paystack',
          ),
          const SizedBox(height: 20),
          _amountField(
            controller: _fundAmountCtrl,
            focusColor: _green,
            label: 'Amount (NGN)',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _fundLoading ? null : _handleFund,
              icon: _fundLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded, size: 18),
              label: Text(
                _fundLoading ? 'Processing...' : 'Fund Wallet with Paystack',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _green.withOpacity(0.5),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pay Tab ────────────────────────────────────────────────────────────────

  Widget _buildPayTab() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tabHeader(
            icon: Icons.credit_card_rounded,
            iconColor: _blue,
            iconBg: _blueLight,
            title: 'Make Payment',
            subtitle: 'Pay from your wallet balance',
          ),
          const SizedBox(height: 20),
          _inputField(
            controller: _recipientCtrl,
            label: 'Recipient Email or ID',
            hint: 'recipient@example.com',
            focusColor: _blue,
          ),
          const SizedBox(height: 12),
          _amountField(
            controller: _payAmountCtrl,
            focusColor: _blue,
            label: 'Amount (NGN)',
          ),
          const SizedBox(height: 12),
          _inputField(
            controller: _descCtrl,
            label: 'Description',
            hint: 'What is this payment for?',
            focusColor: _blue,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _payLoading ? null : _handlePay,
              icon: _payLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _payLoading ? 'Processing...' : 'Send Payment',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _blue.withOpacity(0.5),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Withdraw Tab ───────────────────────────────────────────────────────────

  Widget _buildWithdrawTab() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tabHeader(
            icon: Icons.arrow_downward_rounded,
            iconColor: _red,
            iconBg: _redLight,
            title: 'Withdraw Funds',
            subtitle: 'Transfer money to your bank account',
          ),
          const SizedBox(height: 20),

          // Coming soon banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _amberLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _amber.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.access_time_rounded,
                    color: _amber,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Coming Soon',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "We're working on enabling withdrawals to your bank account. This feature will be available shortly. Stay tuned!",
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Disabled state
          Opacity(
            opacity: 0.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _amountField(
                  controller: TextEditingController(),
                  focusColor: _red,
                  label: 'Amount (NGN)',
                  enabled: false,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: const Text(
                      'Withdraw to Bank',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD1D5DB),
                      foregroundColor: _textSecondary,
                      disabledBackgroundColor: const Color(0xFFD1D5DB),
                      disabledForegroundColor: _textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Transaction History ────────────────────────────────────────────────────

  Widget _buildTransactionHistory() {
    final transactions = (_wallet?['transactions'] as List<dynamic>?) ?? [];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transaction History',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              if (transactions.isNotEmpty)
                Text(
                  '${transactions.length} records',
                  style: const TextStyle(fontSize: 12, color: _textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (transactions.isEmpty)
            _buildEmptyTransactions()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: transactions.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _divider),
              itemBuilder: (_, i) => _buildTransactionTile(transactions[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? 'pay';
    final status = tx['status'] as String? ?? 'pending';
    final amount = tx['amount'];
    final description = tx['description'] as String?;
    final createdAt = tx['createdAt'] as String?;

    Color iconColor;
    Color iconBg;
    IconData icon;
    String typeLabel;

    switch (type) {
      case 'fund':
        iconColor = _green;
        iconBg = _greenLight;
        icon = Icons.arrow_upward_rounded;
        typeLabel = 'Fund';
        break;
      case 'withdraw':
        iconColor = _red;
        iconBg = _redLight;
        icon = Icons.arrow_downward_rounded;
        typeLabel = 'Withdraw';
        break;
      default:
        iconColor = _blue;
        iconBg = _blueLight;
        icon = Icons.credit_card_rounded;
        typeLabel = 'Payment';
    }

    final isSuccess = status == 'success';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description?.isNotEmpty == true
                      ? description!
                      : _formatDate(createdAt),
                  style: const TextStyle(fontSize: 11.5, color: _textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatCurrency(amount),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSuccess
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 13,
                    color: isSuccess ? _green : _red,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    isSuccess ? 'Success' : 'Failed',
                    style: TextStyle(
                      fontSize: 11,
                      color: isSuccess ? _green : _red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactions() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _blueLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: _blue,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '₦0.00',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No transactions yet',
            style: TextStyle(fontSize: 13, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Skeleton ───────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _shimmer(height: 140, radius: 20),
          const SizedBox(height: 16),
          _shimmer(height: 56, radius: 14),
          const SizedBox(height: 16),
          _shimmer(height: 200, radius: 16),
          const SizedBox(height: 16),
          _shimmer(height: 280, radius: 16),
        ],
      ),
    );
  }

  Widget _shimmer({required double height, double radius = 8}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ── Reusable Widgets ───────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _tabHeader({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: _textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required Color focusColor,
    required String label,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: enabled,
          style: const TextStyle(fontSize: 14, color: _textPrimary),
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: const TextStyle(fontSize: 14, color: _textSecondary),
            prefixText: '₦ ',
            prefixStyle: const TextStyle(fontSize: 14, color: _textSecondary),
            filled: true,
            fillColor: enabled
                ? const Color(0xFFF9FAFB)
                : const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: focusColor, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color focusColor,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14, color: _textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 14, color: _textSecondary),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: focusColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
