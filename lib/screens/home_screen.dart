//player_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/models/match.dart';
import 'package:premier_league/data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';



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
    final response = await supabaseService.supabase.from('spieltag').select();

    setState(() {
      spieltage = response;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spieltag')),
      body:
      spieltage.isEmpty
          ? Center(
        child: CircularProgressIndicator(),
      ) // Ladeanzeige, falls noch keine Daten geladen sind
          : ListView.builder(
        itemCount: spieltage.length,
        itemBuilder: (context, index) {
          final spieltag = spieltage[index];
          return ListTile(
            title: Text("Spieltag ${spieltag['round']}"),
            subtitle: Text("Status: ${spieltag['status']}"),
          );
        },
      ),
    );
  }
}
