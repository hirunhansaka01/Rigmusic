import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A consistent, unobtrusive status message for authentication screens.
void showAuthMessage(BuildContext context, String message, {bool error = true}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: error ? AppColors.errorContainer : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: error ? AppColors.error.withValues(alpha: 0.55) : AppColors.secondary.withValues(alpha: 0.35),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: error ? AppColors.onErrorContainer : AppColors.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: error ? AppColors.onErrorContainer : AppColors.onSurface, height: 1.25)),
            ),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: messenger.hideCurrentSnackBar,
              icon: Icon(Icons.close_rounded, color: error ? AppColors.onErrorContainer : AppColors.onSurfaceVariant, size: 18),
            ),
          ],
        ),
      ),
    ),
  );
}
