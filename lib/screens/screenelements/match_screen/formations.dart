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
  // Optional: Visual overrides für Drag & Drop Status
  final bool showHoverEffect;
  final bool showValidTargetEffect;

  const PlayerAvatar({
    super.key,
    required this.player,
    required this.teamColor,
    this.radius = 18,
    this.showHoverEffect = false,
    this.showValidTargetEffect = false,
  });

  Widget _buildEventIcon(IconData icon, Color color, int count, double size) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(size * 0.15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 0.5),
      ),
      child: Icon(icon, color: color, size: size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper = player.position.toUpperCase() == 'TW' || player.position.toUpperCase() == 'G';
    final bool isPlaceholder = player.id < 0;

    final double ratingFontSize = radius * 0.5;
    final double nameFontSize = radius * 0.45;
    final double eventIconSize = radius * 0.45;
    final double spaceAfterAvatar = radius * 0.15;

    // --- Drag & Drop Visual Effects ---
    double scale = 1.0;
    Color borderColor = isPlaceholder
        ? Colors.grey.shade400
        : (isGoalkeeper ? Colors.orange.shade700 : teamColor);
    double borderWidth = 1.5;

    if (showHoverEffect) {
      scale = 1.15; // "Snap" / Vergrößerung
      borderColor = Colors.greenAccent.shade700; // Grüner Rand beim Fangen
      borderWidth = 3.0;
    } else if (showValidTargetEffect) {
      borderColor = Colors.yellow.shade700; // Gelber Rand für mögliche Ziele
      borderWidth = 2.5;
    }
    // ----------------------------------

    return Transform.scale(
      scale: scale,
      child: SizedBox(
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
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: borderColor,
                      width: borderWidth,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                    image: player.profileImageUrl != null
                        ? DecorationImage(
                      image: NetworkImage(player.profileImageUrl!),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: player.profileImageUrl == null
                      ? Icon(
                    isPlaceholder ? Icons.add : Icons.person,
                    color: isPlaceholder ? Colors.grey.shade500 : Colors.grey.shade400,
                    size: radius * (isPlaceholder ? 1.0 : 1.2),
                  )
                      : null,
                ),
                if (!isPlaceholder)
                  Positioned(
                    bottom: -radius * 0.25,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: radius * 0.25, vertical: radius * 0.05),
                      decoration: BoxDecoration(
                        color: getColorForRating(player.rating, player.maxRating),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white, width: 1),
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 2, offset: const Offset(0, 1))
                        ],
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
                if (!isPlaceholder)
                  Positioned(
                    top: -radius * 0.2,
                    right: -radius * 0.3,
                    child: Column(
                      children: [
                        _buildEventIcon(Icons.sports_soccer, Colors.white, player.goals, eventIconSize),
                        if (player.goals > 0) SizedBox(height: 1),
                        _buildEventIcon(Icons.assistant, Colors.lightBlueAccent, player.assists, eventIconSize),
                        if (player.assists > 0) SizedBox(height: 1),
                        _buildEventIcon(Icons.sports_soccer, Colors.red, player.ownGoals, eventIconSize),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: spaceAfterAvatar),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isPlaceholder ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
                border: isPlaceholder ? Border.all(color: Colors.grey.shade300, width: 0.5) : null,
              ),
              child: Text(
                player.name.split(' ').last,
                style: TextStyle(
                    color: isPlaceholder ? Colors.black87 : Colors.white,
                    fontSize: nameFontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class MatchFormationDisplay extends StatefulWidget {
  final String homeFormation;
  final List<PlayerInfo> homePlayers;
  final Color homeColor;
  final String? awayFormation;
  final List<PlayerInfo>? awayPlayers;
  final Color? awayColor;
  final void Function(int playerId, double radius) onPlayerTap;
  final List<PlayerInfo>? substitutes;
  final void Function(PlayerInfo fieldSlot, PlayerInfo benchPlayer)? onPlayerDrop;
  final void Function(PlayerInfo player)? onMoveToBench;
  // NEU: Die Liste der Rollen für die Slots (z.B. ["TW", "RV", ...])
  final List<String> requiredPositions;

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
    this.onPlayerDrop,
    this.onMoveToBench, // NEU
    this.requiredPositions = const [],
  });

  @override
  State<MatchFormationDisplay> createState() => _MatchFormationDisplayState();
}

class _MatchFormationDisplayState extends State<MatchFormationDisplay> {
  PlayerInfo? _draggingPlayer;

  bool _isPositionValid(String requiredRole, String playerPos) {
    final req = requiredRole.toUpperCase();
    final p = playerPos.toUpperCase();
    return p == req || p.contains(req);
  }

  @override
  Widget build(BuildContext context) {
    final bool singleTeamMode = widget.awayPlayers == null ||
        widget.awayFormation == null;
    final bool showBench = widget.substitutes != null &&
        widget.substitutes!.isNotEmpty;

    final homeGoalkeeper = _findGoalkeeper(widget.homePlayers);
    final homeFieldPlayers = _findFieldPlayers(
        widget.homePlayers, homeGoalkeeper);
    final homeFormationLines = _parseFormation(widget.homeFormation);

    if (homeGoalkeeper == null || homeFieldPlayers.length < 10) {
      return const Center(
          child: Text('Ungültige Spielerdaten für das Heimteam.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;

        const double widthFactor = 23.0;
        final double fieldAspectRatio = singleTeamMode ? (68 / 60) : (68 / 105);
        final double fieldHeightFactor = widthFactor / fieldAspectRatio;
        const double benchContainerFactor = 4.5;
        const double benchMarginFactor = 0.5;
        final double totalBenchFactor = showBench ? (benchContainerFactor +
            benchMarginFactor) : 0.0;
        final double totalHeightFactor = fieldHeightFactor + totalBenchFactor;

        double radius = min(w / widthFactor, h / totalHeightFactor);
        radius = radius.clamp(5.0, 50.0);

        final double fieldWidth = radius * widthFactor;
        final double fieldHeight = radius * fieldHeightFactor;
        final double benchHeight = radius * benchContainerFactor;
        final double benchMargin = radius * benchMarginFactor;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- SPIELFELD ---
            Container(
              width: fieldWidth,
              height: fieldHeight,
              decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5))
                  ]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    CustomPaint(size: Size.infinite,
                        painter: _SoccerFieldPainter(
                            singleTeamMode: singleTeamMode)),

                    if (singleTeamMode) ...[
                      _buildPlayerLine(
                          context,
                          [homeGoalkeeper],
                          0.96,
                          widget.homeColor,
                          widget.onPlayerTap,
                          radius,
                          false),
                      ..._buildFormationLines(
                          context,
                          homeFormationLines,
                          homeFieldPlayers,
                          false,
                          widget.homeColor,
                          widget.onPlayerTap,
                          radius,
                          singleTeamMode: true),
                    ] else
                      ...[
                        _buildPlayerLine(
                            context,
                            [homeGoalkeeper],
                            0.98,
                            widget.homeColor,
                            widget.onPlayerTap,
                            radius,
                            false),
                        ..._buildFormationLines(
                            context,
                            homeFormationLines,
                            homeFieldPlayers,
                            false,
                            widget.homeColor,
                            widget.onPlayerTap,
                            radius),
                      ],

                    if (!singleTeamMode)
                      _buildAwayTeam(context, constraints, radius),
                  ],
                ),
              ),
            ),

            // --- BANK (Drop Target & Draggable Source) ---
            // --- BANK (Drop Target & Draggable Source) ---
            if (showBench)
              DragTarget<PlayerInfo>(
                // 1. ZIEL: Akzeptiere Drops von überall, solange es ein echter Spieler ist
                onWillAccept: (player) {
                  return player != null && player.id > 0;
                },
                onAccept: (player) {
                  // WICHTIG: Hier wird der Move ausgeführt!
                  if (widget.onMoveToBench != null) {
                    widget.onMoveToBench!(player);
                  }
                  setState(() => _draggingPlayer = null);
                },
                builder: (context, candidateData, rejectedData) {
                  final bool isHovering = candidateData.isNotEmpty;

                  // Container Design
                  return Container(
                    height: benchHeight,
                    width: fieldWidth,
                    margin: EdgeInsets.only(top: benchMargin),
                    decoration: BoxDecoration(
                      color: isHovering ? Colors.green.withOpacity(0.1) : Colors
                          .white, // Visuelles Feedback
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ],
                      border: Border.all(
                          color: isHovering ? Colors.green : Colors.grey
                              .shade200,
                          width: isHovering ? 2 : 1
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: radius * 0.8,
                              top: radius * 0.3,
                              bottom: radius * 0.1),
                          child: Text(
                            isHovering ? "LOSLASSEN ZUM AUSWECHSELN" : "BANK",
                            // Text Feedback
                            style: TextStyle(
                                fontSize: radius * 0.5,
                                fontWeight: FontWeight.bold,
                                color: isHovering ? Colors.green : Colors.grey
                                    .shade600,
                                letterSpacing: 1.0
                            ),
                          ),
                        ),
                        // ... (Restlicher Inhalt der Bank: ScrollView, Row, Draggables wie zuvor) ...
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.symmetric(
                                horizontal: radius * 0.5),
                            child: Row(
                              children: widget.substitutes!.map((player) {
                                // ... (Code für Bank-Spieler Draggable bleibt gleich) ...
                                return Padding(
                                  padding: EdgeInsets.only(right: radius * 0.2),
                                  child: LongPressDraggable<PlayerInfo>(
                                    data: player,
                                    delay: const Duration(milliseconds: 200),
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Opacity(opacity: 0.9,
                                          child: PlayerAvatar(player: player,
                                              teamColor: widget.homeColor,
                                              radius: radius * 1.1)),
                                    ),
                                    childWhenDragging: Opacity(opacity: 0.3,
                                        child: PlayerAvatar(player: player,
                                            teamColor: widget.homeColor,
                                            radius: radius)),
                                    onDragStarted: () {
                                      setState(() => _draggingPlayer = player);
                                    },
                                    onDragEnd: (_) =>
                                        setState(() => _draggingPlayer = null),
                                    child: GestureDetector(
                                      onTap: () =>
                                          widget.onPlayerTap(player.id, radius),
                                      child: PlayerAvatar(player: player,
                                          teamColor: widget.homeColor,
                                          radius: radius),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildAwayTeam(BuildContext context, BoxConstraints constraints,
      double radius) {
    final awayGoalkeeper = _findGoalkeeper(widget.awayPlayers!);
    final awayFieldPlayers = _findFieldPlayers(
        widget.awayPlayers!, awayGoalkeeper);
    final awayFormationLines = _parseFormation(widget.awayFormation!);
    if (awayGoalkeeper == null || awayFieldPlayers.length < 10)
      return const SizedBox.shrink();
    return Stack(
      children: [
        _buildPlayerLine(
            context,
            [awayGoalkeeper],
            0.02,
            widget.awayColor!,
            widget.onPlayerTap,
            radius,
            true),
        ..._buildFormationLines(
            context,
            awayFormationLines,
            awayFieldPlayers,
            true,
            widget.awayColor!,
            widget.onPlayerTap,
            radius),
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

  List<PlayerInfo> _findFieldPlayers(List<PlayerInfo> players,
      PlayerInfo? goalkeeper) {
    if (goalkeeper == null) return [];
    return players.where((p) => p != goalkeeper).toList();
  }

  List<int> _parseFormation(String formation) {
    return formation.split('-').map((e) => int.tryParse(e) ?? 0).toList();
  }

  List<Widget> _buildFormationLines(BuildContext context,
      List<int> formationLines, List<PlayerInfo> fieldPlayers, bool isAwayTeam,
      Color teamColor, void Function(int, double) onPlayerTap, double radius,
      {bool singleTeamMode = false}) {
    final List<Widget> lines = [];
    int playerIndexOffset = 0;
    double verticalSpacingFactor;

    if (singleTeamMode) {
      verticalSpacingFactor = (0.325 * 105 / 60) /
          (formationLines.length > 1 ? formationLines.length - 0.8 : 1);
    } else {
      verticalSpacingFactor =
          0.325 / (formationLines.length > 1 ? formationLines.length - 1 : 1);
    }

    for (int i = 0; i < formationLines.length; i++) {
      final linePlayerCount = formationLines[i];
      if (playerIndexOffset + linePlayerCount > fieldPlayers.length) continue;

      double lineYPosition;
      if (singleTeamMode) {
        lineYPosition = 0.78 - (i * verticalSpacingFactor);
      } else if (isAwayTeam) {
        lineYPosition = 0.12 + (i * verticalSpacingFactor);
      } else {
        lineYPosition = 0.88 - (i * verticalSpacingFactor);
      }

      final linePlayers = fieldPlayers.sublist(
          playerIndexOffset, playerIndexOffset + linePlayerCount);
      lines.add(_buildPlayerLine(
          context,
          linePlayers,
          lineYPosition,
          teamColor,
          onPlayerTap,
          radius,
          isAwayTeam));
      playerIndexOffset += linePlayerCount;
    }
    return lines;
  }

  Widget _buildPlayerLine(BuildContext context, List<PlayerInfo> players,
      double lineYPosition, Color teamColor,
      void Function(int, double) onPlayerTap, double radius, bool isAwayTeam) {
    final playerCount = players.length;
    final orderedPlayers = isAwayTeam ? players : players.reversed.toList();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: List.generate(playerCount, (i) {
              final playerXPosition = (i + 1) / (playerCount + 1);
              final targetPlayer = orderedPlayers[i];

              // Validierung für Drag Targets
              final int slotIndex = widget.homePlayers.indexOf(targetPlayer);
              String requiredRole = "";
              if (slotIndex != -1 &&
                  slotIndex < widget.requiredPositions.length) {
                requiredRole = widget.requiredPositions[slotIndex];
              }
              final bool isValidTarget = _draggingPlayer != null &&
                  requiredRole.isNotEmpty &&
                  _isPositionValid(requiredRole, _draggingPlayer!.position);

              // Avatar Widget (Basis)
              final avatarWidget = GestureDetector(
                onTap: () => onPlayerTap(targetPlayer.id, radius),
                child: PlayerAvatar(
                  player: targetPlayer,
                  teamColor: teamColor,
                  radius: radius,
                  showHoverEffect: false,
                  // Wird unten vom DragTarget gesteuert
                  showValidTargetEffect: isValidTarget,
                ),
              );

              return Align(
                alignment: Alignment(
                    (playerXPosition * 2) - 1, (lineYPosition * 2) - 1),

                // 1. ZIEL (Empfänger)
                child: DragTarget<PlayerInfo>(
                  onWillAccept: (incomingPlayer) {
                    if (incomingPlayer == null || requiredRole.isEmpty)
                      return false;
                    return _isPositionValid(
                        requiredRole, incomingPlayer.position);
                  },
                  onAccept: (incomingPlayer) {
                    if (widget.onPlayerDrop != null) {
                      widget.onPlayerDrop!(targetPlayer, incomingPlayer);
                    }
                    setState(() => _draggingPlayer = null);
                  },
                  builder: (context, candidateData, rejectedData) {
                    final bool isHovering = candidateData.isNotEmpty;

                    // Wrapper für Hover-Effekt
                    final displayWidget = PlayerAvatar(
                      player: targetPlayer,
                      teamColor: teamColor,
                      radius: radius,
                      showHoverEffect: isHovering,
                      showValidTargetEffect: isValidTarget,
                    );

                    // 2. QUELLE (Sender): Ist es ein echter Spieler? Dann mach ihn ziehbar.
                    if (targetPlayer.id > 0) {
                      return LongPressDraggable<PlayerInfo>(
                        data: targetPlayer,
                        delay: const Duration(milliseconds: 100),
                        feedback: Material(
                          color: Colors.transparent,
                          child: Opacity(
                            opacity: 0.9,
                            child: PlayerAvatar(player: targetPlayer,
                                teamColor: teamColor,
                                radius: radius * 1.1),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          // Spieler wird blass, bleibt aber visuell da
                          child: displayWidget,
                        ),
                        onDragStarted: () {
                          setState(() => _draggingPlayer = targetPlayer);
                        },
                        // WICHTIG: Hier darf KEINE Logik stehen, die Daten ändert!
                        onDragEnd: (details) {
                          setState(() => _draggingPlayer = null);
                        },
                        // WICHTIG: Auch hier NICHTS tun (außer Reset)
                        // Wenn der Spieler ins Leere gezogen wird, passiert einfach nichts.
                        onDraggableCanceled: (velocity, offset) {
                          setState(() => _draggingPlayer = null);
                        },

                        child: GestureDetector(
                          onTap: () => onPlayerTap(targetPlayer.id, radius),
                          child: displayWidget,
                        ),
                      );
                    } else {
                      // Platzhalter: Nur Ziel, nicht Quelle
                      return GestureDetector(
                        onTap: () => onPlayerTap(targetPlayer.id, radius),
                        child: displayWidget,
                      );
                    }
                  },
                ),
              );
            }),
          );
        },
      ),
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