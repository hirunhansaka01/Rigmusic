import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

/// Minimal login (login_minimal): DM Sans, mint primary button,
/// Google / Apple / Guest rows, Sign-up footer. Auth wiring unchanged.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loggingIn = false;
  String? _socialBusy; // 'google' | 'apple' — which social button is spinning.
  bool _keepSignedIn = true;
  String? _error;
  late final AnimationController _errorController;

  @override
  void initState() {
    super.initState();
    _errorController = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _error = null);
        }
      });
    _restoreKeepSignedIn();
  }

  /// Loads the stored "Keep me signed in" choice so the checkbox reflects
  /// what the user last picked (default: on — the original behaviour).
  Future<void> _restoreKeepSignedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keep = prefs.getBool('keep_signed_in') ?? true;
      if (mounted && keep != _keepSignedIn) {
        setState(() => _keepSignedIn = keep);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _errorController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _error = message);
    _errorController.forward(from: 0);
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (!email.contains('@') || password.isEmpty) {
      _showError('Enter a valid email address or password.');
      return;
    }
    setState(() => _loggingIn = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(email, password);
    if (!mounted) return;
    setState(() => _loggingIn = false);
    if (!ok) {
      _showError(auth.error ?? 'Login failed.');
      return;
    }
    // AuthGate rebuilds to MainScaffold automatically.
  }

  void _guest() {
    // Persistent local guest session; AuthGate rebuilds into the app.
    context.read<AuthProvider>().continueAsGuest();
  }

  Future<void> _socialLogin(Future<bool> Function() run, String which) async {
    setState(() => _socialBusy = which);
    final auth = context.read<AuthProvider>();
    final ok = await run();
    if (!mounted) return;
    setState(() => _socialBusy = null);
    // Cancel is silent (auth.error stays null); real failures show a banner.
    if (!ok && auth.error != null) _showError(auth.error!);
    // On success AuthGate rebuilds to MainScaffold automatically.
  }

  Future<void> _google() => _socialLogin(
        () => context.read<AuthProvider>().signInWithGoogle(),
        'google',
      );

  Future<void> _apple() => _socialLogin(
        () => context.read<AuthProvider>().signInWithApple(),
        'apple',
      );

  void _showForgotPassword() {
    showDialog(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _emailCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().isBusy;
    final disabled = busy || _loggingIn || _socialBusy != null;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const Icon(Icons.music_note, size: 40, color: AppColors.accent),
              ),
              const SizedBox(height: 16),
              Text('Rig Music',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 30, fontWeight: FontWeight.w500, color: Colors.white)),
              const SizedBox(height: 6),
              Text("The Modern Guitarist's Toolkit",
                  style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 20),
              _errorBanner(),
              _loginCard(disabled),
              const SizedBox(height: 16),
              _divider(),
              const SizedBox(height: 10),
              _socialButton(
                label: 'Continue with Google',
                leading: Text('G',
                    style: GoogleFonts.dmSans(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                busy: _socialBusy == 'google',
                onTap: disabled ? null : _google,
              ),
              const SizedBox(height: 10),
              _socialButton(
                label: 'Continue with Apple',
                leading: const Icon(Icons.phone_iphone, size: 20, color: Colors.white),
                busy: _socialBusy == 'apple',
                onTap: disabled ? null : _apple,
              ),
              const SizedBox(height: 10),
              _guestCard(),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Don't have an account?",
                      style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: disabled
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterScreen()),
                            ),
                    child: Text('Sign up',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.accent)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('By continuing, you agree to Rig Music\u2019s Terms & Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.55)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.onErrorContainer, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(
                        color: AppColors.onErrorContainer, fontWeight: FontWeight.w600, height: 1.25)),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  _errorController.stop();
                  setState(() => _error = null);
                },
                icon: const Icon(Icons.close_rounded, color: AppColors.onErrorContainer, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _errorController,
            builder: (context, _) => ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: 1 - _errorController.value,
                minHeight: 4,
                backgroundColor: AppColors.onErrorContainer.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(AppColors.onErrorContainer),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard(bool disabled) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF18181F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email address',
              style: GoogleFonts.dmSans(
                  fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1))),
          const SizedBox(height: 6),
          _field(
            controller: _emailCtrl,
            hintText: 'guitarist@example.com',
            keyboardType: TextInputType.emailAddress,
            enabled: !disabled,
            prefix: const Icon(Icons.mail_outline, size: 18, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Password',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1))),
              GestureDetector(
                onTap: _showForgotPassword,
                child: Text('Forgot password?',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _field(
            controller: _passCtrl,
            hintText: '••••••••••••',
            obscure: _obscure,
            enabled: !disabled,
            prefix: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
            suffix: GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF94A3B8), size: 20),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () async {
              final next = !_keepSignedIn;
              setState(() => _keepSignedIn = next);
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('keep_signed_in', next);
              } catch (_) {}
            },
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _keepSignedIn ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: _keepSignedIn ? AppColors.accent : const Color(0xFF475569)),
                  ),
                  child: _keepSignedIn
                      ? const Icon(Icons.check, size: 12, color: AppColors.onAccent)
                      : null,
                ),
                const SizedBox(width: 10),
                Text('Keep me signed in',
                    style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF94A3B8))),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: disabled ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                disabledBackgroundColor: AppColors.surfaceVariant.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _loggingIn
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
                  : Text('Sign In',
                      style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    TextEditingController? controller,
    String? hintText,
    bool obscure = false,
    TextInputType? keyboardType,
    bool enabled = true,
    Widget? prefix,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        enabled: enabled,
        onSubmitted: onSubmitted,
        style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.dmSans(fontSize: 14, color: const Color(0xFF64748B)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefixIcon: prefix != null
              ? Padding(padding: const EdgeInsets.only(left: 14, right: 10), child: prefix)
              : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffix != null ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix) : null,
          suffixIconConstraints: const BoxConstraints(maxHeight: 32),
        ),
      ),
    );
  }

  Widget _divider() {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Divider(color: Color(0x14FFFFFF), thickness: 1),
        Container(
          color: const Color(0xFF101014),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR CONTINUE WITH',
              style: GoogleFonts.dmSans(
                  fontSize: 11, letterSpacing: 1.2, color: const Color(0xFF64748B))),
        ),
      ],
    );
  }

  Widget _socialButton({
    required String label,
    required Widget leading,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    final enabled = onTap != null;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF18181F),
          foregroundColor: const Color(0xFFE2E8F0),
          disabledBackgroundColor: const Color(0xFF18181F),
          disabledForegroundColor: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
              const SizedBox(width: 12),
              Text('Connecting…', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w500)),
            ] else ...[
              Opacity(opacity: enabled ? 1 : 0.6, child: leading),
              const SizedBox(width: 12),
              Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _guestCard() {
    return GestureDetector(
      onTap: _guest,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF18181F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.tune, size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Continue as Guest',
                      style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFFE2E8F0))),
                  Text('Practice offline, tune guitar, & explore chords',
                      style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF94A3B8))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  const _ForgotPasswordDialog({required this.initialEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _ctrl;
  bool _sending = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _ctrl.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _error = 'Enter a valid email address.';
        _status = null;
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _status = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _status = 'Reset email sent — check your inbox (and spam).';
      } else {
        _error = auth.error ?? 'Could not send reset email.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF18181F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Forgot password?',
          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter your account email and we will send a reset link.',
              style: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF94A3B8))),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.emailAddress,
              enabled: !_sending,
              style: GoogleFonts.dmSans(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'you@example.com',
                hintStyle: GoogleFonts.dmSans(color: const Color(0xFF64748B)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: GoogleFonts.dmSans(
                    color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(_status!,
                style: GoogleFonts.dmSans(
                    color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.dmSans(color: const Color(0xFF94A3B8))),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _send,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: _sending
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
              : const Text('Send email'),
        ),
      ],
    );
  }
}
