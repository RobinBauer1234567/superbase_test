import 'dart:math' as math;

import 'package:flutter/material.dart';

const int singleMatchRatingMax = 250;
const double defaultRatingColorDecayBase = 0.8;

Color getColorForRating(num rating, int maxValue) {
  final effectiveMax = maxValue <= 0 ? 1.0 : maxValue.toDouble();
  final t = (rating / effectiveMax).clamp(0.0, 1.0);

  final colorSequence = TweenSequence<Color?>([
    TweenSequenceItem(
      tween: ColorTween(
        begin: Colors.red.shade800,
        end: Colors.orange.shade700,
      ),
      weight: 40.0,
    ),
    TweenSequenceItem(
      tween: ColorTween(
        begin: Colors.orange.shade700,
        end: const Color(0xFFFFD700),
      ),
      weight: 30.0,
    ),
    TweenSequenceItem(
      tween: ColorTween(
        begin: const Color(0xFFFFD700),
        end: Colors.lightGreen.shade500,
      ),
      weight: 30.0,
    ),
    TweenSequenceItem(
      tween: ColorTween(
        begin: Colors.lightGreen.shade500,
        end: Colors.green.shade500,
      ),
      weight: 30.0,
    ),
    TweenSequenceItem(
      tween: ColorTween(
        begin: Colors.green.shade500,
        end: Colors.teal.shade500,
      ),
      weight: 30.0,
    ),
    TweenSequenceItem(
      tween: ColorTween(
        begin: Colors.teal.shade500,
        end: Colors.purple.shade500,
      ),
      weight: 30.0,
    ),
  ]);
  return colorSequence.transform(t)!;
}

double getAggregateRatingFactor(
  int gameCount,
  double decayBase,
) {
  final safeGameCount = math.max(1, gameCount);
  final safeDecayBase =
      decayBase > 0 && decayBase <= 1
          ? decayBase
          : defaultRatingColorDecayBase;

  return math
      .pow(safeDecayBase, math.log(safeGameCount.toDouble()))
      .toDouble();
}

/// Converts a cumulative score into the equivalent single-match rating used by
/// the shared color scale.
///
/// Formula:
///   equivalent = (totalPoints / games) * decayBase ^ ln(games)
///
/// For one game the factor is exactly 1, so the color is identical to the
/// single-match color for the same score.
double getAggregateEquivalentRating(
  num totalPoints,
  int gameCount,
  double decayBase,
) {
  final safeGameCount = math.max(1, gameCount);
  final factor = getAggregateRatingFactor(safeGameCount, decayBase);
  return (totalPoints.toDouble() / safeGameCount) * factor;
}

/// Keeps displaying the cumulative score while producing the same color as
/// getAggregateEquivalentRating(..., 250). This lets existing widgets keep
/// using getColorForRating(rawTotal, maxValue) without changing the number
/// shown to the user.
int getAggregateRatingMaxValue(
  int gameCount,
  double decayBase, {
  int singleMatchMax = singleMatchRatingMax,
}) {
  final safeGameCount = math.max(1, gameCount);
  final factor = getAggregateRatingFactor(safeGameCount, decayBase);
  final maxValue = (safeGameCount * singleMatchMax) / factor;
  return math.max(1, maxValue.round());
}
