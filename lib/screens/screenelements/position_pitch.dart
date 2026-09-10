import 'package:flutter/material.dart';
// Importiere deine Formations-Datei!
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';

class PositionPitch extends StatelessWidget {
  final List<String> availablePositions;

  const PositionPitch({super.key, required this.availablePositions});

  Widget _buildPositionDot(String position, Alignment alignment) {
    final bool isAvailable = availablePositions.contains(position);

    return Align(
      alignment: alignment,
      child: Container(
        width: 22, // Groß genug für ZDM
        height: 22,
        decoration: BoxDecoration(
          color: isAvailable ? Colors.blueGrey.shade800 : Colors.white.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: isAvailable ? Colors.white : Colors.grey.shade400,
            width: isAvailable ? 1.5 : 1.0,
          ),
          boxShadow: isAvailable ? [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2))
          ] : [],
        ),
        alignment: Alignment.center,
        // FittedBox verhindert zwingend Zeilenumbrüche!
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(3.0),
            child: Text(
              position,
              maxLines: 1,
              style: TextStyle(
                fontSize: 6,
                fontWeight: FontWeight.bold,
                color: isAvailable ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      // Erzwingt exakt das Seitenverhältnis aus formations.dart für die Halbfeld-Ansicht
      child: AspectRatio(
        aspectRatio: 68 / 60,
        child: Stack(
          children: [
            // Nutzt deinen eigenen Painter im Halbfeld-Modus!
            CustomPaint(
              size: Size.infinite,
              painter: SoccerFieldPainter(singleTeamMode: true),
            ),

            // --- DIE 11 POSITIONEN ---
            // Torwart (Unten am eigenen Tor)
            _buildPositionDot('TW', const Alignment(0.0, 0.85)),

            // Abwehr (Viererkette)
            _buildPositionDot('LV', const Alignment(-0.8, 0.45)),
            _buildPositionDot('IV', const Alignment(-0.35, 0.55)),
            _buildPositionDot('IV', const Alignment(0.35, 0.55)),
            _buildPositionDot('RV', const Alignment(0.8, 0.45)),

            // Mittelfeld
            _buildPositionDot('ZDM', const Alignment(0.0, 0.15)),
            _buildPositionDot('ZM', const Alignment(-0.4, -0.15)),
            _buildPositionDot('ZOM', const Alignment(0.4, -0.35)),

            // Sturm (Oben in der gegnerischen Hälfte)
            _buildPositionDot('LA', const Alignment(-0.7, -0.75)),
            _buildPositionDot('ST', const Alignment(0.0, -0.85)),
            _buildPositionDot('RA', const Alignment(0.7, -0.75)),
          ],
        ),
      ),
    );
  }
}