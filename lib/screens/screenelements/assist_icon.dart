import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Einheitliches Assist-Symbol auf Basis eines externen CC0-Fußballschuh-SVGs.
/// Quelle: https://www.svgrepo.com/svg/39123/football-shoe
class AssistIcon extends StatelessWidget {
  final double size;
  final Color color;

  const AssistIcon({
    super.key,
    this.size = 18,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vorlage',
      image: true,
      child: SvgPicture.asset(
        'assets/icons/assist_football_shoe.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }
}
