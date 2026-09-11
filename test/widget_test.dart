import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/data_service.dart';
import 'package:premier_league/screens/premier_league/premier_league_screen.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';

void main() {
  final requests = <http.Request>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey: 'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/leagues')) {
          return http.Response('{"season_id":101}',200,request:request,headers:{'content-type':'application/json'});
        }
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(requests.clear);

  test(
    'season check stores SofaScore IDs with conflict-ignore and propagates failure',
    () async {
      await http.runWithClient(
        () => ApiService().checkSeasons(17),
        () => MockClient((request) async {
          expect(request.url.path, '/api/v1/unique-tournament/17/seasons');
          return http.Response(
            jsonEncode({
              'seasons': [
                {'id': 102, 'year': '26/27'},
                {'id': 101, 'year': '25/26'},
              ],
            }),
            200,
          );
        }),
      );
      final insert = requests.single;
      expect(
        insert.headers['prefer'],
        contains('resolution=ignore-duplicates'),
      );
      final rows = jsonDecode(insert.body) as List;
      expect(rows.map((r) => r['id']), [102, 101]);
      expect(
        rows.every((r) => r['tournament_id'] == 17 && r['is_active'] == false),
        true,
      );
      requests.clear();
      await expectLater(
        http.runWithClient(
          () => ApiService().checkSeasons(17),
          () => MockClient((_) async => http.Response('{}', 403)),
        ),
        throwsException,
      );
      expect(requests, isEmpty);
    },
  );

  test('Fantasy league resolves its stored season independently of tournament selection', () async {
    expect(await SupabaseService().fetchLeagueSeasonId(42),101);
    expect(requests.single.url.queryParameters['id'],'eq.42');
  });

  test('Global Scout cannot overwrite an existing active season', () async {
    await SupabaseService().saveDiscoveredLeague(
      17,
      'League',
      null,
      null,
      101,
      '25/26',
    );
    final insert = requests.last;
    expect(insert.url.path, endsWith('/season'));
    expect(insert.headers['prefer'], contains('resolution=ignore-duplicates'));
  });

  testWidgets(
    'active and historical season selection reloads all three views by season_id',
    (tester) async {
      final vm = TournamentViewModel(
        autoLoad: false,
        load:
            () async => [
              {
                'id': 17,
                'name': 'Premier League',
                'season': [
                  {
                    'id': 102,
                    'name': '26/27',
                    'is_active': true,
                    'is_initialized': true,
                  },
                  {
                    'id': 101,
                    'name': '25/26',
                    'is_active': false,
                    'is_initialized': true,
                    'archived_at': '2026-09-11',
                  },
                ],
              },
            ],
      );
      await vm.fetchTournaments();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: const MaterialApp(
            home: PremierLeagueScreen(enableRealtime: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Premier League – Saison 26/27'), findsOneWidget);
      expect(
        requests.any(
          (r) =>
              r.url.path.endsWith('/spiel') &&
              r.url.queryParameters['season_id'] == 'eq.102',
        ),
        true,
      );
      await tester.tap(find.text('Premier League – Saison 26/27'));
      await tester.pumpAndSettle();
      expect(find.text('archiviert · initialisiert'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('season-101')));
      await tester.pumpAndSettle();
      expect(vm.currentSeasonId, 101);
      expect(vm.leagueCreationSeasonId, 102);
      expect(find.text('Premier League – Saison 25/26'), findsOneWidget);
      expect(
        requests.any(
          (r) =>
              r.url.path.endsWith('/spiel') &&
              r.url.queryParameters['season_id'] == 'eq.101',
        ),
        true,
      );
      await tester.tap(find.text('TABELLE'));
      await tester.pumpAndSettle();
      expect(
        requests.any(
          (r) =>
              r.url.path.endsWith('/season_teams') &&
              r.url.queryParameters['season_id'] == 'eq.101',
        ),
        true,
      );
      await tester.tap(find.text('TOP-TEAM'));
      await tester.pumpAndSettle();
      expect(
        requests.any(
          (r) =>
              r.url.path.endsWith('/spieler') &&
              r.url.queryParameters['season_players.season_id'] == 'eq.101',
        ),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
}
