// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';

enum AurumPlan { monthly, sixMonths, lifetime }

extension AurumPlanX on AurumPlan {
  String get id {
    switch (this) {
      case AurumPlan.monthly:   return 'monthly';
      case AurumPlan.sixMonths: return 'sixMonths';
      case AurumPlan.lifetime:  return 'lifetime';
    }
  }

  String get label {
    switch (this) {
      case AurumPlan.monthly:   return '1 Month';
      case AurumPlan.sixMonths: return '6 Months';
      case AurumPlan.lifetime:  return 'Lifetime';
    }
  }

  int get amountRupees {
    switch (this) {
      case AurumPlan.monthly:   return 19;
      case AurumPlan.sixMonths: return 149;
      case AurumPlan.lifetime:  return 249;
    }
  }

  String get priceLabel => '\u20b9$amountRupees';

  Duration? get duration {
    switch (this) {
      case AurumPlan.monthly:   return const Duration(days: 30);
      case AurumPlan.sixMonths: return const Duration(days: 180);
      case AurumPlan.lifetime:  return null;
    }
  }

  bool get isLifetime => this == AurumPlan.lifetime;
}

class PaymentService {
  PaymentService._internal();
  static final PaymentService instance = PaymentService._internal();

  static const String _workerBaseUrl = 'https://aurum-worker.shivamsharma962122.workers.dev';

  static const String goldHex = '#C9A84C';

  static const _kCachedPremium     = 'aurum_is_premium_cached';
  static const _kPremiumGrantedAt  = 'aurum_premium_granted_at';
  static const _kPremiumPlan       = 'aurum_premium_plan';
  static const _kPremiumPaymentId  = 'aurum_premium_payment_id';
  static const _kPremiumExpiresAt  = 'aurum_premium_expires_at';
  static const _kPremiumOwnerId    = 'aurum_premium_owner_id';
  static const String guestOwnerId = 'guest';

  final CFPaymentGatewayService _cfPaymentGatewayService = CFPaymentGatewayService();

  AurumPlan? _pendingPlan;
  String? _pendingOrderId;

  void Function(AurumPlan plan, String paymentId)? onPaymentSuccess;
  void Function(String message)? onPaymentError;
  void Function()? onPaymentCancelled;

  void init({
    required void Function(AurumPlan plan, String paymentId) onSuccess,
    required void Function(String message) onError,
    void Function()? onCancelled,
  }) {
    onPaymentSuccess = onSuccess;
    onPaymentError = onError;
    onPaymentCancelled = onCancelled;

    _cfPaymentGatewayService.setCallback(_handleVerify, _handleError);
  }

  void dispose() {}

  Future<void> startPayment(AurumPlan plan, {String? userEmail, String? userName}) async {
    _pendingPlan = plan;

    try {
      final orderId = 'aurum_${plan.id}_${DateTime.now().millisecondsSinceEpoch}';
      _pendingOrderId = orderId;

      final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;

      final resp = await http.post(
        Uri.parse('$_workerBaseUrl/api/create-cf-order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderId': orderId,
          'orderAmount': plan.amountRupees,
          'planId': plan.id,
          'customerEmail': userEmail ?? 'guest@aurum.app',
          'customerName': userName ?? 'Astra User',
          'accessToken': accessToken,
        }),
      );

      if (resp.statusCode != 200) {
        onPaymentError?.call('Could not start payment. Please try again.');
        return;
      }

      final data = jsonDecode(resp.body);
      final sessionId = data['payment_session_id'] as String?;
      if (sessionId == null) {
        onPaymentError?.call('Could not start payment. Please try again.');
        return;
      }

      final session = CFSessionBuilder()
          .setEnvironment(CFEnvironment.PRODUCTION)
          .setOrderId(orderId)
          .setPaymentSessionId(sessionId)
          .build();

      final cfWebCheckout = CFWebCheckoutPaymentBuilder()
          .setSession(session)
          .build();

      _cfPaymentGatewayService.doPayment(cfWebCheckout);
    } catch (e, st) {
      debugPrint('[PaymentService] startPayment error: $e\n$st');
      onPaymentError?.call('Could not open payment sheet: $e');
    }
  }

  void _handleVerify(String orderId) async {
    if (orderId != _pendingOrderId) return;
    final plan = _pendingPlan;
    if (plan == null) return;

    try {
      final resp = await http.get(
        Uri.parse('$_workerBaseUrl/api/verify-cf-order?orderId=$orderId'),
      );
      if (orderId != _pendingOrderId) return;
      if (resp.statusCode != 200) {
        onPaymentError?.call('Could not verify payment. Please contact support if you were charged.');
        return;
      }
      final data = jsonDecode(resp.body);
      final status = data['order_status'] as String?;
      var grantPlan = plan;

      if (status == 'PAID') {
        final serverPlanId = data['plan'] as String?;
        if (serverPlanId != null) {
          final matched = AurumPlan.values.where((p) => p.id == serverPlanId);
          if (matched.isNotEmpty) grantPlan = matched.first;
        }
        await _grantPremiumLocally(grantPlan, orderId);
        onPaymentSuccess?.call(grantPlan, orderId);
      } else if (status == 'AMOUNT_MISMATCH') {
        onPaymentError?.call('Payment amount could not be verified. Please contact support if you were charged.');
      } else if (status == 'ACTIVE') {
        onPaymentError?.call('Payment not completed. Please try again.');
      } else {
        onPaymentCancelled?.call();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PaymentService] verify error: $e');
      onPaymentError?.call('Could not verify payment. Please contact support if you were charged.');
    } finally {
      if (_pendingOrderId == orderId) {
        _pendingPlan = null;
        _pendingOrderId = null;
      }
    }
  }

  void _handleError(CFErrorResponse errorResponse, String orderId) {
    final rawMessage = errorResponse.getMessage();
    final message = (rawMessage != null && rawMessage.isNotEmpty)
        ? rawMessage
        : 'Payment failed. Please try again.';
    if (kDebugMode) {
      debugPrint('[PaymentService] payment error: $message (order=$orderId)');
    }
    onPaymentError?.call(message);
  }

  Future<void> _grantPremiumLocally(AurumPlan plan, String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    final payerId = Supabase.instance.client.auth.currentUser?.id ?? guestOwnerId;

    await prefs.setBool(_kCachedPremium, true);
    await prefs.setString(_kPremiumGrantedAt, now.toIso8601String());
    await prefs.setString(_kPremiumPlan, plan.id);
    await prefs.setString(_kPremiumPaymentId, orderId);
    await prefs.setString(_kPremiumOwnerId, payerId);

    if (!plan.isLifetime && plan.duration != null) {
      final expiry = now.add(plan.duration!);
      await prefs.setString(_kPremiumExpiresAt, expiry.toIso8601String());
    } else {
      await prefs.remove(_kPremiumExpiresAt);
    }
  }

  static Future<bool> hasValidLocalGrant() async {
    final prefs = await SharedPreferences.getInstance();
    final isCached = prefs.getBool(_kCachedPremium) ?? false;
    if (!isCached) return false;

    final ownerId = prefs.getString(_kPremiumOwnerId) ?? guestOwnerId;
    if (ownerId != guestOwnerId) {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null && currentUserId != ownerId) {
        return false;
      }
    }

    final plan = prefs.getString(_kPremiumPlan);
    if (plan == 'lifetime') return true;

    final expiresAtStr = prefs.getString(_kPremiumExpiresAt);
    if (expiresAtStr == null) return false;

    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null) return false;

    return DateTime.now().isBefore(expiresAt);
  }

  static Future<String?> currentPlanId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPremiumPlan);
  }

  static Future<DateTime?> currentExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kPremiumExpiresAt);
    if (s == null) return null;
    return DateTime.tryParse(s);
  }
}
