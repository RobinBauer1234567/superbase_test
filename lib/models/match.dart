import 'package:supabase_flutter/supabase_flutter.dart';


enum SpielStatus {
  notPlayed,
  live,
  provisional,
  finalStatus,
}


extension SpielStatusExtension on SpielStatus {
  String get description {
    switch (this) {
      case SpielStatus.notPlayed:
        return "Noch nicht gespielt";
      case SpielStatus.live:
        return "Spielt gerade";
      case SpielStatus.provisional:
        return "Beendet, aber nicht final";
      case SpielStatus.finalStatus:
        return "Final";
    }
  }
}

class Spiel {
  final int matchId;
  final String homeTeam;
  final String awayTeam;
  final int homeScore;
  final int awayScore;
  final DateTime startTime;
  SpielStatus _status; // Status ist nicht final, da er änderbar sein soll.

  // Optional: Ein Callback, das aufgerufen wird, wenn sich der Status ändert.
  void Function()? onStatusChanged;

  Spiel({
    required this.matchId,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeScore,
    required this.awayScore,
    required this.startTime,
    required SpielStatus status,
    this.onStatusChanged,
  }) : _status = status;

  SpielStatus get status => _status;

  // Methode zum Ändern des Status.
  void setStatus(SpielStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      // Rufe das Callback auf, z. B. um den übergeordneten Spieltag zu aktualisieren.
      if (onStatusChanged != null) {
        onStatusChanged!();
      }
    }
  }

  /// **Spiel in Supabase speichern**
  Future<void> saveToSupabase() async {
    final supabase = Supabase.instance.client;
    await supabase.from('spiele').upsert(toJson());
  }

  /// **Spiele aus Supabase abrufen**
  static Future<List<Spiel>> fetchFromSupabase() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.from('spiele').select();

    return response.map((json) => Spiel.fromJson(json)).toList();
  }

  // Factory-Methode zum Erzeugen eines Spiel-Objekts aus JSON-Daten.
  factory Spiel.fromJson(Map<String, dynamic> json, {void Function()? onStatusChanged}) {
    SpielStatus parsedStatus = SpielStatus.notPlayed;

    if (json['status'] is int) {
      parsedStatus = SpielStatus.values[json['status']]; // Direkt über Index aus Enum holen
    } else if (json['status'] is String) {
      parsedStatus = SpielStatus.values.firstWhere(
            (e) => e.toString().split('.').last.toLowerCase() == json['status'].toLowerCase(),
        orElse: () => SpielStatus.notPlayed, // Fallback
      );
    }

    return Spiel(
      matchId: json['id'] ?? 0,
      homeTeam: json['homeTeam'] is Map<String, dynamic> ? json['homeTeam']['name'] ?? 'Unbekannt' : json['homeTeam']?.toString() ?? 'Unbekannt',
      awayTeam: json['awayTeam'] is Map<String, dynamic> ? json['awayTeam']['name'] ?? 'Unbekannt' : json['awayTeam']?.toString() ?? 'Unbekannt',
      homeScore: json['homeScore'] is int ? json['homeScore'] : int.tryParse(json['homeScore'].toString()) ?? 0,
      awayScore: json['awayScore'] is int ? json['awayScore'] : int.tryParse(json['awayScore'].toString()) ?? 0,
      startTime: DateTime.fromMillisecondsSinceEpoch(
          (json['startTimestamp'] is int ? json['startTimestamp'] : int.tryParse(json['startTimestamp'].toString()) ?? 0) * 1000
      ),
      status: parsedStatus,
      onStatusChanged: onStatusChanged,
    );
  }
  void listenForSpielUpdates() {
    final supabase = Supabase.instance.client;
    supabase
        .from('spiele')
        .stream(primaryKey: ['id'])
        .listen((data) {
      print("Neue Spieldaten empfangen: $data");
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'id': matchId,
      'homeTeam': homeTeam,
      'awayTeam': awayTeam,
      'homeScore': homeScore,
      'awayScore': awayScore,
      'startTimestamp': startTime.millisecondsSinceEpoch ~/ 1000,
      'status': status.index, // Speichern als int
    };
  }

}

class Spieltag {
  final int roundNumber;
  SpielStatus status;
  List<Spiel> spiele = [];
  void Function()? onStatusChanged;

  Spieltag({
    required this.roundNumber,
    required this.status,
    this.onStatusChanged,
  }) {
    status = SpielStatus.notPlayed;
    updateStatus(); // Initialer Status
  }

  /// Aktualisiert den Status des Spieltages basierend auf den enthaltenen Spielen.
  void updateStatus() {
    final oldStatus = status;
    if (spiele.isEmpty) {
      status = SpielStatus.notPlayed;
    } else if (spiele.every((spiel) => spiel.status == SpielStatus.finalStatus)) {
      status = SpielStatus.finalStatus;
    } else if (spiele.any((spiel) => spiel.status == SpielStatus.live)) {
      status = SpielStatus.live;
    } else if (spiele.any((spiel) => spiel.status == SpielStatus.provisional)) {
      status = SpielStatus.provisional;
    } else {
      status = SpielStatus.notPlayed;
    }

    // Callback ausführen, wenn sich der Status ändert.
    if (oldStatus != status) {
      onStatusChanged?.call();
    }
  }

  void addSpiel(Spiel spiel) {
    spiel.onStatusChanged = () {
      updateStatus();
    };
    spiele.add(spiel);
    updateStatus();
  }

  factory Spieltag.fromJson(Map<String, dynamic> json, {void Function()? onStatusChanged}) {
    int roundNumber = json['round'] ?? 0;
    if (json.containsKey('roundNumber')) {
      if (json['roundNumber'] is int) {
        roundNumber = json['roundNumber'];
      } else if (json['roundNumber'] is String) {
        roundNumber = int.tryParse(json['roundNumber']) ?? 0;
      }
    }

    SpielStatus parsedStatus = SpielStatus.notPlayed;
    if (json['status'] is int) {
      parsedStatus = SpielStatus.values[json['status']]; // Enum aus Index holen
    }

    return Spieltag(roundNumber: roundNumber,status: parsedStatus, onStatusChanged: onStatusChanged)..status = parsedStatus;
  }


  Map<String, dynamic> toJson() {
    return {
      'roundNumber': roundNumber,
      'spiele': spiele.map((spiel) => spiel.toJson()).toList(),
      'status': status.index, // Speichern als int
    };
  }

  /// **Spieltag in Supabase speichern**
  Future<void> saveToSupabase() async {
    final supabase = Supabase.instance.client;
    await supabase.from('spieltage').upsert(toJson());
  }

  /// **Spieltage aus Supabase abrufen**
  static Future<List<Spieltag>> fetchFromSupabase() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.from('spieltage').select();

    return response.map((json) => Spieltag.fromJson(json)).toList();
  }

}
