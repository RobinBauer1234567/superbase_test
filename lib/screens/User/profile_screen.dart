// lib/screens/profile_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/auth_service.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/screenelements/matchday_team_shared.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/leagues/matchday_team_overlay.dart';

class ProfileScreen extends StatefulWidget {
  // NEU: Optionale Parameter, um fremde Profile und eine bestimmte Liga direkt zu öffnen
  final String? userId;
  final int? initialLeagueId;

  const ProfileScreen({super.key, this.userId, this.initialLeagueId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  late TabController _tabController;
  int _previousTabIndex = 1;

  bool _isLoadingProfile = true;
  String _username = '';
  String _email = '';
  String? _avatarUrl;
  Uint8List? _localAvatarBytes;

  List<Map<String, dynamic>> _userLeagues = [];
  int? _selectedLeagueId;

  bool _isLoadingLeagueData = false;
  List<Map<String, dynamic>> _matchdays = [];
  Map<String, dynamic>? _currentMatchdayData;
  int _currentRound = 1;
  List<Map<String, dynamic>> _transfers = [];

  bool _isTeamListView = false;
  Map<String, List<String>> _allFormations = {};
  String _teamFormation = '4-4-2';
  List<PlayerInfo> _teamFieldPlayers = [];
  List<PlayerInfo> _teamSubstitutePlayers = [];
  List<int> _teamFrozenIds = [];

  // NEU: Variablen zur Unterscheidung von "Mein Profil" und "Fremdes Profil"
  late String _effectiveUserId;
  late bool _isCurrentUser;

  @override
  void initState() {
    super.initState();

    // Festlegen, wessen Profil geladen wird
    final currentUser = supabase.auth.currentUser;
    _effectiveUserId = widget.userId ?? currentUser?.id ?? '';
    _isCurrentUser = currentUser != null && _effectiveUserId == currentUser.id;
    _selectedLeagueId = widget.initialLeagueId; // Die übergebene Liga voreinstellen

    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _loadProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  ImageProvider? _getAvatarProvider() {
    if (_localAvatarBytes != null) return MemoryImage(_localAvatarBytes!);
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) return NetworkImage(_avatarUrl!);
    return null;
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoadingProfile = true);

    // E-Mail-Adresse nur beim eigenen Profil anzeigen
    if (_isCurrentUser) {
      final user = supabase.auth.currentUser;
      _email = user?.email ?? 'Keine E-Mail';
    } else {
      _email = '';
    }

    try {
      final dataManagement = context.read<DataManagement>();
      _allFormations = await dataManagement.supabaseService.fetchFormationsFromDb();

      // Profil-Daten für die effektive User-ID holen
      final profileRes = await supabase.from('profiles').select('username, avatar_url').eq('user_id', _effectiveUserId).maybeSingle();

      if (profileRes != null) {
        _username = profileRes['username'] ?? 'Manager';
        _avatarUrl = profileRes['avatar_url'];
      }

      // Ligen für diese User-ID holen
      final leaguesRes = await supabase.from('league_members').select('league_id, leagues(name)').eq('user_id', _effectiveUserId);

      List<Map<String, dynamic>> leaguesWithRanks = [];
      for (var l in leaguesRes) {
        final int leagueId = l['league_id'];
        final String leagueName = l['leagues']['name'];
        final rankingRes = await supabase.rpc('get_ranking_overall', params: {'p_league_id': leagueId});
        final rankingList = List<Map<String, dynamic>>.from(rankingRes);

        int rank = 0;
        int totalPoints = 0;
        for (int i = 0; i < rankingList.length; i++) {
          if (rankingList[i]['user_id'] == _effectiveUserId) {
            rank = i + 1;
            totalPoints = (rankingList[i]['total_points'] as num).toInt();
            break;
          }
        }
        leaguesWithRanks.add({'league_id': leagueId, 'name': leagueName, 'rank': rank, 'points': totalPoints});
      }

      leaguesWithRanks.sort((a, b) => b['points'].compareTo(a['points']));
      _userLeagues = leaguesWithRanks;

      if (_userLeagues.isNotEmpty) {
        // Falls eine `initialLeagueId` übergeben wurde, wird diese vorausgewählt.
        // Ansonsten oder falls die Liga nicht gefunden wird, nehmen wir die erste.
        if (_selectedLeagueId == null || !_userLeagues.any((l) => l['league_id'] == _selectedLeagueId)) {
          _selectedLeagueId = _userLeagues.first['league_id'];
        }
        await _loadLeagueSpecificData();
      }
    } catch (e) {
      print('Fehler beim Laden des Profils: $e');
    }

    if (mounted) setState(() => _isLoadingProfile = false);
  }

  void _parseTeamDataForPitch(Map<String, dynamic> matchdayData) {
    final parsedData = parseMatchdayTeamData(matchdayData, _allFormations);
    _teamFormation = parsedData.formation;
    _teamFieldPlayers = parsedData.fieldPlayers;
    _teamSubstitutePlayers = parsedData.substitutePlayers;
    _teamFrozenIds = parsedData.frozenPlayerIds;
  }

  Future<void> _loadLeagueSpecificData() async {
    if (_selectedLeagueId == null) return;
    setState(() => _isLoadingLeagueData = true);

    try {
      final dataManagement = context.read<DataManagement>();
      final seasonId = dataManagement.seasonId;

      final matchdaysRes = await supabase.from('user_matchday_points').select('round, total_points, is_locked, spieltag(status)').eq('user_id', _effectiveUserId).eq('league_id', _selectedLeagueId!).order('round', ascending: false);

      final rankingFutures = matchdaysRes.map((md) async {
        final rankingRes = await supabase.rpc('get_ranking_matchday', params: {'p_league_id': _selectedLeagueId, 'p_round': md['round']});
        final rankingList = List<Map<String, dynamic>>.from(rankingRes);
        int rank = 0;
        for (int i = 0; i < rankingList.length; i++) {
          if (rankingList[i]['user_id'] == _effectiveUserId) { rank = i + 1; break; }
        }
        return { ...md, 'rank': rank };
      }).toList();

      final resolvedMatchdays = await Future.wait(rankingFutures);
      resolvedMatchdays.sort((a, b) => (b['round'] as int).compareTo(a['round'] as int));

      _currentRound = await dataManagement.supabaseService.getCurrentRound(seasonId);
      final teamData = await dataManagement.supabaseService.fetchMatchdayData(_selectedLeagueId!, seasonId, _currentRound, userId: _effectiveUserId);

      final activitiesRes = await supabase.from('league_activities').select().eq('league_id', _selectedLeagueId!).eq('type', 'TRANSFER').order('created_at', ascending: false);

      final userTransfers = activitiesRes.where((activity) {
        final content = activity['content'] as Map<String, dynamic>? ?? {};
        return content['buyer_name']?.toString() == _username || content['seller_name']?.toString() == _username;
      }).toList();

      if (mounted) {
        setState(() {
          _matchdays = resolvedMatchdays;
          _currentMatchdayData = teamData;
          _parseTeamDataForPitch(teamData);
          _transfers = List<Map<String, dynamic>>.from(userTransfers);
          _isLoadingLeagueData = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Ligadaten: $e');
      if (mounted) setState(() => _isLoadingLeagueData = false);
    }
  }

  Future<void> _pickNewProfileImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() => _localAvatarBytes = bytes);

    try {
      final newUrl = await context.read<AuthService>().updateProfilePicture(bytes);
      if (mounted && newUrl != null) {
        setState(() => _avatarUrl = newUrl);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profilbild erfolgreich aktualisiert!')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _localAvatarBytes = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    final bool showLeagueRow = _tabController.index != 0 && _userLeagues.isNotEmpty;
    final double bottomHeight = showLeagueRow ? 104.0 : 48.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                expandedHeight: 320.0,
                floating: false,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 1,
                iconTheme: const IconThemeData(color: Colors.black87), // Sorgt für den schwarzen Zurück-Pfeil
                actions: [
                  // Logout nur anzeigen, wenn es das eigene Profil ist
                  if (_isCurrentUser)
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.black87),
                      tooltip: 'Abmelden',
                      onPressed: () {
                        context.read<AuthService>().signOut();
                        // Nur navigieren, wenn wir auf dem eigenen Screen sind
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                    )
                ],
                flexibleSpace: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double safeAreaTop = MediaQuery.of(context).padding.top;
                    final double collapsedHeight = kToolbarHeight + bottomHeight + safeAreaTop;
                    final double expandedHeight = 320.0;
                    final double currentHeight = constraints.maxHeight;

                    double fade = 1.0;
                    if (expandedHeight > collapsedHeight) {
                      fade = (currentHeight - collapsedHeight) / (expandedHeight - collapsedHeight);
                      fade = fade.clamp(0.0, 1.0);
                    }

                    return Container(
                      color: Colors.white,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            top: safeAreaTop + 16,
                            left: 0, right: 0,
                            child: IgnorePointer(
                              ignoring: fade < 0.5,
                              child: Opacity(
                                opacity: fade,
                                child: Column(
                                  children: [
                                    Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        CircleAvatar(
                                          radius: 50,
                                          backgroundColor: Colors.grey.shade200,
                                          backgroundImage: _getAvatarProvider(),
                                          child: _getAvatarProvider() == null ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                                        ),
                                        // Kamera-Icon nur bei eigenem Profil
                                        if (_isCurrentUser)
                                          Container(
                                            decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                                            child: IconButton(
                                              icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                                              padding: const EdgeInsets.all(6),
                                              constraints: const BoxConstraints(),
                                              onPressed: _pickNewProfileImage,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(_username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    const SizedBox(height: 4),
                                    // E-Mail Text nur wenn vorhanden und eigenes Profil
                                    if (_email.isNotEmpty)
                                      Text(_email, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: safeAreaTop,
                            left: Navigator.canPop(context) ? 64.0 : 16.0,
                            right: 60,
                            height: kToolbarHeight,
                            child: IgnorePointer(
                              ignoring: fade > 0.5,
                              child: Opacity(
                                opacity: 1.0 - fade,
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.grey.shade200,
                                      backgroundImage: _getAvatarProvider(),
                                      child: _getAvatarProvider() == null ? const Icon(Icons.person, size: 18, color: Colors.grey) : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (_email.isNotEmpty)
                                            Text(_email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(bottomHeight),
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.center,
                          labelColor: primaryColor,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: primaryColor,
                          tabs: const [
                            Tab(text: 'Ligen'),
                            Tab(text: 'Spieltage'),
                            Tab(text: 'Team'),
                            Tab(text: 'Transfers'),
                          ],
                        ),
                        if (showLeagueRow)
                          _buildSelectedLeagueRow(primaryColor),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildLeaguesTab(primaryColor),
              _buildMatchdaysTab(),
              _buildTeamTab(primaryColor),
              _buildTransfersTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedLeagueRow(Color primaryColor) {
    final selectedLeague = _userLeagues.firstWhere(
            (l) => l['league_id'] == _selectedLeagueId,
        orElse: () => _userLeagues.isNotEmpty ? _userLeagues.first : {'name': 'Liga wählen'}
    );

    return InkWell(
      onTap: () {
        _previousTabIndex = _tabController.index;
        _tabController.animateTo(0);
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: primaryColor.withOpacity(0.1),
              child: Icon(Icons.emoji_events, size: 18, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedLeague['name'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.swap_horiz, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaguesTab(Color primaryColor) {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('leaguesTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),

            if (_userLeagues.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text("Dieser Manager ist noch in keiner Liga.")))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final league = _userLeagues[index];
                      final rank = league['rank'] as int;
                      final bool isSelected = league['league_id'] == _selectedLeagueId;
                      Color rankColor = rank == 1 ? Colors.amber : (rank == 2 ? Colors.blueGrey : (rank == 3 ? Colors.brown : Colors.grey));

                      return Card(
                        elevation: isSelected ? 2 : 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: isSelected ? BorderSide(color: primaryColor.withOpacity(0.5), width: 1.5) : BorderSide.none,
                        ),
                        color: Colors.white,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: rankColor.withOpacity(0.1), shape: BoxShape.circle),
                            child: Center(child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: rankColor))),
                          ),
                          title: Text(league['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text("Punkte gesamt: ${league['points']}"),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: primaryColor)
                              : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          onTap: () {
                            setState(() => _selectedLeagueId = league['league_id']);
                            _loadLeagueSpecificData();
                            int targetTab = _previousTabIndex != 0 ? _previousTabIndex : 1;
                            _tabController.animateTo(targetTab);
                          },
                        ),
                      );
                    },
                    childCount: _userLeagues.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMatchdaysTab() {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('matchdaysTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),

            if (_selectedLeagueId == null)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text("Bitte wähle eine Liga.")))
            else if (_isLoadingLeagueData)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_matchdays.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState(Icons.calendar_today, 'Noch keine Spieltage.'))
              else
                SliverPadding(
                  padding: const EdgeInsets.only(top: 12, bottom: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        final matchday = _matchdays[index];
                        final points = matchday['total_points'] ?? 0;
                        final round = matchday['round'];
                        final rank = matchday['rank'] ?? 0;
                        final statusText = matchday['spieltag']?['status'] ?? '';
                        final bool isPlayed = statusText.toString().toLowerCase() != 'nicht gestartet';
                        final ptsColor = isPlayed ? getColorForRating(points, 2500) : Colors.grey;
                        final ptsText = isPlayed ? '$points' : '-';
                        final rankColor = rank == 1 ? Colors.amber : (rank == 2 ? Colors.blueGrey : (rank == 3 ? Colors.brown : Colors.grey));

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Card(
                            elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(color: rankColor.withOpacity(0.1), shape: BoxShape.circle),
                                    child: Center(child: Text(rank > 0 ? '$rank' : '-', style: TextStyle(fontWeight: FontWeight.bold, color: rankColor))),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Spieltag $round", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        if (statusText.isNotEmpty) Text(statusText, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      if (_selectedLeagueId == null) return;
                                      showDialog(
                                        context: context,
                                        builder: (context) => MatchdayTeamOverlay(
                                          leagueId: _selectedLeagueId!,
                                          userId: _effectiveUserId,
                                          userName: _username,
                                          round: round,
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: ptsColor.withOpacity(0.1), border: Border.all(color: ptsColor.withOpacity(0.3)), borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        children: [
                                          Text("PUNKTE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: ptsColor)),
                                          Text(ptsText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ptsColor)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _matchdays.length,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildTeamTab(Color primaryColor) {
    return Builder(
      builder: (BuildContext context) {

        bool hasTeam = _currentMatchdayData != null && _currentMatchdayData!['players'] != null && (_currentMatchdayData!['players'] as List).isNotEmpty;

        // NEU: Punktzahl auslesen
        final int totalPoints = _currentMatchdayData?['points_data']?['total_points'] ?? 0;
        final bool isLocked = _currentMatchdayData?['points_data']?['is_locked'] == true;

        final bool showLeagueRow = _tabController.index != 0 && _userLeagues.isNotEmpty;
        final double bottomHeight = showLeagueRow ? 104.0 : 48.0;
        final double safeAreaTop = MediaQuery.of(context).padding.top;
        final double collapsedAppBarHeight = kToolbarHeight + bottomHeight + safeAreaTop;

        final double screenHeight = MediaQuery.of(context).size.height;
        final double availablePitchHeight = screenHeight - collapsedAppBarHeight - 64.0 - 24.0;
        final pointsColor = isLocked ? getColorForRating(totalPoints, 2500) : Colors.grey;
        final pointsText = isLocked ? '$totalPoints' : '-';

        return CustomScrollView(
          key: const PageStorageKey<String>('teamTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),

            if (_selectedLeagueId == null)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text("Bitte wähle eine Liga.")))
            else if (_isLoadingLeagueData)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (!hasTeam)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState(Icons.sports_soccer, 'Kein Team aufgestellt.'))
              else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text("Spieltag $_currentRound", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),

                          // --- NEU: Punkte-Pille im Ranking-Design ---
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: pointsColor.withOpacity(0.1),
                              border: Border.all(color: pointsColor.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("PUNKTE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: pointsColor)),
                                Text(pointsText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: pointsColor)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          Card(
                            elevation: 2,
                            shadowColor: Colors.black12,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: EdgeInsets.zero,
                            child: IconButton(
                              icon: Icon(_isTeamListView ? Icons.sports_soccer : Icons.list_alt),
                              color: primaryColor,
                              tooltip: _isTeamListView ? "Zur Spielfeldansicht" : "Zur Listenansicht",
                              onPressed: () => setState(() => _isTeamListView = !_isTeamListView),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isTeamListView)
                    SliverPadding(
                      padding: const EdgeInsets.only(bottom: 24),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(_buildTeamPlayerList()),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: SizedBox(
                          height: availablePitchHeight > 300 ? availablePitchHeight : 300,
                          child: MatchFormationDisplay(
                            homeFormation: _teamFormation,
                            homePlayers: _teamFieldPlayers,
                            homeColor: primaryColor,
                            substitutes: _teamSubstitutePlayers,
                            frozenPlayerIds: _teamFrozenIds,
                            requiredPositions: _allFormations[_teamFormation] ?? [],
                            currentRound: _currentRound,
                            displayMode: AvatarDisplayMode.matchday,
                            isReadOnly: true,
                            onPlayerTap: (playerId, radius) {
                              if (playerId > 0) {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId)));
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                ]
          ],
        );
      },
    );
  }

  List<Widget> _buildTeamPlayerList() {
    return buildTeamPlayerListSections(
      context,
      _currentMatchdayData!,
      onPlayerTap: (playerId) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId)));
      },
      startHeaderPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      benchHeaderPadding: const EdgeInsets.only(left: 12, right: 12, top: 16, bottom: 8),
    );
  }

  Widget _buildTransfersTab() {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('transfersTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),

            if (_selectedLeagueId == null)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text("Bitte wähle eine Liga.")))
            else if (_isLoadingLeagueData)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_transfers.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState(Icons.handshake_outlined, 'Noch keine Transfers getätigt.'))
              else
                SliverPadding(
                  padding: const EdgeInsets.only(top: 12, bottom: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
                        final transfer = _transfers[index];
                        final content = transfer['content'] as Map<String, dynamic>;
                        final date = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(transfer['created_at']).toLocal());
                        final isBuyer = content['buyer_name'] == _username;
                        final price = content['price'] ?? 0;
                        final otherParty = isBuyer ? (content['seller_name'] ?? 'System') : (content['buyer_name'] ?? 'System');
                        final iconColor = isBuyer ? Colors.green : Colors.red;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Card(
                            elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
                                    child: Icon(isBuyer ? Icons.arrow_downward : Icons.arrow_upward, color: iconColor),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(content['player_name'] ?? 'Unbekannt', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        const SizedBox(height: 4),
                                        Text(isBuyer ? 'Von: $otherParty' : 'An: $otherParty', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                        const SizedBox(height: 2),
                                        Text(date, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(isBuyer ? 'Zugang' : 'Abgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: iconColor)),
                                      const SizedBox(height: 4),
                                      Text(fmt.format(price), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: iconColor)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _transfers.length,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(message, style: TextStyle(color: Colors.grey.shade500)),
      ],
    );
  }
}
