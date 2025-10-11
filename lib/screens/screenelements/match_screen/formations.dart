import 'package:flutter/material.dart';
import 'package:premier_league/utils/color_helper.dart';
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
                    color: getColorForRating(player.rating, 250),
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
    required this.onPlayerTap,
    this.homeColor = Colors.blue,
    this.awayColor = Colors.red,
  })  : assert(homePlayers.length >= 11, 'Heimteam muss 11 Spieler haben.'),
        assert(awayPlayers.length >= 11, 'Auswärtsteam muss 11 Spieler haben.');

  @override
  Widget build(BuildContext context) {
    final homeGoalkeeper = _findGoalkeeper(homePlayers);
    final homeFieldPlayers = _findFieldPlayers(homePlayers, homeGoalkeeper);
    final homeFormationLines = _parseFormation(homeFormation);

    final awayGoalkeeper = _findGoalkeeper(awayPlayers);
    final awayFieldPlayers = _findFieldPlayers(awayPlayers, awayGoalkeeper);
    final awayFormationLines = _parseFormation(awayFormation);

    if (homeGoalkeeper == null || awayGoalkeeper == null) {
      return const Center(child: Text('Fehler: Torwart nicht in beiden Teams gefunden.'));
    }
    if (homeFieldPlayers.length < 10 || awayFieldPlayers.length < 10) {
      return const Center(child: Text('Fehler: Falsche Anzahl an Feldspielern.'));
    }

    return AspectRatio(
      aspectRatio: 68 / 105, // Standard-Spielfeldverhältnis
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double playerAvatarRadius = constraints.maxWidth / 23;

          return Stack(
            children: [
              CustomPaint(size: Size.infinite, painter: _SoccerFieldPainter()),

              _buildPlayerLine(constraints, [homeGoalkeeper], 0.99, homeColor, false, onPlayerTap, playerAvatarRadius),
              ..._buildFormationLines(constraints, homeFormationLines, homeFieldPlayers, false, homeColor, onPlayerTap, playerAvatarRadius),

              _buildPlayerLine(constraints, [awayGoalkeeper], 0.01, awayColor, true, onPlayerTap, playerAvatarRadius),
              ..._buildFormationLines(constraints, awayFormationLines, awayFieldPlayers, true, awayColor, onPlayerTap, playerAvatarRadius),
            ],
          );
        },
      ),
    );
  }

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

  List<Widget> _buildFormationLines(
      BoxConstraints constraints,
      List<int> formationLines,
      List<PlayerInfo> fieldPlayers,
      bool isAwayTeam,
      Color teamColor,
      void Function(int) onPlayerTap,
      double avatarRadius) { // Radius wird übergeben
    final List<Widget> lines = [];
    int playerIndexOffset = 0;
    // Der vertikale Raum, der für die Feldspieler zur Verfügung steht
    final double availableVerticalSpace = 0.325;
    // Der Abstand zwischen den Linien
    final double verticalSpacingFactor = availableVerticalSpace / (formationLines.length > 1 ? formationLines.length - 1 : 1);

    for (int i = 0; i < formationLines.length; i++) {
      final linePlayerCount = formationLines[i];
      if (playerIndexOffset + linePlayerCount > fieldPlayers.length) continue;

      double lineYPosition;
      if (isAwayTeam) {
        // Obere Hälfte: Verteidigung (i=0) weiter oben
        lineYPosition = 0.12 + (i * verticalSpacingFactor);
      } else {
        // Untere Hälfte: Verteidigung (i=0) weiter unten
        lineYPosition = 0.88 - (i * verticalSpacingFactor);
      }

      final linePlayers = fieldPlayers.sublist(playerIndexOffset, playerIndexOffset + linePlayerCount);

      lines.add(_buildPlayerLine(constraints, linePlayers, lineYPosition, teamColor, isAwayTeam, onPlayerTap, avatarRadius));
      playerIndexOffset += linePlayerCount;
    }
    return lines;
  }

  Widget _buildPlayerLine(
      BoxConstraints constraints,
      List<PlayerInfo> players,
      double lineYPosition,
      Color teamColor,
      bool isAwayTeam,
      void Function(int) onPlayerTap,
      double avatarRadius) { // Radius wird übergeben
    final playerCount = players.length;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: List.generate(playerCount, (i) {
              final playerXPosition = (i + 1) / (playerCount + 1);
              return Align(
                alignment: Alignment((playerXPosition * 2) - 1, (lineYPosition * 2) - 1),
                child: _PlayerMarker(player: players[i], teamColor: teamColor, onPlayerTap: onPlayerTap, radius: avatarRadius),
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
    final penaltyAreaWidth = size.width * 0.6; // Angepasst für bessere Proportionen
    final penaltyAreaHeight = size.height * 0.18; // Angepasst für bessere Proportionen
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, penaltyAreaHeight / 2), width: penaltyAreaWidth, height: penaltyAreaHeight,), paint,);
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, size.height - penaltyAreaHeight / 2), width: penaltyAreaWidth, height: penaltyAreaHeight,), paint,);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
