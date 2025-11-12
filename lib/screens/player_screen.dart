import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:premier_league/screens/spieltag_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/viewmodels/radar_chart_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/screenelements/match_screen/matchrating_screen.dart';
import 'package:premier_league/utils/color_helper.dart';


class PlayerScreen extends StatefulWidget {
  final int playerId;

  const PlayerScreen({super.key, required this.playerId});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabController;
  final RadarChartViewModel _radarChartViewModel = RadarChartViewModel();
  final ScrollController _scrollController = ScrollController();

  // Player Info
  String playerName = "";
  String teamName = "";
  List<GroupData> radarChartData = [];
  String? profileImageUrl;
  String? teamImageUrl;
  Map<String, dynamic>? teamData;

  // Data for views
  bool isLoading = true;
  String _errorMessage = '';
  List<dynamic> teamMatches = []; // NEU: Liste für alle Team-Spiele
  List<dynamic> matchRatingsRaw = []; // Behalten für Radar-Chart-Logik
  List<String> availablePositions = [];
  String? selectedPosition;
  double averagePlayerRating = 0.0;
  double averagePlayerRatingPercentile = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        // Scrollt zum nächsten anstehenden Spiel
        _scrollToUpcomingMatch();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fetchPlayerData();
  }

  // NEU: Scrollt zum nächsten anstehenden Spiel
  void _scrollToUpcomingMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (teamMatches.isEmpty || !_scrollController.hasClients) return;

      final now = DateTime.now();
      int? upcomingMatchIndex;

      // Finde das erste Spiel, das nach "jetzt" stattfindet
      for (int i = 0; i < teamMatches.length; i++) {
        final match = teamMatches[i];
        if (match['datum'] != null) {
          try {
            final matchDate = DateTime.parse(match['datum']);
            if (matchDate.isAfter(now)) {
              upcomingMatchIndex = i;
              break;
            }
          } catch (_) {
            // Parsing-Fehler ignorieren
          }
        }
      }

      // Wenn kein zukünftiges Spiel gefunden wurde, scrolle zum letzten Spiel
      if (upcomingMatchIndex == null) {
        upcomingMatchIndex = teamMatches.isNotEmpty ? teamMatches.length - 1 : 0;
      }

      _scrollController.animateTo(
        upcomingMatchIndex * 90.0, // Annahme: Jedes Item ist ca. 90 Pixel hoch
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> fetchPlayerData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      _errorMessage = '';
    });

    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

    try {
      // 1. Spieler- und Teamdaten abrufen (wie bisher)
      final playerResponse = await supabase
          .from('season_players')
          .select(
          'team:team(id, name, image_url), spieler:spieler(name, position, profilbild_url)')
          .eq('season_id', seasonId)
          .eq('player_id', widget.playerId)
          .single();

      final spielerData = playerResponse['spieler'];
      teamData = playerResponse['team'];
      final playerTeamId = teamData!['id'];

      // 2. ALLE Spiele des Teams abrufen
      final teamMatchesResponse = await supabase
          .from('spiel')
          .select(
          '*, ' // Alle Spalten von 'spiel'
              'heimteam:team!spiel_heimteam_id_fkey(name, image_url), '
              'auswaertsteam:team!spiel_auswärtsteam_id_fkey(name, image_url), '
              'matchrating!left(*)' // WICHTIG: Left Join
      )
          .eq('season_id', seasonId)
      // HIER IST DIE KORREKTUR:
          .or('heimteam_id.eq.$playerTeamId,auswärtsteam_id.eq.$playerTeamId') // Sicherstellen, dass 'auswärtsteam_id' mit 'ä' geschrieben wird
          .eq('matchrating.spieler_id',
          widget.playerId) // Filtert den 'matchrating'-Join
          .order('datum', ascending: true); // Sortiert nach Datum

      if (!mounted) return;

      // 3. Daten für die Radar-Chart vorbereiten (nur die Spiele, bei denen der Spieler ein Rating hat)
      final actualRatings = teamMatchesResponse
          .where((match) => (match['matchrating'] as List<dynamic>).isNotEmpty)
          .map((match) {
        // Baut die Struktur nach, die der RadarChartViewModel erwartet
        final rating = (match['matchrating'] as List<dynamic>).first;
        return {
          'match_position': rating['match_position'],
          'punkte': rating['punkte'],
          'statistics': rating['statistics'],
          'spiel':
          match, // 'spiel' ist hier der gesamte Match-Eintrag
        };
      }).toList();

      // 4. Durchschnitts-Rating berechnen (nur aus echten Ratings)
      double totalRating = 0;
      for (var rating in actualRatings) {
        totalRating += (rating['punkte'] as num? ?? 0.0).toDouble();
      }
      final double calculatedAverageRating =
      actualRatings.isNotEmpty ? totalRating / actualRatings.length : 0.0;

      // 5. Positionen parsen (wie bisher)
      String rawPositions = spielerData['position'] ?? 'N/A';
      List<String> parsedPositions =
      rawPositions.split(',').map((p) => p.trim()).toList();
      if (parsedPositions.isEmpty || parsedPositions.first.isEmpty) {
        parsedPositions = ['N/A'];
      }

      final String selectedPos =
      (selectedPosition != null && parsedPositions.contains(selectedPosition))
          ? selectedPosition!
          : parsedPositions.last;


      setState(() {
        playerName = spielerData['name'];
        teamName = teamData!['name'];
        teamImageUrl = teamData!['image_url'];
        profileImageUrl = spielerData['profilbild_url'] ??
            'https://rcfetlzldccwjnuabfgj.supabase.co/storage/v1/object/public/spielerbilder//Photo-Missing.png';

        teamMatches = teamMatchesResponse; // Für die ListView
        matchRatingsRaw = actualRatings; // Für die Radar-Chart
        availablePositions = parsedPositions;
        selectedPosition = selectedPos;
        averagePlayerRating = calculatedAverageRating;
      });

      _scrollToUpcomingMatch();

      // 6. Radar-Chart-Berechnung anstoßen (wie bisher)
      if (selectedPosition != null) {
        await _triggerRadarChartCalculation(selectedPosition!);
      } else {
        setState(() => isLoading = false);
      }
    } catch (error) {
      print("Fehler beim Laden der Spielerdaten: $error");
      if (mounted) {
        setState(() {
          isLoading = false;
          _errorMessage = "Fehler beim Laden der Spielerdaten.";
        });
      }
    }
  }
  Future<void> _triggerRadarChartCalculation(String comparisonPosition) async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });

    final result = await _radarChartViewModel.calculateRadarChartData(
      comparisonPosition: comparisonPosition,
      matchRatings: List<Map<String, dynamic>>.from(matchRatingsRaw),
      averagePlayerRating: averagePlayerRating,
    );

    if (mounted) {
      setState(() {
        radarChartData = result.radarChartData;
        averagePlayerRatingPercentile = result.averagePlayerRatingPercentile;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(playerName.isNotEmpty ? playerName : "Spieler lädt..."),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Text(_errorMessage))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                SizedBox(
                  height: 150, // Höhe des Spielerbilds
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Opacity(
                            opacity: 0.4,
                            child: teamImageUrl != null
                                ? Image.network(
                              teamImageUrl!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.contain,
                            )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      ClipOval(
                        child: profileImageUrl != null
                            ? Image.network(
                          profileImageUrl!,
                          width: 150,
                          height: 150,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) {
                            return const Icon(Icons.error,
                                size: 120, color: Colors.red);
                          },
                        )
                            : const Icon(Icons.person,
                            size: 120, color: Colors.grey),
                      ),
                      Expanded(flex: 2, child: Container()),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text("Team: $teamName",
                    style: const TextStyle(fontSize: 18)),
                Text("Positionen: ${availablePositions.join(', ')}",
                    style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Saisonspiele'),
              Tab(text: 'Radar Chart'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Zeigt jetzt teamMatches statt matchRatingsRaw
                teamMatches.isEmpty
                    ? const Center(
                    child: Text("Keine Spiele vorhanden"))
                    : ListView.builder(
                  controller: _scrollController,
                  itemCount: teamMatches.length,
                  itemBuilder: (context, index) {
                    final match = teamMatches[index];
                    return MatchRatingRow(
                      match: match, // Übergibt das gesamte Spiel-Objekt
                      playerId: widget.playerId,
                      playerName: playerName,
                      playerProfileImageUrl: profileImageUrl,
                    );
                  },
                ),
                radarChartData.isEmpty
                    ? const Center(
                    child: Text("Statistiken nicht verfügbar."))
                    : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 16.0),
                      child: DropdownButton<String>(
                        value: selectedPosition,
                        isExpanded: true,
                        hint: const Text(
                            "Vergleichsposition wählen"),
                        items:
                        availablePositions.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setState(() {
                              selectedPosition = newValue;
                            });
                            _triggerRadarChartCalculation(
                                newValue);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: RadialSegmentChart(
                          groups: radarChartData,
                          maxAbsValue: 100.0,
                          centerDisplayValue:
                          averagePlayerRating.round(),
                          centerComparisonValue:
                          averagePlayerRatingPercentile,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MatchRatingRow extends StatelessWidget {
  final Map<String, dynamic> match; // Spiel-Objekt
  final int playerId;
  final String playerName;
  final String? playerProfileImageUrl;

  const MatchRatingRow({
    super.key,
    required this.match,
    required this.playerId,
    required this.playerName,
    this.playerProfileImageUrl,
  });

  Widget _buildEventIcon(IconData icon, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
      child: Icon(icon, color: color, size: 14),
    );
  }

  // NEUE METHODE: Bestimmt das Status-Icon des Spielers
  Widget _buildPlayerStatusIcon(BuildContext context) {
    final status = match['status']?.toString().toLowerCase() ?? 'nicht gestartet';

    // Für zukünftige Spiele kein Icon anzeigen
    if (status == 'nicht gestartet') {
      return const SizedBox(width: 16); // Platzhalter, damit Layout konsistent bleibt
    }

    final ratingList = match['matchrating'] as List<dynamic>;
    final playerRating =
    ratingList.isNotEmpty ? ratingList.first as Map<String, dynamic> : null;

    // Fall 1: Spiel gespielt, aber kein Rating -> Nicht im Kader
    if (playerRating == null) {
      return Tooltip(
        message: 'Nicht im Kader',
        child: Icon(Icons.person_off_outlined,
            size: 16, color: Colors.grey.shade700),
      );
    }

    final formationIndex = playerRating['formationsindex'] as int?;

    // Fall 2: Rating vorhanden, Index < 11 -> Startelf
    if (formationIndex != null && formationIndex < 11) {
      return Tooltip(
        message: 'Startelf',
        child: Icon(Icons.play_circle_fill_outlined,
            size: 16, color: Colors.green.shade700),
      );
    }

    // Fall 3: Rating vorhanden, Index >= 11 -> Bank
    return Tooltip(
      message: 'Bank',
      child: Icon(Icons.event_seat_outlined,
          size: 16, color: Colors.orange.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Logik, um das Rating aus dem Spiel-Objekt zu extrahieren
    final ratingList = match['matchrating'] as List<dynamic>;
    final playerRating =
    ratingList.isNotEmpty ? ratingList.first as Map<String, dynamic> : null;

    final stats = playerRating?['statistics'] as Map<String, dynamic>? ?? {};
    final punkte = playerRating?['punkte'] ?? 0;
    final minutesPlayed = stats['minutesPlayed'] ?? 0;
    final goals = stats['goals'] ?? 0;
    final assists = stats['assists'] ?? 0;
    final ownGoals = stats['ownGoals'] ?? 0;

    // Spiel-Daten direkt aus 'match'
    // *** START ÄNDERUNG ***
    final status = match['status']?.toString().toLowerCase() ?? 'nicht gestartet';
    final bool isNotStarted = status == 'nicht gestartet';
    // *** ENDE ÄNDERUNG ***

    final heimTeam = match['heimteam'];
    final auswaertsTeam = match['auswaertsteam'];
    final ergebnis = match['ergebnis'] ?? 'N/A';
    final datumString = match['datum'] ?? '';
    final datum = DateTime.tryParse(datumString);
    final formattedDate =
    datum != null ? DateFormat('dd.MM.yy').format(datum) : 'N/A';

    // *** START ÄNDERUNG ***
    // Uhrzeit für "nicht gestartet" Spiele extrahieren
    final formattedTime =
    datum != null ? DateFormat('HH:mm').format(datum) : 'N/A';
    // *** ENDE ÄNDERUNG ***

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GameScreen(spiel: match),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  formattedDate,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showTeamNames = constraints.maxWidth > 180;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showTeamNames)
                          Expanded(
                            child: Text(
                              heimTeam['name'] ?? '?',
                              style:
                              const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (showTeamNames) const SizedBox(width: 8),
                        _TeamCrest(imageUrl: heimTeam['image_url']),

                        // *** START ÄNDERUNG: Ergebnis ODER Uhrzeit ***
                        Padding(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 12.0),
                          child: isNotStarted
                              ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '-:-',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formattedTime,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          )
                              : Text(
                            ergebnis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        // *** ENDE ÄNDERUNG ***

                        _TeamCrest(imageUrl: auswaertsTeam['image_url']),
                        if (showTeamNames) const SizedBox(width: 8),
                        if (showTeamNames)
                          Expanded(
                            child: Text(
                              auswaertsTeam['name'] ?? '?',
                              style:
                              const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              GestureDetector(
                onTap: () {
                  // Verhindert das Öffnen des Dialogs, wenn keine Stats vorhanden sind
                  if (stats.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Keine Spieldaten verfügbar"),
                          duration: Duration(seconds: 2)),
                    );
                    return;
                  }

                  final playerInfoForMatch = PlayerInfo(
                    id: playerId,
                    name: playerName,
                    position: playerRating?['match_position'] ?? 'N/A',
                    profileImageUrl: playerProfileImageUrl,
                    rating: punkte,
                    goals: goals,
                    assists: assists,
                    ownGoals: ownGoals,
                  );
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return MatchRatingScreen(
                        playerInfo: playerInfoForMatch,
                        matchStatistics: stats,
                      );
                    },
                  );
                },
                child: Container(
                  color: Colors.transparent, // Wichtig für Hit-Detection
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // *** START ÄNDERUNG: Spielzeit & Events ausblenden ***
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildPlayerStatusIcon(context),
                          const SizedBox(width: 4),
                          // Nur anzeigen, wenn Spiel gestartet
                          if (!isNotStarted) ...[
                            Icon(Icons.timer_outlined,
                                size: 14, color: Colors.grey.shade700),
                            const SizedBox(width: 4),
                            Text("$minutesPlayed'",
                                style: const TextStyle(fontSize: 12)),
                          ],
                          const Spacer(),
                          // Nur anzeigen, wenn Spiel gestartet
                          if (!isNotStarted) ...[
                            _buildEventIcon(
                                Icons.sports_soccer, Colors.black, goals),
                            _buildEventIcon(
                                Icons.assistant, Colors.blue, assists),
                            _buildEventIcon(
                                Icons.sports_soccer, Colors.red, ownGoals),
                          ]
                        ],
                      ),
                      const SizedBox(height: 4),
                      // *** START ÄNDERUNG: Punkte-Box ausblenden ***
                      Opacity(
                        opacity: isNotStarted ? 0.0 : 1.0, // Verstecken, wenn nicht gestartet
                        child: Container(
                          width: 40,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: getColorForRating(punkte, 250),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            punkte.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // *** ENDE ÄNDERUNGEN ***
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helfer-Widget für die Team-Wappen
class _TeamCrest extends StatelessWidget {
  final String? imageUrl;
  const _TeamCrest({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: imageUrl != null
          ? Image.network(
        imageUrl!,
        errorBuilder: (context, error, stackTrace) =>
        const Icon(Icons.shield, color: Colors.grey, size: 24),
      )
          : const Icon(Icons.shield, color: Colors.grey, size: 24),
    );
  }
}