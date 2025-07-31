import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerScreen extends StatefulWidget {
  final int playerId;

  PlayerScreen({required this.playerId});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final supabase = Supabase.instance.client;
  Map<int, double> matchRatings = {};
  String playerName = "";
  String position = "";
  String teamName = "";
  String? profileImageUrl;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPlayerData();
  }

  Future<void> fetchPlayerData() async {
    try {
      final playerResponse = await supabase
          .from('spieler')
          .select('name, position, team_id, profilbild_url')
          .eq('id', widget.playerId)
          .single();

      if (playerResponse != null) {
        final teamResponse = await supabase
            .from('team')
            .select('name')
            .eq('id', playerResponse['team_id'])
            .single();

        final matchRatingsResponse = await supabase
            .from('matchrating')
            .select('spiel_id, punkte')
            .eq('spieler_id', widget.playerId);

        setState(() {
          playerName = playerResponse['name'];
          position = playerResponse['position'];
          teamName = teamResponse['name'];
          profileImageUrl = playerResponse['profilbild_url'] != null
              ? playerResponse['profilbild_url']
              : 'https://erpsqbbbdibtdddaxhfh.supabase.co/storage/v1/object/public/spielerbilder//Photo-Missing.png';
          matchRatings = {
            for (var rating in matchRatingsResponse)
              rating['spiel_id']: rating['punkte']
          };
          isLoading = false;
        });
      }
    } catch (error) {
      print("Fehler beim Laden der Daten: $error");
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playerName.isNotEmpty ? playerName : "Spieler lädt...")),
      body: isLoading
          ? Center(child: CircularProgressIndicator()) // Ladeanzeige
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profilbild anzeigen
            Center(
              child: ClipOval(
                child: profileImageUrl != null
                    ? Image.network(
                  profileImageUrl!,
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(Icons.error, size: 120, color: Colors.red);
                  },
                )
                    : Icon(Icons.person, size: 120, color: Colors.grey),
              ),
            ),
            SizedBox(height: 16),
            Text("Team: $teamName", style: TextStyle(fontSize: 18)),
            Text("Position: $position", style: TextStyle(fontSize: 18)),
            SizedBox(height: 16),
            Text("Match Ratings:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Expanded(
              child: matchRatings.isEmpty
                  ? Text("Keine Bewertungen vorhanden")
                  : ListView(
                children: matchRatings.entries.map((entry) {
                  return ListTile(
                    title: Text("Match ID: ${entry.key}"),
                    trailing: Text("Rating: ${entry.value.toStringAsFixed(1)}"),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
