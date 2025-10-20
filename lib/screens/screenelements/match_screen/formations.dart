// lib/screens/screenelements/match_screen/formations.dart
import 'package:flutter/material.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'dart:ui' as ui;

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


  const MatchFormationDisplay({
    super.key,
    required this.homeFormation,
    required this.homePlayers,
    this.awayFormation,
    this.awayPlayers,
    required this.onPlayerTap,
    this.homeColor = Colors.blue,
    this.awayColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    // Prüfen, ob es sich um ein Einzel- oder Zwei-Team-Display handelt
    final bool singleTeamMode = awayPlayers == null || awayFormation == null;

    final homeGoalkeeper = _findGoalkeeper(homePlayers);
    final homeFieldPlayers = _findFieldPlayers(homePlayers, homeGoalkeeper);
    final homeFormationLines = _parseFormation(homeFormation);

    if (homeGoalkeeper == null || homeFieldPlayers.length < 10) {
      return const Center(child: Text('Ungültige Spielerdaten für das Heimteam.'));
    }

    return AspectRatio(
      aspectRatio: singleTeamMode ? (68 / 60) : (68 / 105), // halbes Feld für Einzelteam
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double playerAvatarRadius = constraints.maxWidth / 23;

          return Stack(
            children: [
              CustomPaint(size: Size.infinite, painter: _SoccerFieldPainter(singleTeamMode: singleTeamMode)),

              // Spieler für Heimteam / Einzelteam
              if (singleTeamMode) ...[
                // Positionierung für ein einzelnes Team
                _buildPlayerLine(constraints, [homeGoalkeeper], 0.99, homeColor, onPlayerTap, playerAvatarRadius, false),
                ..._buildFormationLines(constraints, homeFormationLines, homeFieldPlayers, false, homeColor, onPlayerTap, playerAvatarRadius, singleTeamMode: true),
              ] else ...[
                // Positionierung für Heimteam im Zwei-Team-Modus
                _buildPlayerLine(constraints, [homeGoalkeeper], 0.99, homeColor, onPlayerTap, playerAvatarRadius, false),
                ..._buildFormationLines(constraints, homeFormationLines, homeFieldPlayers, false, homeColor, onPlayerTap, playerAvatarRadius),
              ],

              if (!singleTeamMode)
                _buildAwayTeam(constraints, playerAvatarRadius),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAwayTeam(BoxConstraints constraints, double playerAvatarRadius) {
    final awayGoalkeeper = _findGoalkeeper(awayPlayers!);
    final awayFieldPlayers = _findFieldPlayers(awayPlayers!, awayGoalkeeper);
    final awayFormationLines = _parseFormation(awayFormation!);

    if (awayGoalkeeper == null || awayFieldPlayers.length < 10) {
      return const SizedBox.shrink(); // Oder eine Fehlermeldung
    }

    return Stack(
      children: [
        _buildPlayerLine(constraints, [awayGoalkeeper], 0.01, awayColor!, onPlayerTap, playerAvatarRadius, true),
        ..._buildFormationLines(constraints, awayFormationLines, awayFieldPlayers, true, awayColor!, onPlayerTap, playerAvatarRadius),
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
      BoxConstraints constraints,
      List<int> formationLines,
      List<PlayerInfo> fieldPlayers,
      bool isAwayTeam,
      Color teamColor,
      void Function(int) onPlayerTap,
      double avatarRadius, {
        bool singleTeamMode = false,
      }) {
    final List<Widget> lines = [];
    int playerIndexOffset = 0;

    double availableVerticalSpace, verticalSpacingFactor;

    if (singleTeamMode) {
      availableVerticalSpace = 0.325 *105/60;
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
      lines.add(_buildPlayerLine(constraints, linePlayers, lineYPosition, teamColor, onPlayerTap, avatarRadius, isAwayTeam));
      playerIndexOffset += linePlayerCount;
    }
    return lines;
  }

  Widget _buildPlayerLine(
      BoxConstraints constraints,
      List<PlayerInfo> players,
      double lineYPosition,
      Color teamColor,
      void Function(int) onPlayerTap,
      double avatarRadius,
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
                child: _PlayerMarker(player: orderedPlayers[i], teamColor: teamColor, onPlayerTap: onPlayerTap, radius: avatarRadius),
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
    paint.color = Colors.green.shade700;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    paint.color = Colors.white.withOpacity(0.8);
    paint.strokeWidth = 1.5;
    paint.style = PaintingStyle.stroke;

    final centerLineY = singleTeamMode ? size.height * (1 - 52.5 / 65) : size.height / 2;


    canvas.drawLine(Offset(0, centerLineY), Offset(size.width, centerLineY), paint);
    canvas.drawCircle(Offset(size.width / 2, centerLineY), size.width * 0.15, paint);
    if (!singleTeamMode) {
      canvas.drawCircle(Offset(size.width / 2, centerLineY), 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final penaltyAreaWidth = size.width * 0.6;
    final penaltyAreaHeight = size.height * (singleTeamMode ? (16.5 / 70) : 0.18);

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height - penaltyAreaHeight / 2),
        width: penaltyAreaWidth,
        height: penaltyAreaHeight,
      ),
      paint,
    );

    if (!singleTeamMode) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(size.width / 2, penaltyAreaHeight / 2),
          width: penaltyAreaWidth,
          height: penaltyAreaHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoccerFieldPainter oldDelegate) => oldDelegate.singleTeamMode != singleTeamMode;
}