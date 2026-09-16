import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/utils/match_time_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchPreviewTab extends StatefulWidget {
  final Map<String, dynamic> match;

  const MatchPreviewTab({
    super.key,
    required this.match,
  });

  @override
  State<MatchPreviewTab> createState() => _MatchPreviewTabState();
}

class _MatchPreviewTabState extends State<MatchPreviewTab> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _homeForm = const [];
  List<Map<String, dynamic>> _awayForm = const [];
  Map<String, dynamic>? _previousMeeting;

  @override
  void initState() {
    super.initState();
    _loadPreviewData();
  }

  @override
  void didUpdateWidget(covariant MatchPreviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match['id'] != widget.match['id']) {
      _loadPreviewData();
    }
  }

  Future<void> _loadPreviewData() async {
    final seasonId = widget.match['season_id'];
    final homeId = widget.match['heimteam_id'];
    final awayId = widget.match['auswärtsteam_id'];
    final matchDate = widget.match['datum']?.toString();

    if (seasonId == null || homeId == null || awayId == null || matchDate == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Vorschau-Daten sind für dieses Spiel noch nicht vollständig.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _loadRecentMatches(
          seasonId: seasonId as int,
          teamId: homeId as int,
          beforeDate: matchDate,
        ),
        _loadRecentMatches(
          seasonId: seasonId,
          teamId: awayId as int,
          beforeDate: matchDate,
        ),
        _loadPreviousMeetings(
          seasonId: seasonId,
          homeId: homeId,
          awayId: awayId,
          beforeDate: matchDate,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _homeForm = results[0].take(5).toList();
        _awayForm = results[1].take(5).toList();
        _previousMeeting = results[2].isEmpty ? null : results[2].first;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Die zusätzlichen Spielinformationen konnten nicht geladen werden.';
      });
      debugPrint('Fehler beim Laden der Match-Vorschau: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadRecentMatches({
    required int seasonId,
    required int teamId,
    required String beforeDate,
  }) async {
    final rows = await _supabase
        .from('spiel')
        .select(
          'id, datum, heimteam_id, auswärtsteam_id, ergebnis, status, '
          'heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), '
          'auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)',
        )
        .eq('season_id', seasonId)
        .lt('datum', beforeDate)
        .or('heimteam_id.eq.$teamId,auswärtsteam_id.eq.$teamId')
        .order('datum', ascending: false)
        .limit(12);

    return List<Map<String, dynamic>>.from(rows)
        .where((row) => _isFinished(row['status']))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadPreviousMeetings({
    required int seasonId,
    required int homeId,
    required int awayId,
    required String beforeDate,
  }) async {
    final rows = await _supabase
        .from('spiel')
        .select(
          'id, datum, heimteam_id, auswärtsteam_id, ergebnis, status, '
          'heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), '
          'auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)',
        )
        .eq('season_id', seasonId)
        .lt('datum', beforeDate)
        .or(
          'and(heimteam_id.eq.$homeId,auswärtsteam_id.eq.$awayId),'
          'and(heimteam_id.eq.$awayId,auswärtsteam_id.eq.$homeId)',
        )
        .order('datum', ascending: false)
        .limit(8);

    return List<Map<String, dynamic>>.from(rows)
        .where((row) => _isFinished(row['status']))
        .toList();
  }

  bool _isFinished(dynamic value) {
    final status = (value ?? '').toString().toLowerCase();
    return status == 'final' ||
        status == 'beendet' ||
        status == 'finished' ||
        status == 'ended';
  }

  bool _lineupsAvailable() {
    final homeFormation = widget.match['hometeam_formation']?.toString();
    final awayFormation = widget.match['awayteam_formation']?.toString();
    return homeFormation != null &&
        awayFormation != null &&
        homeFormation.isNotEmpty &&
        awayFormation.isNotEmpty &&
        homeFormation != 'N/A' &&
        awayFormation != 'N/A';
  }

  String _matchStatusLabel() {
    final status = (widget.match['status'] ?? '').toString();
    final normalized = status.toLowerCase();
    if (normalized == 'nicht gestartet' || normalized == 'not started') {
      return 'Noch nicht gestartet';
    }
    if (normalized == 'postponed') return 'Verschoben';
    if (_isFinished(status)) return 'Beendet';
    return status.isEmpty ? 'Status unbekannt' : status;
  }

  String _kickoffHint() {
    final kickoff = MatchTimeHelper.parseToLocal(widget.match['datum']);
    if (kickoff == null) return '';

    final difference = kickoff.difference(DateTime.now());
    if (difference.isNegative) return '';

    if (difference.inDays >= 1) {
      final hours = difference.inHours.remainder(24);
      return 'Anstoß in ${difference.inDays} T. ${hours} Std.';
    }
    if (difference.inHours >= 1) {
      final minutes = difference.inMinutes.remainder(60);
      return 'Anstoß in ${difference.inHours} Std. ${minutes} Min.';
    }
    return 'Anstoß in ${difference.inMinutes.clamp(0, 59)} Min.';
  }

  ({int home, int away})? _parseScore(dynamic value) {
    final match = RegExp(r'(\d+)\s*:\s*(\d+)').firstMatch(value?.toString() ?? '');
    if (match == null) return null;
    final home = int.tryParse(match.group(1)!);
    final away = int.tryParse(match.group(2)!);
    if (home == null || away == null) return null;
    return (home: home, away: away);
  }

  String _formResult(Map<String, dynamic> match, int teamId) {
    final score = _parseScore(match['ergebnis']);
    if (score == null) return '?';

    final isHome = match['heimteam_id'] == teamId;
    final goalsFor = isHome ? score.home : score.away;
    final goalsAgainst = isHome ? score.away : score.home;
    if (goalsFor > goalsAgainst) return 'S';
    if (goalsFor < goalsAgainst) return 'N';
    return 'U';
  }

  Color _formColor(BuildContext context, String result) {
    switch (result) {
      case 'S':
        return Colors.green.shade600;
      case 'U':
        return Colors.orange.shade600;
      case 'N':
        return Colors.red.shade600;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  Widget _sectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildMatchInfo(BuildContext context) {
    final kickoff = MatchTimeHelper.parseToLocal(widget.match['datum']);
    final dateText = kickoff == null
        ? 'Termin offen'
        : DateFormat('dd.MM.yyyy • HH:mm').format(kickoff);
    final round = widget.match['round'];
    final kickoffHint = _kickoffHint();

    return _sectionCard(
      context: context,
      title: 'SPIELINFO',
      icon: Icons.event_outlined,
      child: Column(
        children: [
          _InfoRow(icon: Icons.calendar_today_outlined, text: dateText),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.emoji_events_outlined,
            text: round == null ? 'Spieltag offen' : '$round. Spieltag',
          ),
          const SizedBox(height: 10),
          _InfoRow(icon: Icons.schedule_outlined, text: _matchStatusLabel()),
          if (kickoffHint.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                kickoffHint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormRow({
    required BuildContext context,
    required Map<String, dynamic> team,
    required int teamId,
    required List<Map<String, dynamic>> matches,
  }) {
    final results = matches.map((match) => _formResult(match, teamId)).toList();

    return Row(
      children: [
        _TeamBadge(team: team, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            team['name']?.toString() ?? 'Team',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (results.isEmpty)
          Text(
            'Keine Daten',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: results.reversed.map((result) {
              return Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(left: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _formColor(context, result),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  result,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final homeTeam = Map<String, dynamic>.from(widget.match['heimteam'] ?? const {});
    final awayTeam = Map<String, dynamic>.from(widget.match['auswaertsteam'] ?? const {});
    final homeId = widget.match['heimteam_id'] as int?;
    final awayId = widget.match['auswärtsteam_id'] as int?;

    return _sectionCard(
      context: context,
      title: 'FORM',
      icon: Icons.trending_up,
      child: Column(
        children: [
          if (homeId != null)
            _buildFormRow(
              context: context,
              team: homeTeam,
              teamId: homeId,
              matches: _homeForm,
            ),
          const SizedBox(height: 14),
          if (awayId != null)
            _buildFormRow(
              context: context,
              team: awayTeam,
              teamId: awayId,
              matches: _awayForm,
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _LegendDot(color: Colors.green.shade600, text: 'S'),
              const SizedBox(width: 10),
              _LegendDot(color: Colors.orange.shade600, text: 'U'),
              const SizedBox(width: 10),
              _LegendDot(color: Colors.red.shade600, text: 'N'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviousMeeting(BuildContext context) {
    final previous = _previousMeeting;
    if (previous == null) {
      return _sectionCard(
        context: context,
        title: 'LETZTES DIREKTES DUELL',
        icon: Icons.history,
        child: Text(
          'Für diese Saison ist noch kein früheres direktes Duell gespeichert.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    final homeTeam = Map<String, dynamic>.from(previous['heimteam'] ?? const {});
    final awayTeam = Map<String, dynamic>.from(previous['auswaertsteam'] ?? const {});
    final date = MatchTimeHelper.parseToLocal(previous['datum']);

    return _sectionCard(
      context: context,
      title: 'LETZTES DIREKTES DUELL',
      icon: Icons.history,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _PreviousTeam(team: homeTeam)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  previous['ergebnis']?.toString() ?? '- : -',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Expanded(child: _PreviousTeam(team: awayTeam)),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: 10),
            Text(
              DateFormat('dd.MM.yyyy').format(date),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLineupCard(BuildContext context) {
    final available = _lineupsAvailable();
    return _sectionCard(
      context: context,
      title: 'AUFSTELLUNGEN',
      icon: Icons.groups_2_outlined,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: available
                  ? Colors.green.withOpacity(0.12)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              available ? Icons.check_rounded : Icons.schedule_rounded,
              color: available ? Colors.green.shade700 : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available ? 'Aufstellungen verfügbar' : 'Noch nicht veröffentlicht',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  available
                      ? 'Die Formationen und Spieler findest du im Tab „Spielfeld“.'
                      : 'Sobald die Aufstellungen vorliegen, erscheinen sie automatisch im Tab „Spielfeld“.',
                  style: TextStyle(
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadPreviewData,
      child: ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          if (_error != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _buildMatchInfo(context),
          const SizedBox(height: 10),
          _buildFormCard(context),
          const SizedBox(height: 10),
          _buildPreviousMeeting(context),
          const SizedBox(height: 10),
          _buildLineupCard(context),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _TeamBadge extends StatelessWidget {
  final Map<String, dynamic> team;
  final double size;

  const _TeamBadge({required this.team, required this.size});

  @override
  Widget build(BuildContext context) {
    final imageUrl = team['image_url']?.toString() ?? '';
    if (imageUrl.isEmpty) {
      return Icon(Icons.shield_outlined, size: size);
    }
    return Image.network(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.shield_outlined, size: size),
    );
  }
}

class _PreviousTeam extends StatelessWidget {
  final Map<String, dynamic> team;

  const _PreviousTeam({required this.team});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TeamBadge(team: team, size: 42),
        const SizedBox(height: 7),
        Text(
          team['name']?.toString() ?? 'Team',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendDot({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
