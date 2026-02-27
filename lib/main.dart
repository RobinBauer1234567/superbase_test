// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/main_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/auth_service.dart';
import 'package:premier_league/screens/auth_screen.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:premier_league/main.dart';
import 'http/http_factory.dart'
if (dart.library.html) 'http/http_factory_web.dart'
if (dart.library.io) 'http/http_factory_io.dart';

void main() async {
  // 1. Die Motor-Vorbereitung (Läuft auf Web leer durch, auf Mobile startet Cronet)
  await initPlatformClient();

  // 2. Wir starten sofort die "sichere Netzwerk-Zone"
  http.runWithClient(
        () async {
      // 3. ALLES, was Flutter braucht, passiert JETZT innerhalb dieser Zone!
      WidgetsFlutterBinding.ensureInitialized();

      // 4. Supabase innerhalb der Zone starten
      await Supabase.initialize(
          url: 'https://rcfetlzldccwjnuabfgj.supabase.co',
          anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJjZmV0bHpsZGNjd2pudWFiZmdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5OTkwNDQsImV4cCI6MjA2OTU3NTA0NH0.Fe4Aa3b7vxn9gnye1Cl0VvhxyT7UREJYDCRvICkGNsM'
      );

      // 5. App starten
      runApp(const AppRoot());
    },
    // 6. Die Client-Fabrik (Holt automatisch den richtigen Client für Web, iOS oder Android)
        () => getPlatformClient(),
  );
}

// lib/main.dart (Ausschnitt)

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
          // ---> NEU: Setzt den Standard-Hintergrund für alle Scaffolds in der App
          scaffoldBackgroundColor: Colors.grey.shade100,
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