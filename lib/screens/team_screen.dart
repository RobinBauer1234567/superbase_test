// lib/screens/team_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/premier_league/matches_screen.dart'; // Wiederverwendung der MatchCard

class TeamScreen extends StatefulWidget {
  final int teamId;

  const TeamScreen({super.key, required this.teamId});

  @override
  _TeamScreenState createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _teamData;
  List<dynamic> _teamMatches = [];
  List<Map<String, dynamic>> _topPlayers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchTeamData();
  }

  Future<void> _fetchTeamData() async {
    try {
      // Team-Informationen abrufen
      final teamResponse = await Supabase.instance.client
          .from('team')
          .select()
          .eq('id', widget.teamId)
          .single();

      // Spiele des Teams abrufen
      final matchesResponse = await Supabase.instance.client
          .from('spiel')
          .select('*, heimteam:spiel_heimteam_id_fkey(name, image_url), auswaertsteam:spiel_auswärtsteam_id_fkey(name, image_url)')
          .or('heimteam_id.eq.${widget.teamId},auswärtsteam_id.eq.${widget.teamId}')
          .order('datum', ascending: false);

      // Spieler und deren gesamte Punkte berechnen
      final playersResponse = await Supabase.instance.client
          .from('spieler')
          .select('id, name, profilbild_url, matchrating(punkte)')
          .eq('team_id', widget.teamId);

      List<Map<String, dynamic>> topPlayersList = [];
      for (var player in playersResponse) {
        int totalPoints = 0;
        for (var rating in player['matchrating']) {
          totalPoints += (rating['punkte'] as int?) ?? 0;
        }
        topPlayersList.add({
          'id': player['id'],
          'name': player['name'],
          'profilbild_url': player['profilbild_url'],
          'total_punkte': totalPoints,
        });
      }

      // Spieler nach Gesamtpunktzahl sortieren
      topPlayersList.sort((a, b) => b['total_punkte'].compareTo(a['total_punkte']));

      setState(() {
        _teamData = teamResponse;
        _teamMatches = matchesResponse;
        _topPlayers = topPlayersList;
        _isLoading = false;
      });
    } catch (e) {
      print("Fehler beim Laden der Teamdaten: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getColorForRating(int rating) {
    if (rating >= 150) return Colors.teal;
    if (rating >= 100) return Colors.green;
    if (rating >= 50) return Colors.yellow.shade700;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_teamData?['name'] ?? 'Team wird geladen...'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Team-Wappen
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Image.network(
              _teamData?['image_url'] ?? '',
              height: 120,
              width: 120,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.shield, size: 120, color: Colors.grey),
            ),
          ),
          // Tab-Leiste
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Spiele'),
              Tab(text: 'Top-Spieler'),
            ],
          ),
          // Tab-Inhalte
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Spiele-Tab
                ListView.builder(
                  itemCount: _teamMatches.length,
                  itemBuilder: (context, index) {
                    return MatchCard(spiel: _teamMatches[index]);
                  },
                ),
                // Top-Spieler-Tab
                ListView.builder(
                  itemCount: _topPlayers.length,
                  itemBuilder: (context, index) {
                    final player = _topPlayers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: player['profilbild_url'] != null
                            ? NetworkImage(player['profilbild_url'])
                            : null,
                        child: player['profilbild_url'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(player['name']),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getColorForRating(player['total_punkte']),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          player['total_punkte'].toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PlayerScreen(playerId: player['id']),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}