class UefaCountryGroup {
  final String country;
  final List<Map<String, dynamic>> tournaments;

  const UefaCountryGroup({
    required this.country,
    required this.tournaments,
  });
}

/// UEFA five-year association coefficient order for the 2026/27 season.
///
/// The order was verified on 2026-09-16. Countries outside UEFA are kept
/// after all ranked associations and are then sorted alphabetically.
const List<String> uefaAssociationRanking2026_27 = <String>[
  'England',
  'Italy',
  'Spain',
  'Germany',
  'France',
  'Portugal',
  'Belgium',
  'Netherlands',
  'Türkiye',
  'Poland',
  'Czechia',
  'Greece',
  'Norway',
  'Denmark',
  'Cyprus',
  'Switzerland',
  'Austria',
  'Hungary',
  'Scotland',
  'Sweden',
  'Croatia',
  'Romania',
  'Ukraine',
  'Israel',
  'Azerbaijan',
  'Slovenia',
  'Slovakia',
  'Bulgaria',
  'Serbia',
  'Russia',
  'Iceland',
  'Ireland',
  'Armenia',
  'Kosovo',
  'Bosnia & Herzegovina',
  'Latvia',
  'Finland',
  'Kazakhstan',
  'Liechtenstein',
  'Moldova',
  'Faroe Islands',
  'Albania',
  'North Macedonia',
  'Belarus',
  'Lithuania',
  'Andorra',
  'Malta',
  'Gibraltar',
  'Estonia',
  'Northern Ireland',
  'Georgia',
  'Luxembourg',
  'Montenegro',
  'Wales',
  'San Marino',
];

const Map<String, String> _countryAliases = <String, String>{
  'Turkey': 'Türkiye',
  'Turkiye': 'Türkiye',
  'Czech Republic': 'Czechia',
  'Republic of Ireland': 'Ireland',
  'Bosnia and Herzegovina': 'Bosnia & Herzegovina',
  'Bosnia-Herzegovina': 'Bosnia & Herzegovina',
  'Macedonia': 'North Macedonia',
  'FYR Macedonia': 'North Macedonia',
};

final Map<String, int> _uefaRankByCountry = <String, int>{
  for (var index = 0; index < uefaAssociationRanking2026_27.length; index++)
    uefaAssociationRanking2026_27[index]: index,
};

String normalizeTournamentCountry(String? rawCountry) {
  final trimmed = rawCountry?.trim() ?? '';
  if (trimmed.isEmpty) return 'Sonstige';
  return _countryAliases[trimmed] ?? trimmed;
}

int uefaAssociationRank(String? country) {
  final normalized = normalizeTournamentCountry(country);
  return _uefaRankByCountry[normalized] ?? 10000;
}

List<UefaCountryGroup> groupTournamentsByUefaCountryRanking(
  List<Map<String, dynamic>> tournaments,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};

  for (final tournament in tournaments) {
    final country = normalizeTournamentCountry(
      tournament['country_name']?.toString(),
    );
    grouped.putIfAbsent(country, () => <Map<String, dynamic>>[]).add(tournament);
  }

  final countries = grouped.keys.toList()
    ..sort((a, b) {
      final rankCompare = uefaAssociationRank(a).compareTo(uefaAssociationRank(b));
      if (rankCompare != 0) return rankCompare;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  return countries.map((country) {
    final countryTournaments = grouped[country]!
      ..sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });
    return UefaCountryGroup(
      country: country,
      tournaments: countryTournaments,
    );
  }).toList();
}
