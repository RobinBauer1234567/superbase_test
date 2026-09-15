from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 occurrence, found {count}")
    return text.replace(old, new, 1)


# Sanity scan: the user-visible FORM tile should currently exist exactly once.
form_label_hits = []
for path in Path('lib').rglob('*.dart'):
    text = path.read_text()
    if "label: 'FORM'" in text:
        form_label_hits.append(str(path))

if form_label_hits != ['lib/screens/player_screen.dart']:
    raise SystemExit(f"Unexpected FORM label locations: {form_label_hits}")


# Central helper functions.
helper_path = Path('lib/utils/color_helper.dart')
helper = helper_path.read_text()
marker = "\ndouble getAveragePoints(num totalPoints, int appearanceCount) {\n"
insert = """
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
if insert.strip() not in helper:
    helper = replace_once(helper, marker, "\n" + insert + "double getAveragePoints(num totalPoints, int appearanceCount) {\n", 'color helper insertion')
helper_path.write_text(helper)


# Player profile FORM tile.
player_path = Path('lib/screens/player_screen.dart')
player = player_path.read_text()
old = """                    // 3. Form (Wert zwischen 0.0 und 3.0 aus der DB).
                    // Da getColorForRating wahrscheinlich Ganzzahlen (int) nutzt, multiplizieren wir es mit 10 (z.B. 2.5 wird 25 von 30)
                    final Color colorForm = getColorForRating(playerForm.round(), 250);
"""
new = """                    // 3. Form: gleiche kumulative Farbformel wie Gesamtpunkte,
                    // aber mit maximal fünf gewerteten Spieltagen.
                    final int formColorValue = getFormRatingColorValue(
                      playerForm,
                      _ratedRoundCount,
                    );
                    final int formColorMax = getFormRatingMaxValue(
                      _ratedRoundCount,
                      _ratingColorDecayBase,
                    );
                    final Color colorForm = getColorForRating(
                      formColorValue,
                      formColorMax,
                    );
"""
player = replace_once(player, old, new, 'player form color block')
player_path.write_text(player)


# Tests.
test_path = Path('test/color_helper_test.dart')
test = test_path.read_text()
needle = "\n}\n"
block = """

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
if "group('form rating color scaling'" not in test:
    idx = test.rfind(needle)
    if idx == -1:
        raise SystemExit('test file closing brace not found')
    test = test[:idx] + block + test[idx:]
test_path.write_text(test)
