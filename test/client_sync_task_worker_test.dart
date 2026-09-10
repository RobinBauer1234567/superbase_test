import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/services/client_sync_task_worker.dart';
import 'package:premier_league/data_service.dart';

class RecordingImports extends ApiService {
  final calls = <List<int>>[];
  @override
  Future<void> fetchAndStoreSpielerundMatchratings(
    int match,
    int home,
    int away,
    int season,
  ) async {
    calls.add([match, home, away, season]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  for (final scenario in [
    'success',
    'http_error',
    'database_error',
    'cancel',
    'concurrent',
    'refetch',
    'refetch_finished',
    'refetch_wrong_id',
    'refetch_wrong_season',
    'refetch_conflict',
    'refetch_cancelled',
  ]) {
    test('worker $scenario', () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      final writes = <Map<String, dynamic>>[];
      final reimport = scenario.startsWith('refetch');
      final imports = RecordingImports();
      final started = Completer<void>();
      final unblock = Completer<void>();
      final mock = MockClient((request) async {
        final path = request.url.path;
        calls.add(path);
        if (path.endsWith('/token')) {
          final payload = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': '00000000-0000-0000-0000-000000000001',
                    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                  }),
                ),
              )
              .replaceAll('=', '');
          return http.Response(
            jsonEncode({
              'access_token': 'e30.$payload.signature',
              'token_type': 'bearer',
              'refresh_token': 'test',
              'expires_in': 3600,
              'user': {
                'id': '00000000-0000-0000-0000-000000000001',
                'aud': 'authenticated',
                'email': 'test@example.test',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-01-01T00:00:00Z',
              },
            }),
            200,
            request: request,
          );
        }
        if (path.endsWith('/get_next_sync_task')) {
          return http.Response(
            jsonEncode([
              {
                'id': '10000000-0000-0000-0000-000000000001',
                'task_type': reimport ? 'UPDATE_MATCH' : 'FETCH_ROUNDS',
                'tournament_id': 17,
                'season_id': 78229,
                'match_id': 14159939,
                'round_id': 1,
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/event/14159939')) {
          return http.Response(
            jsonEncode({
              'event': {
                'id': scenario == 'refetch_wrong_id' ? 99 : 14159939,
                'tournament': {
                  'uniqueTournament': {'id': 17},
                },
                'season': {
                  'id': scenario == 'refetch_wrong_season' ? 99 : 78229,
                },
                'roundInfo': {'round': 3},
                'homeTeam': {'id': 81},
                'awayTeam': {'id': 124},
                'startTimestamp': 1750000000,
                'status': {
                  'type':
                      scenario == 'refetch_cancelled'
                          ? 'canceled'
                          : scenario == 'refetch_finished'
                          ? 'finished'
                          : 'notstarted',
                },
              },
            }),
            200,
            request: request,
          );
        }
        if (path.endsWith('/spiel')) {
          expect(request.method, isNot('GET'));
          writes.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          if (scenario == 'refetch_conflict') {
            return http.Response(
              jsonEncode({'message': 'duplicate team slot', 'code': '23505'}),
              409,
              request: request,
            );
          }
        }
        if (path.endsWith('/rounds')) {
          started.complete();
          if (scenario == 'cancel' || scenario == 'concurrent') {
            await unblock.future;
          }
          return http.Response(
            jsonEncode({
              'rounds': [
                {'round': 1},
              ],
            }),
            scenario == 'http_error' ? 503 : 200,
            request: request,
          );
        }
        if (path.endsWith('/spieltag') && scenario == 'database_error') {
          return http.Response(
            jsonEncode({'message': 'permission denied', 'code': '42501'}),
            403,
            request: request,
          );
        }
        return http.Response('', 204, request: request);
      });
      final client = SupabaseClient(
        'http://database.test',
        'test-key',
        httpClient: mock,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.signInWithPassword(
        email: 'test@example.test',
        password: 'test',
      );
      final worker = ClientSyncTaskWorker(
        supabase: client,
        apiService: imports,
      );
      final future = http.runWithClient(
        () => worker.processNextTask(),
        () => mock,
      );
      if (scenario == 'cancel' || scenario == 'concurrent') {
        await started.future;
        if (scenario == 'cancel') {
          worker.stop();
        } else {
          expect(await worker.processNextTask(), isFalse);
        }
        unblock.complete();
      }
      final success = await future;
      expect(
        success,
        [
          'success',
          'concurrent',
          'refetch',
          'refetch_finished',
        ].contains(scenario),
      );
      if (reimport && success) {
        expect(writes.first['round'], 3);
        expect(writes.first['heimteam_id'], 81);
        expect(writes.first['auswärtsteam_id'], 124);
        expect(
          imports.calls,
          scenario == 'refetch_finished'
              ? [
                [14159939, 81, 124, 78229],
              ]
              : isEmpty,
        );
      }
      if ([
        'refetch_wrong_id',
        'refetch_wrong_season',
        'refetch_cancelled',
      ].contains(scenario)) {
        expect(writes, isEmpty);
      }
      expect(
        calls.where((p) => p.endsWith('/get_next_sync_task')),
        hasLength(1),
      );
      expect(calls.any((p) => p.endsWith('/complete_sync_task')), success);
      expect(calls.any((p) => p.endsWith('/fail_sync_task')), !success);
      if (scenario == 'cancel') {
        expect(calls.any((p) => p.endsWith('/spieltag')), isFalse);
        expect(calls.where((p) => p.endsWith('/rounds')), hasLength(1));
      }
      await client.dispose();
    });
  }
}
