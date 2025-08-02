//player_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/models/match.dart';
import 'package:premier_league/data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/spieltag_screen.dart';

class SpieltageScreen extends StatefulWidget {
  @override
  _SpieltageScreenState createState() => _SpieltageScreenState();
}

class _SpieltageScreenState extends State<SpieltageScreen> {
  List<dynamic> spieltage = [];
  final ApiService apiService = ApiService();
  SupabaseService supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    fetchSpieltage();
  }

  Future<void> fetchSpieltage() async {
    final response = await supabaseService.supabase.from('spieltag').select().order('round', ascending: true);
    setState(() {
      spieltage = response;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spieltage')), // Titel angepasst für Klarheit
      body: spieltage.isEmpty
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: spieltage.length,
        itemBuilder: (context, index) {
          final spieltag = spieltage[index];
          return ListTile(
            title: Text("Spieltag ${spieltag['round']}"),
            subtitle: Text("Status: ${spieltag['status']}"),
            trailing: Icon(Icons.arrow_forward_ios), // Optional: Ein Pfeil-Icon
            onTap: () {
              // HIER IST DIE NEUE LOGIK FÜR DIE NAVIGATION
              Navigator.push(
                context,
                MaterialPageRoute(
                  // Navigiere zum HomeScreen (der die Spiele anzeigt)
                  // und übergib die 'round' Nummer des angeklickten Spieltags.
                  builder: (context) =>
                      HomeScreen(round: spieltag['round']),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
