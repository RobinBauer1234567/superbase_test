import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/match_details_screen.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/team_screen.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:premier_league/utils/match_time_helper.dart';
import 'package:premier_league/services/app_data_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class MatchesScreen extends StatefulWidget {
  final bool enableRealtime;
  const MatchesScreen({super.key, this.enableRealtime = true});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final AppDataRepository _repository = AppDataRepository.instance;

  bool _isLoading = true;
  Map<int, List<dynamic>> _spieleProSpieltag = {};
  RealtimeChannel? _spieleChannel;

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  int? _aktuellerSpieltag;
  int? _loadedSeasonId;
  bool _hasInitialAutoScroll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final seasonId = context.read<TournamentViewModel>().currentSeasonId;
    if (seasonId == null || seasonId == _loadedSeasonId) return;

    _loadedSeasonId = seasonId;
    _hasInitialAutoScroll = false;
    _initialize(seasonId);
  }

  Future<void> _initialize(int seasonId) async {
    await _fetchSpiele(seasonId: seasonId);
    if (!mounted || _loadedSeasonId != seasonId) return;
    if (widget.enableRealtime) _subscribeToChanges(seasonId);
  }

  Future<void> _fetchSpiele({
    int? seasonId,
    bool forceRefresh = false,
  }) async {
    if (!mounted) return;
    final targetSeasonId =
        seasonId ?? context.read<TournamentViewModel>().currentSeasonId;
    if (targetSeasonId == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (_spieleProSpieltag.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final data = await _repository.getMatches(
        targetSeasonId,
        forceRefresh: forceRefresh,
      );
      if (!mounted || _loadedSeasonId != targetSeasonId) return;

      _updateStateWithData(data);

      if (!_hasInitialAutoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _loadedSeasonId == targetSeasonId) {
            _scrollToAktuellenSpieltag();
          }
        });
        _hasInitialAutoScroll = true;
      }
    } catch (e) {
      debugPrint('Fehler beim Laden der Spiele: $e');
    } finally {
      if (mounted && _loadedSeasonId == targetSeasonId) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updateStateWithData(List<Map<String, dynamic>> data) {
    final Map<int, List<dynamic>> groupedSpiele = {};
    final now = DateTime.now().toUtc();
    int? currentRound;

    for (final spiel in data) {
      final round = spiel['round'];
      if (round is! int) continue;
      groupedSpiele.putIfAbsent(round, () => []).add(spiel);

      final matchDate = MatchTimeHelper.parseToUtc(spiel['datum']);
      if (matchDate != null && matchDate.isAfter(now) && currentRound == null) {
        currentRound = round;
      }
    }

    final sortedRounds = groupedSpiele.keys.toList()..sort();
    _aktuellerSpieltag =
        currentRound ?? (sortedRounds.isNotEmpty ? sortedRounds.last : null);

    if (mounted) {
      setState(() => _spieleProSpieltag = groupedSpiele);
    }
  }

  Future<void> _scrollToAktuellenSpieltag() async {
    if (_aktuellerSpieltag == null || _spieleProSpieltag.isEmpty) return;

    final spieltage = _spieleProSpieltag.keys.toList()..sort();
    final index = spieltage.indexOf(_aktuellerSpieltag!);
    if (index == -1) return;

    try {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } catch (e) {
      debugPrint('Fehler beim scrollTo: $e');
    }
  }

  void _subscribeToChanges(int seasonId) {
    if (_spieleChannel != null) {
      Supabase.instance.client.removeChannel(_spieleChannel!);
    }

    _spieleChannel = Supabase.instance.client
        .channel('public:spiel:$seasonId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'spiel',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'season_id',
            value: seasonId,
          ),
          callback: (payload) {
            if (!mounted || _loadedSeasonId != seasonId) return;

            if (payload.eventType == PostgresChangeEvent.delete) {
              _fetchSpiele(seasonId: seasonId, forceRefresh: true);
              return;
            }

            final record = Map<String, dynamic>.from(payload.newRecord);
            final updated = _repository.applyMatchChange(seasonId, record);
            if (updated != null) {
              _updateStateWithData(updated);
            } else {
              _fetchSpiele(seasonId: seasonId, forceRefresh: true);
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_spieleChannel != null) {
      Supabase.instance.client.removeChannel(_spieleChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _spieleProSpieltag.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final spieltage = _spieleProSpieltag.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () => _fetchSpiele(forceRefresh: true),
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        itemCount: spieltage.length,
        itemBuilder: (context, index) {
          final spieltagNummer = spieltage[index];
          final spieleDesSpieltags = _spieleProSpieltag[spieltagNummer]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Text(
                  'SPIELTAG $spieltagNummer',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
              ...spieleDesSpieltags.map(
                (spiel) => MatchCard(
                  spiel: spiel,
                  onRefresh: () => _fetchSpiele(forceRefresh: true),
                ),
              ),
              const Divider(height: 20, thickness: 1),
            ],
          );
        },
      ),
    );
  }
}

class MatchCard extends StatelessWidget {
  final dynamic spiel;
  final Future<void> Function() onRefresh;
  const MatchCard({super.key, required this.spiel, required this.onRefresh});

  Widget _buildTeamColumn(BuildContext context, dynamic teamData) {
    if (teamData == null || teamData['id'] == null) {
      return const Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield, color: Colors.grey, size: 40),
            SizedBox(height: 6),
            Text('...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    return Expanded(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TeamScreen(teamId: teamData['id']),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              teamData['image_url'] ?? '',
              width: 40,
              height: 40,
              errorBuilder: (c, e, s) =>
                  const Icon(Icons.shield, size: 40),
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 6),
            Text(
              teamData['name'] ?? 'Unbekannt',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heimTeam = spiel['heimteam'];
    final auswaertsTeam = spiel['auswaertsteam'];
    final ergebnis = spiel['ergebnis'] ?? '- : -';
    final status = (spiel['status'] ?? 'unbekannt') as String;

    final normalizedStatus = status.toLowerCase();
    final isFinished = normalizedStatus == 'finished' ||
        normalizedStatus == 'beendet' ||
        normalizedStatus == 'final';
    final isNotStarted = normalizedStatus == 'not started' ||
        normalizedStatus == 'nicht gestartet' ||
        normalizedStatus == 'postponed';

    final datum = MatchTimeHelper.parseToLocal(spiel['datum']) ?? DateTime.now();
    final uhrzeit = DateFormat('HH:mm').format(datum);
    final datumsString = DateFormat('dd.MM.yyyy').format(datum);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Text(
                  datumsString,
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildTeamColumn(context, heimTeam),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GameScreen(spiel: spiel),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isNotStarted ? '- : -' : ergebnis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isFinished
                              ? 'Endstand'
                              : (isNotStarted ? uhrzeit : status),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildTeamColumn(context, auswaertsTeam),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
