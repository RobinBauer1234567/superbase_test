import 'package:flutter_test/flutter_test.dart';
import 'package:premier_league/utils/uefa_country_ranking.dart';

void main() {
  test('UEFA countries follow the five-year association ranking', () {
    final groups = groupTournamentsByUefaCountryRanking([
      {'id': 1, 'name': 'Bundesliga', 'country_name': 'Germany'},
      {'id': 2, 'name': 'Premier League', 'country_name': 'England'},
      {'id': 3, 'name': 'Serie A', 'country_name': 'Italy'},
      {'id': 4, 'name': 'LaLiga', 'country_name': 'Spain'},
    ]);

    expect(
      groups.map((group) => group.country).toList(),
      ['England', 'Italy', 'Spain', 'Germany'],
    );
  });

  test('country aliases are normalized before sorting', () {
    final groups = groupTournamentsByUefaCountryRanking([
      {'id': 1, 'name': 'Süper Lig', 'country_name': 'Turkey'},
      {'id': 2, 'name': 'Czech First League', 'country_name': 'Czech Republic'},
    ]);

    expect(groups.map((group) => group.country).toList(), ['Türkiye', 'Czechia']);
  });

  test('non UEFA countries follow ranked associations alphabetically', () {
    final groups = groupTournamentsByUefaCountryRanking([
      {'id': 1, 'name': 'A-League', 'country_name': 'Australia'},
      {'id': 2, 'name': 'Premier League', 'country_name': 'England'},
      {'id': 3, 'name': 'Brasileirão', 'country_name': 'Brazil'},
    ]);

    expect(
      groups.map((group) => group.country).toList(),
      ['England', 'Australia', 'Brazil'],
    );
  });

  test('leagues inside a country are sorted by name', () {
    final groups = groupTournamentsByUefaCountryRanking([
      {'id': 1, 'name': '3. Liga', 'country_name': 'Germany'},
      {'id': 2, 'name': 'Bundesliga', 'country_name': 'Germany'},
      {'id': 3, 'name': '2. Bundesliga', 'country_name': 'Germany'},
    ]);

    expect(
      groups.single.tournaments.map((tournament) => tournament['name']).toList(),
      ['2. Bundesliga', '3. Liga', 'Bundesliga'],
    );
  });
}
