//player_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/provider/player_provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/models/match.dart';
import 'package:premier_league/data_service.dart';



class SpielListeScreen extends StatefulWidget {
  @override
  _SpielListeScreenState createState() => _SpielListeScreenState();
}

class _SpielListeScreenState extends State<SpielListeScreen> {
  List<Spiel> spiele = [];
  final ApiService apiService = ApiService();

  @override
  void initState() {
    super.initState();
    fetchSpiele();
  }

  Future<void> fetchSpiele() async {
    final fetchedSpiele = await Spiel.fetchFromSupabase();
    setState(() {
      spiele = fetchedSpiele;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spiele Übersicht')),
      body: ListView.builder(
        itemCount: spiele.length,
        itemBuilder: (context, index) {
          final spiel = spiele[index];
          return ListTile(
            title: Text("${spiel.homeTeam} vs ${spiel.awayTeam}"),
            subtitle: Text("Stand: ${spiel.homeScore} - ${spiel.awayScore}"),
            onTap: () => apiService.fetchLineups(spiel.matchId),
          );
        },
      ),
    );
  }
}
