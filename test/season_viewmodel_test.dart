import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:premier_league/utils/season_order.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';

Map<String, dynamic> season(
  int id,
  String name, {
  bool active = false,
  bool initialized = true,
  bool finished = false,
  bool archived = false,
}) => {
  'id': id,
  'name': name,
  'is_active': active,
  'is_initialized': initialized,
  'finished_at': finished ? '2026-05-31T18:00:00Z' : null,
  'archived_at': archived ? '2026-06-01T08:00:00Z' : null,
};

void main() {
  test('deterministic chronological ordering including short historical labels', () {
    final result = sortedSeasons([
      season(900, 'unknown'),
      season(3, '25/26'),
      season(2, '2026'),
      season(1, '26/27'),
      season(4, '99/00'),
    ]);
    expect(result.map((s) => s['id']), [2, 1, 3, 4, 900]);
    expect(seasonYear({'name': '1999/2000'}), 1999);
    expect(seasonYear({'name': '99/00'}), 1999);
    expect(seasonYear({'name': '26/27'}), 2026);
    expect(
      () => discoveredSeason(17, {'id': null, 'year': '26/27'}),
      throwsFormatException,
    );
  });

  test('manager seasons keep newest plus initialized archive only', () {
    final result = managerSeasons([
      season(103, '26/27', initialized: false),
      season(102, '25/26', initialized: true),
      season(101, '24/25', initialized: false),
      season(100, '23/24', initialized: true),
    ]);

    expect(result.map((s) => s['id']), [103, 102, 100]);
  });

  test(
    'latest default, explicit archive retained, league creation stays latest',
    () async {
      var rows = [
        {
          'id': 17,
          'name': 'League',
          'season': [
            season(101, '25/26', active: true),
            season(102, '26/27', initialized: false),
            season(100, '24/25', initialized: false),
          ],
        },
      ];
      final vm = TournamentViewModel(load: () async => rows, autoLoad: false);
      await vm.fetchTournaments();
      expect(vm.currentSeasonId, 102);
      expect(vm.seasons.map((s) => s['id']), [102, 101]);
      expect(vm.leagueCreationSeasonId, isNull);

      rows = [
        {
          'id': 17,
          'name': 'League',
          'season': [
            season(101, '25/26'),
            season(102, '26/27', active: true),
          ],
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
        {
          'id': 17,
          'name': 'League',
          'season': [season(102, '26/27', active: true, finished: true)],
        },
      ];
      await vm.fetchTournaments();
      expect(vm.isCurrentFinished, true);
      expect(vm.leagueCreationSeasonId, isNull);
      expect(TournamentViewModel.seasonStatus(vm.latestSeason!), contains('beendet'));

      rows = [
        {'id': 17, 'name': 'League', 'season': <Map<String, dynamic>>[]},
      ];
      await vm.fetchTournaments();
      expect(vm.currentSeasonId, isNull);
      expect(vm.leagueCreationSeasonId, isNull);
      vm.dispose();
    },
  );

  test('archived finished season is labelled as archive and finished', () {
    final status = TournamentViewModel.seasonStatus(
      season(101, '25/26', active: false, finished: true, archived: true),
    );
    expect(status, contains('archiviert'));
    expect(status, contains('beendet'));
  });

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
