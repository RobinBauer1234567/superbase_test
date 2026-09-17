class LeagueCountryGroup {
  final String country;
  final String displayCountry;
  final double coefficient;
  final List<Map<String, dynamic>> tournaments;

  const LeagueCountryGroup({
    required this.country,
    required this.displayCountry,
    required this.coefficient,
    required this.tournaments,
  });
}

/// Five-year UEFA association coefficients plus deliberately simple manual
/// comparison values for non-UEFA associations.
///
/// UEFA values are a 2026/27 snapshot. Non-UEFA values are intentionally
/// marked/maintained as manual values in the database and only provide a
/// pragmatic global ordering until a better cross-confederation source exists.
const Map<String, double> fallbackAssociationCoefficients = <String, double>{
  // UEFA
  'England': 103.352,
  'Italy': 88.303,
  'Spain': 83.243,
  'Germany': 81.545,
  'France': 69.153,
  'Portugal': 65.350,
  'Belgium': 59.050,
  'Netherlands': 52.562,
  'Türkiye': 49.875,
  'Czechia': 45.125,
  'Poland': 45.125,
  'Greece': 44.612,
  'Denmark': 36.181,
  'Norway': 34.212,
  'Cyprus': 33.193,
  'Switzerland': 29.075,
  'Hungary': 26.562,
  'Sweden': 25.625,
  'Austria': 25.250,
  'Scotland': 25.050,
  'Croatia': 24.531,
  'Romania': 24.500,
  'Ukraine': 24.087,
  'Israel': 22.625,
  'Slovenia': 22.468,
  'Azerbaijan': 21.187,
  'Bulgaria': 20.187,
  'Slovakia': 20.125,
  'Serbia': 17.500,
  'Russia': 17.332,
  'Iceland': 16.770,
  'Ireland': 16.093,
  'Armenia': 15.437,
  'Kosovo': 13.531,
  'Bosnia & Herzegovina': 13.468,
  'Latvia': 13.375,
  'Finland': 12.875,
  'Kazakhstan': 12.375,
  'Liechtenstein': 10.500,
  'Moldova': 10.250,
  'Faroe Islands': 9.625,
  'North Macedonia': 8.800,
  'Albania': 8.250,
  'Belarus': 8.208,
  'Lithuania': 7.875,
  'Malta': 7.625,
  'Andorra': 7.165,
  'Estonia': 7.041,
  'Gibraltar': 6.874,
  'Northern Ireland': 6.375,
  'Georgia': 6.250,
  'Luxembourg': 6.250,
  'Montenegro': 5.833,
  'Wales': 4.499,
  'San Marino': 2.998,

  // Manual cross-confederation comparison values.
  'Brazil': 72.0,
  'Argentina': 60.0,
  'Saudi Arabia': 52.0,
  'USA': 48.0,
  'Mexico': 45.0,
  'Japan': 42.0,
  'South Korea': 36.0,
  'Morocco': 34.0,
  'Ecuador': 32.0,
  'Qatar': 30.0,
  'Paraguay': 29.0,
  'Chile': 28.0,
  'Australia': 26.0,
  'United Arab Emirates': 25.0,
  'South Africa': 23.0,
  'Costa Rica': 22.0,
  'Uzbekistan': 20.0,
  'Bolivia': 19.0,
  'India': 17.0,
  'Thailand': 16.0,
  'Vietnam': 14.0,
  'Malaysia': 13.0,
  'Guatemala': 12.0,
  'Singapore': 11.0,
  'Kyrgyzstan': 10.0,
  'Cambodia': 8.0,
  'Asia': 0.0,
};

const Map<String, String> _countryAliases = <String, String>{
  'Turkey': 'Türkiye',
  'Turkiye': 'Türkiye',
  'Czech Republic': 'Czechia',
  'Republic of Ireland': 'Ireland',
  'Bosnia and Herzegovina': 'Bosnia & Herzegovina',
  'Bosnia-Herzegovina': 'Bosnia & Herzegovina',
  'Macedonia': 'North Macedonia',
  'FYR Macedonia': 'North Macedonia',
  'United States': 'USA',
  'United States of America': 'USA',
  'Korea Republic': 'South Korea',
};

const Map<String, String> _germanCountryNames = <String, String>{
  'Albania': 'Albanien',
  'Andorra': 'Andorra',
  'Argentina': 'Argentinien',
  'Armenia': 'Armenien',
  'Asia': 'Asien',
  'Australia': 'Australien',
  'Austria': 'Österreich',
  'Azerbaijan': 'Aserbaidschan',
  'Belarus': 'Belarus',
  'Belgium': 'Belgien',
  'Bolivia': 'Bolivien',
  'Bosnia & Herzegovina': 'Bosnien und Herzegowina',
  'Brazil': 'Brasilien',
  'Bulgaria': 'Bulgarien',
  'Cambodia': 'Kambodscha',
  'Chile': 'Chile',
  'Costa Rica': 'Costa Rica',
  'Croatia': 'Kroatien',
  'Cyprus': 'Zypern',
  'Czechia': 'Tschechien',
  'Denmark': 'Dänemark',
  'Ecuador': 'Ecuador',
  'England': 'England',
  'Estonia': 'Estland',
  'Faroe Islands': 'Färöer',
  'Finland': 'Finnland',
  'France': 'Frankreich',
  'Georgia': 'Georgien',
  'Germany': 'Deutschland',
  'Gibraltar': 'Gibraltar',
  'Greece': 'Griechenland',
  'Guatemala': 'Guatemala',
  'Hungary': 'Ungarn',
  'Iceland': 'Island',
  'India': 'Indien',
  'Ireland': 'Irland',
  'Israel': 'Israel',
  'Italy': 'Italien',
  'Japan': 'Japan',
  'Kazakhstan': 'Kasachstan',
  'Kosovo': 'Kosovo',
  'Kyrgyzstan': 'Kirgisistan',
  'Latvia': 'Lettland',
  'Liechtenstein': 'Liechtenstein',
  'Lithuania': 'Litauen',
  'Luxembourg': 'Luxemburg',
  'Malaysia': 'Malaysia',
  'Malta': 'Malta',
  'Mexico': 'Mexiko',
  'Moldova': 'Moldau',
  'Montenegro': 'Montenegro',
  'Morocco': 'Marokko',
  'Netherlands': 'Niederlande',
  'North Macedonia': 'Nordmazedonien',
  'Northern Ireland': 'Nordirland',
  'Norway': 'Norwegen',
  'Paraguay': 'Paraguay',
  'Poland': 'Polen',
  'Portugal': 'Portugal',
  'Qatar': 'Katar',
  'Romania': 'Rumänien',
  'Russia': 'Russland',
  'San Marino': 'San Marino',
  'Saudi Arabia': 'Saudi-Arabien',
  'Scotland': 'Schottland',
  'Serbia': 'Serbien',
  'Singapore': 'Singapur',
  'Slovakia': 'Slowakei',
  'Slovenia': 'Slowenien',
  'South Africa': 'Südafrika',
  'South Korea': 'Südkorea',
  'Spain': 'Spanien',
  'Sweden': 'Schweden',
  'Switzerland': 'Schweiz',
  'Thailand': 'Thailand',
  'Türkiye': 'Türkei',
  'Ukraine': 'Ukraine',
  'United Arab Emirates': 'Vereinigte Arabische Emirate',
  'USA': 'USA',
  'Uzbekistan': 'Usbekistan',
  'Vietnam': 'Vietnam',
  'Wales': 'Wales',
};

String normalizeTournamentCountry(String? rawCountry) {
  final trimmed = rawCountry?.trim() ?? '';
  if (trimmed.isEmpty) return 'Sonstige';
  return _countryAliases[trimmed] ?? trimmed;
}

String displayTournamentCountry(String? rawCountry) {
  final normalized = normalizeTournamentCountry(rawCountry);
  return _germanCountryNames[normalized] ?? normalized;
}

String tournamentGender(Map<String, dynamic> tournament) {
  final value = (tournament['gender'] ?? 'M').toString().toUpperCase();
  return value == 'F' ? 'F' : 'M';
}

int tournamentTier(Map<String, dynamic> tournament) {
  final raw = tournament['tier'];
  if (raw is num && raw.toInt() > 0) return raw.toInt();
  return 1;
}

double tournamentAssociationCoefficient(Map<String, dynamic> tournament) {
  final raw = tournament['association_coefficient'];
  if (raw is num) return raw.toDouble();
  final country = normalizeTournamentCountry(tournament['country_name']?.toString());
  return fallbackAssociationCoefficients[country] ?? 0.0;
}

bool tournamentMatchesSearch(Map<String, dynamic> tournament, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  final name = (tournament['name'] ?? '').toString().toLowerCase();
  final country = normalizeTournamentCountry(
    tournament['country_name']?.toString(),
  ).toLowerCase();
  final displayCountry = displayTournamentCountry(
    tournament['country_name']?.toString(),
  ).toLowerCase();

  return name.contains(q) || country.contains(q) || displayCountry.contains(q);
}

List<Map<String, dynamic>> filterTournaments({
  required List<Map<String, dynamic>> tournaments,
  String query = '',
  String? gender,
}) {
  final normalizedGender = gender?.toUpperCase();
  return tournaments.where((tournament) {
    if (!tournamentMatchesSearch(tournament, query)) return false;
    if (normalizedGender == 'M' || normalizedGender == 'F') {
      return tournamentGender(tournament) == normalizedGender;
    }
    return true;
  }).toList();
}

List<LeagueCountryGroup> groupTournamentsByAssociationRanking(
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
      final aCoefficient = grouped[a]!
          .map(tournamentAssociationCoefficient)
          .fold<double>(0, (maxValue, value) => value > maxValue ? value : maxValue);
      final bCoefficient = grouped[b]!
          .map(tournamentAssociationCoefficient)
          .fold<double>(0, (maxValue, value) => value > maxValue ? value : maxValue);
      final byCoefficient = bCoefficient.compareTo(aCoefficient);
      if (byCoefficient != 0) return byCoefficient;
      return displayTournamentCountry(a)
          .toLowerCase()
          .compareTo(displayTournamentCountry(b).toLowerCase());
    });

  return countries.map((country) {
    final countryTournaments = grouped[country]!..sort(_compareTournamentsWithinCountry);
    final coefficient = countryTournaments
        .map(tournamentAssociationCoefficient)
        .fold<double>(0, (maxValue, value) => value > maxValue ? value : maxValue);
    return LeagueCountryGroup(
      country: country,
      displayCountry: displayTournamentCountry(country),
      coefficient: coefficient,
      tournaments: countryTournaments,
    );
  }).toList();
}

int _compareTournamentsWithinCountry(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  final aGender = tournamentGender(a) == 'M' ? 0 : 1;
  final bGender = tournamentGender(b) == 'M' ? 0 : 1;
  final byGender = aGender.compareTo(bGender);
  if (byGender != 0) return byGender;

  final byTier = tournamentTier(a).compareTo(tournamentTier(b));
  if (byTier != 0) return byTier;

  final aName = (a['name'] ?? '').toString().toLowerCase();
  final bName = (b['name'] ?? '').toString().toLowerCase();
  return aName.compareTo(bName);
}
