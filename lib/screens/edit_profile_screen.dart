import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_message.dart';

/// Edit profile. Loads the real `profiles/{uid}` doc from Firestore, edits
/// it, and saves it back. The photo is stored in Firestore as a base64 data
/// URL. Save shows the banner and writes for real.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _guitarCtrl = TextEditingController();
  final _spotifyCtrl = TextEditingController();
  final _soundCtrl = TextEditingController();
  String _instrument = 'Acoustic';
  String _tuning = 'Standard';
  final _styles = {'Fingerstyle': false, 'Acoustic Folk': false, 'Percussive': false, 'Blues': false};
  bool _visible = true;

  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;
  Uint8List? _photoBytes;
  String? _photoDataUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _handleCtrl.dispose();
    _bioCtrl.dispose();
    _guitarCtrl.dispose();
    _spotifyCtrl.dispose();
    _soundCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await ProfileService.instance.loadProfile(uid);
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = _asString(data['display_name']);
        _handleCtrl.text = _asString(data['username']);
        _bioCtrl.text = _asString(data['bio']);
        _guitarCtrl.text = _asString(data['primary_guitar']);
        _spotifyCtrl.text = _asString(data['spotify_url']);
        _soundCtrl.text = _asString(data['soundcloud_url']);
        final inst = _asString(data['instrument']);
        if (inst.isNotEmpty) _instrument = inst;
        final tun = _asString(data['default_tuning']);
        if (tun.isNotEmpty) _tuning = tun;
        final pub = data['public_profile'];
        if (pub is bool) _visible = pub;
        final styles = data['styles'];
        if (styles is List) {
          for (final k in _styles.keys) {
            _styles[k] = styles.contains(k);
          }
        }
        final photo = _asString(data['photo']);
        if (photo.isNotEmpty) {
          _photoDataUrl = photo;
          _photoBytes = _decodeDataUrl(photo);
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _asString(dynamic v) => v is String ? v : '';

  Uint8List? _decodeDataUrl(String url) {
    try {
      final comma = url.indexOf(',');
      if (comma == -1) return null;
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _photoBytes = bytes;
          _photoDataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        });
      }
    } catch (_) {
      if (mounted) showAuthMessage(context, 'Could not open photo library.', error: false);
    }
  }

  Future<void> _save() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) {
      showAuthMessage(context, 'Not signed in.', error: true);
      return;
    }
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    final name = _nameCtrl.text.trim();
    final styles = _styles.entries.where((e) => e.value).map((e) => e.key).toList();
    try {
      await ProfileService.instance.saveProfile(uid, {
        'display_name': name,
        'username': _handleCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'primary_guitar': _guitarCtrl.text.trim(),
        'instrument': _instrument,
        'default_tuning': _tuning,
        'styles': styles,
        'public_profile': _visible,
        'spotify_url': _spotifyCtrl.text.trim(),
        'soundcloud_url': _soundCtrl.text.trim(),
        if (_photoDataUrl != null && _photoDataUrl!.isNotEmpty) 'photo': _photoDataUrl,
      });
      // Keep the Firebase Auth display name in sync so the home greeting
      // and any other auth-based name reflect the edit.
      if (name.isNotEmpty) {
        try {
          await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _saving = false);
      // Brief confirmation, then pop back — the profile screen streams live
      // Firestore data, so it will already show the changes.
      setState(() => _saved = true);
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save changes. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceContainerLow,
                        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.arrow_back, size: 18, color: AppColors.onSurface),
                    ),
                  ),
                  const Expanded(
                    child: Text('Edit Profile',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  _photoSection(),
                  const SizedBox(height: 16),
                  _personalCard(),
                  const SizedBox(height: 16),
                  _gearCard(),
                  const SizedBox(height: 16),
                  _privacyCard(),
                  const SizedBox(height: 16),
                  _actions(),
                  if (_error != null) _errorBanner(),
                  if (_saved) _savedBanner(),
                ],
              ),
            ),
    );
  }

  Widget _photoSection() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceContainerLow,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 2),
              ),
              child: _photoBytes != null
                  ? ClipOval(child: Image.memory(_photoBytes!, fit: BoxFit.cover))
                  : const Icon(Icons.person, size: 48, color: AppColors.onSurfaceVariant),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                  child: const Icon(Icons.photo_camera, size: 14, color: AppColors.onPrimary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickPhoto,
          child: const Text('Change Photo',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary)),
        ),
      ],
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _personalCard() {
    return _sectionCard('PERSONAL INFORMATION', [
      _label('Full Name'),
      const SizedBox(height: 6),
      _field(_nameCtrl),
      const SizedBox(height: 12),
      _label('Username'),
      const SizedBox(height: 6),
      _field(_handleCtrl, prefix: '@'),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _label('Bio'),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _bioCtrl,
            builder: (_, v, __) => Text('${v.text.length}/250',
                style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _field(_bioCtrl, maxLines: 3, maxLength: 250),
    ]);
  }

  Widget _gearCard() {
    return _sectionCard('GUITARS & GEAR', [
      _label('Primary Guitar'),
      const SizedBox(height: 6),
      _field(_guitarCtrl),
      const SizedBox(height: 12),
      _label('Instrument Type'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ['Acoustic', 'Electric', 'Classical', 'Bass'].map((t) {
          final sel = t == _instrument;
          return GestureDetector(
            onTap: () => setState(() => _instrument = t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: sel ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sel) const Icon(Icons.check, size: 12, color: AppColors.onPrimary),
                  if (sel) const SizedBox(width: 4),
                  Text(t,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: sel ? AppColors.onPrimary : AppColors.onSurface)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      _label('Default Tuning'),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [
          _tuningTile('Standard', 'E A D G B E'),
          _tuningTile('Drop D', 'D A D G B E'),
          _tuningTile('DADGAD', 'Celtic / Folk'),
          _tuningTile('Open D', 'D A D F# A D'),
        ],
      ),
      const SizedBox(height: 12),
      _label('Playing Styles'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _styles.keys.map((s) {
          final sel = _styles[s]!;
          return GestureDetector(
            onTap: () => setState(() => _styles[s] = !sel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: sel
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Text(s,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: sel ? AppColors.primary : AppColors.onSurfaceVariant)),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  Widget _tuningTile(String name, String notes) {
    final sel = name == _tuning;
    return GestureDetector(
      onTap: () => setState(() => _tuning = name),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? AppColors.primary.withValues(alpha: 0.6) : AppColors.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                  Text(notes, style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            if (sel) const Icon(Icons.check, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _privacyCard() {
    return _sectionCard('CONNECTED ACCOUNTS & PRIVACY', [
      Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Public Profile',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                Text('Make your repertoire and recordings discoverable',
                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _visible = !_visible),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: _visible ? AppColors.primary : AppColors.surfaceContainerHigh,
              ),
              alignment: _visible ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerLowest,
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _label('Spotify Artist Link'),
      const SizedBox(height: 6),
      _field(_spotifyCtrl,
          prefixIcon: const Icon(Icons.podcasts, size: 16, color: AppColors.onSurfaceVariant)),
      const SizedBox(height: 12),
      _label('SoundCloud or YouTube'),
      const SizedBox(height: 6),
      _field(_soundCtrl,
          prefixIcon: const Icon(Icons.graphic_eq, size: 16, color: AppColors.onSurfaceVariant)),
    ]);
  }

  Widget _actions() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: _saving ? null : () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: const Text('Cancel',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: _saving ? AppColors.primary.withValues(alpha: 0.6) : AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _saving
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, size: 16, color: AppColors.onPrimary),
                          SizedBox(width: 6),
                          Text('Save Changes',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onPrimary)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 16, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _savedBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(children: [
        Icon(Icons.check_circle, size: 16, color: AppColors.tertiary),
        SizedBox(width: 8),
        Text('Profile saved.',
            style: TextStyle(fontSize: 12, color: AppColors.tertiary, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _label(String text) {
    return Text(text, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant));
  }

  Widget _field(
    TextEditingController controller, {
    String? prefix,
    Widget? prefixIcon,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (prefix != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(prefix, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ),
          if (prefixIcon != null)
            Padding(padding: const EdgeInsets.only(left: 12), child: prefixIcon),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              maxLength: maxLength,
              buildCounter: (context,
                      {required currentLength, required isFocused, maxLength}) =>
                  const SizedBox.shrink(),
              style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
