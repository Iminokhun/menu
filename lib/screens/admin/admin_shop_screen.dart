import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../image_upload.dart';

class AdminShopScreen extends StatefulWidget {
  const AdminShopScreen({super.key});

  @override
  State<AdminShopScreen> createState() => _AdminShopScreenState();
}

class _AdminShopScreenState extends State<AdminShopScreen> {
  final _client = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _qrUrlCtrl = TextEditingController();
  String _logoUrl = '';
  bool _loading = true;
  bool _saving = false;

  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sloganCtrl.dispose();
    _phoneCtrl.dispose();
    _qrUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _client.from('shop').select().single();
      setState(() {
        _nameCtrl.text = data['name'] ?? '';
        _sloganCtrl.text = data['slogan'] ?? '';
        _phoneCtrl.text = data['phone'] ?? '';
        _logoUrl = data['logo_url'] ?? '';
        _qrUrlCtrl.text = data['qr_url'] ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<String?> _uploadImage(String prefix) async {
    try {
      return await pickAndUploadImage('${prefix}_');
    } catch (e) {
      _toast('Ошибка загрузки: $e', isError: true);
      return null;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _client.from('shop').update({
        'name': _nameCtrl.text.trim(),
        'slogan': _sloganCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'logo_url': _logoUrl,
        'qr_url': _qrUrlCtrl.text.trim(),
      }).eq('id', 1);
      _toast('Настройки сохранены!');
    } catch (e) {
      _toast('Ошибка сохранения: $e', isError: true);
    }
    setState(() => _saving = false);
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _field(TextEditingController c, String label, {IconData? icon}) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: icon != null ? Icon(icon, color: Colors.white38, size: 20) : null,
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
      ),
    );
  }

  Widget _qrCard() {
    final link = _qrUrlCtrl.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ссылка на меню (для QR-кода)',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('QR-код создаётся автоматически из этой ссылки',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 12),
          TextField(
            controller: _qrUrlCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'https://ваш-сайт.web.app',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.link, color: Colors.white38, size: 20),
              enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: link.isEmpty
                  ? const SizedBox(
                      width: 140,
                      height: 140,
                      child: Icon(Icons.qr_code_2, size: 70, color: Colors.black26),
                    )
                  : QrImageView(
                      data: link,
                      version: QrVersions.auto,
                      size: 140,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageCard(String label, String url, String prefix, VoidCallback onUploaded) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (url.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(url, height: 120, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24, size: 60)),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final newUrl = await _uploadImage(prefix);
                if (newUrl != null) {
                  setState(() {
                    if (prefix == 'logo') _logoUrl = newUrl;
                  });
                }
              },
              icon: const Icon(Icons.cloud_upload_outlined, color: _accent, size: 18),
              label: Text(url.isNotEmpty ? 'Заменить' : 'Загрузить', style: const TextStyle(color: _accent)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _accent)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        automaticallyImplyLeading: false,
        title: Text('Настройки магазина', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Основные данные
                  Text('ОСНОВНОЕ', style: GoogleFonts.manrope(color: Colors.white38, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _field(_nameCtrl, 'Название заведения', icon: Icons.storefront_outlined),
                  const SizedBox(height: 12),
                  _field(_sloganCtrl, 'Слоган / Подзаголовок', icon: Icons.format_quote_outlined),
                  const SizedBox(height: 12),
                  _field(_phoneCtrl, 'Телефон', icon: Icons.phone_outlined),
                  const SizedBox(height: 30),

                  // Логотип
                  Text('ЛОГОТИП', style: GoogleFonts.manrope(color: Colors.white38, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _imageCard('Логотип заведения', _logoUrl, 'logo', () {}),
                  const SizedBox(height: 30),

                  // QR-код меню
                  Text('QR-КОД МЕНЮ', style: GoogleFonts.manrope(color: Colors.white38, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _qrCard(),
                  const SizedBox(height: 40),

                  // Кнопка сохранить
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _saving ? 'Сохранение...' : 'СОХРАНИТЬ',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
