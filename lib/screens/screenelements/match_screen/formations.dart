// lib/screens/screenelements/match_screen/formations.dart
import 'package:flutter/material.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'dart:ui' as ui;
import 'dart:math';

// PlayerInfo-Modell bleibt unverändert
class PlayerInfo {
  final int id;
  final String name;
  final String position;
  final String? profileImageUrl;
  final int rating; // Das ist der 'punkte'-Wert
  final int goals;
  final int maxRating;
  final int assists;
  final int ownGoals;
  final int? jerseyNumber;


  const PlayerInfo({
    required this.id,
    required this.name,
    required this.position,
    this.profileImageUrl,
    required this.rating,
    required this.goals,
    required this.assists,
    required this.ownGoals,
    this.jerseyNumber,
    this.maxRating = 250
  });
}
/// Ein wiederverwendbares Widget für Spieler-Avatare mit Team-farbigem Rand.
class PlayerAvatar extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final double radius;

  const PlayerAvatar({
    super.key,
    required this.player,
    required this.teamColor,
    this.radius = 18,
  });



  // Baut ein Icon für ein bestimmtes Ereignis (Tor, Assist, etc.)
  Widget _buildEventIcon(IconData icon, Color color, int count, double size) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(size * 0.15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper = player.position.toUpperCase() == 'TW' || player.position.toUpperCase() == 'G';

    // === DYNAMISCHE GRÖSSENANPASSUNG ===
    final double ratingFontSize = radius * 0.5;
    final double nameFontSize = radius * 0.5;
    final double eventIconSize = radius * 0.45;
    final double spaceAfterAvatar = radius * 0.25;

    return SizedBox(
      width: radius * 3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isGoalkeeper ? Colors.orange.shade700 : teamColor,
                    width: 0.5,
                  ),
                  image: player.profileImageUrl != null
                      ? DecorationImage(
                    image: NetworkImage(player.profileImageUrl!),
                    fit: BoxFit.cover, // Diese Zeile verhindert das Abschneiden
                  )
                      : null,
                ),
                child: player.profileImageUrl == null
                    ? Icon(Icons.person, color: Colors.white, size: radius * 1.2)
                    : null,
              ),
              // Rating-Box
              Positioned(
                bottom: -radius * 0.2,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: radius * 0.2, vertical: radius * 0.05),
                  decoration: BoxDecoration(
                    color: getColorForRating(player.rating, player.maxRating),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    player.rating.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: ratingFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Event-Icons
              Positioned(
                top: -radius * 0.1,
                right: -radius * 0.1,
                child: Column(
                  children: [
                    _buildEventIcon(Icons.sports_soccer, Colors.white, player.goals, eventIconSize),
                    if (player.goals > 0) SizedBox(height: radius * 0.05),
                    _buildEventIcon(Icons.assistant, Colors.lightBlueAccent, player.assists, eventIconSize),
                    if (player.assists > 0) SizedBox(height: radius * 0.05),
                    _buildEventIcon(Icons.sports_soccer, Colors.red, player.ownGoals, eventIconSize),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spaceAfterAvatar),
          // Spielername
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              player.name.split(' ').last,
              style: TextStyle(color: Colors.white, fontSize: nameFontSize, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class MatchFormationDisplay extends StatelessWidget {
  // --- Heimteam (immer erforderlich) ---
  final String homeFormation;
  final List<PlayerInfo> homePlayers;
  final Color homeColor;

  // --- Auswärtsteam (optional) ---
  final String? awayFormation;
  final List<PlayerInfo>? awayPlayers;
  final Color? awayColor;
  final void Function(int playerId) onPlayerTap;
  final List<PlayerInfo>? substitutes;


  const MatchFormationDisplay({
    super.key,
    required this.homeFormation,
    required this.homePlayers,
    this.awayFormation,
    this.awayPlayers,
    required this.onPlayerTap,
    this.homeColor = Colors.blue,
    this.awayColor = Colors.red,
    this.substitutes,
  });

  @override
  @override
  Widget build(BuildContext context) {
    final bool singleTeamMode = awayPlayers == null || awayFormation == null;
    final bool showBench = substitutes != null && substitutes!.isNotEmpty;

    final homeGoalkeeper = _findGoalkeeper(homePlayers);
    final homeFieldPlayers = _findFieldPlayers(homePlayers, homeGoalkeeper);
    final homeFormationLines = _parseFormation(homeFormation);

    if (homeGoalkeeper == null || homeFieldPlayers.length < 10) {
      return const Center(child: Text('Ungültige Spielerdaten für das Heimteam.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;

        // 1. Feld-Berechnung
        const double widthFactor = 23.0;
        final double fieldAspectRatio = singleTeamMode ? (68 / 60) : (68 / 105);
        final double fieldHeightFactor = widthFactor / fieldAspectRatio;

        // 2. Bank-Berechnung (KORRIGIERT)
        // Höhe Container: 4.5 * Radius
        // Margin oben: 0.5 * Radius
        // Gesamtbedarf: 5.0 * Radius
        const double benchContainerFactor = 4.5;
        const double benchMarginFactor = 0.5;

        final double totalBenchFactor = showBench ? (benchContainerFactor + benchMarginFactor) : 0.0;
        final double totalHeightFactor = fieldHeightFactor + totalBenchFactor;

        // 3. Radius berechnen (Min aus Breite und Höhe)
        double radius = min(w / widthFactor, h / totalHeightFactor);
        radius = radius.clamp(5.0, 50.0);

        // 4. Tatsächliche Pixel-Größen
        final double fieldWidth = radius * widthFactor;
        final double fieldHeight = radius * fieldHeightFactor;
        final double benchHeight = radius * benchContainerFactor;
        final double benchMargin = radius * benchMarginFactor;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- SPIELFELD ---
            SizedBox(
              width: fieldWidth,
              height: fieldHeight,
              child: Stack(
                children: [
                  CustomPaint(size: Size.infinite, painter: _SoccerFieldPainter(singleTeamMode: singleTeamMode)),

                  if (singleTeamMode) ...[
                    _buildPlayerLine(context, [homeGoalkeeper], 0.99, homeColor, onPlayerTap, radius, false),
                    ..._buildFormationLines(context, homeFormationLines, homeFieldPlayers, false, homeColor, onPlayerTap, radius, singleTeamMode: true),
                  ] else ...[
                    _buildPlayerLine(context, [homeGoalkeeper], 0.99, homeColor, onPlayerTap, radius, false),
                    ..._buildFormationLines(context, homeFormationLines, homeFieldPlayers, false, homeColor, onPlayerTap, radius),
                  ],

                  if (!singleTeamMode)
                    _buildAwayTeam(context, constraints, radius),
                ],
              ),
            ),

            // --- BANK ---
            if (showBench)
              Container(
                height: benchHeight,
                width: fieldWidth,
                margin: EdgeInsets.only(top: benchMargin), // Nutzt den jetzt eingerechneten Margin
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black.withOpacity(0.1)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: radius),
                  child: Row(
                    children: substitutes!.map((player) {
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: radius * 0.5),
                        child: GestureDetector(
                          onTap: () => onPlayerTap(player.id),
                          child: PlayerAvatar(
                            player: player,
                            teamColor: homeColor,
                            radius: radius,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
  Widget _buildAwayTeam(BuildContext context, BoxConstraints constraints, double radius) {
    final awayGoalkeeper = _findGoalkeeper(awayPlayers!);
    final awayFieldPlayers = _findFieldPlayers(awayPlayers!, awayGoalkeeper);
    final awayFormationLines = _parseFormation(awayFormation!);

    if (awayGoalkeeper == null || awayFieldPlayers.length < 10) return const SizedBox.shrink();

    return Stack(
      children: [
        _buildPlayerLine(context, [awayGoalkeeper], 0.01, awayColor!, onPlayerTap, radius, true),
        ..._buildFormationLines(context, awayFormationLines, awayFieldPlayers, true, awayColor!, onPlayerTap, radius),
      ],
    );
  }

  PlayerInfo? _findGoalkeeper(List<PlayerInfo> players) {
    try {
      return players.firstWhere((p) => (p.position).contains('TW'));
    } catch (e) {
      return null;
    }
  }

  List<PlayerInfo> _findFieldPlayers(List<PlayerInfo> players, PlayerInfo? goalkeeper) {
    if (goalkeeper == null) return [];
    return players.where((p) => p != goalkeeper).toList();
  }

  List<int> _parseFormation(String formation) {
    return formation.split('-').map((e) => int.tryParse(e) ?? 0).toList();
  }

  List<Widget> _buildFormationLines(
      BuildContext context,
      List<int> formationLines,
      List<PlayerInfo> fieldPlayers,
      bool isAwayTeam,
      Color teamColor,
      void Function(int) onPlayerTap,
      double radius, { // Radius statt constraints nutzen
        bool singleTeamMode = false,
      }) {
    final List<Widget> lines = [];
    int playerIndexOffset = 0;

    double availableVerticalSpace, verticalSpacingFactor;

    if (singleTeamMode) {
      availableVerticalSpace = 0.325 * 105 / 60;
      verticalSpacingFactor = availableVerticalSpace / (formationLines.length > 1 ? formationLines.length - 1 : 1);
    } else {
      availableVerticalSpace = 0.325;
      verticalSpacingFactor = availableVerticalSpace / (formationLines.length > 1 ? formationLines.length - 1 : 1);
    }

    for (int i = 0; i < formationLines.length; i++) {
      final linePlayerCount = formationLines[i];
      if (playerIndexOffset + linePlayerCount > fieldPlayers.length) continue;

      double lineYPosition;
      if (singleTeamMode) {
        lineYPosition = 0.8 - (i * verticalSpacingFactor);
      } else if (isAwayTeam) {
        lineYPosition = 0.12 + (i * verticalSpacingFactor);
      } else {
        lineYPosition = 0.88 - (i * verticalSpacingFactor);
      }

      final linePlayers = fieldPlayers.sublist(playerIndexOffset, playerIndexOffset + linePlayerCount);
      lines.add(_buildPlayerLine(context, linePlayers, lineYPosition, teamColor, onPlayerTap, radius, isAwayTeam));
      playerIndexOffset += linePlayerCount;
    }
    return lines;
  }

  Widget _buildPlayerLine(
      BuildContext context,
      List<PlayerInfo> players,
      double lineYPosition,
      Color teamColor,
      void Function(int) onPlayerTap,
      double radius,
      bool isAwayTeam) {
    final playerCount = players.length;
    final orderedPlayers = isAwayTeam ? players : players.reversed.toList();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: List.generate(playerCount, (i) {
              final playerXPosition = (i + 1) / (playerCount + 1);
              return Align(
                alignment: Alignment((playerXPosition * 2) - 1, (lineYPosition * 2) - 1),
                child: GestureDetector(
                  onTap: () => onPlayerTap(orderedPlayers[i].id),
                  child: PlayerAvatar(
                    player: orderedPlayers[i],
                    teamColor: teamColor,
                    radius: radius, // Nutzung des berechneten Radius
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}


class _PlayerMarker extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final void Function(int) onPlayerTap;
  final double radius; // Radius wird empfangen

  const _PlayerMarker({
    required this.player,
    required this.teamColor,
    required this.onPlayerTap,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onPlayerTap(player.id),
      child: PlayerAvatar(player: player, teamColor: teamColor, radius: radius), // Radius wird weitergegeben
    );
  }
}

class _SoccerFieldPainter extends CustomPainter {
  final bool singleTeamMode;

  _SoccerFieldPainter({this.singleTeamMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // 1. Rasen: Schickes Streifenmuster
    final Color grassLight = const Color(0xFF4CAF50); // Klassisches Fußballgrün
    final Color grassDark = const Color(0xFF43A047);  // Leicht dunklerer Streifen

    // Hintergrund
    paint.color = grassLight;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Streifen zeichnen
    paint.color = grassDark;
    final double stripeHeight = size.height / 12; // 12 horizontale Streifen
    for (int i = 0; i < 12; i++) {
      if (i % 2 == 0) { // Jeder zweite Streifen
        canvas.drawRect(
          Rect.fromLTWH(0, i * stripeHeight, size.width, stripeHeight),
          paint,
        );
      }
    }

    // 2. Linien (Weiß, leicht transparent für besseres Blending)
    paint.color = Colors.white.withOpacity(0.9);
    paint.strokeWidth = 1.5; // Feine Linien
    paint.style = PaintingStyle.stroke;

    // Außenlinie
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final centerLineY = singleTeamMode ? size.height * (1 - 52.5 / 65) : size.height / 2;

    // Mittellinie
    canvas.drawLine(Offset(0, centerLineY), Offset(size.width, centerLineY), paint);

    // Mittelkreis
    canvas.drawCircle(Offset(size.width / 2, centerLineY), size.width * 0.15, paint);

    // Anstoßpunkt
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width / 2, centerLineY), 2.5, paint);
    paint.style = PaintingStyle.stroke;

    // --- Strafraumbereiche ---

    // Funktion zum Zeichnen einer Strafraumseite
    void drawPenaltyArea(bool isBottom) {
      final double yBase = isBottom ? size.height : 0;
      final int direction = isBottom ? -1 : 1;

      final penaltyAreaWidth = size.width * 0.6;
      final penaltyAreaHeight = size.height * (singleTeamMode ? 0.18 : 0.16);

      final goalAreaWidth = size.width * 0.25;
      final goalAreaHeight = size.height * (singleTeamMode ? 0.06 : 0.05);

      // Großer Strafraum (16er)
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(size.width / 2, yBase + (penaltyAreaHeight / 2 * direction)),
          width: penaltyAreaWidth,
          height: penaltyAreaHeight,
        ),
        paint,
      );

      // Torraum (5er)
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(size.width / 2, yBase + (goalAreaHeight / 2 * direction)),
          width: goalAreaWidth,
          height: goalAreaHeight,
        ),
        paint,
      );

      // Elfmeterpunkt
      final penaltySpotDist = size.height * (singleTeamMode ? 0.12 : 0.11);
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size.width / 2, yBase + (penaltySpotDist * direction)), 2, paint);
      paint.style = PaintingStyle.stroke;

      // Strafraum-Halbkreis (Arc)
      final arcRectSize = penaltyAreaWidth * 0.35;
      final arcRect = Rect.fromCenter(
        center: Offset(size.width / 2, yBase + (penaltySpotDist * direction)),
        width: arcRectSize,
        height: arcRectSize,
      );

      // Zeichnet nur den Teil des Kreises außerhalb des Strafraums
      final startAngle = isBottom ? pi : 0.0;
      // Wir zeichnen hier vereinfacht den Bogen, clipping wäre komplexer aber für die Größe okay
      // canvas.drawArc(arcRect, startAngle - 0.6, 1.2, false, paint);
      // (Optional: Bogen hinzufügen, wenn gewünscht, oft reicht der Punkt bei kleinen Screens)
    }

    // Zeichne unteren Strafraum (Heim)
    drawPenaltyArea(true);

    // Zeichne oberen Strafraum (Auswärts) nur im 2-Team-Modus
    if (!singleTeamMode) {
      drawPenaltyArea(false);
    }

    // Ecken (Corner Arcs)
    final double cornerSize = size.width * 0.02;
    if (!singleTeamMode) canvas.drawArc(Rect.fromLTWH(-cornerSize, -cornerSize, cornerSize*2, cornerSize*2), 0, pi/2, false, paint); // TL
    if (!singleTeamMode) canvas.drawArc(Rect.fromLTWH(size.width-cornerSize, -cornerSize, cornerSize*2, cornerSize*2), pi/2, pi/2, false, paint); // TR
    canvas.drawArc(Rect.fromLTWH(-cornerSize, size.height-cornerSize, cornerSize*2, cornerSize*2), -pi/2, pi/2, false, paint); // BL
    canvas.drawArc(Rect.fromLTWH(size.width-cornerSize, size.height-cornerSize, cornerSize*2, cornerSize*2), pi, pi/2, false, paint); // BR
  }

  @override
  bool shouldRepaint(covariant _SoccerFieldPainter oldDelegate) => oldDelegate.singleTeamMode != singleTeamMode;
}