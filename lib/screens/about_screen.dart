import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AboutProstoScreen extends StatelessWidget {
  const AboutProstoScreen({super.key});

  // Цвета (хардкод для стиля Midnight)
  static const bgColor = Color(0xFF000000);
  static const accentColor = Color(0xFFD4AF37);
  static const textColor = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [accentColor.withValues(alpha: 0.15), bgColor],
                ),
              ),
            ),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: const Icon(Icons.code, size: 60, color: accentColor),
                ),
                const SizedBox(height: 30),

                Text(
                  "PROSTO",
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 54,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: accentColor,
                  ),
                ),
                Text(
                  "SOFTWARE SOLUTIONS",
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    letterSpacing: 5,
                    color: textColor.withValues(alpha: 0.5),
                  ),
                ),

                const SizedBox(height: 50),
                const Divider(
                  color: accentColor,
                  endIndent: 100,
                  indent: 100,
                  thickness: 0.5,
                ),
                const SizedBox(height: 50),

                Text(
                  "ТЕХНИЧЕСКАЯ ПОДДЕРЖКА",
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 15),

                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                      const ClipboardData(text: "+996553356666"),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Номер скопирован"),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 25,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone, color: accentColor, size: 20),
                        const SizedBox(width: 15),
                        Text(
                          "+996 553 35 66 66",
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Text(
                    "© 2026 PROSTO Corp.\nMade in Kyrgyzstan",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: textColor.withValues(alpha: 0.3),
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
}
