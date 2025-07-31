import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui; // Für lerpDouble benötigt



class RadialSegmentChart extends StatelessWidget {
  final List<double> values;
  final double maxAbsValue;
  final int? centerLabel;
  final List<String> segmentNames;
  final double innerOuterRadiusRatio;

  // KEIN 'const' mehr hier!
  RadialSegmentChart({
    super.key,
    required this.values,
    required this.maxAbsValue,
    this.centerLabel,
    this.segmentNames = kSegmentNames,
    this.innerOuterRadiusRatio = 5.0,
  }) : assert(values.length == 14, 'Values list must have 14 elements.'),
        assert(segmentNames.length == 14, 'SegmentNames list must have 14 elements.'),
  // Dieser Assert kann bleiben, da er auf top-level Konstanten basiert
        assert(kGroupStructure.fold(0, (sum, group) => sum + group.segmentCount) == 14, 'Group structure must sum to 14 segments.'),
        assert(kGroupBackgroundColors.length == kGroupStructure.length, 'Must have a background color for each group.'),
        assert(innerOuterRadiusRatio > 1.0, 'innerOuterRadiusRatio must be > 1.0');
  // assert(values.every((v) => v >= 0), 'All values must be positive or zero.'); // Laufzeit-Check wäre hier ok

  @override
  Widget build(BuildContext context) {
    // Lässt die Größenbestimmung durch das Parent-Widget zu
    return CustomPaint(
      painter: _RadialSegmentPainter(
        values: values,
        maxAbsValue: maxAbsValue,
        centerLabel: centerLabel,
        segmentNames: segmentNames,
        groupStructure: kGroupStructure,
        groupBackgroundColors: kGroupBackgroundColors,
        innerOuterRadiusRatio: innerOuterRadiusRatio,
      ),
    );
  }
}
// --- Datenstruktur für Gruppen (unverändert) ---
class GroupInfo {
  final String name;
  final int segmentCount;
  GroupInfo(this.name, this.segmentCount);
}

// --- Namen der 14 Segmente (unverändert) ---
const List<String> kSegmentNames = [
  'Abschlussvolumen', 'Abschlussqualität', 'Passvolumen', 'Passsicherheit',
  'Kreative Pässe', 'Zweikampfaktivität', 'Zweikämpferfolg', 'Fouls',
  'Ballberührungen', 'Ballverluste', 'Abgefangene Bälle', 'Tacklings',
  'Klärende Aktionen', 'Fehler',
];

// --- Struktur der 5 Gruppen (unverändert) ---
final List<GroupInfo> kGroupStructure = [
  GroupInfo('Schießen', 2), GroupInfo('Passen', 3), GroupInfo('Duelle', 3),
  GroupInfo('Ballbesitz', 3), GroupInfo('Defensive', 3),
];

// --- Dezente Hintergrundfarben (unverändert) ---
final List<Color> kGroupBackgroundColors = [
  Colors.blue.withOpacity(0.12), Colors.green.withOpacity(0.12),
  Colors.orange.withOpacity(0.12), Colors.red.withOpacity(0.12),
  Colors.purple.withOpacity(0.12),
];



// --- Der Painter für das Diagramm ---
class _RadialSegmentPainter extends CustomPainter {
  // Input Daten
  final List<double> values;
  final double maxAbsValue;
  final int? centerLabel;
  final List<String> segmentNames;
  final List<GroupInfo> groupStructure;
  final List<Color> groupBackgroundColors;
  final double innerOuterRadiusRatio;

  // Referenzwerte für Skalierung (basierend auf einem Zieldurchmesser von ca. 360)
  static const double _refTargetRadius = 280.0;
  static const double _refSegmentLabelFontSize = 9.0;
  static const double _refGroupLabelFontSize = 11.0;
  static const double _refCenterLabelFontSize = 18.0;
  static const double _refSegmentLabelRadialOffset = 5.0;
  static const double _refGroupRingPaddingInner = 2.0;
  static const double _refGroupRingExtraPadding = 10.0;
  static const double _refGroupLabelPadding = 10.0;
  static const double _refBaseCircleStrokeWidth = 1.5;
  static const double _refBorderStrokeWidth = 1.0;
  // Segment-Wachstumsfaktor (relativ zu baseRadius)
  static const double _segmentGrowthFactor = 1.5;


  _RadialSegmentPainter({
    required this.values, required this.maxAbsValue, required this.centerLabel,
    required this.segmentNames, required this.groupStructure,
    required this.groupBackgroundColors, required this.innerOuterRadiusRatio,
  });

  // --- Hilfsfunktionen ---
  static Size _getTextSize(String text, TextStyle style) {
    final TextPainter textPainter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1, textDirection: TextDirection.ltr)
      ..layout(minWidth: 0, maxWidth: double.infinity);
    return textPainter.size;
  }

  Color _getColorForValue(double value, double maxAbsValueRef) {
    // Da nur positive Werte erwartet werden, vereinfacht sich die Opacity-Logik evtl.
    // Hier wird aber `abs()` genutzt, was auch für nur positive Werte funktioniert.
    final effectiveMax = maxAbsValueRef <= 0 ? 1.0 : maxAbsValueRef; // Vermeide Div/0
    final t = (value.abs() / effectiveMax).clamp(0.0, 1.0);
    final hue = ui.lerpDouble(120, 0, t)!; // Grün nach Rot
    // Feste Opacity für positive Werte / Mittelkreis
    const opacity = 0.95;
    return HSVColor.fromAHSV(opacity, hue, 0.85, 0.9).toColor();
  }

  /// Berechnet alle dynamischen Größen basierend auf einem Basisradius und Skalierungsfaktor.
  Map<String, dynamic> _calculateSizes(double currentBaseRadius, double currentScale) {
    // Skalierte Größen
    final segmentLabelFontSize = _refSegmentLabelFontSize * currentScale;
    final groupLabelFontSize = _refGroupLabelFontSize * currentScale;
    final centerLabelFontSize = _refCenterLabelFontSize * currentScale;
    final segmentLabelRadialOffset = _refSegmentLabelRadialOffset * currentScale;
    final groupRingPaddingInner = _refGroupRingPaddingInner * currentScale;
    final groupRingExtraPadding = _refGroupRingExtraPadding * currentScale;
    final groupLabelPadding = _refGroupLabelPadding * currentScale;
    final baseCircleStrokeWidth = _refBaseCircleStrokeWidth * currentScale;
    final borderStrokeWidth = _refBorderStrokeWidth * currentScale;

    // Textstile
    final segmentLabelStyle = TextStyle(fontSize: segmentLabelFontSize, color: Colors.black87);
    final groupLabelStyle = TextStyle(fontSize: groupLabelFontSize, fontWeight: FontWeight.bold, color: Colors.black87);
    final centerLabelStyle = TextStyle(fontSize: centerLabelFontSize, fontWeight: FontWeight.bold, color: Colors.black.withOpacity(0.8));

    // Radien nach außen
    // Max. Radius, bis zu dem die Segmente wachsen können
    final maxPossibleSegmentRadius = currentBaseRadius + (currentBaseRadius * _segmentGrowthFactor);
    final groupRingInnerRadius = currentBaseRadius + groupRingPaddingInner;
    final groupRingOuterRadius = maxPossibleSegmentRadius + segmentLabelRadialOffset + groupRingExtraPadding;
    final typicalGroupCharHeight = _getTextSize('T', groupLabelStyle).height;
    // Äußerster Radius bis zur Baseline der Gruppenlabels
    final groupLabelPathRadius = groupRingOuterRadius + groupLabelPadding + typicalGroupCharHeight / 2;

    return {
      'baseRadius': currentBaseRadius, 'scale': currentScale,
      'segmentLabelFontSize': segmentLabelFontSize, 'groupLabelFontSize': groupLabelFontSize, 'centerLabelFontSize': centerLabelFontSize,
      'segmentLabelRadialOffset': segmentLabelRadialOffset, 'groupRingPaddingInner': groupRingPaddingInner, 'groupRingExtraPadding': groupRingExtraPadding, 'groupLabelPadding': groupLabelPadding,
      'baseCircleStrokeWidth': baseCircleStrokeWidth, 'borderStrokeWidth': borderStrokeWidth,
      'segmentLabelStyle': segmentLabelStyle, 'groupLabelStyle': groupLabelStyle, 'centerLabelStyle': centerLabelStyle,
      'maxPossibleSegmentRadius': maxPossibleSegmentRadius, 'groupRingInnerRadius': groupRingInnerRadius, 'groupRingOuterRadius': groupRingOuterRadius,
      'groupLabelPathRadius': groupLabelPathRadius,
    };
  }


  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double availableRadius = min(size.width, size.height) / 2;
    final double targetOuterRadius = availableRadius * 0.95; // Zielradius mit Rand

    // --- Schritt 1: Initiale Skalierung und Basis-Radius-Schätzung ---
    double scale = max(0.5, targetOuterRadius / _refTargetRadius);

    // Schätze den Platz für äußere Elemente, um einen initialen maxSegmentRadius zu finden
    final estGroupLabelFontSize = _refGroupLabelFontSize * scale;
    final estGroupLabelStyle = TextStyle(fontSize: estGroupLabelFontSize, fontWeight: FontWeight.bold);
    final estTypicalGroupCharHeight = _getTextSize('T', estGroupLabelStyle).height;
    final estGroupLabelPadding = _refGroupLabelPadding * scale;
    final estGroupRingExtraPadding = _refGroupRingExtraPadding * scale;
    final estSegmentLabelRadialOffset = _refSegmentLabelRadialOffset * scale;
    final outerSpaceEstimate = estGroupLabelPadding + estTypicalGroupCharHeight / 2
        + estGroupRingExtraPadding + estSegmentLabelRadialOffset;

    // Schätze den Radius, an dem Segmente maximal enden können
    double initialMaxPossibleSegmentRadius = max(1.0, targetOuterRadius - outerSpaceEstimate);
    // Berechne den initialen Basisradius basierend auf dem Verhältnis
    double initialBaseRadius = max(1.0, initialMaxPossibleSegmentRadius / innerOuterRadiusRatio);


    // --- Schritt 2: Erste Berechnung aller Größen ---
    var sizes = _calculateSizes(initialBaseRadius, scale);
    double calculatedOuterRadius = sizes['groupLabelPathRadius'];

    // --- Schritt 3: Prüfen und ggf. herunterskalieren ---
    if (calculatedOuterRadius > targetOuterRadius && calculatedOuterRadius > 0) {
      final double downScaleFactor = targetOuterRadius / calculatedOuterRadius;
      // Passe baseRadius und scale an
      initialBaseRadius *= downScaleFactor;
      scale *= downScaleFactor;
      // Berechne alle Größen NEU mit den angepassten Werten
      sizes = _calculateSizes(initialBaseRadius, scale);
    }

    // --- Schritt 4: Finale Größen aus der Map holen ---
    // (Variablennamen wie im vorherigen Schritt, werden hier übersichtlich aufgelistet)
    final double baseRadius = sizes['baseRadius'];
    final double segmentLabelFontSize = sizes['segmentLabelFontSize'];
    final double groupLabelFontSize = sizes['groupLabelFontSize'];
    final double centerLabelFontSize = sizes['centerLabelFontSize'];
    final double segmentLabelRadialOffset = sizes['segmentLabelRadialOffset'];
    // final double groupRingPaddingInner = sizes['groupRingPaddingInner']; // Nicht direkt gebraucht
    // final double groupRingExtraPadding = sizes['groupRingExtraPadding']; // Nicht direkt gebraucht
    // final double groupLabelPadding = sizes['groupLabelPadding']; // Nicht direkt gebraucht
    final double baseCircleStrokeWidth = sizes['baseCircleStrokeWidth'];
    final double borderStrokeWidth = sizes['borderStrokeWidth'];
    final TextStyle segmentLabelStyle = sizes['segmentLabelStyle'];
    final TextStyle groupLabelStyle = sizes['groupLabelStyle'];
    final TextStyle centerLabelStyle = sizes['centerLabelStyle'];
    final double maxPossibleSegmentRadius = sizes['maxPossibleSegmentRadius'];
    final double groupRingInnerRadius = sizes['groupRingInnerRadius'];
    final double groupRingOuterRadius = sizes['groupRingOuterRadius'];
    final double groupLabelPathRadius = sizes['groupLabelPathRadius'];


    // --- Schritt 5: Zeichnen mit finalen Größen ---

    // Paints vorbereiten
    const int segmentCount = 14;
    const double anglePerSegment = 2 * pi / segmentCount;
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()..color = Colors.black.withOpacity(0.1)..style = PaintingStyle.stroke..strokeWidth = borderStrokeWidth;
    final Paint groupBackgroundPaint = Paint()..style = PaintingStyle.fill;
    final Paint centerFillPaint = Paint()..style = PaintingStyle.fill;
    final Paint baseCirclePaint = Paint()..color = Colors.grey.shade500..style = PaintingStyle.stroke..strokeWidth = baseCircleStrokeWidth;

    // 0. Gruppen-Hintergrundringe
    int currentSegmentIndexBg = 0;
    for (int i = 0; i < groupStructure.length; i++) {
      final group = groupStructure[i];
      final groupStartAngle = currentSegmentIndexBg * anglePerSegment - (pi / 2);
      final groupSweepAngle = group.segmentCount * anglePerSegment;
      groupBackgroundPaint.color = groupBackgroundColors[i];
      final path = Path();
      path.addArc( Rect.fromCircle(center: center, radius: groupRingOuterRadius), groupStartAngle, groupSweepAngle);
      path.arcTo( Rect.fromCircle(center: center, radius: groupRingInnerRadius), groupStartAngle + groupSweepAngle, -groupSweepAngle, false);
      path.close();
      canvas.drawPath(path, groupBackgroundPaint);
      currentSegmentIndexBg += group.segmentCount;
    }

    // 0.5 Inneren Kreis füllen
    if (centerLabel != null) {
      centerFillPaint.color = _getColorForValue(centerLabel!.toDouble(), maxAbsValue);
    } else {
      centerFillPaint.color = Colors.grey.withOpacity(0.1);
    }
    canvas.drawCircle(center, baseRadius, centerFillPaint); // Finaler baseRadius

    // 1. Segmente (nur positive Werte) und Labels
    for (int i = 0; i < segmentCount; i++) {
      // Sicherstellen, dass der Wert nicht negativ ist (obwohl nicht erwartet)
      final value = max(0.0, values[i].clamp(0, maxAbsValue)); // Clamp 0 bis max
      final startAngle = i * anglePerSegment - (pi / 2);
      final sweepAngle = anglePerSegment;
      final midAngle = startAngle + sweepAngle / 2;

      // Delta Radius (nur positiv)
      final deltaRadius = (value / maxAbsValue) * baseRadius * _segmentGrowthFactor;
      // Radien (vereinfacht für nur positive Werte)
      final double innerRadius = baseRadius; // Startet immer am Basisradius
      final double outerRadius = baseRadius + deltaRadius; // Wächst immer nach außen

      // Segment-Pfad
      final segmentPath = Path();
      const steps = 20;
      for (int j = 0; j <= steps; j++) {
        final angle = startAngle + sweepAngle * j / steps;
        final x = center.dx + cos(angle) * outerRadius;
        final y = center.dy + sin(angle) * outerRadius;
        if (j == 0) segmentPath.moveTo(x, y); else segmentPath.lineTo(x, y);
      }
      for (int j = steps; j >= 0; j--) {
        final angle = startAngle + sweepAngle * j / steps;
        final x = center.dx + cos(angle) * innerRadius;
        final y = center.dy + sin(angle) * innerRadius;
        segmentPath.lineTo(x, y);
      }
      segmentPath.close();

      // Zeichnen
      fillPaint.color = _getColorForValue(value.toDouble(), maxAbsValue);
      canvas.drawPath(segmentPath, fillPaint);
      canvas.drawPath(segmentPath, borderPaint);

      // Segment-Label
      final labelRadius = maxPossibleSegmentRadius + segmentLabelRadialOffset;
      final labelX = center.dx + cos(midAngle) * labelRadius;
      final labelY = center.dy + sin(midAngle) * labelRadius;
      final labelText = segmentNames[i];
      final labelSize = _getTextSize(labelText, segmentLabelStyle);

      canvas.save();
      canvas.translate(labelX, labelY);
      canvas.rotate(midAngle + pi);
      final labelPainter = TextPainter(
          text: TextSpan(text: labelText, style: segmentLabelStyle),
          textAlign: TextAlign.center, textDirection: TextDirection.ltr)
        ..layout();
      labelPainter.paint(canvas, Offset(0, -labelSize.height / 2));
      canvas.restore();
    }

    // 2. Basis-Kreis (Null-Linie)
    canvas.drawCircle(center, baseRadius, baseCirclePaint);

    // 3. Gruppen-Labels auf Kreisbahn
    int currentSegmentIndexLabel = 0;
    for (var group in groupStructure) {
      final groupName = group.name.toUpperCase();
      final groupStartAngle = currentSegmentIndexLabel * anglePerSegment - (pi / 2);
      final groupSweepAngle = group.segmentCount * anglePerSegment;
      final groupMidAngle = groupStartAngle + groupSweepAngle / 2;

      double totalTextWidth = 0;
      for (int charIndex = 0; charIndex < groupName.length; charIndex++) {
        totalTextWidth += _getTextSize(groupName[charIndex], groupLabelStyle).width;
      }
      final totalAngularWidth = totalTextWidth / groupLabelPathRadius;
      double currentCharacterAngle = groupMidAngle - totalAngularWidth / 2;

      for (int charIndex = 0; charIndex < groupName.length; charIndex++) {
        final character = groupName[charIndex];
        final charSize = _getTextSize(character, groupLabelStyle);
        final charWidth = charSize.width;
        final charHeight = charSize.height;
        final charAngularWidth = charWidth / groupLabelPathRadius;
        final charCenterAngle = currentCharacterAngle + charAngularWidth / 2;
        final charX = center.dx + cos(charCenterAngle) * groupLabelPathRadius;
        final charY = center.dy + sin(charCenterAngle) * groupLabelPathRadius;
        final charRotation = charCenterAngle + pi / 2;

        canvas.save();
        canvas.translate(charX, charY);
        canvas.rotate(charRotation);
        final charPainter = TextPainter(
            text: TextSpan(text: character, style: groupLabelStyle),
            textAlign: TextAlign.center, textDirection: TextDirection.ltr)
          ..layout();
        charPainter.paint(canvas, Offset(-charWidth / 2, -charHeight / 2));
        canvas.restore();
        currentCharacterAngle += charAngularWidth;
      }
      currentSegmentIndexLabel += group.segmentCount;
    }

    // 4. Mittelwert / Label als Text
    if (centerLabel != null) {
      final centerTextPainter = TextPainter(
          text: TextSpan( text: centerLabel.toString(), style: centerLabelStyle ),
          textDirection: TextDirection.ltr, textAlign: TextAlign.center )
        ..layout();
      centerTextPainter.paint( canvas,
          Offset(center.dx - centerTextPainter.width / 2, center.dy - centerTextPainter.height / 2) );
    }
  }

  @override
  bool shouldRepaint(covariant _RadialSegmentPainter oldDelegate) {
    // Vergleicht alle relevanten Input-Parameter
    return oldDelegate.values.toString() != values.toString() ||
        oldDelegate.centerLabel != centerLabel ||
        oldDelegate.maxAbsValue != maxAbsValue ||
        oldDelegate.innerOuterRadiusRatio != innerOuterRadiusRatio || // Verhältnis prüfen
        oldDelegate.segmentNames != segmentNames ||
        oldDelegate.groupStructure != groupStructure ||
        oldDelegate.groupBackgroundColors != groupBackgroundColors;
  }
}
