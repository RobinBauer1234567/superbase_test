//main
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:premier_league/screens/home_screen.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/spieltag_screen.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';


void main() async {
   WidgetsFlutterBinding.ensureInitialized();
   await Supabase.initialize(
     url: 'https://rcfetlzldccwjnuabfgj.supabase.co',
     anonKey:
     'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJjZmV0bHpsZGNjd2pudWFiZmdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5OTkwNDQsImV4cCI6MjA2OTU3NTA0NH0.Fe4Aa3b7vxn9gnye1Cl0VvhxyT7UREJYDCRvICkGNsM'   );
 DataManagement dataManagement = DataManagement();
  //await dataManagement.collectNewData();
   runApp(MyApp());
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
      home: SpieltageScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}


class ChartScreen extends StatelessWidget {
  const ChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // =================================================================
    // DATENDEFINITON MIT DER NEUEN, FLEXIBLEN STRUKTUR
    // =================================================================
    // Du definierst jetzt Gruppen und Segmente direkt als Objekte.
    // Das macht den Code lesbarer und einfacher zu warten.
    final List<GroupData> sampleChartData = [
      GroupData(
        name: 'Schießen',
        backgroundColor: Colors.blue.withOpacity(0.12),
        segments: const [
          SegmentData(name: 'Abschlussvolumen', value: 85.0),
          SegmentData(name: 'Abschlussqualität', value: 70.0),
        ],
      ),
      GroupData(
        name: 'Passen',
        backgroundColor: Colors.green.withOpacity(0.12),
        segments: const [
          SegmentData(name: 'Passvolumen', value: 95.0),
          SegmentData(name: 'Passsicherheit', value: 40.0),
          SegmentData(name: 'Kreative Pässe', value: 65.0),
        ],
      ),
      GroupData(
        name: 'Duelle',
        backgroundColor: Colors.orange.withOpacity(0.12),
        segments: const [
          SegmentData(name: 'Zweikampfaktivität', value: 55.0),
          SegmentData(name: 'Zweikämpferfolg', value: 20.0),
          SegmentData(name: 'Fouls', value: 30.0),
        ],
      ),
      GroupData(
        name: 'Ballbesitz',
        backgroundColor: Colors.red.withOpacity(0.12),
        segments: const [
          SegmentData(name: 'Ballberührungen', value: 78.0),
          SegmentData(name: 'Ballverluste', value: 88.0),
          SegmentData(name: 'Abgefangene Bälle', value: 92.0),
        ],
      ),
      GroupData(
        name: 'Defensive',
        backgroundColor: Colors.purple.withOpacity(0.12),
        segments: const [
          SegmentData(name: 'Tacklings', value: 60.0),
          SegmentData(name: 'Klärende Aktionen', value: 45.0),
          SegmentData(name: 'Fehler', value: 80.0),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interaktives Spielerprofil'),
        backgroundColor: Colors.black87,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          // Aufruf des Widgets mit der neuen Datenstruktur
          child: RadialSegmentChart(
            groups: sampleChartData,
            maxAbsValue: 100.0, // Der Maximalwert, auf den die Balken skaliert werden
            centerLabel: 72, // Der Wert, der in der Mitte angezeigt wird
          ),
        ),
      ),
    );
  }
}
