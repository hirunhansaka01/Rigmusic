import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'edit_profile_screen.dart';

/// Minimal profile (profile_minimal). Sign-out + Edit navigation preserved;
/// toggles are local state; name streams from `profiles/{uid}`.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  var _calibration = true;
  var _haptic = true;
  var _offline = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?.uid;
    final email = auth.email ?? 'you@example.com';
    final fallback = auth.displayNameFallback('Guitarist');
    if (uid == null) return _body(context, <String, dynamic>{}, fallback, email);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('profiles').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final raw = data['display_name'];
        final name = (raw is String && raw.trim().isNotEmpty) ? raw.trim() : fallback;
        return _body(context, data, name, email);
      },
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> data, String name, String email) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          children: [
            _header(),
            const SizedBox(height: 12),
            _hero(context, data, name),
            const SizedBox(height: 20),
            _stats(data),
            const SizedBox(height: 20),
            _gear(data),
            const SizedBox(height: 20),
            _preferences(),
            const SizedBox(height: 20),
            _account(email),
            const SizedBox(height: 16),
            const Text('Rig Music • Version 2.4.0',
                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.music_note, size: 14, color: AppColors.onSurface),
          ),
          const SizedBox(width: 10),
          const Text('Rig Music',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
          const Spacer(),
          const Icon(Icons.tune, size: 19, color: AppColors.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, Map<String, dynamic> data, String name) {
    final photo = data['photo'];
    final Uint8List? photoBytes = photo is String ? _decodeDataUrl(photo) : null;
    final bio = (data['bio'] is String && (data['bio'] as String).trim().isNotEmpty)
        ? (data['bio'] as String).trim()
        : 'Guitarist on Rig Music';
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceContainerHigh,
                border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: photoBytes != null
                  ? Image.memory(photoBytes, fit: BoxFit.cover)
                  : const Icon(Icons.person, size: 40, color: AppColors.onSurfaceVariant),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.tertiary,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(bio,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit, size: 12, color: AppColors.onSurfaceVariant),
                SizedBox(width: 6),
                Text('Edit Profile', style: TextStyle(fontSize: 12, color: AppColors.onSurface)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Uint8List? _decodeDataUrl(String url) {
    try {
      final comma = url.indexOf(',');
      if (comma == -1) return null;
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  String _stat(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v is int) return '$v';
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return '—';
  }

  Widget _stats(Map<String, dynamic> data) {
    return Row(
      children: [
        _statCard('${_stat(data, 'streak_days')} Days', 'Streak'),
        const SizedBox(width: 10),
        _statCard(_stat(data, 'total_practice_min'), 'Practice Min'),
        const SizedBox(width: 10),
        _statCard(_stat(data, 'level'), 'Level'),
      ],
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _gear(Map<String, dynamic> data) {
    final guitar = (data['primary_guitar'] is String &&
            (data['primary_guitar'] as String).trim().isNotEmpty)
        ? (data['primary_guitar'] as String).trim()
        : 'No guitar added yet';
    final tuning = (data['default_tuning'] is String &&
            (data['default_tuning'] as String).trim().isNotEmpty)
        ? (data['default_tuning'] as String).trim()
        : 'Standard';
    final instrument = (data['instrument'] is String &&
            (data['instrument'] as String).trim().isNotEmpty)
        ? (data['instrument'] as String).trim()
        : 'Acoustic';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('GEAR & TUNING',
                style: TextStyle(fontSize: 11, letterSpacing: 1.0, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant)),
            GestureDetector(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
              child: const Text('Edit', style: TextStyle(fontSize: 12, color: AppColors.tertiary)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainer,
                ),
                child: const Icon(Icons.music_note, size: 16, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(guitar,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                    Text('$tuning • $instrument',
                        style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.circle, size: 8, color: AppColors.tertiary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preferences() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PREFERENCES & AUDIO',
            style: TextStyle(fontSize: 11, letterSpacing: 1.0, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              _toggleRow(
                'Tuner Calibration',
                'Concert Pitch A = 440 Hz',
                _calibration,
                (v) => setState(() => _calibration = v),
                last: false,
              ),
              _toggleRow(
                'Haptic Feedback',
                'Vibrate on accurate pitch detection',
                _haptic,
                (v) => setState(() => _haptic = v),
                last: false,
              ),
              _toggleRow(
                'Offline Mode',
                'Cache songbook and audio engine offline',
                _offline,
                (v) => setState(() => _offline = v),
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged,
      {required bool last}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: value
                    ? AppColors.tertiary.withValues(alpha: 0.2)
                    : AppColors.surfaceContainer,
                border: Border.all(
                    color: value
                        ? AppColors.tertiary.withValues(alpha: 0.4)
                        : AppColors.outlineVariant),
              ),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? AppColors.tertiary : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _account(String email) {
    final auth = context.read<AuthProvider>();
    final guest = auth.isGuest && auth.user == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ACCOUNT',
            style: TextStyle(fontSize: 11, letterSpacing: 1.0, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(guest ? 'Guest Mode' : 'Signed In',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                          Text(
                              guest
                                  ? 'Progress saved on this device'
                                  : '${auth.providerLabel} ($email)',
                              style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Text(guest ? 'Local' : 'Synced',
                        style: TextStyle(
                            fontSize: 11,
                            color: guest ? AppColors.onSurfaceVariant : AppColors.tertiary)),
                  ],
                ),
              ),
              if (guest)
                _accountAction(
                  label: 'Sign in to sync progress',
                  icon: Icons.login,
                  color: AppColors.tertiary,
                  onTap: () async {
                    // Exit guest mode and return to the login screen.
                    await auth.signOut();
                    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.3))),
                  ),
                  child: _accountAction(
                    label: 'Sign Out',
                    icon: Icons.logout,
                    color: const Color(0xFFFB7185),
                    onTap: () async {
                      await auth.signOut();
                      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
            Icon(icon, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
