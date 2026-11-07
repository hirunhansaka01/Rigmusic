import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'tuner_screen.dart';
import 'chord_screen.dart';
import 'songbook_screen.dart';
import 'profile_screen.dart';

/// 5-tab bar matching the minimal design (HOME / TUNER / CHORDS / SONGS /
/// PROFILE). The SONGS tab is the single AI Song Finder (Oracle). TempoScreen
/// stays reachable via the dashboard Metronome card. No FAB in the new design.
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _tunerKey = GlobalKey<TunerScreenState>();

  void _go(int index) {
    setState(() => _currentIndex = index);
    // Reload HOME's song history/stats whenever the user returns to it, so
    // songs searched on the SONGS tab show up immediately.
    if (index == 0) _homeKey.currentState?.refresh();
    // The tuner has no mic button: the mic engages whenever the TUNER tab is
    // visible and is released the moment the user switches away (privacy +
    // battery). Rapid tab switches are guarded inside startMic/stopMic.
    if (index == 1) {
      _tunerKey.currentState?.startMic();
    } else {
      _tunerKey.currentState?.stopMic();
    }
  }

  late final _screens = [
    HomeScreen(key: _homeKey, onNavigate: _go),
    TunerScreen(key: _tunerKey),
    const ChordScreen(),
    const SongbookScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.grid_view, 'HOME'),
              _navItem(1, Icons.tune, 'TUNER'),
              _navItem(2, Icons.grid_on, 'CHORDS'),
              _navItem(3, Icons.menu_book, 'SONGS'),
              _navItem(4, Icons.account_circle, 'PROFILE'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => _go(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 21,
              color: isActive ? AppColors.accent : AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? AppColors.accent : AppColors.onSurfaceVariant.withValues(alpha: 0.75),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
