import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

/// Einheitliches Assist-Symbol auf Basis des bestehenden
/// Material Design Icons `shoe-cleat` von Pictogrammers.
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
      child: Icon(
        MdiIcons.shoeCleat,
        size: size,
        color: color,
      ),
    );
  }
}
