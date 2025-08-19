import 'package:flutter/material.dart';
import 'dart:ui' as ui;

// PlayerInfo-Modell angepasst, um nur die benötigten Daten zu enthalten
class PlayerInfo {
  final int id;
  final String name;
  final String position;
  final String? profileImageUrl;
  final int rating; // Das ist der 'punkte'-Wert
  final int goals;
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
  });
}

/// Ein wiederverwendbares Widget für Spieler-Avatare mit Team-farbigem Rand.
class PlayerAvatar extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final double radius;

  const PlayerAvatar({
    required this.player,
    required this.teamColor,
    this.radius = 18, // Verkleinert für die Feldansicht
  });

  // Bestimmt die Farbe für die Rating-Box basierend auf dem Wert
  Color _getColorForRating(int rating) {
    if (rating >= 150) return Colors.teal;
    if (rating >= 100) return Colors.green;
    if (rating >= 50) return Colors.yellow.shade700;
    return Colors.red;
  }

  // Baut ein Icon für ein bestimmtes Ereignis (Tor, Assist, etc.)
  Widget _buildEventIcon(IconData icon, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper = player.position.toUpperCase() == 'TW' || player.position.toUpperCase() == 'G';

    return SizedBox(
      width: radius * 2 + 10, // Genug Platz für den Namen
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Spielerbild mit farbigem Rand
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isGoalkeeper ? Colors.orange.shade700 : teamColor,
                    width: 1.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: radius,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: player.profileImageUrl != null
                      ? NetworkImage(player.profileImageUrl!)
                      : null,
                  child: player.profileImageUrl == null
                      ? Icon(Icons.person, color: Colors.white, size: radius * 1.2)
                      : null,
                ),
              ),
              // Rating-Box
              Positioned(
                bottom: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _getColorForRating(player.rating),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    player.rating.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Event-Icons
              Positioned(
                top: -2,
                right: -2,
                child: Column(
                  children: [
                    _buildEventIcon(Icons.sports_soccer, Colors.white, player.goals),
                    if (player.goals > 0) const SizedBox(height: 1),
                    _buildEventIcon(Icons.assistant, Colors.lightBlueAccent, player.assists),
                    if (player.assists > 0) const SizedBox(height: 1),
                    _buildEventIcon(Icons.sports_soccer, Colors.red, player.ownGoals),

                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Spielername
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              player.name.split(' ').last,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}



/// Ein Widget, das die Formationen beider Mannschaften auf einem Spielfeld anzeigt.
class MatchFormationDisplay extends StatelessWidget {
  // --- Heimteam ---
  final String homeFormation;
  final List<PlayerInfo> homePlayers;
  final Color homeColor;

  // --- Auswärtsteam ---
  final String awayFormation;
  final List<PlayerInfo> awayPlayers;
  final Color awayColor;
  final void Function(int playerId) onPlayerTap;


  const MatchFormationDisplay({
    super.key,
    required this.homeFormation,
    required this.homePlayers,
    required this.awayFormation,
    required this.awayPlayers,
    required this.onPlayerTap, // Im Konstruktor hinzugefügt

    this.homeColor = Colors.blue, // Standardfarbe für Heimteam
    this.awayColor = Colors.red, // Standardfarbe für Auswärtsteam
  })  : assert(homePlayers.length >= 11, 'Heimteam muss 11 Spieler haben.'),
        assert(awayPlayers.length >= 11, 'Auswärtsteam muss 11 Spieler haben.');

  @override
  Widget build(BuildContext context) {
    // Daten für das Heimteam aufbereiten
    final homeGoalkeeper = _findGoalkeeper(homePlayers);
    final homeFieldPlayers = _findFieldPlayers(homePlayers, homeGoalkeeper);
    final homeFormationLines = _parseFormation(homeFormation);

    // Daten für das Auswärtsteam aufbereiten
    final awayGoalkeeper = _findGoalkeeper(awayPlayers);
    final awayFieldPlayers = _findFieldPlayers(awayPlayers, awayGoalkeeper);
    final awayFormationLines = _parseFormation(awayFormation);

    // Fehlerprüfung
    if (homeGoalkeeper == null || awayGoalkeeper == null) {
      return const Center(child: Text('Fehler: Torwart nicht in beiden Teams gefunden.'));
    }
    if (homeFieldPlayers.length < 10 || awayFieldPlayers.length < 10) {
      return const Center(child: Text('Fehler: Falsche Anzahl an Feldspielern.'));
    }

    return AspectRatio(
      aspectRatio: 68 / 105,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              CustomPaint(size: Size.infinite, painter: _SoccerFieldPainter()),

              // --- Heimteam aufstellen (untere Hälfte) ---
              _buildPlayerLine(constraints, [homeGoalkeeper], 0.95, homeColor, false, onPlayerTap),
              ..._buildFormationLines(constraints, homeFormationLines, homeFieldPlayers, false, homeColor, onPlayerTap),

              // --- Auswärtsteam aufstellen (obere Hälfte, gespiegelt) ---
              _buildPlayerLine(constraints, [awayGoalkeeper], 0.05, awayColor, true, onPlayerTap),
              ..._buildFormationLines(constraints, awayFormationLines, awayFieldPlayers, true, awayColor, onPlayerTap),
            ],
          );
        },
      ),
    );
  }

  // Hilfsmethoden zur Datenaufbereitung (unverändert)
  PlayerInfo? _findGoalkeeper(List<PlayerInfo> players) {
    try {
      return players.firstWhere((p) => p.position.toUpperCase() == 'TW' || p.position.toUpperCase() == 'G');
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

  // Baut die Formationslinien für ein Team auf
  List<Widget> _buildFormationLines(
      BoxConstraints constraints,
      List<int> formationLines,
      List<PlayerInfo> fieldPlayers,
      bool isAwayTeam,
      Color teamColor,
      void Function(int) onPlayerTap) {
    final List<Widget> lines = [];
    int playerIndexOffset = 0;
    final double verticalSpacingFactor = 0.35 / (formationLines.length - 1); // Breiterer Abstand

    for (int i = 0; i < formationLines.length; i++) {
      final linePlayerCount = formationLines[i];

      double lineYPosition;
      if (isAwayTeam) {
        // Obere Hälfte: Verteidigung weiter oben, Sturm näher an der Mitte
        lineYPosition = 0.15 + (i * verticalSpacingFactor);
      } else {
        // Untere Hälfte: Verteidigung weiter unten, Sturm näher an der Mitte
        lineYPosition = 0.85 - (i * verticalSpacingFactor);
      }

      final linePlayers = fieldPlayers.sublist(playerIndexOffset, playerIndexOffset + linePlayerCount);

      lines.add(_buildPlayerLine(constraints, linePlayers, lineYPosition, teamColor, isAwayTeam, onPlayerTap));
      playerIndexOffset += linePlayerCount;
    }
    return lines;
  }

  // Baut eine einzelne Spielerreihe auf (unverändert)
  Widget _buildPlayerLine(BoxConstraints constraints, List<PlayerInfo> players, double lineYPosition, Color teamColor, bool isAwayTeam, void Function(int) onPlayerTap) {
    final playerCount = players.length;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: List.generate(playerCount, (i) {
              double playerXPosition;
              if (isAwayTeam) {
                // Auswärtsteam (oben): Spieler von links nach rechts aufstellen (0.0 -> 1.0)
                playerXPosition = (i + 1) / (playerCount + 1);
              } else {
                // Heimteam (unten): Spieler von rechts nach links aufstellen (1.0 -> 0.0)
                playerXPosition = 1.0 - ((i + 1) / (playerCount + 1));
              }              return Align(
                alignment: Alignment((playerXPosition * 2) - 1, (lineYPosition * 2) - 1),
                child: _PlayerMarker(player: players[i], teamColor: teamColor,onPlayerTap: onPlayerTap),
              );
            }),
          );
        },
      ),
    );
  }
}

// _PlayerMarker und _SoccerFieldPainter (unverändert)
// In lib/screens/screenelements/match_screen/formations.dart

class _PlayerMarker extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final void Function(int) onPlayerTap;

  const _PlayerMarker({
    required this.player,
    required this.teamColor,
    required this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onPlayerTap(player.id),
      child: PlayerAvatar(player: player, teamColor: teamColor),
    );
  }
}

class _SoccerFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = Colors.green.shade700;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.color = Colors.white.withOpacity(0.8);
    paint.strokeWidth = 1.5;
    paint.style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * 0.15, paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 2, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
    final penaltyAreaWidth = size.width * 0.5; // Verkleinert
    final penaltyAreaHeight = size.height * 0.16; // Verkleinert
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, penaltyAreaHeight / 2), width: penaltyAreaWidth, height: penaltyAreaHeight,), paint,);
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, size.height - penaltyAreaHeight / 2), width: penaltyAreaWidth, height: penaltyAreaHeight,), paint,);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}