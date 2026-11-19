import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../l10n/translation_service.dart';
import '../models/branch.dart';
import '../open_link.dart';
import '../review/review_message.dart';
import '../review/review_once.dart';
import '../responsive.dart';
import '../review/review_sender.dart';
import '../theme/current_theme.dart';
import '../theme/theme_config.dart';
import '../widgets/star_rating.dart';

/// Открыть форму отзыва поверх текущего экрана.
///
/// Диалогом посередине, а не шторкой снизу: шторка — для продолжения
/// того, что уже на экране (корзина, оформление заказа), а отзыв ни с чем
/// на экране не связан. К тому же полей всего четыре — внизу экрана форма
/// выглядела бы оборванной.
///
/// Функция живёт здесь, а не в экране меню, как корзина: зовут её из
/// одного места — с верхнего экрана филиала.
void showReviewForm(
  BuildContext context, {
  required Branch branch,
  required ReviewSender sender,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => ReviewDialog(branch: branch, sender: sender),
  );
}

/// Отзыв гостя: звёзды и три необязательных поля.
///
/// Обязательных полей нет вовсе, поэтому нет и красных ошибок: кнопка просто
/// не нажимается, пока не поставлена оценка — без неё отправлять нечего.
class ReviewDialog extends StatefulWidget {
  final Branch branch;
  final ReviewSender sender;

  const ReviewDialog({super.key, required this.branch, required this.sender});

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final _waiter = TextEditingController();
  final _table = TextEditingController();
  final _comment = TextEditingController();

  int _rating = 0;
  bool _sent = false;

  /// Отзыв не записался на сервере. Красным это гостю не показываем: он уже
  /// нажал «Отправить», и ругаться поздно и не за что
  String? _notice;

  /// Ссылка на переписку — чтобы открыть её ещё раз, если окно заблокировали
  String? _lastLink;

  @override
  void dispose() {
    _waiter.dispose();
    _table.dispose();
    _comment.dispose();
    super.dispose();
  }

  ReviewDraft _draft() => ReviewDraft(
    rating: _rating,
    waiter: _waiter.text.trim(),
    tableNo: _table.text.trim(),
    comment: _comment.text.trim(),
  );

  /// ВАЖНО: метод НЕ async и до открытия ссылки не содержит ни одного
  /// `await`. Браузер открывает новую вкладку только внутри жеста гостя;
  /// после любого ожидания Safari её молча блокирует. Поэтому ссылка
  /// открывается первой строкой внутри `submit`, а результат запроса
  /// приходит потом и ни на что уже не влияет.
  void _submit() {
    if (_rating == 0) return;
    final draft = _draft();
    _lastLink = widget.sender.linkFor(draft, widget.branch);
    final saving = widget.sender.submit(
      draft,
      branch: widget.branch,
      lang: currentLocale.value.languageCode,
    );
    setState(() => _sent = true);
    // Отзыв одноразовый — помним это сразу, не дожидаясь ответа сервера:
    // ссылка в WhatsApp уже открыта, и второй отзыв был бы дублем
    unawaited(rememberReview(widget.branch.id));
    unawaited(saving.then(_onSaved, onError: (_) => _onSaved(false)));
  }

  void _onSaved(bool ok) {
    if (!mounted || ok) return;
    setState(() => _notice = AppLocalizations.of(context).reviewFailed);
  }

  void _openAgain() {
    final link = _lastLink;
    if (link != null) openLink(link);
  }

  @override
  Widget build(BuildContext context) {
    final config = appTheme.value;
    final l = AppLocalizations.of(context);
    final screen = MediaQuery.sizeOf(context);
    final inset = Responsive.isWide(screen) ? 20.0 : 15.0;
    // Ширина желаемая, но не больше экрана; на широком мониторе форма из
    // четырёх полей во всю ширину смотрелась бы нелепо
    final width = math.min(460.0, screen.width - inset * 2);
    return Dialog(
      backgroundColor: Colors.transparent,
      // Dialog сам поднимает содержимое над клавиатурой
      insetPadding: EdgeInsets.all(inset),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: config.surface,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: config.accent.withValues(alpha: 0.5)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(25, 20, 25, 25),
          child: _sent ? _done(config, l) : _form(config, l),
        ),
      ),
    );
  }

  Widget _title(ThemeConfig config, String text) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Text(
          text,
          style: GoogleFonts.cormorantGaramond(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: config.accent,
          ),
        ),
      ),
      IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.close_rounded, size: 26, color: config.text),
      ),
    ],
  );

  Widget _form(ThemeConfig config, AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _title(config, l.reviewTitle),
      const SizedBox(height: 6),
      Text(
        l.reviewRatingHint,
        style: TextStyle(color: config.text.withValues(alpha: 0.7), fontSize: 15),
      ),
      const SizedBox(height: 10),
      Center(
        child: StarRating(
          value: _rating,
          color: config.accent,
          onChanged: (v) => setState(() => _rating = v),
        ),
      ),
      const SizedBox(height: 18),
      _field(config, _waiter, l.reviewWaiter, icon: Icons.person_outline, maxLength: 60),
      _field(
        config,
        _table,
        l.reviewTable,
        icon: Icons.table_restaurant_outlined,
        maxLength: 20,
      ),
      _field(
        config,
        _comment,
        l.reviewComment,
        icon: Icons.chat_bubble_outline,
        maxLength: 1000,
        lines: 3,
      ),
      const SizedBox(height: 6),
      ElevatedButton(
        // Пока нет оценки, отправлять нечего. Это не «ошибка поля», а
        // просто незаконченная форма, поэтому красного ничего нет
        onPressed: _rating == 0 ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: config.accent,
          foregroundColor: config.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          widget.sender.opensWhatsapp ? l.sendToWhatsapp : l.sendReview,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    ],
  );

  Widget _field(
    ThemeConfig config,
    TextEditingController controller,
    String label, {
    required IconData icon,
    int? maxLength,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      keyboardType: lines > 1 ? TextInputType.multiline : TextInputType.text,
      textCapitalization: TextCapitalization.sentences,
      minLines: lines,
      // Многострочное поле растёт, а не прокручивается внутри себя.
      // Иначе в настольном браузере поверх последних букв ложится полоса
      // прокрутки: она всегда прижата к краю текста, и отступом её не
      // отодвинуть — отступ двигает и текст, и полосу. Прокручивается
      // теперь сам диалог, а у него по краям есть отбивка, в которой
      // полосе есть где встать
      maxLines: lines > 1 ? null : 1,
      maxLength: maxLength,
      // Счётчик под каждым полем только мешает — предел всё равно сработает
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      style: TextStyle(color: config.text),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: config.text.withValues(alpha: 0.6)),
        labelStyle: TextStyle(color: config.text.withValues(alpha: 0.7)),
        filled: true,
        fillColor: config.bg.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _done(ThemeConfig config, AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _title(config, l.reviewTitle),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: config.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              // Без номера WhatsApp не открывался, и просить «нажмите
              // Отправить» было бы неправдой
              widget.sender.opensWhatsapp
                  ? l.reviewSentWhatsappHint
                  : l.reviewSentHint,
              style: TextStyle(color: config.text, fontSize: 16),
            ),
          ),
        ],
      ),
      if (_notice != null) ...[
        const SizedBox(height: 14),
        Text(
          _notice!,
          style: TextStyle(
            color: config.text.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
      ],
      const SizedBox(height: 20),
      if (_lastLink != null)
        OutlinedButton.icon(
          onPressed: _openAgain,
          icon: const Icon(Icons.open_in_new, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: config.text,
            side: BorderSide(color: config.text.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          label: Text(l.openWhatsappAgain),
        ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          l.close,
          style: TextStyle(color: config.text.withValues(alpha: 0.6)),
        ),
      ),
    ],
  );
}
