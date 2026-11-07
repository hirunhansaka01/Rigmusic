import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'auth_gate.dart';

/// Launch splash — shows the Rig Music logo with a glow pulse + staggered
/// text reveal, then hands off to the auth gate.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  // Staggered reveal driven by the same controller.
  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
  );
  late final Animation<double> _titleSlide = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _tagSlide = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.5, 0.9, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _dots = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
  );

  // Continuous glow pulse behind the logo (loops forever).
  late final AnimationController _glowC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);
  late final Animation<double> _glow = CurvedAnimation(
    parent: _glowC,
    curve: Curves.easeInOut,
  );

  Timer? _nav;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _nav = Timer(const Duration(milliseconds: 2600), _go);
  }

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  @override
  void dispose() {
    _nav?.cancel();
    _c.dispose();
    _glowC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = (size.width * 0.34).clamp(120.0, 220.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 0.9,
            colors: [Color(0xFF241E3A), AppColors.background],
            stops: [0.0, 0.7],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo + glow
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: SizedBox(
                    width: logoSize * 1.6,
                    height: logoSize * 1.6,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulsing glow halo
                        FadeTransition(
                          opacity: Tween(begin: 0.15, end: 0.5).animate(_glow),
                          child: ScaleTransition(
                            scale: Tween(begin: 0.9, end: 1.08).animate(_glow),
                            child: Container(
                              width: logoSize * 1.5,
                              height: logoSize * 1.5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppColors.accent.withValues(alpha: 0.35),
                                    blurRadius: 60,
                                    spreadRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // The logo itself
                        Container(
                          width: logoSize,
                          height: logoSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(logoSize * 0.22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.music_note_rounded,
                              size: 64,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Title
              FadeTransition(
                opacity: _titleSlide,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(_titleSlide),
                  child: const Text(
                    'RIG MUSIC',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Tagline
              FadeTransition(
                opacity: _tagSlide,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.6),
                    end: Offset.zero,
                  ).animate(_tagSlide),
                  child: const Text(
                    'ACOUSTIC STUDIO',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 6,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Loading dots
              FadeTransition(
                opacity: _dots,
                child: _PulseDots(animation: _glow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three dots that pulse in sequence to signal loading.
class _PulseDots extends StatelessWidget {
  final Animation<double> animation;
  const _PulseDots({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (t + i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).abs();
            final scale = 0.7 + 0.5 * (1 - (phase - 0.5).abs() * 2).abs();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: opacity),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
