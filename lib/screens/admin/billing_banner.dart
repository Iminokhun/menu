import 'package:flutter/material.dart';

import '../../api/api_client.dart';

/// Полоса об оплате над админкой кафе. Видна, только когда срок подходит
/// к концу или прошёл; при обычной оплате и «навсегда» её нет.
class BillingBanner extends StatefulWidget {
  const BillingBanner({super.key});

  @override
  State<BillingBanner> createState() => _BillingBannerState();
}

class _BillingBannerState extends State<BillingBanner> {
  Me? _me = api.me;

  @override
  void initState() {
    super.initState();
    // Срок мог измениться после входа — например, владелец платформы
    // только что отметил оплату
    api.refreshMe().then((me) {
      if (mounted) setState(() => _me = me);
    }).catchError((_) {
      // Нет связи — показываем то, что было при входе
    });
  }

  static String _ruDate(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (me == null || me.cafeId == null || me.access == 'ok') return const SizedBox.shrink();

    final until = _ruDate(me.paidUntil);
    final left = me.daysLeft ?? 0;
    final off = me.menuOffIn ?? 0;
    final contact = me.billingContact.isEmpty ? '' : ' Оплата: ${me.billingContact}';
    final (color, icon, text) = switch (me.access) {
      'ending' => (
          Colors.orangeAccent,
          Icons.schedule,
          '${me.plan == 'trial' ? 'Пробный период' : 'Оплата'} до $until — осталось $left дн.$contact',
        ),
      'grace' => (
          Colors.deepOrangeAccent,
          Icons.warning_amber_rounded,
          'Оплата просрочена с $until. Через $off дн. меню у гостей выключится.$contact',
        ),
      _ => (
          Colors.redAccent,
          Icons.block,
          'Оплата просрочена — меню у гостей выключено, изменения недоступны.$contact',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
