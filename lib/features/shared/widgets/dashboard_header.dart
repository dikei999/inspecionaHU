import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../../core/constants/app_colors.dart';

/// Cabeçalho institucional dos dashboards: bloco azul flat com canto
/// inferior arredondado (24px), saudação em Sora branco, ações em branco
/// e espaço para indicadores em versão clara. A linha fina verde na base
/// é o ÚNICO uso decorativo do verde da marca.
class DashboardHeader extends StatelessWidget {
  final String greeting;
  final String? subtitle;
  final List<Widget> actions;

  /// Conteúdo claro exibido dentro do bloco (donut/indicadores).
  final Widget? child;

  const DashboardHeader({
    super.key,
    required this.greeting,
    this.subtitle,
    this.actions = const [],
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ClipRRect(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: Container(
        color: AppColors.primary,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Ações (sino, perfil, sair) em branco sobre o azul.
                    IconTheme(
                      data: const IconThemeData(color: Colors.white, size: 24),
                      child: IconButtonTheme(
                        data: IconButtonThemeData(
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: actions,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (child != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: child,
                ),
              const SizedBox(height: 16),
              // Linha fina da marca — único uso decorativo do verde.
              Container(height: 3, color: AppColors.brandGreen),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Indicador numérico claro para uso dentro do [DashboardHeader]:
/// número forte em Sora + rótulo discreto em Manrope.
class HeaderMetric extends StatelessWidget {
  final String value;
  final String label;

  const HeaderMetric({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}
