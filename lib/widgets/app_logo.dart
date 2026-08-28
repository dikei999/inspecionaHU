import 'package:flutter/material.dart';

/// Marca institucional do InspecionaHU (HU-UFPI/EBSERH).
/// [AppLogoVariant.full] = logo completa; [AppLogoVariant.iconOnly] = marca compacta.
enum AppLogoVariant { full, iconOnly }

class AppLogo extends StatelessWidget {
  final AppLogoVariant variant;
  final double height;

  const AppLogo({
    super.key,
    this.variant = AppLogoVariant.iconOnly,
    this.height = 32,
  });

  @override
  Widget build(BuildContext context) {
    final asset = variant == AppLogoVariant.full
        ? 'assets/branding/logo_full.png'
        : 'assets/branding/icon_mark.png';
    return Image.asset(asset, height: height, fit: BoxFit.contain);
  }
}
