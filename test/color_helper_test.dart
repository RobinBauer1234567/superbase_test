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
}
