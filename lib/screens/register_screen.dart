import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

/// Sibling of the minimal login: same DM Sans / mint skin.
/// Validation + AuthProvider.signUp preserved, errors in the same
/// inline 4s banner (no lockout).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _registering = false;
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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _errorController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _error = message);
    _errorController.forward(from: 0);
  }

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (name.isEmpty) {
      _showError('Enter your name.');
      return;
    }
    if (!email.contains('@')) {
      _showError('Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }
    setState(() => _registering = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(email, password, data: {'display_name': name});
    if (!mounted) return;
    setState(() => _registering = false);
    if (!ok) {
      _showError(auth.error ?? 'Registration failed.');
      return;
    }
    // AuthGate rebuilds to MainScaffold automatically.
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().isBusy;
    final disabled = busy || _registering;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF94A3B8)),
                ),
              ),
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
              Text('Create your account',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 28, fontWeight: FontWeight.w500, color: Colors.white)),
              const SizedBox(height: 6),
              Text('Join Rig Music in seconds',
                  style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 20),
              _errorBanner(),
              _registerCard(disabled),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account?',
                      style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: disabled
                        ? null
                        : () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            ),
                    child: Text('Sign in',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.accent)),
                  ),
                ],
              ),
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

  Widget _registerCard(bool disabled) {
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
          _label('Full name'),
          const SizedBox(height: 6),
          _field(controller: _nameCtrl, hintText: 'Alex Vane', enabled: !disabled),
          const SizedBox(height: 16),
          _label('Email address'),
          const SizedBox(height: 6),
          _field(
            controller: _emailCtrl,
            hintText: 'guitarist@example.com',
            keyboardType: TextInputType.emailAddress,
            enabled: !disabled,
          ),
          const SizedBox(height: 16),
          _label('Password'),
          const SizedBox(height: 6),
          _field(
            controller: _passCtrl,
            hintText: 'At least 6 characters',
            obscure: _obscure1,
            enabled: !disabled,
            suffix: GestureDetector(
              onTap: () => setState(() => _obscure1 = !_obscure1),
              child: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF94A3B8), size: 20),
            ),
          ),
          const SizedBox(height: 16),
          _label('Confirm password'),
          const SizedBox(height: 6),
          _field(
            controller: _confirmCtrl,
            hintText: 'Repeat your password',
            obscure: _obscure2,
            enabled: !disabled,
            suffix: GestureDetector(
              onTap: () => setState(() => _obscure2 = !_obscure2),
              child: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF94A3B8), size: 20),
            ),
            onSubmitted: (_) => _register(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: disabled ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                disabledBackgroundColor: AppColors.surfaceVariant.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _registering
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
                  : Text('Create Account',
                      style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(text,
        style: GoogleFonts.dmSans(
            fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)));
  }

  Widget _field({
    TextEditingController? controller,
    String? hintText,
    bool obscure = false,
    TextInputType? keyboardType,
    bool enabled = true,
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
          suffixIcon: suffix != null ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix) : null,
          suffixIconConstraints: const BoxConstraints(maxHeight: 32),
        ),
      ),
    );
  }
}
