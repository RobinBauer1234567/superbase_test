// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/main_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: 'https://rcfetlzldccwjnuabfgj.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJjZmV0bHpsZGNjd2pudWFiZmdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5OTkwNDQsImV4cCI6MjA2OTU3NTA0NH0.Fe4Aa3b7vxn9gnye1Cl0VvhxyT7UREJYDCRvICkGNsM'
  );
  DataManagement dataManagement = DataManagement();
  //await dataManagement.collectNewData();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radial Chart Demo',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
      ),
      // ÄNDERUNG: Starte die App mit dem neuen MainScreen
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
