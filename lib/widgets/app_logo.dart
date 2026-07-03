import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_colors.dart';

/// Logo do InspecionaHU — peso forte + letterSpacing negativo.
/// [onDark] inverte as cores para uso sobre o gradiente institucional.
class AppLogo extends StatelessWidget {
  final double fontSize;
  final bool onDark;
  final bool showIcon;

  const AppLogo({
    super.key,
    this.fontSize = 28,
    this.onDark = false,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = onDark ? Colors.white : AppColors.textPrimary;
    final accentColor = onDark ? Colors.white : AppColors.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          Container(
            padding: EdgeInsets.all(fontSize * 0.28),
            decoration: BoxDecoration(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : AppColors.primary50,
              borderRadius: BorderRadius.circular(fontSize * 0.42),
              border: Border.all(
                color: onDark
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppColors.primary100,
                width: 1,
              ),
            ),
            child: Icon(
              Icons.health_and_safety_outlined,
              size: fontSize * 1.05,
              color: accentColor,
            ),
          ),
          SizedBox(width: fontSize * 0.45),
        ],
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Inspeciona',
                style: GoogleFonts.inter(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -fontSize * 0.045,
                  color: baseColor,
                  height: 1,
                ),
              ),
              TextSpan(
                text: 'HU',
                style: GoogleFonts.inter(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -fontSize * 0.03,
                  color: onDark ? const Color(0xFF93B4F5) : AppColors.primary,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
