import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'main_scaffold.dart';

/// Routes to the main app when signed in (or in guest mode), otherwise to the
/// login screen. Waits for the guest flag to load before deciding, so a
/// returning guest doesn't get a one-frame flash of the login screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF0E0C1A),
        body: SizedBox.shrink(),
      );
    }
    if (auth.isSignedIn || auth.isGuest) return const MainScaffold();
    return const LoginScreen();
  }
}
