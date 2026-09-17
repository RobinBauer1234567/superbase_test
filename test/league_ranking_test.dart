import 'package:flutter_test/flutter_test.dart';
import 'package:premier_league/utils/league_ranking.dart';

void main() {
  test('countries are ordered by association coefficient globally', () {
    final groups = groupTournamentsByAssociationRanking([
      {
        'id': 1,
        'name': 'Liga Portugal Betclic',
        'country_name': 'Portugal',
        'gender': 'M',
        'tier': 1,
        'association_coefficient': 65.350,
      },
      {
        'id': 2,
        'name': 'Brasileirão Betano',
        'country_name': 'Brazil',
        'gender': 'M',
        'tier': 1,
        'association_coefficient': 72.0,
      },
      {
        'id': 3,
        'name': 'Premier League',
        'country_name': 'England',
        'gender': 'M',
        'tier': 1,
        'association_coefficient': 103.352,
      },
    ]);

    expect(
      groups.map((group) => group.country).toList(),
      ['England', 'Brazil', 'Portugal'],
    );
  });

  test('men are ordered by tier before women inside a country', () {
    final groups = groupTournamentsByAssociationRanking([
      {
        'id': 1,
        'name': 'Frauen-Bundesliga',
        'country_name': 'Germany',
        'gender': 'F',
        'tier': 1,
      },
      {
        'id': 2,
        'name': '3. Liga',
        'country_name': 'Germany',
        'gender': 'M',
        'tier': 3,
      },
      {
        'id': 3,
        'name': 'Bundesliga',
        'country_name': 'Germany',
        'gender': 'M',
        'tier': 1,
      },
      {
        'id': 4,
        'name': '2. Bundesliga',
        'country_name': 'Germany',
        'gender': 'M',
        'tier': 2,
      },
    ]);

    expect(
      groups.single.tournaments.map((tournament) => tournament['name']).toList(),
      ['Bundesliga', '2. Bundesliga', '3. Liga', 'Frauen-Bundesliga'],
    );
  });

  test('country search accepts German country names', () {
    final tournaments = [
      {'id': 1, 'name': 'Bundesliga', 'country_name': 'Germany', 'gender': 'M'},
      {'id': 2, 'name': 'Premier League', 'country_name': 'England', 'gender': 'M'},
    ];

    final filtered = filterTournaments(
      tournaments: tournaments,
      query: 'Deutschland',
    );

    expect(filtered.map((tournament) => tournament['name']).toList(), ['Bundesliga']);
  });

  test('league-name search keeps its country grouping', () {
    final tournaments = [
      {'id': 1, 'name': 'Bundesliga', 'country_name': 'Germany', 'gender': 'M'},
      {'id': 2, 'name': '2. Bundesliga', 'country_name': 'Germany', 'gender': 'M'},
      {'id': 3, 'name': 'Premier League', 'country_name': 'England', 'gender': 'M'},
    ];

    final filtered = filterTournaments(
      tournaments: tournaments,
      query: 'Premier League',
    );
    final groups = groupTournamentsByAssociationRanking(filtered);

    expect(groups.single.displayCountry, 'England');
    expect(groups.single.tournaments.single['name'], 'Premier League');
  });

  test('gender filter supports men and women independently', () {
    final tournaments = [
      {'id': 1, 'name': 'Bundesliga', 'country_name': 'Germany', 'gender': 'M'},
      {'id': 2, 'name': 'Frauen-Bundesliga', 'country_name': 'Germany', 'gender': 'F'},
    ];

    final men = filterTournaments(tournaments: tournaments, gender: 'M');
    final women = filterTournaments(tournaments: tournaments, gender: 'F');

    expect(men.single['name'], 'Bundesliga');
    expect(women.single['name'], 'Frauen-Bundesliga');
  });
}
