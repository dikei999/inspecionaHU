import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/utils/compliance_utils.dart';

/// Card branco padronizado para abrigar um gráfico de dashboard.
class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 11.5)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Anel de conformidade: segmentos C/NC/NA (cores de status) com a taxa
/// como número-herói no centro e legenda com contagens abaixo.
class ComplianceDonut extends StatelessWidget {
  final int compliant;
  final int nonCompliant;
  final int notApplicable;

  /// Versão clara para uso sobre fundo azul (header dos dashboards).
  final bool light;

  const ComplianceDonut({
    super.key,
    required this.compliant,
    required this.nonCompliant,
    required this.notApplicable,
    this.light = false,
  });

  /// Fonte unica: ComplianceUtils (C3). A formula estava reimplementada
  /// aqui — igual, mas duplicada.
  double get _rate => ComplianceUtils.taxa(
        compliant: compliant,
        nonCompliant: nonCompliant,
      );

  @override
  Widget build(BuildContext context) {
    final hasData = compliant + nonCompliant + notApplicable > 0;
    final rateColor = _rate >= 80
        ? AppColors.compliant
        : _rate >= 60
            ? AppColors.pending
            : AppColors.nonCompliant;

    return Column(
      children: [
        SizedBox(
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: 2,
                  centerSpaceRadius: 58,
                  sections: hasData
                      ? [
                          if (compliant > 0)
                            PieChartSectionData(
                              value: compliant.toDouble(),
                              color: AppColors.compliant,
                              radius: 22,
                              showTitle: false,
                            ),
                          if (nonCompliant > 0)
                            PieChartSectionData(
                              value: nonCompliant.toDouble(),
                              color: AppColors.nonCompliant,
                              radius: 22,
                              showTitle: false,
                            ),
                          if (notApplicable > 0)
                            PieChartSectionData(
                              value: notApplicable.toDouble(),
                              color: light
                                  ? Colors.white38
                                  : AppColors.borderStrong,
                              radius: 22,
                              showTitle: false,
                            ),
                        ]
                      : [
                          PieChartSectionData(
                            value: 1,
                            color: light ? Colors.white24 : AppColors.border,
                            radius: 22,
                            showTitle: false,
                          ),
                        ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasData ? '${_rate.toStringAsFixed(1)}%' : '—',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: light
                              ? Colors.white
                              : hasData
                                  ? rateColor
                                  : AppColors.textDisabled,
                          height: 1,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'conformidade',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: light ? Colors.white70 : null,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(
                color: AppColors.compliant,
                label: 'Conforme',
                count: compliant,
                light: light),
            const SizedBox(width: 16),
            _LegendItem(
                color: AppColors.nonCompliant,
                label: 'Não conforme',
                count: nonCompliant,
                light: light),
            const SizedBox(width: 16),
            _LegendItem(
                color: light ? Colors.white38 : AppColors.borderStrong,
                label: 'N/A',
                count: notApplicable,
                light: light),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final bool light;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label · $count',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: light
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

/// Barras de série única (uma cor) — ex.: inspeções por dia da semana.
/// Toque em uma barra mostra o valor (tooltip = hover no mobile).
class SingleSeriesBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final String tooltipSuffix;

  const SingleSeriesBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.color = AppColors.primary,
    this.tooltipSuffix = '',
  }) : assert(values.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final maxVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 4.0 : (maxVal * 1.25).ceilToDouble();

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (v) => const FlLine(
              color: AppColors.border,
              strokeWidth: 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textDisabled,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.textPrimary,
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                '${rod.toY.toInt()}$tooltipSuffix',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          barGroups: List.generate(values.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: 18,
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: AppColors.surfaceSubtle,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
