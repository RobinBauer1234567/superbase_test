import 'package:flutter_test/flutter_test.dart';
import 'package:premier_league/services/match_import.dart';

Map<String, dynamic> event(int id, int home, int away) => {
  'id': id,
  'homeTeam': {'id': home},
  'awayTeam': {'id': away},
  'startTimestamp': 1750000000,
  'tournament': {
    'uniqueTournament': {'id': 17},
  },
  'season': {'id': 78229},
  'roundInfo': {'round': 1},
};
void main() {
  List<Map<String, dynamic>> parse(List<dynamic> events) =>
      validateMatchEvents(events, tournamentId: 17, seasonId: 78229, round: 1);
  test('several distinct fixtures in one round are valid', () {
    expect(parse([event(1, 10, 11), event(2, 12, 13)]), hasLength(2));
  });
  test('a team cannot occur again as visitor', () {
    expect(
      () => parse([event(14159939, 124, 81), event(14722090, 90, 124)]),
      throwsFormatException,
    );
  });
  test('repeated event and self matches are rejected', () {
    expect(
      () => parse([event(1, 10, 11), event(1, 10, 11)]),
      throwsFormatException,
    );
    expect(() => parse([event(1, 10, 10)]), throwsFormatException);
  });
  test('response season, tournament and round must match', () {
    for (final change in [
      {
        'season': {'id': 90000},
      },
      {
        'roundInfo': {'round': 2},
      },
      {
        'tournament': {
          'uniqueTournament': {'id': 18},
        },
      },
      {'roundInfo': null},
    ]) {
      expect(
        () => parse([
          {...event(1, 10, 11), ...change},
        ]),
        throwsFormatException,
      );
    }
  });
}
