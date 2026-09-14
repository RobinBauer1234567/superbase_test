import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int singleMatchRatingMax = 250;
const double defaultRatingColorDecayBase = 0.8;
const double defaultAverageRatingColorDecayBase = 0.85;

Future<double> fetchRatingColorDecayBase(SupabaseClient client) async {
  try {
    final settings = await client
        .from('game_settings')
        .select('rating_color_decay_base')
        .eq('id', 1)
        .maybeSingle();
    final rawValue = settings?['rating_color_decay_base'];
    final value = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '');
    if (value != null && value > 0 && value <= 1) return value;
  } catch (_) {
    // Use the safe default below.
  }
  return defaultRatingColorDecayBase;
}

Future<double> fetchAverageRatingColorDecayBase(SupabaseClient client) async {
  try {
    final settings = await client
        .from('game_settings')
        .select('average_rating_color_decay_base')
        .eq('id', 1)
        .maybeSingle();
    final rawValue = settings?['average_rating_color_decay_base'];
    final value = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '');
    if (value != null && value > 0 && value <= 1) return value;
  } catch (_) {
    // Use the safe default below.
  }
  return defaultAverageRatingColorDecayBase;
}

Future<int> fetchRatedSeasonRoundCount(
  SupabaseClient client,
  dynamic seasonId,
) async {
  try {
    final rows = await client
        .from('spieltag')
        .select('round')
        .eq('season_id', seasonId)
        .neq('status', 'nicht gestartet');
    final rounds = rows.map((row) => row['round'].toString()).toSet();
    return math.max(1, rounds.length);
  } catch (_) {
    return 1;
  }
}

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

double getAggregateRatingFactor(int gameCount, double decayBase) {
  final safeGameCount = math.max(1, gameCount);
  final safeDecayBase = decayBase > 0 && decayBase <= 1
      ? decayBase
      : defaultRatingColorDecayBase;

  return math.pow(safeDecayBase, math.log(safeGameCount.toDouble())).toDouble();
}

/// Converts a cumulative score into the equivalent single-match rating used by
/// the shared color scale.
///
/// The aggregate comparison scale is:
///   games * 250 * decayBase ^ ln(games)
///
/// Therefore the equivalent value on the normal 0..250 color scale is:
///   equivalent = (totalPoints / games) / decayBase ^ ln(games)
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
  return (totalPoints.toDouble() / safeGameCount) / factor;
}

/// Keeps displaying the cumulative score while applying exactly the same color
/// function as a single match. The former fixed Top-Team factors are replaced
/// with decayBase ^ ln(games).
int getAggregateRatingMaxValue(
  int gameCount,
  double decayBase, {
  int singleMatchMax = singleMatchRatingMax,
}) {
  final safeGameCount = math.max(1, gameCount);
  final factor = getAggregateRatingFactor(safeGameCount, decayBase);
  final maxValue = safeGameCount * singleMatchMax * factor;
  return math.max(1, maxValue.round());
}

double getAveragePoints(num totalPoints, int appearanceCount) {
  if (appearanceCount <= 0) return 0;
  return totalPoints.toDouble() / appearanceCount;
}

double getAverageRatingFactor(int appearanceCount, double decayBase) {
  final safeAppearanceCount = math.max(1, appearanceCount);
  final safeDecayBase = decayBase > 0 && decayBase <= 1
      ? decayBase
      : defaultAverageRatingColorDecayBase;

  return math
      .pow(safeDecayBase, math.log(safeAppearanceCount.toDouble()))
      .toDouble();
}

/// Maximum of the color scale for displayed season-average points.
///
/// average = total season points / spieler_analytics.anzahl_spiele
/// max = singleMatchMax * decayBase ^ ln(anzahl_spiele)
int getAverageRatingMaxValue(
  int appearanceCount,
  double decayBase, {
  int singleMatchMax = singleMatchRatingMax,
}) {
  final factor = getAverageRatingFactor(appearanceCount, decayBase);
  return math.max(1, (singleMatchMax * factor).round());
}
