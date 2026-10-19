import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Наклейка на стол: название, крупный QR-код и подсказка гостю.
/// Один лист A4 — его печатают как есть или отдают в типографию.
@visibleForTesting
Future<Uint8List> buildQrSticker({
  required String title,
  required String link,
}) async {
  // Шрифт из самого приложения, а не из интернета: иначе на планшете
  // без сети PDF не собрался бы
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Bold.ttf'));

  final doc = pw.Document(title: 'QR-код меню — $title');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    build: (_) => pw.Center(
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(title,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Text('МЕНЮ', style: const pw.TextStyle(fontSize: 18, letterSpacing: 6)),
          pw.SizedBox(height: 30),
          pw.BarcodeWidget(
            // Высокая коррекция ошибок: код читается, даже если наклейку
            // поцарапают или испачкают
            barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high),
            data: link,
            // Подпись под кодом рисовалась бы шрифтом без кириллицы;
            // ссылка и так напечатана ниже отдельной строкой
            drawText: false,
            width: 12 * PdfPageFormat.cm,
            height: 12 * PdfPageFormat.cm,
          ),
          pw.SizedBox(height: 30),
          pw.Text('Наведите камеру телефона на код,\nчтобы открыть меню',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 14),
          pw.Text(link,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        ],
      ),
    ),
  ));
  return doc.save();
}

/// Открывает системное окно печати. Там же можно «Сохранить как PDF».
Future<void> printQrSticker({required String title, required String link}) =>
    Printing.layoutPdf(
      name: 'QR-$title',
      onLayout: (_) => buildQrSticker(title: title, link: link),
    );

/// В браузере скачивает PDF, на планшете открывает «Поделиться»:
/// отправить в мессенджер, на почту или сохранить в файлы.
Future<void> downloadQrSticker({required String title, required String link}) async {
  final bytes = await buildQrSticker(title: title, link: link);
  await Printing.sharePdf(bytes: bytes, filename: 'qr-menu-$title.pdf');
}
