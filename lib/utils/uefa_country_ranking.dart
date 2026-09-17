enum LeagueGenderFilter { all, men, women }

class UefaCountryGroup {
  final String country;
  final double coefficient;
  final List<Map<String, dynamic>> tournaments;

  const UefaCountryGroup({
    required this.country,
    required this.coefficient,
    required this.tournaments,
  });
}

/// UEFA five-year association coefficients used as the European baseline.
///
/// Top values were refreshed from the SofaScore UEFA ranking on 2026-09-17.
/// Lower associations keep the same five-year scale and can be refreshed later
/// without changing the UI/sorting model.
const Map<String, double> uefaAssociationCoefficients2026_27 = <String, double>{
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
  'Israel': 22.625,
  'Ukraine': 22.587,
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
  'Georgia': 6.000,
  'Luxembourg': 5.800,
  'Montenegro': 5.600,
  'Wales': 5.400,
  'San Marino': 1.500,
};

/// Temporary manual comparison values for associations outside UEFA.
///
/// They intentionally share the UEFA coefficient scale so all countries can
/// be sorted together. These are product heuristics, not official rankings.
const Map<String, double> manualNonUefaCountryCoefficients = <String, double>{
  'Brazil': 61.000,
  'Argentina': 54.000,
  'Saudi Arabia': 49.000,
  'USA': 46.000,
  'Mexico': 45.000,
  'Japan': 42.000,
  'South Korea': 36.000,
  'Morocco': 34.000,
  'Qatar': 32.000,
  'United Arab Emirates': 31.000,
  'Australia': 30.000,
  'Ecuador': 29.000,
  'Paraguay': 28.000,
  'Chile': 27.000,
  'South Africa': 25.000,
  'Costa Rica': 24.000,
  'Uzbekistan': 22.000,
  'India': 21.000,
  'Bolivia': 20.000,
  'Thailand': 19.000,
  'Vietnam': 18.000,
  'Malaysia': 17.000,
  'Guatemala': 16.000,
  'Singapore': 12.000,
  'Cambodia': 12.000,
  'Kyrgyzstan': 11.000,
  'Asia': 10.000,
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
};

const Map<String, List<String>> _countrySearchAliases = <String, List<String>>{
  'Germany': ['deutschland'],
  'Italy': ['italien'],
  'Spain': ['spanien'],
  'France': ['frankreich'],
  'Belgium': ['belgien'],
  'Netherlands': ['niederlande', 'holland'],
  'Türkiye': ['tuerkei', 'turkei'],
  'Czechia': ['tschechien'],
  'Greece': ['griechenland'],
  'Denmark': ['daenemark', 'danemark'],
  'Norway': ['norwegen'],
  'Switzerland': ['schweiz'],
  'Austria': ['oesterreich', 'osterreich'],
  'Hungary': ['ungarn'],
  'Scotland': ['schottland'],
  'Sweden': ['schweden'],
  'Croatia': ['kroatien'],
  'Romania': ['rumaenien', 'rumanien'],
  'Ireland': ['irland'],
  'Bosnia & Herzegovina': ['bosnien', 'bosnien und herzegowina'],
  'Northern Ireland': ['nordirland'],
  'Wales': ['wales'],
  'Brazil': ['brasilien'],
  'Argentina': ['argentinien'],
  'Saudi Arabia': ['saudi arabien', 'saudi-arabien'],
  'USA': ['vereinigte staaten', 'usa', 'united states'],
  'Mexico': ['mexiko'],
  'Japan': ['japan'],
  'South Korea': ['suedkorea', 'sudkorea'],
  'Morocco': ['marokko'],
  'United Arab Emirates': ['vereinigte arabische emirate', 'vae'],
  'Australia': ['australien'],
  'South Africa': ['suedafrika', 'sudafrika'],
  'India': ['indien'],
};

String _foldSearchText(String value) => value
    .toLowerCase()
    .trim()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll('é', 'e')
    .replaceAll('è', 'e')
    .replaceAll('á', 'a')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

String normalizeTournamentCountry(String? rawCountry) {
  final trimmed = rawCountry?.trim() ?? '';
  if (trimmed.isEmpty) return 'Sonstige';
  return _countryAliases[trimmed] ?? trimmed;
}

double countryCoefficient(String? country, {num? storedCoefficient}) {
  if (storedCoefficient != null) return storedCoefficient.toDouble();
  final normalized = normalizeTournamentCountry(country);
  return uefaAssociationCoefficients2026_27[normalized] ??
      manualNonUefaCountryCoefficients[normalized] ??
      5.0;
}

String tournamentGender(Map<String, dynamic> tournament) {
  final stored = tournament['gender']?.toString().trim().toUpperCase();
  if (stored == 'F' || stored == 'W') return 'F';
  if (stored == 'M') return 'M';

  final name = _foldSearchText((tournament['name'] ?? '').toString());
  const femaleMarkers = <String>[
    'women',
    'women\'s',
    'feminino',
    'feminina',
    'feminine',
    'frauen',
    'liga f',
    'nwsl',
    'we-league',
  ];
  return femaleMarkers.any(name.contains) ? 'F' : 'M';
}

int tournamentTier(Map<String, dynamic> tournament) {
  final stored = tournament['tier'];
  if (stored is num && stored.toInt() > 0) return stored.toInt();

  final name = _foldSearchText((tournament['name'] ?? '').toString());
  if (name.contains('league two') || name.contains('3. liga') || name.contains('j3 league') || name.contains('k3 league')) {
    return 3;
  }
  if (name.contains('championship') ||
      name.contains('2. bundesliga') ||
      name.contains('serie b') ||
      name.contains('laliga 2') ||
      name.contains('liga portugal 2') ||
      name.contains('j2 league') ||
      name.contains('1.lig') ||
      name.contains('1. liga')) {
    return 2;
  }
  return 1;
}

bool tournamentMatchesGender(
  Map<String, dynamic> tournament,
  LeagueGenderFilter filter,
) {
  switch (filter) {
    case LeagueGenderFilter.all:
      return true;
    case LeagueGenderFilter.men:
      return tournamentGender(tournament) == 'M';
    case LeagueGenderFilter.women:
      return tournamentGender(tournament) == 'F';
  }
}

bool tournamentMatchesSearch(
  Map<String, dynamic> tournament,
  String rawQuery,
) {
  final query = _foldSearchText(rawQuery);
  if (query.isEmpty) return true;

  final name = _foldSearchText((tournament['name'] ?? '').toString());
  final country = normalizeTournamentCountry(
    tournament['country_name']?.toString(),
  );
  final countryFolded = _foldSearchText(country);
  final aliases = _countrySearchAliases[country] ?? const <String>[];

  return name.contains(query) ||
      countryFolded.contains(query) ||
      aliases.map(_foldSearchText).any((alias) => alias.contains(query));
}

int _compareTournaments(Map<String, dynamic> a, Map<String, dynamic> b) {
  final genderCompare = tournamentGender(a).compareTo(tournamentGender(b));
  if (genderCompare != 0) return genderCompare; // M before F alphabetically? Fix below.

  final aGender = tournamentGender(a) == 'M' ? 0 : 1;
  final bGender = tournamentGender(b) == 'M' ? 0 : 1;
  if (aGender != bGender) return aGender.compareTo(bGender);

  final tierCompare = tournamentTier(a).compareTo(tournamentTier(b));
  if (tierCompare != 0) return tierCompare;

  final aName = (a['name'] ?? '').toString().toLowerCase();
  final bName = (b['name'] ?? '').toString().toLowerCase();
  return aName.compareTo(bName);
}

List<UefaCountryGroup> groupTournamentsByCountryCoefficient(
  List<Map<String, dynamic>> tournaments, {
  String searchQuery = '',
  LeagueGenderFilter genderFilter = LeagueGenderFilter.all,
}) {
  final grouped = <String, List<Map<String, dynamic>>>{};

  for (final tournament in tournaments) {
    if (!tournamentMatchesGender(tournament, genderFilter) ||
        !tournamentMatchesSearch(tournament, searchQuery)) {
      continue;
    }
    final country = normalizeTournamentCountry(
      tournament['country_name']?.toString(),
    );
    grouped.putIfAbsent(country, () => <Map<String, dynamic>>[]).add(tournament);
  }

  final countries = grouped.keys.toList()
    ..sort((a, b) {
      final aStored = grouped[a]!.first['country_coefficient'];
      final bStored = grouped[b]!.first['country_coefficient'];
      final coefficientCompare = countryCoefficient(
        b,
        storedCoefficient: bStored is num ? bStored : null,
      ).compareTo(
        countryCoefficient(
          a,
          storedCoefficient: aStored is num ? aStored : null,
        ),
      );
      if (coefficientCompare != 0) return coefficientCompare;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  return countries.map((country) {
    final countryTournaments = grouped[country]!..sort(_compareTournaments);
    final stored = countryTournaments.first['country_coefficient'];
    return UefaCountryGroup(
      country: country,
      coefficient: countryCoefficient(
        country,
        storedCoefficient: stored is num ? stored : null,
      ),
      tournaments: countryTournaments,
    );
  }).toList();
}

/// Compatibility helpers for code/tests introduced with the previous UEFA-only
/// implementation. New code should use [groupTournamentsByCountryCoefficient].
final List<String> uefaAssociationRanking2026_27 =
    uefaAssociationCoefficients2026_27.keys.toList()
      ..sort((a, b) => uefaAssociationCoefficients2026_27[b]!
          .compareTo(uefaAssociationCoefficients2026_27[a]!));

int uefaAssociationRank(String? country) {
  final normalized = normalizeTournamentCountry(country);
  final index = uefaAssociationRanking2026_27.indexOf(normalized);
  return index < 0 ? 10000 : index;
}

List<UefaCountryGroup> groupTournamentsByUefaCountryRanking(
  List<Map<String, dynamic>> tournaments,
) =>
    groupTournamentsByCountryCoefficient(tournaments);
