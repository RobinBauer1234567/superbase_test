// lib/screens/premier_league/matches_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/spieltag_screen.dart'; // Für GameScreen
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/team_screen.dart'; // NEUER IMPORT


class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  bool _isLoading = true;
  List<dynamic> _spiele = [];
  Map<int, List<dynamic>> _spieleProSpieltag = {};

  @override
  void initState() {
    super.initState();
    _fetchSpiele();
  }

  Future<void> _fetchSpiele() async {
    try {
      final data = await Supabase.instance.client
          .from('spiel')
          .select('*, heimteam:spiel_heimteam_id_fkey(name, image_url), auswaertsteam:spiel_auswärtsteam_id_fkey(name, image_url)')
          .order('datum', ascending: true);

      final Map<int, List<dynamic>> groupedSpiele = {};
      for (var spiel in data) {
        final round = spiel['round'] as int;
        if (groupedSpiele[round] == null) {
          groupedSpiele[round] = [];
        }
        groupedSpiele[round]!.add(spiel);
      }

      setState(() {
        _spiele = data;
        _spieleProSpieltag = groupedSpiele;
        _isLoading = false;
      });
    } catch (e) {
      print("Fehler beim Laden der Spiele: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final spieltage = _spieleProSpieltag.keys.toList()..sort();

    return ListView.builder(
      itemCount: spieltage.length,
      itemBuilder: (context, index) {
        final spieltagNummer = spieltage[index];
        final spieleDesSpieltags = _spieleProSpieltag[spieltagNummer]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Text(
                'SPIELTAG $spieltagNummer',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
            ),
            ...spieleDesSpieltags.map((spiel) => MatchCard(spiel: spiel)).toList(),
            const Divider(height: 20, thickness: 1),
          ],
        );
      },
    );
  }
}

class MatchCard extends StatelessWidget {
  final dynamic spiel;
  const MatchCard({super.key, required this.spiel});

  // Helper-Widget, um Clicks auf Team-Elemente zu ermöglichen
  Widget _buildTeamColumn(BuildContext context, dynamic teamData) {
    return Expanded(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TeamScreen(teamId: teamData['id']), // Navigation zum TeamScreen
            ),
          );
        },
        child: Column(
          children: [
            Image.network(teamData['image_url'] ?? '', width: 40, height: 40, errorBuilder: (c, e, s) => const Icon(Icons.shield)),
            const SizedBox(height: 8),
            Text(teamData['name'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Füge die Team-IDs hinzu, die für die Navigation benötigt werden
    final heimTeam = {...spiel['heimteam'], 'id': spiel['heimteam_id']};
    final auswaertsTeam = {...spiel['auswaertsteam'], 'id': spiel['auswärtsteam_id']};
    final ergebnis = spiel['ergebnis'] ?? '- : -';
    final isFinished = ergebnis != 'Noch kein Ergebnis';

    final datum = DateTime.parse(spiel['datum']);
    final uhrzeit = DateFormat('HH:mm').format(datum);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      elevation: 2.0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Heimteam (jetzt klickbar)
            _buildTeamColumn(context, heimTeam),
            // Spielstand / Uhrzeit
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => GameScreen(spiel: spiel)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    Text(
                      ergebnis,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isFinished ? 'Endstand' : uhrzeit,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            // Auswärtsteam (jetzt klickbar)
            _buildTeamColumn(context, auswaertsTeam),
          ],
        ),
      ),
    );
  }
}