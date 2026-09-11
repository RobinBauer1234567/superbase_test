import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:premier_league/utils/season_order.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';

Map<String, dynamic> season(
  int id,
  String name, {
  bool active = false,
  bool initialized = true,
}) => {
  'id': id,
  'name': name,
  'is_active': active,
  'is_initialized': initialized,
};
void main() {
  test('deterministic chronological ordering including unknown labels', () {
    final result = sortedSeasons([
      season(900, 'unknown'),
      season(3, '25/26'),
      season(2, '2026'),
      season(1, '26/27'),
    ]);
    expect(result.map((s) => s['id']), [2, 1, 3, 900]);
    expect(seasonYear({'name': '1999/2000'}), 1999);
    expect(
      () => discoveredSeason(17, {'id': null, 'year': '26/27'}),
      throwsFormatException,
    );
  });
  test(
    'active default, explicit history retained, league creation stays active',
    () async {
      var rows = [
        {
          'id': 17,
          'name': 'League',
          'season': [
            season(101, '25/26', active: true),
            season(102, '26/27', initialized: false),
          ],
        },
      ];
      final vm = TournamentViewModel(load: () async => rows, autoLoad: false);
      await vm.fetchTournaments();
      expect(vm.currentSeasonId, 101);
      rows = [
        {
          'id': 17,
          'name': 'League',
          'season': [season(101, '25/26'), season(102, '26/27', active: true)],
        },
      ];
      await vm.fetchTournaments();
      expect(vm.currentSeasonId, 102);
      vm.selectTournament(17, 101);
      await vm.fetchTournaments();
      expect(vm.currentSeasonId, 101);
      expect(vm.leagueCreationSeasonId, 102);
      expect(() => vm.selectTournament(17, 999), throwsArgumentError);
      rows = [
        {'id': 17, 'name': 'League', 'season': <Map<String, dynamic>>[]},
      ];
      await vm.fetchTournaments();
      expect(vm.currentSeasonId, isNull);
      expect(vm.leagueCreationSeasonId, isNull);
      vm.dispose();
    },
  );
  test(
    'late fetch cannot overwrite newer results and empty tournament clears selection',
    () async {
      final first = Completer<List<Map<String, dynamic>>>();
      var calls = 0;
      final vm = TournamentViewModel(
        load:
            () =>
                calls++ == 0
                    ? first.future
                    : Future.value([
                      {
                        'id': 8,
                        'name': 'New',
                        'season': [
                          season(2, '2026', active: true, initialized: false),
                        ],
                      },
                      {
                        'id': 17,
                        'name': 'Empty',
                        'season': <Map<String, dynamic>>[],
                      },
                    ]),
        autoLoad: false,
      );
      final pending = vm.fetchTournaments();
      await vm.fetchTournaments();
      first.complete([
        {'id': 99, 'name': 'Stale', 'season': <Map<String, dynamic>>[]},
      ]);
      await pending;
      expect(vm.currentTournamentId, 8);
      expect(vm.leagueCreationSeasonId, isNull);
      expect(vm.allTournaments.any((t) => t['id'] == 99), false);
      vm.dispose();
    },
  );
}
