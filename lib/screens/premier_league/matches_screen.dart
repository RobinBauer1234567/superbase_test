// lib/screens/premier_league/matches_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/spieltag_screen.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/team_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  bool _isLoading = true;
  Map<int, List<dynamic>> _spieleProSpieltag = {};

  RealtimeChannel? _spieleChannel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initialize();
  }

  Future<void> _initialize() async {
    await _fetchSpiele();
    _subscribeToChanges();
  }

  Future<void> _fetchSpiele() async {
    if (!mounted) return;
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }

    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final supabase = Supabase.instance.client;

    try {
      final data = await supabase
          .from('spiel')
          .select('*, heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)')
          .eq('season_id', dataManagement.seasonId)
          .order('datum', ascending: true);

      _updateStateWithData(data);

    } catch (e) {
      print("Fehler beim Laden der Spiele: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToChanges() {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);

    _spieleChannel = Supabase.instance.client
        .channel('public:spiel')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'spiel',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'season_id',
        value: dataManagement.seasonId,
      ),
      callback: (payload) {
        print("Echtzeit-Update erhalten! Lade Daten neu...");
        _fetchSpiele();
      },
    )
        .subscribe();
  }

  void _updateStateWithData(List<Map<String, dynamic>> data) {
    final Map<int, List<dynamic>> groupedSpiele = {};
    for (var spiel in data) {
      final round = spiel['round'] as int;
      if (groupedSpiele[round] == null) {
        groupedSpiele[round] = [];
      }
      groupedSpiele[round]!.add(spiel);
    }
    if (mounted) {
      setState(() {
        _spieleProSpieltag = groupedSpiele;
      });
    }
  }

  @override
  void dispose() {
    if (_spieleChannel != null) {
      Supabase.instance.client.removeChannel(_spieleChannel!);
    }
    super.dispose();
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

// Die MatchCard bleibt unverändert
class MatchCard extends StatelessWidget {
  final dynamic spiel;
  const MatchCard({super.key, required this.spiel});

  Widget _buildTeamColumn(BuildContext context, dynamic teamData) {
    if (teamData == null || teamData['id'] == null) {
      return Expanded(child: Column(children: [const Icon(Icons.shield, color: Colors.grey), const SizedBox(height: 8), const Text("...")],));
    }

    return Expanded(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TeamScreen(teamId: teamData['id']),
            ),
          );
        },
        child: Column(
          children: [
            Image.network(teamData['image_url'] ?? '', width: 40, height: 40, errorBuilder: (c, e, s) => const Icon(Icons.shield)),
            const SizedBox(height: 8),
            Text(teamData['name'] ?? 'Unbekannt', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heimTeam = spiel['heimteam'];
    final auswaertsTeam = spiel['auswaertsteam'];
    final ergebnis = spiel['ergebnis'] ?? '- : -';
    final status = spiel['status'] ?? 'unbekannt';

    final isFinished = status.toLowerCase() == 'finished' || status == 'beendet' || status == 'final';
    final isNotStarted = status.toLowerCase() == 'not started' || status == 'nicht gestartet';

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
            _buildTeamColumn(context, heimTeam),
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
                      isNotStarted ? '- : -' : ergebnis,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isFinished ? 'Endstand' : (isNotStarted ? uhrzeit : status),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            _buildTeamColumn(context, auswaertsTeam),
          ],
        ),
      ),
    );
  }
}