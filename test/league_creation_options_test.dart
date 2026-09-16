import 'package:flutter_test/flutter_test.dart';
import 'package:premier_league/utils/league_creation_options.dart';

void main() {
  test('only newest active initialized unfinished seasons are offered', () {
    final targets = leagueCreationTargets([
      {
        'id': 17,
        'name': 'Premier League',
        'season': [
          {
            'id': 2026,
            'name': '26/27',
            'is_active': true,
            'is_initialized': true,
            'finished_at': null,
          },
        ],
      },
      {
        'id': 8,
        'name': 'LaLiga',
        'season': [
          {
            'id': 2025,
            'name': '25/26',
            'is_active': true,
            'is_initialized': true,
            'finished_at': '2026-05-30T00:00:00Z',
          },
        ],
      },
      {
        'id': 35,
        'name': 'Bundesliga',
        'season': [
          {
            'id': 2027,
            'name': '26/27',
            'is_active': true,
            'is_initialized': false,
            'finished_at': null,
          },
        ],
      },
      {
        'id': 99,
        'name': 'Archive fallback must not happen',
        'season': [
          {
            'id': 2027,
            'name': '26/27',
            'is_active': false,
            'is_initialized': false,
            'finished_at': null,
          },
          {
            'id': 2026,
            'name': '25/26',
            'is_active': true,
            'is_initialized': true,
            'finished_at': null,
          },
        ],
      },
    ]);

    expect(targets.map((target) => target.tournamentId), [17]);
    expect(targets.single.seasonId, 2026);
  });

  test('current tournament is preferred when it is eligible', () {
    const premier = LeagueCreationTarget(
      tournamentId: 17,
      tournamentName: 'Premier League',
      seasonId: 1,
      seasonName: '26/27',
    );
    const laLiga = LeagueCreationTarget(
      tournamentId: 8,
      tournamentName: 'LaLiga',
      seasonId: 2,
      seasonName: '26/27',
    );

    expect(
      preferredLeagueCreationTarget([laLiga, premier], 17)?.tournamentId,
      17,
    );
    expect(
      preferredLeagueCreationTarget([laLiga, premier], 999)?.tournamentId,
      8,
    );
  });
}
