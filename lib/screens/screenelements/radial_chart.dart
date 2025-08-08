import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;

/// Repräsentiert ein einzelnes Segment (einen "Balken") im Diagramm.
class SegmentData {
  final String name;
  final double value;

  const SegmentData({required this.name, required this.value});
}

/// Repräsentiert eine Gruppe von Segmenten mit einem gemeinsamen Hintergrund.
class GroupData {
  final String name;
  final List<SegmentData> segments;
  final Color backgroundColor;

  const GroupData({
    required this.name,
    required this.segments,
    required this.backgroundColor,
  });
}

// =================================================================
// WIDGET-KLASSE (JETZT STATEFUL UND MIT NEUER DATEN-API)
// =================================================================
class RadialSegmentChart extends StatefulWidget {
  // Nimmt jetzt eine strukturierte Liste von Gruppen entgegen.
  final List<GroupData> groups;
  final double maxAbsValue;
  final int? centerLabel;
  final double innerOuterRadiusRatio;

  const RadialSegmentChart({
    super.key,
    required this.groups,
    required this.maxAbsValue,
    this.centerLabel,
    this.innerOuterRadiusRatio = 2.5,
  }) : assert(innerOuterRadiusRatio > 1.0);

  @override
  State<RadialSegmentChart> createState() => _RadialSegmentChartState();
}

class _RadialSegmentChartState extends State<RadialSegmentChart> {
  OverlayEntry? _overlayEntry;
  int? _selectedSegmentIndex;

  // Hilfs-Getter, um eine flache Liste aller Segmente zu erhalten.
  List<SegmentData> get _allSegments =>
      widget.groups.expand((group) => group.segments).toList();

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _handleTap(Offset localPosition) {
    final painter = _RadialSegmentPainter(
      groups: widget.groups,
      maxAbsValue: widget.maxAbsValue,
      centerLabel: widget.centerLabel,
      innerOuterRadiusRatio: widget.innerOuterRadiusRatio,
    );

    if (context.size == null) return;

    final index = painter.getSegmentIndexAt(localPosition, context.size!);

    _removeOverlay();

    if (index != null && index != _selectedSegmentIndex) {
      setState(() {
        _selectedSegmentIndex = index;
      });
      _showOverlay(context, localPosition, index);
    } else {
      setState(() {
        _selectedSegmentIndex = null;
      });
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, Offset tapPosition, int segmentIndex) {
    final overlayState = Overlay.of(context);
    final segment = _allSegments[segmentIndex];

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _removeOverlay();
            setState(() {
              _selectedSegmentIndex = null;
            });
          },
          child: Stack(
            children: [
              Positioned(
                left: tapPosition.dx + 5,
                top: tapPosition.dy + 5,
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    color: Colors.transparent,
                    child: Card(
                      elevation: 4.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(segment.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Wert: ${segment.value.toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlayState.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _handleTap(details.localPosition),
      child: CustomPaint(
        size: Size.infinite,
        painter: _RadialSegmentPainter(
          groups: widget.groups,
          maxAbsValue: widget.maxAbsValue,
          centerLabel: widget.centerLabel,
          innerOuterRadiusRatio: widget.innerOuterRadiusRatio,
          selectedSegmentIndex: _selectedSegmentIndex,
        ),
      ),
    );
  }
}

// =================================================================
// LAYOUT-KLASSE (unverändert)
// =================================================================
class _ChartLayout {
  final double baseRadius;
  final double maxSegmentRadius;
  final double groupRingOuterRadius;
  final double groupLabelPathRadius;
  final TextStyle segmentLabelStyle;
  final TextStyle groupLabelStyle;
  final TextStyle centerLabelStyle;
  final Paint borderPaint;
  final Paint baseCirclePaint;

  _ChartLayout({
    required this.baseRadius, required this.maxSegmentRadius,
    required this.groupRingOuterRadius, required this.groupLabelPathRadius,
    required this.segmentLabelStyle, required this.groupLabelStyle,
    required this.centerLabelStyle, required this.borderPaint,
    required this.baseCirclePaint,
  });
}

// =================================================================
// PAINTER-KLASSE (komplett überarbeitet)
// =================================================================
class _RadialSegmentPainter extends CustomPainter {
  final List<GroupData> groups;
  final double maxAbsValue;
  final int? centerLabel;
  final double innerOuterRadiusRatio;
  final int? selectedSegmentIndex;

  // Hilfs-Getter
  late final List<SegmentData> _allSegments =
  groups.expand((group) => group.segments).toList();
  late final int _totalSegments = _allSegments.length;

  _RadialSegmentPainter({
    required this.groups,
    required this.maxAbsValue,
    required this.centerLabel,
    required this.innerOuterRadiusRatio,
    this.selectedSegmentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || _totalSegments == 0) return;

    final Offset center = size.center(Offset.zero);
    final layout = _calculateLayout(size);
    final double anglePerSegment = 2 * pi / _totalSegments;

    _drawGroupBackgrounds(canvas, center, layout, anglePerSegment);
    _drawSegmentsAndLabels(canvas, center, layout, anglePerSegment);
    _drawBaseCircle(canvas, center, layout);
    _drawGroupLabels(canvas, center, layout, anglePerSegment);
    _drawCenterContent(canvas, center, layout);
  }

  _ChartLayout _calculateLayout(Size size) {
    final double availableRadius = min(size.width, size.height) / 2;
    const double refSize = 400.0;
    final double scale = availableRadius / (refSize / 2);

    final groupLabelFontSize = 11.0 * scale;
    final segmentLabelFontSize = 9.0 * scale;
    final centerLabelFontSize = 18.0 * scale;
    final groupLabelOffset = 15.0 * scale;
    final segmentLabelOffset = 5.0 * scale;

    final groupLabelStyle = TextStyle(fontSize: groupLabelFontSize, fontWeight: FontWeight.bold, color: Colors.black87);
    final segmentLabelStyle = TextStyle(fontSize: segmentLabelFontSize, color: Colors.black87);
    final centerLabelStyle = TextStyle(fontSize: centerLabelFontSize, fontWeight: FontWeight.bold, color: Colors.black.withOpacity(0.8));

    final groupLabelHeight = _getTextSize('T', groupLabelStyle).height;
    final groupLabelPathRadius = availableRadius - (groupLabelHeight / 2);
    final groupRingOuterRadius = groupLabelPathRadius - groupLabelOffset;

    final segmentLabelHeight = _getTextSize('T', segmentLabelStyle).height;
    final maxSegmentRadius = groupRingOuterRadius - segmentLabelHeight - segmentLabelOffset;
    final baseRadius = maxSegmentRadius / innerOuterRadiusRatio;

    final borderPaint = Paint()..color = Colors.black.withOpacity(0.1)..style = PaintingStyle.stroke..strokeWidth = 1.0 * scale;
    final baseCirclePaint = Paint()..color = Colors.grey.shade500..style = PaintingStyle.stroke..strokeWidth = 1.5 * scale;

    return _ChartLayout(
      baseRadius: baseRadius,
      maxSegmentRadius: maxSegmentRadius,
      groupRingOuterRadius: groupRingOuterRadius,
      groupLabelPathRadius: groupLabelPathRadius,
      segmentLabelStyle: segmentLabelStyle,
      groupLabelStyle: groupLabelStyle,
      centerLabelStyle: centerLabelStyle,
      borderPaint: borderPaint,
      baseCirclePaint: baseCirclePaint,
    );
  }

  void _drawGroupBackgrounds(Canvas canvas, Offset center, _ChartLayout layout, double anglePerSegment) {
    final paint = Paint()..style = PaintingStyle.stroke;
    int currentSegmentIndex = 0;

    for (final group in groups) {
      final startAngle = currentSegmentIndex * anglePerSegment;
      final sweepAngle = group.segments.length * anglePerSegment;

      paint.color = group.backgroundColor;
      paint.strokeWidth = layout.groupRingOuterRadius - layout.baseRadius;
      final drawRadius = layout.baseRadius + paint.strokeWidth / 2;

      canvas.drawArc(Rect.fromCircle(center: center, radius: drawRadius), startAngle, sweepAngle, false, paint);
      currentSegmentIndex += group.segments.length;
    }
  }

  void _drawSegmentsAndLabels(Canvas canvas, Offset center, _ChartLayout layout, double anglePerSegment) {
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _totalSegments; i++) {
      final segment = _allSegments[i];
      final double value = segment.value.clamp(0.0, maxAbsValue);
      final startAngle = i * anglePerSegment;
      final midAngle = startAngle + anglePerSegment / 2;

      final segmentOuterRadius = ui.lerpDouble(layout.baseRadius, layout.maxSegmentRadius, value / maxAbsValue)!;
      final segmentPath = Path()
        ..addArc(Rect.fromCircle(center: center, radius: layout.baseRadius), startAngle, anglePerSegment)
        ..arcTo(Rect.fromCircle(center: center, radius: segmentOuterRadius), startAngle + anglePerSegment, -anglePerSegment, false);

      final baseColor = _getColorForValue(value);
      final highlightColor = HSLColor.fromColor(baseColor).withLightness(min(1.0, HSLColor.fromColor(baseColor).lightness + 0.2)).toColor();
      final segmentBounds = segmentPath.getBounds();

      fillPaint.shader = RadialGradient(
        center: const Alignment(-0.5, -0.5),
        radius: 0.8,
        colors: [highlightColor, baseColor],
        stops: const [0.0, 1.0],
      ).createShader(segmentBounds);

      canvas.drawPath(segmentPath, fillPaint);
      fillPaint.shader = null;

      final isSelected = i == selectedSegmentIndex;
      final borderPaint = isSelected
          ? (Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = layout.borderPaint.strokeWidth * 2.5)
          : layout.borderPaint;
      canvas.drawPath(segmentPath, borderPaint);

      final labelRadius = layout.maxSegmentRadius + layout.segmentLabelStyle.fontSize!;
      _drawCurvedText(
        canvas: canvas,
        center: center,
        text: segment.name,
        style: layout.segmentLabelStyle,
        radius: labelRadius,
        centerAngle: midAngle,
      );
    }
  }

  void _drawBaseCircle(Canvas canvas, Offset center, _ChartLayout layout) {
    canvas.drawCircle(center, layout.baseRadius, layout.baseCirclePaint);
  }

  void _drawGroupLabels(Canvas canvas, Offset center, _ChartLayout layout, double anglePerSegment) {
    int currentSegmentIndex = 0;
    for (final group in groups) {
      final groupStartAngle = currentSegmentIndex * anglePerSegment;
      final groupMidAngle = groupStartAngle + (group.segments.length * anglePerSegment) / 2;
      _drawCurvedText(
        canvas: canvas,
        center: center,
        text: group.name.toUpperCase(),
        style: layout.groupLabelStyle,
        radius: layout.groupLabelPathRadius,
        centerAngle: groupMidAngle,
      );
      currentSegmentIndex += group.segments.length;
    }
  }

  void _drawCenterContent(Canvas canvas, Offset center, _ChartLayout layout) {
    final centerPaint = Paint();
    final baseColor = centerLabel != null ? _getColorForValue(centerLabel!.toDouble()) : Colors.grey.withOpacity(0.1);

    if (centerLabel != null) {
      final highlightColor = HSLColor.fromColor(baseColor).withLightness(min(1.0, HSLColor.fromColor(baseColor).lightness + 0.2)).toColor();
      centerPaint.shader = RadialGradient(
        center: const Alignment(-0.4, -0.4),
        radius: 1.5,
        colors: [highlightColor, baseColor],
      ).createShader(Rect.fromCircle(center: center, radius: layout.baseRadius));
    } else {
      centerPaint.color = baseColor;
    }

    canvas.drawCircle(center, layout.baseRadius, centerPaint);
    centerPaint.shader = null;

    if (centerLabel != null) {
      final textPainter = TextPainter(
          text: TextSpan(text: centerLabel.toString(), style: layout.centerLabelStyle),
          textDirection: TextDirection.ltr, textAlign: TextAlign.center)
        ..layout();
      textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }

  Color _getColorForValue(double value) {
    final effectiveMax = maxAbsValue <= 0 ? 1.0 : maxAbsValue;
    final t = (value.abs() / effectiveMax).clamp(0.0, 1.0);

    final colorSequence = TweenSequence<Color?>([
      TweenSequenceItem(tween: ColorTween(begin: Colors.red.shade800, end: Colors.orange.shade700), weight: 40.0),
      TweenSequenceItem(tween: ColorTween(begin: Colors.orange.shade700, end: const Color(0xFFFFD700)), weight: 30.0),
      TweenSequenceItem(tween: ColorTween(begin: const Color(0xFFFFD700), end: Colors.green.shade500), weight: 30.0),
    ]);
    return colorSequence.transform(t)!;
  }

  Size _getTextSize(String text, TextStyle style) {
    final textPainter = TextPainter(text: TextSpan(text: text, style: style), maxLines: 1, textDirection: TextDirection.ltr)..layout();
    return textPainter.size;
  }

  void _drawCurvedText({
    required Canvas canvas, required Offset center, required String text,
    required TextStyle style, required double radius, required double centerAngle,
  }) {
    double totalTextWidth = 0;
    final List<Size> charSizes = [];
    for (int i = 0; i < text.length; i++) {
      final charSize = _getTextSize(text[i], style);
      charSizes.add(charSize);
      totalTextWidth += charSize.width;
    }

    final double totalAngle = totalTextWidth / radius;
    double currentAngle = centerAngle - totalAngle / 2;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final charSize = charSizes[i];
      final charWidth = charSize.width;
      final double charAngle = charWidth / radius;
      final double charCenterAngle = currentAngle + charAngle / 2;

      canvas.save();
      final position = center + Offset.fromDirection(charCenterAngle, radius);
      canvas.translate(position.dx, position.dy);

      canvas.rotate(charCenterAngle + pi / 2);
      final textPainter = TextPainter(
          text: TextSpan(text: char, style: style),
          textAlign: TextAlign.center, textDirection: TextDirection.ltr)
        ..layout();
      textPainter.paint(canvas, Offset(-charWidth / 2, -charSize.height / 2));
      canvas.restore();
      currentAngle += charAngle;
    }
  }

  // =================================================================
  // ÜBERARBEITETE TREFFER-LOGIK (HIT-TESTING)
  // =================================================================
  int? getSegmentIndexAt(Offset localPosition, Size size) {
    final center = size.center(Offset.zero);
    final layout = _calculateLayout(size);
    if (_totalSegments == 0) return null;
    final anglePerSegment = 2 * pi / _totalSegments;

    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    final distance = sqrt(dx * dx + dy * dy);
    var angle = atan2(dy, dx);

    if (angle < 0) {
      angle += 2 * pi;
    }

    // Prüft, ob der Klick innerhalb des gesamten interaktiven Rings liegt.
    if (distance >= layout.baseRadius && distance <= layout.groupRingOuterRadius) {
      // Berechnet den Index direkt aus dem Winkel.
      final index = (angle / anglePerSegment).floor();

      if (index >= 0 && index < _totalSegments) {
        return index;
      }
    }

    return null; // Kein Treffer
  }

  @override
  bool shouldRepaint(covariant _RadialSegmentPainter oldDelegate) {
    // Die Daten werden jetzt als Ganzes verglichen.
    return oldDelegate is! _RadialSegmentPainter ||
        oldDelegate.groups != groups ||
        oldDelegate.maxAbsValue != maxAbsValue ||
        oldDelegate.centerLabel != centerLabel ||
        oldDelegate.innerOuterRadiusRatio != innerOuterRadiusRatio ||
        oldDelegate.selectedSegmentIndex != selectedSegmentIndex;
  }
}
