//main
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:premier_league/screens/home_screen.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/spieltag_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://erpsqbbbdibtdddaxhfh.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVycHNxYmJiZGlidGRkZGF4aGZoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDIyMDc0MjcsImV4cCI6MjA1Nzc4MzQyN30.19pUS2rKFH8jhzOPA9JOnsEJJnBcAhqFVnnDqcgCHKI',
  );
DataManagement dataManagement = DataManagement();
// await dataManagement.collectNewData();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
   @override
   Widget build(BuildContext context) {
     return MaterialApp(
       title: 'Fußball Liga Manager',
       theme: ThemeData(primarySwatch: Colors.blue),
       home: RadialSegmentChart(
         values: [40, 30, 90, 60, 70, 10, 100, 0, 25, 75, 55, 65, 35, 85],
         maxAbsValue: 100,
         centerLabel: 72,
       )





     );
   }
 }
