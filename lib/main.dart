// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/main_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/auth_service.dart';
import 'package:premier_league/screens/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: 'https://rcfetlzldccwjnuabfgj.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJjZmV0bHpsZGNjd2pudWFiZmdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5OTkwNDQsImV4cCI6MjA2OTU3NTA0NH0.Fe4Aa3b7vxn9gnye1Cl0VvhxyT7UREJYDCRvICkGNsM'
  );
  runApp(const AppRoot());
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    // Provider für die gesamte App bereitstellen
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        Provider<DataManagement>(create: (_) => DataManagement(seasonId: 76986)),
      ],
      child: MaterialApp(
        title: 'Managerspiel',
        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.blue,
        ),
        home: const AuthGate(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

// Dieses Widget entscheidet, welche Seite beim Start angezeigt wird
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Hört auf Änderungen im AuthService
    final authService = context.watch<AuthService>();

    // Zeigt MainScreen bei Login, sonst AuthScreen
    return authService.isLoggedIn ? const MainScreen() : const AuthScreen();
  }
}