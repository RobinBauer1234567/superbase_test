from pathlib import Path
import subprocess


def from_main(path: str) -> str:
    result = subprocess.run(
        ['git', 'show', f'origin/main:{path}'],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


helper_path = Path('lib/utils/color_helper.dart')
helper = from_main(str(helper_path))
marker = "\ndouble getAveragePoints(num totalPoints, int appearanceCount) {\n"
block = """
/// Number of season rounds used to color the rolling form value.
///
/// The form color follows the same cumulative scale as total season points,
/// but freezes the comparison window at five rated rounds.
int getFormRatingRoundCount(
  int ratedRoundCount, {
  int maxRounds = 5,
}) {
  final safeMaxRounds = math.max(1, maxRounds);
  return math.min(math.max(1, ratedRoundCount), safeMaxRounds);
}

/// Converts the displayed rolling form average into the cumulative-equivalent
/// score used by the aggregate color formula.
int getFormRatingColorValue(
  num formAverage,
  int ratedRoundCount, {
  int maxRounds = 5,
}) {
  final rounds = getFormRatingRoundCount(
    ratedRoundCount,
    maxRounds: maxRounds,
  );
  return (formAverage.toDouble() * rounds).round();
}

/// Maximum for the rolling form color scale.
///
/// n = min(ratedRoundCount, 5)
/// max = n * singleMatchMax * decayBase ^ ln(n)
int getFormRatingMaxValue(
  int ratedRoundCount,
  double decayBase, {
  int maxRounds = 5,
  int singleMatchMax = singleMatchRatingMax,
}) {
  final rounds = getFormRatingRoundCount(
    ratedRoundCount,
    maxRounds: maxRounds,
  );
  return getAggregateRatingMaxValue(
    rounds,
    decayBase,
    singleMatchMax: singleMatchMax,
  );
}

"""
if helper.count(marker) != 1:
    raise SystemExit('helper insertion marker mismatch')
helper = helper.replace(marker, '\n' + block + 'double getAveragePoints(num totalPoints, int appearanceCount) {\n', 1)
helper_path.write_text(helper)


test_path = Path('test/color_helper_test.dart')
test = from_main(str(test_path))
test_block = """

  group('form rating color scaling', () {
    test('form round count is capped at five', () {
      expect(getFormRatingRoundCount(1), 1);
      expect(getFormRatingRoundCount(4), 4);
      expect(getFormRatingRoundCount(5), 5);
      expect(getFormRatingRoundCount(12), 5);
    });

    test('one rated round matches the single-match color scale', () {
      const formAverage = 125.0;
      final value = getFormRatingColorValue(formAverage, 1);
      final maxValue = getFormRatingMaxValue(1, 0.8);

      expect(value, 125);
      expect(maxValue, singleMatchRatingMax);
      expect(
        getColorForRating(value, maxValue),
        getColorForRating(125, singleMatchRatingMax),
      );
    });

    test('form uses the aggregate formula with the capped round count', () {
      const formAverage = 100.0;
      const ratedRounds = 4;
      const base = 0.8;
      final rounds = getFormRatingRoundCount(ratedRounds);

      expect(
        getFormRatingColorValue(formAverage, ratedRounds),
        (formAverage * rounds).round(),
      );
      expect(
        getFormRatingMaxValue(ratedRounds, base),
        getAggregateRatingMaxValue(rounds, base),
      );
    });

    test('form color scale no longer changes after round five', () {
      const formAverage = 110.0;
      const base = 0.8;

      expect(
        getFormRatingColorValue(formAverage, 5),
        getFormRatingColorValue(formAverage, 20),
      );
      expect(
        getFormRatingMaxValue(5, base),
        getFormRatingMaxValue(20, base),
      );
    });
  });
"""
closing = '\n}\n'
idx = test.rfind(closing)
if idx == -1:
    raise SystemExit('test closing brace not found')
test = test[:idx] + test_block + test[idx:]
test_path.write_text(test)
