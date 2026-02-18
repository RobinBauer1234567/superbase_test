class LeagueActivity {
  final int id;
  final int leagueId;
  final String type; // 'JOIN', 'LEAVE', 'LISTING', 'TRANSFER'
  final Map<String, dynamic> content;
  final DateTime createdAt;

  LeagueActivity({
    required this.id,
    required this.leagueId,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  factory LeagueActivity.fromJson(Map<String, dynamic> json) {
    return LeagueActivity(
      id: json['id'],
      leagueId: json['league_id'],
      type: json['type'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']).toLocal(),
    );
  }
}