import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Reusable ambient background blurs used across all screens
class ArcaneBackground extends StatelessWidget {
  const ArcaneBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: _blur(260, 260, AppColors.primaryContainer.withValues(alpha: 0.08)),
          ),
          Positioned(
            top: 200,
            right: -60,
            child: _blur(280, 280, AppColors.secondary.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: 200,
            left: 80,
            child: _blur(300, 300, AppColors.tertiaryContainer.withValues(alpha: 0.06)),
          ),
        ],
      ),
    );
  }

  Widget _blur(double w, double h, Color color) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
