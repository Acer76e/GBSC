import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/jsc/jsc_auth_service.dart';
import 'jsc_home_screen.dart';
import 'jsc_login_screen.dart';

class JscTab extends StatelessWidget {
  const JscTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<JscAuthService>();
    if (!auth.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isAuthenticated ? const JscHomeScreen() : const JscLoginScreen();
  }
}
