import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants/app_colors.dart';

/// Bloco base de skeleton com shimmer.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton de lista de cards — substitui CircularProgressIndicator
/// nas listas principais enquanto os dados carregam.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 84,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border,
      highlightColor: AppColors.surfaceSubtle,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, i) => const SizedBox(height: 10),
        itemBuilder: (_, i) => SkeletonBox(height: itemHeight, radius: 12),
      ),
    );
  }
}

/// Skeleton do topo de dashboard: linha de stat cards + bloco de gráfico.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border,
      highlightColor: AppColors.surfaceSubtle,
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 110, radius: 14)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 110, radius: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 110, radius: 14)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 110, radius: 14)),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 220, radius: 14),
        ],
      ),
    );
  }
}
