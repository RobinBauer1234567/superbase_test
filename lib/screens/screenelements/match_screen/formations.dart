import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
// Passe diese Import-Pfade entsprechend deiner Projektstruktur an
import 'package:flutter/material.dart';

// Dein bestehendes PlayerInfo-Modell
class PlayerInfo {
  final int id; // ID hinzugefügt
  final String name;
  final String position;

  const PlayerInfo({required this.id, required this.name, required this.position});
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
      Color teamColor, onPlayerTap) {
    final List<Widget> lines = [];
    int playerIndexOffset = 0;

    for (int i = 0; i < formationLines.length; i++) {
      final linePlayerCount = formationLines[i];

      double lineYPosition;
      // KORREKTUR: Die Logik für die Y-Position wurde für beide Teams überarbeitet,
      // um sicherzustellen, dass die Reihen korrekt von Verteidigung zu Sturm platziert werden.
      if (isAwayTeam) {
        // Obere Hälfte: von 0.45 (Verteidigung, nah an der Mitte) bis 0.2 (Sturm, oben)
        lineYPosition = 0.2 + (0.25 * (i / (formationLines.length - 1)));
      } else {
        // Untere Hälfte: von 0.55 (Sturm, nah an der Mitte) bis 0.8 (Verteidigung, unten)
        lineYPosition = 0.8 - (0.25 * (i / (formationLines.length - 1)));
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
    super.key,
    required this.player,
    required this.teamColor,
    required this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper = player.position.toUpperCase() == 'TW' || player.position.toUpperCase() == 'G';

    return GestureDetector(
      onTap: () => onPlayerTap(player.id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isGoalkeeper ? Colors.orange.shade700 : teamColor,
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7), // Etwas dunkler für bessere Lesbarkeit
                borderRadius: BorderRadius.circular(8)),
            child: Column( // ✅ NAME UND POSITION WERDEN UNTEREINANDER ANGEZEIGT
              children: [
                Text(
                  player.name.split(' ').last, // Zeigt nur den Nachnamen an
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                Text(
                  player.position, // ✅ HIER WIRD DIE POSITION HINZUGEFÜGT
                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
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
    final penaltyAreaWidth = size.width * 0.6;
    final penaltyAreaHeight = size.height * 0.18;
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, penaltyAreaHeight / 2), width: penaltyAreaWidth, height: penaltyAreaHeight,), paint,);
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, size.height - penaltyAreaHeight / 2), width: penaltyAreaWidth, height: penaltyAreaHeight,), paint,);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
