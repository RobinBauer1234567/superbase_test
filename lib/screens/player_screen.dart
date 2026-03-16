import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:premier_league/screens/spiel_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/viewmodels/radar_chart_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/screenelements/match_screen/matchrating_screen.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:premier_league/screens/screenelements/position_pitch.dart';
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
  int? marketValue; // Variable für den State
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
  int totalPlayerPoints = 0;
  bool _hasInitialAutoScroll = false;
  List<Map<String, dynamic>> marktwertHistorie = [];
  double minMarktwert = 0;
  double maxMarktwert = 0;
  int totalGoals = 0;
  int totalAssists = 0;
  int totalMinutes = 0;
  int totalAppearances = 0;
  double playerForm = 0.0; // NEU: Form aus spieler_analytics

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // <-- Auf 4 erhöht
    _tabController.addListener(() {
      setState(() {});
    });
  }
  void didChangeDependencies() {
    super.didChangeDependencies();
    fetchPlayerData();
  }

  void _maybeScrollToUpcomingMatch() {
    if (_hasInitialAutoScroll) return;
    _hasInitialAutoScroll = true;
    _scrollToUpcomingMatch();
  }

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
        upcomingMatchIndex =
            teamMatches.isNotEmpty ? teamMatches.length - 1 : 0;
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

  int _extractMarketValue(dynamic analyticsRaw, int seasonId) {
    if (analyticsRaw is Map) {
      return (analyticsRaw['marktwert'] as num?)?.toInt() ?? 0;
    }
    if (analyticsRaw is List) {
      final selected = analyticsRaw.cast<Map<String, dynamic>>().firstWhere(
        (a) => a['season_id'] == seasonId,
        orElse: () => <String, dynamic>{},
      );
      return (selected['marktwert'] as num?)?.toInt() ?? 0;
    }
    return 0;
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
      // 1. Spieler- und Teamdaten abrufen (inkl. der neuen Analytics-Felder)
      final playerResponse = await supabase
          .from('season_players')
          .select(
          'team:team(id, name, image_url), spieler:spieler(name, position, profilbild_url, spieler_analytics(marktwert, season_id, form, anzahl_spiele, punkteschnitt, gesamtstatistiken))')
          .eq('season_id', seasonId)
          .eq('player_id', widget.playerId)
          .single();

      final spielerData = playerResponse['spieler'];
      teamData = playerResponse['team'];
      final playerTeamId = teamData!['id'];

      // --- ANALYTICS DIREKT AUS DER DATENBANK AUSLESEN ---
      final analyticsRaw = spielerData['spieler_analytics'];
      Map<String, dynamic> analytics = {};
      if (analyticsRaw is List && analyticsRaw.isNotEmpty) {
        analytics = analyticsRaw.firstWhere(
              (a) => a['season_id'] == seasonId,
          orElse: () => <String, dynamic>{},
        );
      } else if (analyticsRaw is Map) {
        analytics = analyticsRaw as Map<String, dynamic>;
      }

      int anzahlSpiele = (analytics['anzahl_spiele'] as num?)?.toInt() ?? 0;
      double form = (analytics['form'] as num?)?.toDouble() ?? 0.0;
      Map<String, dynamic> dbStats = analytics['gesamtstatistiken'] ?? {};

      // Mögliche Keys in gesamtstatistiken abfangen
      int dbTotalPoints = (dbStats['punkte'] as num?)?.toInt() ?? (dbStats['total_points'] as num?)?.toInt() ?? 0;
      int dbGoals = (dbStats['goals'] as num?)?.toInt() ?? (dbStats['tore'] as num?)?.toInt() ?? 0;
      int dbAssists = (dbStats['assists'] as num?)?.toInt() ?? 0;
      int dbMinutes = (dbStats['minutesPlayed'] as num?)?.toInt() ?? (dbStats['minuten'] as num?)?.toInt() ?? 0;


      // 2. ALLE Spiele des Teams abrufen
      final teamMatchesResponse = await supabase
          .from('spiel')
          .select(
          '*, '
              'heimteam:team!spiel_heimteam_id_fkey(name, image_url), '
              'auswaertsteam:team!spiel_auswärtsteam_id_fkey(name, image_url), '
              'matchrating!left(*)')
          .eq('season_id', seasonId)
          .or('heimteam_id.eq.$playerTeamId,auswärtsteam_id.eq.$playerTeamId')
          .eq('matchrating.spieler_id', widget.playerId)
          .order('datum', ascending: true);

      if (!mounted) return;

      // 3. Marktwert Historie abrufen (Wichtig für Graph & MW-Trend)
      final historyResponse = await supabase
          .from('marktwert_historie')
          .select('marktwert, datum')
          .eq('spieler_id', widget.playerId)
          .eq('season_id', seasonId)
          .order('datum', ascending: true);

      double tempMin = double.infinity;
      double tempMax = 0;
      List<Map<String, dynamic>> historyData = [];

      for (var row in historyResponse) {
        double val = (row['marktwert'] as num).toDouble();
        if (val < tempMin) tempMin = val;
        if (val > tempMax) tempMax = val;
        historyData.add({
          'datum': DateTime.parse(row['datum']),
          'marktwert': val,
        });
      }

      int currentMarketValue = _extractMarketValue(analyticsRaw, seasonId);
      if (historyData.isEmpty && currentMarketValue > 0) {
        tempMin = currentMarketValue.toDouble();
        tempMax = currentMarketValue.toDouble();
        historyData.add({'datum': DateTime.now(), 'marktwert': currentMarketValue.toDouble()});
      }

      // 4. Daten für Radar-Chart & Fallback vorbereiten
      final actualRatings = teamMatchesResponse
          .where((match) => (match['matchrating'] as List<dynamic>).isNotEmpty)
          .map((match) {
        final rating = (match['matchrating'] as List<dynamic>).first;
        return {
          'match_position': rating['match_position'],
          'punkte': rating['punkte'],
          'statistics': rating['statistics'],
          'spiel': match,
        };
      }).toList();

      // Fallback-Zähler (falls die DB noch leer ist)
      int aggregatedPoints = 0;
      int tempGoals = 0;
      int tempAssists = 0;
      int tempMinutes = 0;
      int tempAppearances = actualRatings.length;

      for (var rating in actualRatings) {
        final points = (rating['punkte'] as num? ?? 0.0).toDouble();
        aggregatedPoints += points.round();

        final stats = rating['statistics'] as Map<String, dynamic>? ?? {};
        tempGoals += (stats['goals'] as num? ?? 0).toInt();
        tempAssists += (stats['assists'] as num? ?? 0).toInt();
        tempMinutes += (stats['minutesPlayed'] as num? ?? 0).toInt();
      }

      // 5. Zuweisung: DB-Werte haben Vorrang, andernfalls wird der Fallback genutzt
      int finalTotalPoints = dbTotalPoints > 0 ? dbTotalPoints : aggregatedPoints;
      int finalAppearances = anzahlSpiele > 0 ? anzahlSpiele : tempAppearances;
      int finalGoals = dbGoals > 0 ? dbGoals : tempGoals;
      int finalAssists = dbAssists > 0 ? dbAssists : tempAssists;
      int finalMinutes = dbMinutes > 0 ? dbMinutes : tempMinutes;

      // NEU: Durchschnitt strikt aus Gesamtpunktzahl / Anzahl Spiele berechnen!
      double calculatedAverageRating = finalAppearances > 0
          ? (finalTotalPoints / finalAppearances)
          : 0.0;

      // 6. Positionen parsen
      String rawPositions = spielerData['position'] ?? 'N/A';
      List<String> parsedPositions = rawPositions.split(',').map((p) => p.trim()).toList();
      if (parsedPositions.isEmpty || parsedPositions.first.isEmpty) {
        parsedPositions = ['N/A'];
      }

      final String selectedPos =
      (selectedPosition != null && parsedPositions.contains(selectedPosition))
          ? selectedPosition!
          : parsedPositions.last;

      // 7. Alles dem State übergeben
      setState(() {
        playerName = spielerData['name'];
        marketValue = currentMarketValue;
        teamName = teamData!['name'];
        teamImageUrl = teamData!['image_url'];
        profileImageUrl = spielerData['profilbild_url'] ??
            'https://rcfetlzldccwjnuabfgj.supabase.co/storage/v1/object/public/spielerbilder//Photo-Missing.png';

        teamMatches = teamMatchesResponse;
        matchRatingsRaw = actualRatings;
        availablePositions = parsedPositions;
        selectedPosition = selectedPos;

        // Zuweisung der finalen Statistik-Werte
        totalPlayerPoints = finalTotalPoints;
        totalAppearances = finalAppearances;
        totalGoals = finalGoals;
        totalAssists = finalAssists;
        totalMinutes = finalMinutes;
        averagePlayerRating = calculatedAverageRating;
        playerForm = form; // Die Form aus der DB

        // Marktwert-Historie Zuweisung (Für Graphen & Trend)
        marktwertHistorie = historyData;
        minMarktwert = tempMin;
        maxMarktwert = tempMax;
      });

      _maybeScrollToUpcomingMatch();

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

  String _formatMarketValue(int? value) {
    if (value == null) return 'N/A';
    final formatter = NumberFormat.decimalPattern('de_DE');
    return '${formatter.format(value)} €';
  }

  Widget _buildCollapsedPlayerBar() {
    final maxTotalScore = (teamMatches.length * 250 * 0.8).round();
    final playerInfo = PlayerInfo(
      id: widget.playerId,
      name: playerName,
      position: availablePositions.join(', '),
      profileImageUrl: profileImageUrl,
      rating: totalPlayerPoints,
      goals: 0,
      assists: 0,
      ownGoals: 0,
      maxRating: maxTotalScore > 0 ? maxTotalScore : 1,
    );

    final scoreColor = getColorForRating(
      playerInfo.rating,
      playerInfo.maxRating,
    );

    return Container(
      height: kToolbarHeight,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          PlayerAvatar(
            player: playerInfo,
            teamColor: Colors.blueGrey,
            radius: 18,
            showDetails: false,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  _formatMarketValue(marketValue),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (teamImageUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Image.network(
                teamImageUrl!,
                width: 22,
                height: 22,
                errorBuilder:
                    (context, error, stackTrace) =>
                        const Icon(Icons.shield, size: 22),
              ),
            ),
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.1),
              border: Border.all(color: scoreColor.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                playerInfo.rating.toString(),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scoreColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart({required bool isPreview, Function(int)? onSpotTouched, int? selectedIndex,}) {
    List<FlSpot> spots = [];
    for (int i = 0; i < marktwertHistorie.length; i++) {
      spots.add(FlSpot(i.toDouble(), marktwertHistorie[i]['marktwert']));
    }

    ExtraLinesData extraLines = ExtraLinesData();
    if (!isPreview &&
        selectedIndex != null &&
        selectedIndex >= 0 &&
        selectedIndex < marktwertHistorie.length) {
      double xPos = selectedIndex.toDouble();
      double yPos = marktwertHistorie[selectedIndex]['marktwert'];

      extraLines = ExtraLinesData(
        extraLinesOnTop: false,
        verticalLines: [
          VerticalLine(
            x: xPos,
            color: Colors.blueGrey.shade400,
            strokeWidth: 1.5,
            dashArray: [4, 4],
          ),
        ],
        horizontalLines: [
          HorizontalLine(
            y: yPos,
            color: Colors.blueGrey.shade400,
            strokeWidth: 1.5,
            dashArray: [4, 4],
          ),
        ],
      );
    }

    final Color lineColor = Colors.teal.shade600;

    return LineChart(
      LineChartData(
        extraLinesData: extraLines,
        minX: 0,
        maxX: (marktwertHistorie.length - 1).toDouble(),
        minY: minMarktwert * 0.9,
        maxY: maxMarktwert * 1.1,
        lineTouchData: LineTouchData(
          enabled: !isPreview,
          touchCallback: (
            FlTouchEvent event,
            LineTouchResponse? touchResponse,
          ) {
            if (event is FlTapUpEvent || event is FlPanUpdateEvent) {
              if (touchResponse != null &&
                  touchResponse.lineBarSpots != null &&
                  touchResponse.lineBarSpots!.isNotEmpty) {
                if (onSpotTouched != null) {
                  onSpotTouched(touchResponse.lineBarSpots!.first.spotIndex);
                }
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems:
                (touchedSpots) => touchedSpots.map((_) => null).toList(),
          ),
        ),
        gridData: FlGridData(
          show: !isPreview,
          drawVerticalLine: true,
          horizontalInterval: maxMarktwert > 0 ? (maxMarktwert * 0.2) : 1000000,
          getDrawingHorizontalLine:
              (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          getDrawingVerticalLine:
              (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: !isPreview,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: !isPreview,
              reservedSize: 45,
              getTitlesWidget: (value, meta) {
                if (value == minMarktwert * 0.9 || value == maxMarktwert * 1.1)
                  return const SizedBox.shrink();

                String text;
                if (value >= 1000000) {
                  text = '${(value / 1000000).toStringAsFixed(1)}M';
                } else if (value >= 1000) {
                  text = '${(value / 1000).toStringAsFixed(0)}k';
                } else {
                  text = value.toStringAsFixed(0);
                }

                // --- HIER WURDE axisSide ZU meta: meta GEÄNDERT ---
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blueGrey.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 &&
                    value.toInt() < marktwertHistorie.length) {
                  if (value.toInt() % (marktwertHistorie.length / 4).ceil() ==
                      0) {
                    final date =
                        marktwertHistorie[value.toInt()]['datum'] as DateTime;

                    // --- HIER AUCH FÜR DIE X-ACHSE ANGEPASST ---
                    return SideTitleWidget(
                      meta: meta,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          DateFormat('dd.MM.').format(date),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blueGrey.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }
                }
                return const SizedBox.shrink();
              },
              reservedSize: 30,
            ),
          ),
        ),
        borderData: FlBorderData(
          show: !isPreview,
          border: Border(
            bottom: BorderSide(color: Colors.blueGrey.shade200, width: 2),
            left: BorderSide(color: Colors.blueGrey.shade200, width: 2),
            right: const BorderSide(color: Colors.transparent),
            top: const BorderSide(color: Colors.transparent),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, barData) {
                return selectedIndex != null &&
                    spot.x == selectedIndex.toDouble() &&
                    !isPreview;
              },
              // --- HIER WURDE getDrawingDot ZU getDotPainter GEÄNDERT ---
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 6,
                  color: Colors.white,
                  strokeWidth: 3,
                  strokeColor: lineColor,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  lineColor.withOpacity(0.4),
                  lineColor.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarktwertAenderung() {
    // Wenn es weniger als 2 Einträge gibt, gab es noch keine Änderung
    if (marktwertHistorie.length < 2) {
      return const Text(
        ' +/- 0',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      );
    }

    // Aktuellen und vorherigen Wert aus der Historie auslesen
    double currentVal = marktwertHistorie.last['marktwert'];
    double previousVal =
        marktwertHistorie[marktwertHistorie.length - 2]['marktwert'];
    double diff = currentVal - previousVal;

    // Wenn sich der Wert nicht verändert hat
    if (diff == 0) {
      return const Text(
        ' +/- 0',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      );
    }

    bool isPositive = diff > 0;
    return Row(
      children: [
        Icon(
          isPositive ? Icons.arrow_upward : Icons.arrow_downward,
          color: isPositive ? Colors.green : Colors.red,
          size: 16,
        ),
        Text(
          _formatMarketValue(
            diff.abs().toInt(),
          ), // .abs() entfernt das Minuszeichen, da wir den Pfeil haben
          style: TextStyle(
            color: isPositive ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
// --- Helfer: Basis-Kachel (Bento-Box) ---
// --- Helfer: Basis-Kachel exakt wie MatchCard formatiert ---
// --- Helfer: Basis-Kachel exakt wie MatchCard formatiert ---
  Widget _buildBentoBox({required Widget child, VoidCallback? onTap, Color? bgColor, Color? borderColor}) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      // Die Karte selbst ist IMMER weiß, damit der dunkle Schatten nicht durchscheint!
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: borderColor ?? Colors.transparent,
          width: borderColor != null ? 1.5 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        // Das Ink-Widget legt unsere transparente Farbe über das Weiß,
        // ohne den Klick-Effekt (Ripple) kaputt zu machen.
        child: Ink(
          decoration: BoxDecoration(
            color: bgColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: child,
          ),
        ),
      ),
    );
  }
  // --- Helfer: Mini-Bereich (Jetzt auch mit eigenen Text-Icons) ---
  Widget _buildMiniStat({
    required String value,
    required String label,
    IconData? icon,
    Widget? customIcon,
    Color? valueColor,
    Color? iconColor,
    Color? bgColor,
    Color? borderColor,
  }) {
    return _buildBentoBox(
      bgColor: bgColor,
      borderColor: borderColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          customIcon ?? Icon(icon, color: iconColor ?? Colors.blueGrey.shade600, size: 24),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: valueColor ?? Colors.black87)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: iconColor ?? Colors.blueGrey.shade400, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showMarktwertGraphOverlay(BuildContext context) {
    int? selectedSpotIndex =
        marktwertHistorie.isNotEmpty ? marktwertHistorie.length - 1 : null;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setStateOverlay) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      20,
                    ), // Etwas rundere Ecken
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  height: 480,
                  width: double.infinity,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Marktwert Historie',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.black54,
                                size: 20,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width:
                                marktwertHistorie.length > 20
                                    ? marktwertHistorie.length * 20.0
                                    : MediaQuery.of(context).size.width - 72,
                            child: _buildLineChart(
                              isPreview: false,
                              selectedIndex: selectedSpotIndex,
                              onSpotTouched: (index) {
                                setStateOverlay(() {
                                  selectedSpotIndex = index;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- DIE STEUERUNG UNTEN (Neues Design) ---
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child:
                            selectedSpotIndex == null
                                ? const Center(child: Text('Keine Daten'))
                                : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back_ios_rounded,
                                        size: 22,
                                      ),
                                      color:
                                          selectedSpotIndex! > 0
                                              ? Colors.teal.shade700
                                              : Colors.grey.shade400,
                                      onPressed:
                                          selectedSpotIndex! > 0
                                              ? () {
                                                setStateOverlay(() {
                                                  selectedSpotIndex =
                                                      selectedSpotIndex! - 1;
                                                });
                                              }
                                              : null,
                                    ),

                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'DATUM',
                                                style: TextStyle(
                                                  color:
                                                      Colors.blueGrey.shade400,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                DateFormat('dd.MM.yyyy').format(
                                                  marktwertHistorie[selectedSpotIndex!]['datum'],
                                                ),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            width: 1,
                                            height: 30,
                                            color: Colors.blueGrey.shade200,
                                          ), // Trennstrich
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'WERT',
                                                style: TextStyle(
                                                  color:
                                                      Colors.blueGrey.shade400,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatMarketValue(
                                                  marktwertHistorie[selectedSpotIndex!]['marktwert']
                                                      .toInt(),
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: Colors.teal.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 22,
                                      ),
                                      color:
                                          selectedSpotIndex! <
                                                  marktwertHistorie.length - 1
                                              ? Colors.teal.shade700
                                              : Colors.grey.shade400,
                                      onPressed:
                                          selectedSpotIndex! <
                                                  marktwertHistorie.length - 1
                                              ? () {
                                                setStateOverlay(() {
                                                  selectedSpotIndex =
                                                      selectedSpotIndex! + 1;
                                                });
                                              }
                                              : null,
                                    ),
                                  ],
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: anim1,
              curve: const SpringCurve(),
            ), // Etwas weichere Animation
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage))
              : NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context,
                      ),
                      sliver: SliverAppBar(
                        expandedHeight: 240, // <-- REDUZIERT von 290
                        pinned: true,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 1,
                        flexibleSpace: LayoutBuilder(
                          builder: (context, constraints) {
                            final safeAreaTop = MediaQuery.of(context).padding.top;
                            const collapsedBottomHeight = 48.0;
                            final collapsedHeight = kToolbarHeight + collapsedBottomHeight + safeAreaTop;
                            const expandedHeight = 240.0;
                            var fade = 1.0;
                            if (expandedHeight > collapsedHeight) {
                              fade =
                                  (constraints.maxHeight - collapsedHeight) /
                                  (expandedHeight - collapsedHeight);
                              fade = fade.clamp(0.0, 1.0);
                            }

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned(
                                  top: safeAreaTop + 18,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                    ignoring: fade < 0.5,
                                    child: Opacity(
                                      opacity: fade,
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            height: 140,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 2,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Opacity(
                                                      opacity: 0.4,
                                                      child:
                                                          teamImageUrl != null
                                                              ? Image.network(
                                                                teamImageUrl!,
                                                                width: 110,
                                                                height: 110,
                                                                fit:
                                                                    BoxFit
                                                                        .contain,
                                                              )
                                                              : const SizedBox.shrink(),
                                                    ),
                                                  ),
                                                ),
                                                ClipOval(
                                                  child:
                                                      profileImageUrl != null
                                                          ? Image.network(
                                                            profileImageUrl!,
                                                            width: 130,
                                                            height: 130,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) {
                                                              return const Icon(
                                                                Icons.error,
                                                                size: 100,
                                                                color:
                                                                    Colors.red,
                                                              );
                                                            },
                                                          )
                                                          : const Icon(
                                                            Icons.person,
                                                            size: 100,
                                                            color: Colors.grey,
                                                          ),
                                                ),
                                                const Expanded(
                                                  flex: 2,
                                                  child: SizedBox.shrink(),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            playerName,
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: safeAreaTop,
                                  left: 72,
                                  right: 16,
                                  height: kToolbarHeight,
                                  child: IgnorePointer(
                                    ignoring: fade > 0.5,
                                    child: Opacity(
                                      opacity: 1.0 - fade,
                                      child: _buildCollapsedPlayerBar(),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        bottom: TabBar(
                          controller: _tabController,
                          isScrollable: false,
                          indicatorSize: TabBarIndicatorSize.tab,
                          tabs: const [
                            Tab(text: 'Übersicht'),
                            Tab(text: 'Saisonspiele'),
                            Tab(text: 'Radar Chart'),
                            Tab(text: 'Marktwert'),
                          ],
                        ),
                      ),
                    ),
                  ];
                },
            body: TabBarView(
              controller: _tabController,
              children: [
// --- 1. ÜBERSICHTS-TAB (Neues, logisches Layout) ---
                Builder(
                  builder: (context) {
                    final now = DateTime.now();
                    final upcomingMatches = teamMatches.where((m) {
                      if (m['datum'] == null) return false;
                      try {
                        return DateTime.parse(m['datum']).isAfter(now);
                      } catch (_) { return false; }
                    }).take(3).toList();

                    int avgMinutes = totalAppearances > 0 ? (totalMinutes / totalAppearances).round() : 0;
                    int pointsPer90 = totalMinutes > 0 ? (totalPlayerPoints / (totalMinutes / 90)).round() : 0;

                    double pointsPerMio = marketValue != null && marketValue! > 0
                        ? totalPlayerPoints / (marketValue! / 1000000)
                        : 0.0;

                    // --- UNABHÄNGIGE FARBBRECHNUNGEN ---

                    // 1. Gesamtpunkte (Maximalwert abhängig von der Anzahl der Saisonspiele)
                    int maxTotalScore = (teamMatches.length * 250 * 0.8).round();
                    if (maxTotalScore < 1) maxTotalScore = 1;
                    final Color colorGesamt = getColorForRating(totalPlayerPoints, maxTotalScore);

                    // 2. Durchschnitt (Punkte pro einzelnem Spiel, ca. 250 als theoretisches Maximum)
                    final Color colorAvg = getColorForRating(averagePlayerRating.round(), 250);

                    // 3. Form (Wert zwischen 0.0 und 3.0 aus der DB).
                    // Da getColorForRating wahrscheinlich Ganzzahlen (int) nutzt, multiplizieren wir es mit 10 (z.B. 2.5 wird 25 von 30)
                    final Color colorForm = getColorForRating(playerForm.round(), 250);

                    return CustomScrollView(
                      key: const PageStorageKey<String>('playerUebersichtTab'),
                      slivers: [
                        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                        SliverPadding(
                          padding: const EdgeInsets.all(16.0),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              // --- REIHE 1: Marktwert & Pkt/Mio (Links) und Position (Rechts) ---
                              SizedBox(
                                height: 240, // Höhe für die gestapelten, länglichen Boxen
                                child: Row(
                                  children: [
                                    // Linke Spalte (Marktwert & Pkt/Mio)
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            flex: 1,
                                            child: _buildBentoBox(
                                              onTap: () => _tabController.animateTo(3),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.payments_rounded, color: Colors.blueGrey.shade600, size: 22),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            _formatMarketValue(marketValue),
                                                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade900),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildMarktwertAenderung(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          // Pkt/Mio exakt in gleicher Größe direkt darunter
                                          Expanded(
                                            flex: 1,
                                            child: _buildMiniStat(value: pointsPerMio.toStringAsFixed(1), label: 'GESAMMTPUNKTE / MIO', icon: Icons.savings_outlined),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Rechte Spalte (Das Spielfeld)
                                    Expanded(
                                      flex: 4,
                                      child: _buildBentoBox(
                                        child: Center(
                                          child: PositionPitch(availablePositions: availablePositions),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: totalPlayerPoints.toString(),
                                      label: 'GESAMTPUNKTE',
                                      icon: Icons.circle,
                                      valueColor: colorGesamt,
                                      iconColor: colorGesamt,
                                      bgColor: colorGesamt.withOpacity(0.1),
                                      borderColor: colorGesamt.withOpacity(0.3),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: averagePlayerRating.toStringAsFixed(0),
                                      label: 'DURCHSCHNITT',
                                      customIcon: Text('Ø', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: colorAvg)),
                                      valueColor: colorAvg,
                                      iconColor: colorAvg,
                                      bgColor: colorAvg.withOpacity(0.1),
                                      borderColor: colorAvg.withOpacity(0.3),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: playerForm.toStringAsFixed(1),
                                      label: 'FORM',
                                      icon: Icons.query_stats_rounded,
                                      valueColor: colorForm,
                                      iconColor: colorForm,
                                      bgColor: colorForm.withOpacity(0.1),
                                      borderColor: colorForm.withOpacity(0.3),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
// --- REIHE 3: Einsätze, Minuten & Pkt pro 90 (MatchCard Look) ---
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: totalAppearances.toString(),
                                      label: 'EINSÄTZE',
                                      icon: Icons.directions_run_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: '$avgMinutes\'',
                                      label: 'Ø-MINUTEN',
                                      icon: Icons.timer_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: pointsPer90.toString(),
                                      label: 'PKT / 90 MIN',
                                      icon: Icons.av_timer_rounded,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // --- REIHE 4: Tore & Vorlagen (MatchCard Look) ---
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: totalGoals.toString(),
                                      label: 'TORE',
                                      icon: Icons.sports_soccer,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildMiniStat(
                                      value: totalAssists.toString(),
                                      label: 'VORLAGEN',
                                      customIcon: const Text('👟', style: TextStyle(fontSize: 24)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // --- REIHE 5: Nächste Spiele (MatchCard Look) ---
                              _buildBentoBox(
                                onTap: () => _tabController.animateTo(1),
                                child: upcomingMatches.isEmpty
                                    ? Center(child: Text('Keine Spiele', style: TextStyle(color: Colors.blueGrey.shade300)))
                                    : Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: upcomingMatches.map((match) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _TeamCrest(imageUrl: match['heimteam']['image_url']),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                          child: Text(':', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade300)),
                                        ),
                                        _TeamCrest(imageUrl: match['auswaertsteam']['image_url']),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),

                            ]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Builder(
            builder: (context) {
              return CustomScrollView(
                key: const PageStorageKey<String>('playerMatchesTab'),
                controller: _scrollController,
                slivers: [
                  SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                  if (teamMatches.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('Keine Spiele vorhanden')),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final match = teamMatches[index];
                          return MatchRatingRow(
                            match: match,
                            playerId: widget.playerId,
                            playerName: playerName,
                            playerProfileImageUrl: profileImageUrl,
                          );
                        },
                        childCount: teamMatches.length,
                      ),
                    ),
                ],
              );
            },
          ),
                Builder(
                      builder: (context) {
                        return CustomScrollView(
                          key: const PageStorageKey<String>('playerRadarTab'),
                          slivers: [
                            SliverOverlapInjector(
                              handle:
                                  NestedScrollView.sliverOverlapAbsorberHandleFor(
                                    context,
                                  ),
                            ),
                            if (radarChartData.isEmpty)
                              const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text('Statistiken nicht verfügbar.'),
                                ),
                              )
                            else
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8.0,
                                        horizontal: 16.0,
                                      ),
                                      child: DropdownButton<String>(
                                        value: selectedPosition,
                                        isExpanded: true,
                                        hint: const Text(
                                          'Vergleichsposition wählen',
                                        ),
                                        items:
                                            availablePositions.map((
                                              String value,
                                            ) {
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
                                              newValue,
                                            );
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
                              ),
                          ],
                        );
                      },
                    ),
                Builder(
                      builder: (context) {
                        return CustomScrollView(
                          key: const PageStorageKey<String>(
                            'playerMarktwertTab',
                          ),
                          slivers: [
                            SliverOverlapInjector(
                              handle:
                                  NestedScrollView.sliverOverlapAbsorberHandleFor(
                                    context,
                                  ),
                            ),
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Allgemeine Infos',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            // --- DIESER BEREICH WIRD ANGEPASST ---
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Aktueller Wert',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    Text(
                                                      _formatMarketValue(
                                                        marketValue,
                                                      ),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                      width: 8,
                                                    ), // Etwas Abstand
                                                    _buildMarktwertAenderung(), // Aufruf unserer neuen Methode!
                                                  ],
                                                ),
                                              ],
                                            ),
                                            // ------------------------------------
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                const Text(
                                                  'Höchstwert',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                Text(
                                                  _formatMarketValue(
                                                    maxMarktwert.toInt(),
                                                  ),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text(
                                      'Marktwert Verlauf',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Das klickbare Vorschau-Fenster für den Graphen
                                    GestureDetector(
                                      onTap: () {
                                        if (marktwertHistorie.isNotEmpty) {
                                          _showMarktwertGraphOverlay(context);
                                        }
                                      },
                                      child: Card(
                                        elevation: 2,
                                        child: Container(
                                          height: 200,
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(16),
                                          child:
                                              marktwertHistorie.isEmpty
                                                  ? const Center(
                                                    child: Text(
                                                      'Keine Historie vorhanden',
                                                    ),
                                                  )
                                                  : IgnorePointer(
                                                    // Deaktiviert Interaktion auf der Vorschau
                                                    child: _buildLineChart(
                                                      isPreview: true,
                                                    ),
                                                  ),
                                        ),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8.0),
                                      child: Center(
                                        child: Text(
                                          'Tippe auf den Graphen, um ihn interaktiv zu öffnen.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
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
    final status =
        match['status']?.toString().toLowerCase() ?? 'nicht gestartet';

    // Für zukünftige Spiele kein Icon anzeigen
    if (status == 'nicht gestartet') {
      return const SizedBox(
        width: 16,
      ); // Platzhalter, damit Layout konsistent bleibt
    }

    final ratingList = match['matchrating'] as List<dynamic>;
    final playerRating =
        ratingList.isNotEmpty ? ratingList.first as Map<String, dynamic> : null;

    // Fall 1: Spiel gespielt, aber kein Rating -> Nicht im Kader
    if (playerRating == null) {
      return Tooltip(
        message: 'Nicht im Kader',
        child: Icon(
          Icons.person_off_outlined,
          size: 16,
          color: Colors.grey.shade700,
        ),
      );
    }

    final formationIndex = playerRating['formationsindex'] as int?;

    // Fall 2: Rating vorhanden, Index < 11 -> Startelf
    if (formationIndex != null && formationIndex < 11) {
      return Tooltip(
        message: 'Startelf',
        child: Icon(
          Icons.play_circle_fill_outlined,
          size: 16,
          color: Colors.green.shade700,
        ),
      );
    }

    // Fall 3: Rating vorhanden, Index >= 11 -> Bank
    return Tooltip(
      message: 'Bank',
      child: Icon(
        Icons.event_seat_outlined,
        size: 16,
        color: Colors.orange.shade700,
      ),
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
    final status =
        match['status']?.toString().toLowerCase() ?? 'nicht gestartet';
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
          MaterialPageRoute(builder: (context) => GameScreen(spiel: match)),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (showTeamNames) const SizedBox(width: 8),
                        _TeamCrest(imageUrl: heimTeam['image_url']),

                        // *** START ÄNDERUNG: Ergebnis ODER Uhrzeit ***
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child:
                              isNotStarted
                                  ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        '-:-',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        formattedTime,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  )
                                  : Text(
                                    ergebnis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                        ),

                        // *** ENDE ÄNDERUNG ***
                        _TeamCrest(imageUrl: auswaertsTeam['image_url']),
                        if (showTeamNames) const SizedBox(width: 8),
                        if (showTeamNames)
                          Expanded(
                            child: Text(
                              auswaertsTeam['name'] ?? '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                        duration: Duration(seconds: 2),
                      ),
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
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "$minutesPlayed'",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                          const Spacer(),
                          // Nur anzeigen, wenn Spiel gestartet
                          if (!isNotStarted) ...[
                            _buildEventIcon(
                              Icons.sports_soccer,
                              Colors.black,
                              goals,
                            ),
                            _buildEventIcon(
                              Icons.assistant,
                              Colors.blue,
                              assists,
                            ),
                            _buildEventIcon(
                              Icons.sports_soccer,
                              Colors.red,
                              ownGoals,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: (isNotStarted
                                  ? Colors.grey
                                  : getColorForRating(punkte, 250))
                              .withOpacity(0.1),
                          border: Border.all(
                            color: (isNotStarted
                                    ? Colors.grey
                                    : getColorForRating(punkte, 250))
                                .withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isNotStarted ? '-' : punkte.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                isNotStarted
                                    ? Colors.grey
                                    : getColorForRating(punkte, 250),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
      child:
          imageUrl != null
              ? Image.network(
                imageUrl!,
                errorBuilder:
                    (context, error, stackTrace) =>
                        const Icon(Icons.shield, color: Colors.grey, size: 24),
              )
              : const Icon(Icons.shield, color: Colors.grey, size: 24),
    );
  }
}

// Eine kleine Hilfsklasse für eine schönere Pop-Up Animation
class SpringCurve extends Curve {
  const SpringCurve();
  @override
  double transformInternal(double t) {
    return (1.0 - (1.0 - t) * (1.0 - t));
  }
}
