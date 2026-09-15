import 'package:flutter_test/flutter_test.dart';
import 'package:premier_league/utils/color_helper.dart';

void main() {
  group('aggregate rating color scaling', () {
    test('one game is identical to single-match scale', () {
      expect(getAggregateRatingFactor(1, 0.8), closeTo(1.0, 1e-12));
      expect(getAggregateRatingMaxValue(1, 0.8), singleMatchRatingMax);
      expect(
        getColorForRating(125, getAggregateRatingMaxValue(1, 0.8)),
        getColorForRating(125, singleMatchRatingMax),
      );
    });

    test('factor decreases with more games', () {
      final factor1 = getAggregateRatingFactor(1, 0.8);
      final factor4 = getAggregateRatingFactor(4, 0.8);
      final factor10 = getAggregateRatingFactor(10, 0.8);

      expect(factor4, lessThan(factor1));
      expect(factor10, lessThan(factor4));
    });

    test('aggregate max follows games * 250 * factor', () {
      final factor = getAggregateRatingFactor(4, 0.8);
      final expected = (4 * singleMatchRatingMax * factor).round();

      expect(getAggregateRatingMaxValue(4, 0.8), expected);
    });

    test('equivalent rating produces the same normalized position', () {
      const totalPoints = 500;
      const games = 4;
      const base = 0.8;

      final aggregateMax = getAggregateRatingMaxValue(games, base);
      final equivalent = getAggregateEquivalentRating(totalPoints, games, base);
      final aggregateRatio = totalPoints / aggregateMax;
      final singleMatchRatio = equivalent / singleMatchRatingMax;

      // Aggregate max is rounded to the integer expected by the existing widgets,
      // so allow the tiny rounding difference.
      expect(aggregateRatio, closeTo(singleMatchRatio, 0.001));
    });

    test('invalid decay base falls back to 0.8', () {
      expect(
        getAggregateRatingFactor(5, 2.0),
        closeTo(getAggregateRatingFactor(5, 0.8), 1e-12),
      );
    });
  });


  test('season-wide round count is independent of player appearances', () {
    const roundCount = 4;
    const playerAppearances = 1;
    final seasonMax = getAggregateRatingMaxValue(roundCount, 0.8);
    final appearanceMax = getAggregateRatingMaxValue(playerAppearances, 0.8);
    expect(seasonMax, isNot(appearanceMax));
    expect(seasonMax, greaterThan(appearanceMax));
  });

  group('average rating color scaling', () {
    test('average points use total points divided by analytics appearances', () {
      expect(getAveragePoints(500, 4), closeTo(125.0, 1e-12));
      expect(getAveragePoints(500, 0), 0);
    });

    test('one appearance keeps the normal 250 maximum', () {
      expect(getAverageRatingFactor(1, 0.85), closeTo(1.0, 1e-12));
      expect(
        getAverageRatingMaxValue(1, 0.85),
        singleMatchRatingMax,
      );
    });

    test('average color maximum decays with more appearances', () {
      final max1 = getAverageRatingMaxValue(1, 0.85);
      final max4 = getAverageRatingMaxValue(4, 0.85);
      final max10 = getAverageRatingMaxValue(10, 0.85);

      expect(max4, lessThan(max1));
      expect(max10, lessThan(max4));
      expect(
        max4,
        (singleMatchRatingMax * getAverageRatingFactor(4, 0.85)).round(),
      );
    });

    test('invalid average decay base falls back to 0.85', () {
      expect(
        getAverageRatingFactor(5, 2.0),
        closeTo(getAverageRatingFactor(5, 0.85), 1e-12),
      );
    });
  });


  group('form rating color scaling', () {
    test('form appearance count follows player appearances and caps at five', () {
      expect(getFormRatingAppearanceCount(0), 1);
      expect(getFormRatingAppearanceCount(1), 1);
      expect(getFormRatingAppearanceCount(4), 4);
      expect(getFormRatingAppearanceCount(5), 5);
      expect(getFormRatingAppearanceCount(12), 5);
    });

    test('one appearance keeps the normal 250 average maximum', () {
      expect(
        getFormRatingMaxValue(1, 0.85),
        singleMatchRatingMax,
      );
    });

    test('form uses the same 0.85 average decay as average points', () {
      const appearances = 4;
      const base = 0.85;
      expect(
        getFormRatingMaxValue(appearances, base),
        getAverageRatingMaxValue(appearances, base),
      );
    });

    test('form color scale stops changing after the fifth appearance', () {
      const base = 0.85;
      expect(
        getFormRatingMaxValue(5, base),
        getFormRatingMaxValue(20, base),
      );
    });

    test('form uses the configured average fallback for invalid bases', () {
      expect(
        getFormRatingMaxValue(5, 2.0),
        getFormRatingMaxValue(5, defaultAverageRatingColorDecayBase),
      );
    });
  });

}
