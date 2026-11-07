import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final Color? iconColor;
  final VoidCallback? onTrailingTap;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.iconColor,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.secondary),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        if (trailing != null)
          GestureDetector(
            onTap: onTrailingTap,
            child: Text(
              trailing!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: iconColor ?? AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}
