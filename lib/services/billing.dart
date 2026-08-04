import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'api_service.dart';
import 'pro_state.dart';
import 'session.dart';

/// Sigmacta Pro subscription via Google Play.
///
/// The client's only job is to run the purchase UI and hand the resulting
/// purchase token to our server. **Entitlement is never decided here** — a
/// patched APK can claim any purchase it likes, so `/api/billing/verify` reads
/// the truth back from the Play Developer API and it alone grants Pro.
///
/// Must be started early and left running: Play can deliver a purchase LATER
/// (payment pending, or an interrupted checkout completing on next launch), and
/// a purchase that arrives while nothing is listening is money taken without
/// entitlement given.
class Billing {
  Billing._();

  static const productId = 'sigmacta_pro_monthly';

  static final _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;
  static bool _started = false;

  /// Last error, for the UI to show. Null when the last attempt was fine.
  static String? lastError;

  /// True while a purchase is in flight, so the button can show progress.
  static bool busy = false;

  /// Whether the server can verify purchases. Drives whether a Buy button is
  /// shown at all — starts false so a slow/failed check never exposes one.
  static final ValueNotifier<bool> available = ValueNotifier(false);

  // kIsWeb short-circuits before Platform.isAndroid/isIOS — those getters
  // throw at runtime on web (no dart:io there), so touching them at all
  // behind a truthy kIsWeb would crash Billing.init() on every web page load.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Starts listening for purchase updates. Idempotent.
  static Future<void> init() async {
    if (_started || !supported) return;
    _started = true;
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (e) => lastError = e.toString(),
    );
    // Ask the server whether verification is even possible before any Buy
    // button can appear.
    available.value = await ApiService.billingAvailable();
    // Past purchases are replayed into purchaseStream, which is how a
    // subscription bought on another device — or before a reinstall — is
    // restored without the user doing anything.
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  /// Opens Play's purchase sheet. Returns false if it couldn't even start.
  static Future<bool> buy() async {
    if (!supported) {
      lastError = 'unsupported_platform';
      return false;
    }
    lastError = null;
    try {
      if (!await _iap.isAvailable()) {
        lastError = 'store_unavailable';
        return false;
      }
      final resp = await _iap.queryProductDetails({productId});
      final product = resp.productDetails
          .where((p) => p.id == productId)
          .cast<ProductDetails?>()
          .firstOrNull;
      if (product == null) {
        // Almost always a console/rollout problem rather than a code one: the
        // product isn't active, or this build isn't on a track the account can
        // see. Surfaced verbatim so it isn't mistaken for a purchase failure.
        lastError = 'product_not_found';
        return false;
      }
      busy = true;
      // buyNonConsumable, not buyConsumable: a subscription must not be
      // consumed — consuming it would make Play offer it for sale again.
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      lastError = e.toString();
      busy = false;
      return false;
    }
  }

  static Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          busy = true;
          break;

        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          busy = false;
          lastError = p.error?.message ?? 'cancelled';
          // Still completed: an errored/cancelled purchase left un-completed
          // is redelivered on every launch forever.
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p);
          break;
      }
    }
  }

  static Future<void> _verify(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;
    final r = await ApiService.verifyPurchase(
      purchaseToken: token,
      productId: p.productID,
    );
    busy = false;

    if (r['success'] == true) {
      lastError = null;
      await Session.patch({
        'is_pro': true,
        'pro_until': r['data']?['pro_until'],
      });
      ProState.set(true);
      // Only completed after OUR server granted entitlement. Completing first
      // would drop the purchase from the stream, leaving nothing to retry with
      // if verification had failed.
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      return;
    }

    lastError = r['error']?.toString() ?? 'verify_failed';
    // Deliberately NOT completed: leaving it pending means Play redelivers it
    // on the next launch, so a server hiccup doesn't cost the user their
    // subscription.
  }
}
