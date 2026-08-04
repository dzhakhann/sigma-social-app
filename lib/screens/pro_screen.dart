import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/billing.dart';
import '../services/pro_state.dart';
import '../services/session.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

/// Sigmacta Pro — subscription upsell. Store billing isn't live yet, but a
/// promo code issued from the CRM panel grants a real subscription today.
class ProScreen extends StatelessWidget {
  final Map user;
  const ProScreen({Key? key, required this.user}) : super(key: key);

  static const _benefits = [
    ['emoji_emotions_rounded', 'proB1t', 'proB1d'],
    ['block_rounded', 'proB2t', 'proB2d'],
    ['auto_awesome_rounded', 'proB3t', 'proB3d'],
    ['insights_rounded', 'proB4t', 'proB4d'],
    ['palette_rounded', 'proB5t', 'proB5d'],
  ];

  IconData _icon(String k) {
    switch (k) {
      case 'emoji_emotions_rounded': return Icons.emoji_emotions_rounded;
      case 'block_rounded': return Icons.block_rounded;
      case 'auto_awesome_rounded': return Icons.auto_awesome_rounded;
      case 'insights_rounded': return Icons.insights_rounded;
      case 'palette_rounded': return Icons.palette_rounded;
      default: return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('proTitle'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.accent3]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text(context.t('proTitle'),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                Text(context.t('proSubtitle'),
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 18),

          ..._benefits.map((b) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.ink.withOpacity(0.06))),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: c.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(_icon(b[0]), color: c.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t(b[1]),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: c.ink)),
                        const SizedBox(height: 2),
                        Text(context.t(b[2]),
                            style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ]),
              )),

          const SizedBox(height: 12),
          const _BuyButton(),
          const SizedBox(height: 10),
          Text(
            context.t('proFootnote'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 18),
          const _PromoBox(),
        ],
      ),
    );
  }
}

/// Promo-code redemption. Codes are issued from the CRM panel and grant a
/// real, time-limited Pro subscription — this is a working path to Pro that
/// doesn't depend on store billing being live yet.
class _PromoBox extends StatefulWidget {
  const _PromoBox();

  @override
  State<_PromoBox> createState() => _PromoBoxState();
}

class _PromoBoxState extends State<_PromoBox> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// The server returns stable reason codes rather than prose, so the message
  /// can be localized here instead of echoing English back at the user.
  String _messageFor(String? reason) {
    switch (reason) {
      case 'not_found':
        return context.t('promoErrNotFound');
      case 'expired':
        return context.t('promoErrExpired');
      case 'exhausted':
        return context.t('promoErrExhausted');
      case 'already_used':
        return context.t('promoErrAlreadyUsed');
      case 'inactive':
        return context.t('promoErrInactive');
      default:
        return context.t('promoErrGeneric');
    }
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ApiService.redeemPromo(code);
    if (!mounted) return;
    if (r['success'] == true) {
      final days = (r['data']?['days'] ?? 0).toString();
      _ctrl.clear();
      // Pro is now active server-side — mirror it into the cached session so
      // Premium themes unlock immediately instead of after the next login.
      await Session.patch({
        'is_pro': true,
        'pro_until': r['data']?['pro_until'],
      });
      // Unlocks Premium themes on the spot — every gate reads this notifier.
      ProState.set(true);
      if (!mounted) return;
      setState(() => _busy = false);
      showDialog(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(context.t('promoOkTitle')),
          content:
              Text(context.t('promoOkBody').replaceAll('{n}', days)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: Text(context.t('ok'))),
          ],
        ),
      );
    } else {
      setState(() {
        _busy = false;
        _error = _messageFor(r['error']?.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.ink.withOpacity(0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.t('promoTitle'),
            style: TextStyle(
                color: c.ink, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _apply(),
              style: TextStyle(color: c.ink, fontSize: 15),
              decoration: InputDecoration(
                hintText: context.t('promoHint'),
                hintStyle: TextStyle(color: c.inkSoft),
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accentFill,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _busy ? null : _apply,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(context.t('promoApply'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
        ],
      ]),
    );
  }
}

/// The real purchase button.
///
/// Deliberately hides itself when the user is ALREADY Pro: an app that keeps
/// offering a subscription you already pay for looks broken, and on Play it also
/// invites a duplicate-purchase support ticket.
class _BuyButton extends StatefulWidget {
  const _BuyButton();

  @override
  State<_BuyButton> createState() => _BuyButtonState();
}

class _BuyButtonState extends State<_BuyButton> {
  bool _busy = false;

  String _message(String? code) {
    switch (code) {
      case 'store_unavailable':
        return context.t('buyErrStore');
      case 'product_not_found':
        return context.t('buyErrProduct');
      case 'verification_unavailable':
        return context.t('buyErrVerify');
      case 'not_active':
        return context.t('buyErrNotActive');
      case 'token_in_use':
        return context.t('buyErrTokenUsed');
      case 'cancelled':
        return '';
      default:
        return context.t('buyErrGeneric');
    }
  }

  Future<void> _buy() async {
    setState(() => _busy = true);
    final started = await Billing.buy();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!started) {
      final msg = _message(Billing.lastError);
      if (msg.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
    // Success is NOT reported here: the purchase completes asynchronously
    // through Billing's stream after the server has verified it, and ProState
    // flipping is what the UI reacts to.
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ValueListenableBuilder<bool>(
      valueListenable: Billing.available,
      builder: (_, canBuy, __) => ValueListenableBuilder<bool>(
        valueListenable: ProState.isPro,
        builder: (_, isPro, __) {
          // No Buy button until the server can verify a purchase. Offering one
          // otherwise means Play charges the user and verification refuses —
          // a charge with nothing to show for it until Play's 3-day auto-refund.
          // Promo codes stay available either way.
          if (!canBuy && !isPro) return const SizedBox.shrink();
          if (isPro) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: c.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.accent.withOpacity(0.35)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_rounded, color: c.accent, size: 20),
              const SizedBox(width: 8),
              Text(context.t('proActive'),
                  style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ]),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accentFill,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : _buy,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(context.t('proBuyBtn'),
                    style:
                        const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          );
        },
      ),
    );
  }
}
