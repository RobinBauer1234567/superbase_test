// lib/main.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:premier_league/auth_service.dart';
import 'package:premier_league/screens/auth_screen.dart';
import 'package:premier_league/screens/main_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'http/http_factory.dart'
    if (dart.library.html) 'http/http_factory_web.dart'
    if (dart.library.io) 'http/http_factory_io.dart';

void main() async {
  await initPlatformClient();

  http.runWithClient(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await Supabase.initialize(
        url: 'https://rcfetlzldccwjnuabfgj.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
            'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJjZmV0bHpsZGNjd2pudWFiZmdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5OTkwNDQsImV4cCI6MjA2OTU3NTA0NH0.'
            'Fe4Aa3b7vxn9gnye1Cl0VvhxyT7UREJYDCRvICkGNsM',
      );

      runApp(const AppRoot());
    },
    () => getPlatformClient(),
  );
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<TournamentViewModel>(
          create: (_) => TournamentViewModel(),
        ),
        ChangeNotifierProxyProvider<TournamentViewModel, DataManagement>(
          create: (_) => DataManagement(),
          update: (_, tournament, dataManagement) {
            final manager = dataManagement ?? DataManagement();
            manager.setSelectedSeason(tournament.currentSeasonId);
            return manager;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Managerspiel',
        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.grey.shade100,
        ),
        home: const AuthGate(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    return authService.isLoggedIn ? const MainScreen() : const AuthScreen();
  }
}
