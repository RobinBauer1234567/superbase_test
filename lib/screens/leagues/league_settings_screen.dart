// lib/screens/leagues/league_settings_screen.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class LeagueSettingsScreen extends StatefulWidget {
  final int leagueId;

  const LeagueSettingsScreen({super.key, required this.leagueId});

  @override
  State<LeagueSettingsScreen> createState() => _LeagueSettingsScreenState();
}

class _LeagueSettingsScreenState extends State<LeagueSettingsScreen> with SingleTickerProviderStateMixin {
  static const double _headerImageRadius = 50;
  static const double _collapsedImageRadius = 18;
  static const double _imageEditButtonSize = 28;

  final supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  late TabController _tabController;

  bool _isLoading = true;
  bool _isAdmin = false;

  // Liga-Daten
  Map<String, dynamic> _leagueData = {};
  String _adminUsername = 'Unbekannt';

  // Bild-Variablen
  Uint8List? _localImageBytes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadLeagueData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  ImageProvider? _getLeagueImageProvider() {
    if (_localImageBytes != null) return MemoryImage(_localImageBytes!);
    final url = _leagueData['image_url'] as String?;
    if (url != null && url.isNotEmpty) return NetworkImage(url);
    return null;
  }

  Future<void> _loadLeagueData() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final response = await supabase
          .from('leagues')
          .select('*, admin:profiles!leagues_admin_id_fkey(username)')
          .eq('id', widget.leagueId)
          .single();

      _leagueData = response;
      _isAdmin = _leagueData['admin_id'] == currentUser.id;

      if (_leagueData['admin'] != null) {
        _adminUsername = _leagueData['admin']['username'] ?? 'Unbekannt';
      }

    } catch (e) {
      print('Fehler beim Laden der Liga-Daten: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // --- BILD UPLOAD (Nur für Admin) ---
  Future<void> _pickNewLeagueImage() async {
    if (!_isAdmin) return;

    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() => _localImageBytes = bytes);

    try {
      // Dateiname ist einfach die Liga-ID. Wird überschrieben, wenn schon vorhanden (upsert).
      final path = '${widget.leagueId}.jpg';

      await supabase.storage.from('league_images').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final newUrl = supabase.storage.from('league_images').getPublicUrl(path);

      await supabase.from('leagues').update({'image_url': newUrl}).eq('id', widget.leagueId);

      if (mounted) {
        setState(() => _leagueData['image_url'] = newUrl);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ligabild erfolgreich aktualisiert!')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _localImageBytes = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Hochladen: $e')));
    }
  }

  // --- UPDATE FUNKTIONEN (Nur für Admin) ---
  Future<void> _updateLeagueName(String newName) async {
    if (!_isAdmin || newName.trim().isEmpty) return;
    try {
      await supabase.from('leagues').update({'name': newName.trim()}).eq('id', widget.leagueId);
      setState(() => _leagueData['name'] = newName.trim());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Liganame aktualisiert!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _updateVisibility(bool isPublic) async {
    if (!_isAdmin) return;
    try {
      await supabase.from('leagues').update({'is_public': isPublic}).eq('id', widget.leagueId);
      setState(() => _leagueData['is_public'] = isPublic);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _updateSquadLimit(int limit) async {
    if (!_isAdmin) return;
    try {
      await supabase.from('leagues').update({'squad_limit': limit}).eq('id', widget.leagueId);
      setState(() => _leagueData['squad_limit'] = limit);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kadergröße aktualisiert!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  // --- DIALOGE FÜR EINGABEN ---
  void _showEditNameDialog() {
    final TextEditingController controller = TextEditingController(text: _leagueData['name']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liganame ändern'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Neuer Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateLeagueName(controller.text);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  void _showEditSquadLimitDialog() {
    final currentLimit = _leagueData['squad_limit']?.toString() ?? '15';
    final TextEditingController controller = TextEditingController(text: currentLimit);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maximale Kadergröße'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Anzahl Spieler'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final newLimit = int.tryParse(controller.text);
              if (newLimit != null && newLimit > 0) {
                Navigator.pop(context);
                _updateSquadLimit(newLimit);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    const double bottomHeight = 48.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                expandedHeight: 280.0,
                floating: false,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 1,
                iconTheme: const IconThemeData(color: Colors.black87),
                flexibleSpace: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double safeAreaTop = MediaQuery.of(context).padding.top;
                    final double screenWidth = MediaQuery.of(context).size.width;
                    final double collapsedHeight = kToolbarHeight + bottomHeight + safeAreaTop;
                    final double expandedHeight = 280.0;
                    final double currentHeight = constraints.maxHeight;
                    final double leagueImageRadius = (screenWidth * 0.14).clamp(40.0, _headerImageRadius);
                    final double cameraButtonSize = (leagueImageRadius * 0.56).clamp(22.0, _imageEditButtonSize);
                    final double cameraIconSize = (cameraButtonSize * 0.58).clamp(14.0, 18.0);
                    final double cameraCenterOffset = leagueImageRadius + (leagueImageRadius / math.sqrt2) - (cameraButtonSize / 2);

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
                          // --- GROSSE ANSICHT ---
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
                                          radius: leagueImageRadius,
                                          backgroundColor: primaryColor.withOpacity(0.1),
                                          backgroundImage: _getLeagueImageProvider(),
                                          child: _getLeagueImageProvider() == null
                                              ? Icon(Icons.emoji_events, size: leagueImageRadius, color: primaryColor)
                                              : null,
                                        ),
                                        if (_isAdmin)
                                          Positioned(
                                            left: cameraCenterOffset,
                                            top: cameraCenterOffset,
                                            child: _buildEditImageButton(
                                              primaryColor: primaryColor,
                                              buttonSize: cameraButtonSize,
                                              iconSize: cameraIconSize,
                                              onPressed: _pickNewLeagueImage,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _leagueData['name'] ?? 'Liga',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Gemanagt von $_adminUsername',
                                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600)
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // --- KLEINE EINGEKLAPPTE ANSICHT ---
                          Positioned(
                            top: safeAreaTop,
                            left: Navigator.canPop(context) ? 64.0 : 16.0,
                            right: 16,
                            height: kToolbarHeight,
                            child: IgnorePointer(
                              ignoring: fade > 0.5,
                              child: Opacity(
                                opacity: 1.0 - fade,
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: _collapsedImageRadius,
                                      backgroundColor: primaryColor.withOpacity(0.1),
                                      backgroundImage: _getLeagueImageProvider(),
                                      child: _getLeagueImageProvider() == null
                                          ? Icon(Icons.emoji_events, size: _collapsedImageRadius, color: primaryColor)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              _leagueData['name'] ?? 'Liga',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                              maxLines: 1, overflow: TextOverflow.ellipsis
                                          ),
                                          Text(
                                              'Gemanagt von $_adminUsername',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                              maxLines: 1, overflow: TextOverflow.ellipsis
                                          ),
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
                  preferredSize: const Size.fromHeight(bottomHeight),
                  child: Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: primaryColor,
                      tabs: const [
                        Tab(text: 'Einstellungen'),
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
              _buildSettingsTab(primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditImageButton({
    required Color primaryColor,
    required double buttonSize,
    required double iconSize,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        color: primaryColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: IconButton(
        icon: Icon(Icons.camera_alt, color: Colors.white, size: iconSize),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }

  // --- DER EINSTELLUNGS-TAB ---
  Widget _buildSettingsTab(Color primaryColor) {
    final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('settingsTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('ALLGEMEIN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit),
                          title: const Text('Name der Liga'),
                          subtitle: Text(_leagueData['name'] ?? ''),
                          trailing: _isAdmin ? const Icon(Icons.chevron_right) : null,
                          onTap: _isAdmin ? _showEditNameDialog : null,
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.public),
                          title: const Text('Öffentliche Liga'),
                          subtitle: const Text('Jeder kann der Liga beitreten'),
                          value: _leagueData['is_public'] ?? false,
                          activeColor: primaryColor,
                          onChanged: _isAdmin ? (val) => _updateVisibility(val) : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('REGELN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.groups),
                      title: const Text('Max. Kadergröße'),
                      subtitle: Text('${_leagueData['squad_limit'] ?? 'Kein Limit'} Spieler'),
                      trailing: _isAdmin ? const Icon(Icons.chevron_right) : null,
                      onTap: _isAdmin ? _showEditSquadLimitDialog : null,
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('STARTBEDINGUNGEN (Fix)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.account_balance_wallet),
                          title: const Text('Startbudget'),
                          trailing: Text(
                            fmt.format(_leagueData['starting_budget'] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.person_add),
                          title: const Text('Zugeloste Spieler'),
                          trailing: Text(
                            '${_leagueData['num_starting_players'] ?? 0}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.trending_up),
                          title: const Text('Wert der zugelosten Spieler'),
                          trailing: Text(
                            fmt.format(_leagueData['starting_team_value'] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}
