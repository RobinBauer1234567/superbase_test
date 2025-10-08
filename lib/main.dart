// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/main_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

void main() async {
  // --- HIER DIE SAISON AUSWÄHLEN ---
  const activeSeasonId = 76986; // ID für 2024/25

  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: 'https://rcfetlzldccwjnuabfgj.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJjZmV0bHpsZGNjd2pudWFiZmdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5OTkwNDQsImV4cCI6MjA2OTU3NTA0NH0.Fe4Aa3b7vxn9gnye1Cl0VvhxyT7UREJYDCRvICkGNsM'
  );
  DataManagement dataManagement = DataManagement(seasonId: activeSeasonId);

  //dataManagement.updateData();

  runApp(MyApp(activeSeasonId: activeSeasonId));
}

class MyApp extends StatelessWidget {
  final int activeSeasonId;
  const MyApp({super.key, required this.activeSeasonId});

  @override
  Widget build(BuildContext context) {
    return Provider<DataManagement>(
      create: (_) => DataManagement(seasonId: activeSeasonId),
      child: MaterialApp(
        title: 'Radial Chart Demo',
        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.blue,
        ),
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}