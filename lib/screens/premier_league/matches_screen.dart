// lib/screens/premier_league/matches_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/spieltag_screen.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/team_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

// neu: scrollable_positioned_list
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  bool _isLoading = true;
  Map<int, List<dynamic>> _spieleProSpieltag = {};
  RealtimeChannel? _spieleChannel;

  // ScrollablePositionedList controller / listener
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  int? _aktuellerSpieltag;

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
    setState(() => _isLoading = true);

    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final supabase = Supabase.instance.client;

    try {
      final data = await supabase
          .from('spiel')
          .select(
        '*, heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)',
      )
          .eq('season_id', dataManagement.seasonId)
          .order('datum', ascending: true);

      _updateStateWithData(List<Map<String, dynamic>>.from(data));

      // Kleines Delay, dann scrollen (scrollable_positioned_list ist robust gegenüber nicht gebauten Items)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToAktuellenSpieltag();
      });
    } catch (e) {
      print("Fehler beim Laden der Spiele: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateStateWithData(List<Map<String, dynamic>> data) {
    final Map<int, List<dynamic>> groupedSpiele = {};
    DateTime now = DateTime.now();
    int? currentRound;

    for (var spiel in data) {
      final round = spiel['round'] as int;
      groupedSpiele.putIfAbsent(round, () => []).add(spiel);

      try {
        final matchDate = DateTime.parse(spiel['datum']);
        if (matchDate.isAfter(now) && currentRound == null) {
          currentRound = round;
        }
      } catch (_) {
        // ignore parse error
      }
    }

    _aktuellerSpieltag = currentRound ?? (groupedSpiele.keys.isNotEmpty ? groupedSpiele.keys.last : null);

    if (mounted) {
      setState(() {
        _spieleProSpieltag = groupedSpiele;
      });
    }
  }

  Future<void> _scrollToAktuellenSpieltag() async {
    if (_aktuellerSpieltag == null) return;
    if (_spieleProSpieltag.isEmpty) return;

    final spieltage = _spieleProSpieltag.keys.toList()..sort();
    final index = spieltage.indexOf(_aktuellerSpieltag!);
    if (index == -1) return;

    // scrollable_positioned_list kann direkt zu einem Index scrollen — zuverlässig auch bei lazy-build
    try {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 10),
        curve: Curves.easeOutCubic,
      );
      print("✅ Scroll attempt to index $index (Spieltag $_aktuellerSpieltag)");
    } catch (e) {
      print("⚠️ Fehler beim scrollTo: $e");
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
        print("🔁 Echtzeit-Update erhalten → Spiele neu laden...");
        _fetchSpiele();
      },
    )
        .subscribe();
  }

  @override
  void dispose() {
    if (_spieleChannel != null) {
      Supabase.instance.client.removeChannel(_spieleChannel!);
    }
    // itemPositionsListener braucht kein dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final spieltage = _spieleProSpieltag.keys.toList()..sort();

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      itemCount: spieltage.length,
      itemBuilder: (context, index) {
        final spieltagNummer = spieltage[index];
        final spieleDesSpieltags = _spieleProSpieltag[spieltagNummer]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Text(
                'SPIELTAG $spieltagNummer',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
            ...spieleDesSpieltags
                .map((spiel) => MatchCard(spiel: spiel))
                .toList(),
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

  Widget _buildTeamColumn(BuildContext context, dynamic teamData) {
    if (teamData == null || teamData['id'] == null) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.shield, color: Colors.grey, size: 40),
            SizedBox(height: 6),
            Text("...", style: TextStyle(fontSize: 12)),
          ],
        ),
      );
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo bleibt 40x40
            Image.network(
              teamData['image_url'] ?? '',
              width: 40,
              height: 40,
              errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 40),
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 6),
            // kleinere Schrift, damit Karte kompakt bleibt
            Text(
              teamData['name'] ?? 'Unbekannt',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
    final status = (spiel['status'] ?? 'unbekannt') as String;

    final isFinished = status.toLowerCase() == 'finished' ||
        status.toLowerCase() == 'beendet' ||
        status.toLowerCase() == 'final';
    final isNotStarted = status.toLowerCase() == 'not started' ||
        status.toLowerCase() == 'nicht gestartet' ||
        status.toLowerCase() == 'postponed';

    DateTime datum;
    try {
      datum = DateTime.parse(spiel['datum']);
    } catch (_) {
      datum = DateTime.now();
    }
    final uhrzeit = DateFormat('HH:mm').format(datum);
    final datumsString = DateFormat('dd.MM.yyyy').format(datum);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0), // weniger vertical margin
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0), // weniger padding
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Datum klein oben links, platzsparend
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Text(
                datumsString,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            // Hauptinhalt in einer einzigen Reihe — kompakter
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildTeamColumn(context, heimTeam),
                // Score-Block: schmaler und kleinere Schrift als vorher
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => GameScreen(spiel: spiel)),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isNotStarted ? '- : -' : ergebnis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isFinished ? 'Endstand' : (isNotStarted ? uhrzeit : status),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildTeamColumn(context, auswaertsTeam),
              ],
            ),
          ],
        ),
      ),
    );
  }
}