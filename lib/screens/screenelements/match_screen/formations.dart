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
  final int rating;
  final int goals;
  final int maxRating;
  final int assists;
  final int ownGoals;
  final int? jerseyNumber;

  // NEUE FELDER für Liste & Filter
  final String? teamImageUrl;
  final int? marketValue;
  final String? teamName; // Für den Team-Filter

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
    this.maxRating = 250,
    this.teamImageUrl,
    this.marketValue,
    this.teamName,
  });
}

class PlayerAvatar extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final double radius;
  final bool showHoverEffect;
  final bool showValidTargetEffect;

  final bool showDetails;
  final bool showPositions;


  const PlayerAvatar({
    super.key,
    required this.player,
    required this.teamColor,
    this.radius = 18,
    this.showHoverEffect = false,
    this.showValidTargetEffect = false,
    this.showDetails = true,
    this.showPositions = true
  });

  Widget _buildEventIcon(IconData icon, Color color, int count, double size) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 2, offset: const Offset(0, 1))
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.9),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper = player.position.toUpperCase().contains('TW') ||
        player.position.toUpperCase().contains('GK');
    final bool isPlaceholder = player.id < 0;

    // --- Größen-Berechnung ---
    final double imageRadius = radius;
    final double whiteRingWidth = 1.0;
    final double colorRingWidth = isPlaceholder ? 1.0 : 1.8;
    final double totalRadius = imageRadius + whiteRingWidth + colorRingWidth;

    final double ratingFontSize = radius * 0.55;
    final double posFontSize = radius * 0.35;
    final double nameFontSize = radius * 0.42;
    final double eventIconSize = radius * 0.45;

    Color outerColor = isGoalkeeper ? Colors.orange.shade700 : teamColor;
    if (isPlaceholder) outerColor = Colors.grey.shade400;

    double scale = 1.0;
    if (showHoverEffect) {
      scale = 1.2;
      outerColor = Colors.green.shade600;
    } else if (showValidTargetEffect) {
      outerColor = Colors.yellow.shade700;
    }

    // Positionen parsen
    List<String> positions = player.position.split(',').map((e) => e.trim()).toList();
    if (positions.isEmpty || (positions.length == 1 && positions.first.isEmpty)) {
      positions = [];
    }

    return Transform.scale(
      scale: scale,
      child: SizedBox(
        // WICHTIG: Wenn keine Details, brauchen wir weniger Platz in der Breite
        width: totalRadius * (showDetails ? 2.8 : 2.2),
        child: Column(
          mainAxisSize: MainAxisSize.min, // WICHTIG gegen Overflow
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 1. Schatten
                Container(
                  width: totalRadius * 2,
                  height: totalRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2)),
                    ],
                  ),
                ),

                // 2. Kreise (Rahmen + Bild)
                CircleAvatar(radius: totalRadius, backgroundColor: outerColor),
                CircleAvatar(radius: imageRadius + whiteRingWidth, backgroundColor: Colors.white),
                CircleAvatar(
                  radius: imageRadius,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: (player.profileImageUrl != null && !isPlaceholder)
                      ? NetworkImage(player.profileImageUrl!)
                      : null,
                  child: (player.profileImageUrl == null || isPlaceholder)
                      ? Icon(isPlaceholder ? Icons.add_rounded : Icons.person, color: Colors.grey.shade400, size: imageRadius * 1.2)
                      : null,
                ),

                // 3. Positions-Badges (IMMER ANZEIGEN, auch in Liste)
                if (!isPlaceholder && positions.isNotEmpty && showPositions)
                  ...List.generate(positions.length, (index) {
                    // Positionierung am Kreisbogen
                    const double startAngle = 225 * (pi / 180);
                    const double stepAngle = 22 * (pi / 180);
                    final double angle = startAngle - (index * stepAngle);
                    final double dist = totalRadius;
                    final double badgeSize = radius * 0.75;

                    final double left = totalRadius + (dist * cos(angle)) - (badgeSize / 2);
                    final double top = totalRadius + (dist * sin(angle) * -1 * -1) - (badgeSize / 2);

                    return Positioned(
                      left: left,
                      top: top,
                      child: Container(
                        width: badgeSize,
                        height: badgeSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: teamColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.0),
                          boxShadow: [
                            BoxShadow(color: Colors.black38, blurRadius: 1, offset: const Offset(1, 1))
                          ],
                        ),
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(1.0),
                            child: Text(
                              positions[index],
                              style: TextStyle(color: Colors.white, fontSize: posFontSize, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                // 4. Event Icons (Nur wenn showDetails = true)
                if (!isPlaceholder && showDetails)
                  Positioned(
                    top: 0,
                    right: -radius * 0.5,
                    child: Column(
                      children: [
                        _buildEventIcon(Icons.sports_soccer, const Color(0xFF2E7D32), player.goals, eventIconSize),
                        _buildEventIcon(Icons.auto_fix_high, Colors.blueAccent, player.assists, eventIconSize),
                        _buildEventIcon(Icons.cancel, Colors.redAccent, player.ownGoals, eventIconSize),
                      ],
                    ),
                  ),

                // 5. Rating Pill (Nur wenn showDetails = true)
                if (!isPlaceholder && showDetails)
                  Positioned(
                    bottom: -radius * 0.45,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: radius * 0.3, vertical: 1),
                      decoration: BoxDecoration(
                        color: getColorForRating(player.rating, player.maxRating),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 2, offset: const Offset(0, 1))
                        ],
                      ),
                      child: Text(
                        player.rating.toString(),
                        style: TextStyle(color: Colors.white, fontSize: ratingFontSize, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),

            // 6. Name (Nur wenn showDetails = true)
            if (showDetails) ...[
              SizedBox(height: radius * 0.35),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isPlaceholder ? 0.8 : 0.95),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: isPlaceholder ? [] : [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1))
                  ],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    player.name.split(' ').last.toUpperCase(),
                    style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: nameFontSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}class MatchFormationDisplay extends StatefulWidget {
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
      // ... innerhalb von MatchFormationDisplay -> build -> LayoutBuilder ...

      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;

        // --- ANPASSUNG 1: Radius verkleinern ---
        // War 23.0. Erhöhen auf 28.0 sorgt für kleinere Avatare,
        // damit sie sich bei 5er-Ketten nicht überlappen.
        const double widthFactor = 28.0;

        final double fieldAspectRatio = singleTeamMode ? (68 / 60) : (68 / 105);
        final double fieldHeightFactor = widthFactor / fieldAspectRatio;

        // --- ANPASSUNG 2: Bank höher machen ---
        // War 4.5. Das neue Design mit Name drunter braucht mehr Platz.
        const double benchContainerFactor = 6.0;

        const double benchMarginFactor = 0.5;
        final double totalBenchFactor = showBench ? (benchContainerFactor + benchMarginFactor) : 0.0;
        final double totalHeightFactor = fieldHeightFactor + totalBenchFactor;

        double radius = min(w / widthFactor, h / totalHeightFactor);

        // --- ANPASSUNG 3: Limits anpassen ---
        // Minimum etwas senken, damit es auf kleinen Screens nicht kaputt geht
        radius = radius.clamp(4.0, 50.0);

        // ... Rest bleibt gleich ...

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
            if (showBench)
              DragTarget<PlayerInfo>(
                onWillAccept: (player) {
                  // Akzeptiere echte Spieler
                  return player != null && player.id > 0;
                },
                onAccept: (player) {
                  if (widget.onMoveToBench != null) {
                    widget.onMoveToBench!(player);
                  }
                  setState(() => _draggingPlayer = null);
                },
                builder: (context, candidateData, rejectedData) {
                  final bool isHovering = candidateData.isNotEmpty;

                  return Container(
                    height: benchHeight,
                    width: fieldWidth,
                    margin: EdgeInsets.only(top: benchMargin),
                    decoration: BoxDecoration(
                      // WICHTIG: Visuelles Feedback beim Hovern
                      color: isHovering ? Colors.green.withOpacity(0.2) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isHovering ? Colors.green : Colors.grey.shade200,
                          width: isHovering ? 2 : 1
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: radius * 0.8, top: radius * 0.3, bottom: radius * 0.1),
                          child: Text(
                            isHovering ? "LOSLASSEN ZUM AUSWECHSELN" : "BANK",
                            style: TextStyle(
                                fontSize: radius * 0.5,
                                fontWeight: FontWeight.bold,
                                color: isHovering ? Colors.green : Colors.grey.shade600,
                                letterSpacing: 1.0
                            ),
                          ),
                        ),
                        // Scrollbare Liste der Bankspieler
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.symmetric(horizontal: radius * 0.5),
                            child: Row(
                              children: widget.substitutes!.map((player) {
                                return Padding(
                                  padding: EdgeInsets.only(right: radius * 0.2),
                                  child: LongPressDraggable<PlayerInfo>(
                                    data: player,
                                    delay: const Duration(milliseconds: 200),
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Opacity(
                                        opacity: 0.9,
                                        child: PlayerAvatar(player: player, teamColor: widget.homeColor, radius: radius * 1.1),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.3,
                                      child: PlayerAvatar(player: player, teamColor: widget.homeColor, radius: radius),
                                    ),
                                    onDragStarted: () {
                                      setState(() => _draggingPlayer = player);
                                    },
                                    onDragEnd: (_) => setState(() => _draggingPlayer = null),
                                    child: GestureDetector(
                                      onTap: () => widget.onPlayerTap(player.id, radius),
                                      child: PlayerAvatar(player: player, teamColor: widget.homeColor, radius: radius),
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

  // --- WICHTIG: Korrigierte _buildPlayerLine (Damit Feldspieler ziehbar sind) ---
  Widget _buildPlayerLine(BuildContext context, List<PlayerInfo> players, double lineYPosition, Color teamColor, void Function(int, double) onPlayerTap, double radius, bool isAwayTeam) {
    final playerCount = players.length;
    final orderedPlayers = isAwayTeam ? players : players.reversed.toList();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: List.generate(playerCount, (i) {
              final playerXPosition = (i + 1) / (playerCount + 1);
              final targetPlayer = orderedPlayers[i];

              final int slotIndex = widget.homePlayers.indexOf(targetPlayer);
              String requiredRole = "";
              if (slotIndex != -1 && slotIndex < widget.requiredPositions.length) {
                requiredRole = widget.requiredPositions[slotIndex];
              }

              final bool isValidTarget = _draggingPlayer != null &&
                  requiredRole.isNotEmpty &&
                  _isPositionValid(requiredRole, _draggingPlayer!.position);

              final avatarWidget = GestureDetector(
                onTap: () => onPlayerTap(targetPlayer.id, radius),
                child: PlayerAvatar(
                  player: targetPlayer,
                  teamColor: teamColor,
                  radius: radius,
                  showHoverEffect: false, // Wird unten vom DragTarget gesteuert
                  showValidTargetEffect: isValidTarget,
                ),
              );

              return Align(
                alignment: Alignment((playerXPosition * 2) - 1, (lineYPosition * 2) - 1),
                child: DragTarget<PlayerInfo>(
                  onWillAccept: (incomingPlayer) {
                    if (incomingPlayer == null || requiredRole.isEmpty) return false;
                    return _isPositionValid(requiredRole, incomingPlayer.position);
                  },
                  onAccept: (incomingPlayer) {
                    if (widget.onPlayerDrop != null) {
                      widget.onPlayerDrop!(targetPlayer, incomingPlayer);
                    }
                    setState(() => _draggingPlayer = null);
                  },
                  builder: (context, candidateData, rejectedData) {
                    final bool isHovering = candidateData.isNotEmpty;

                    // Das Basis-Widget (Avatar)
                    final displayWidget = PlayerAvatar(
                      player: targetPlayer,
                      teamColor: teamColor,
                      radius: radius,
                      showHoverEffect: isHovering,
                      showValidTargetEffect: isValidTarget,
                    );

                    // Fallunterscheidung: Echter Spieler vs. Platzhalter
                    if (targetPlayer.id > 0) {
                      // Echter Spieler -> Ziehbar (Draggable)
                      return LongPressDraggable<PlayerInfo>(
                        data: targetPlayer,
                        delay: const Duration(milliseconds: 100),
                        feedback: Material(
                          color: Colors.transparent,
                          child: Opacity(
                            opacity: 0.9,
                            child: PlayerAvatar(player: targetPlayer, teamColor: teamColor, radius: radius * 1.1),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: displayWidget,
                        ),
                        onDragStarted: () => setState(() => _draggingPlayer = targetPlayer),
                        onDragEnd: (_) => setState(() => _draggingPlayer = null),
                        onDraggableCanceled: (_, __) => setState(() => _draggingPlayer = null),

                        // Auch der Draggable braucht einen GestureDetector für normale Taps!
                        child: GestureDetector(
                          onTap: () => onPlayerTap(targetPlayer.id, radius),
                          child: displayWidget,
                        ),
                      );
                    } else {
                      // Platzhalter -> NICHT ziehbar, aber KLICKBAR!
                      return GestureDetector(
                        onTap: () {
                          // Debugging-Hilfe, falls es immer noch nicht geht:
                          print("Platzhalter getippt: ${targetPlayer.id}");
                          onPlayerTap(targetPlayer.id, radius);
                        },
                        child: displayWidget,
                      );
                    }
                  },                ),
              );
            }),
          );
        },
      ),
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