from pathlib import Path


def replace(path, old, new, count=1):
    p = Path(path)
    text = p.read_text()
    found = text.count(old)
    if found != count:
        raise SystemExit(f'{path}: expected {count} matches, found {found}')
    p.write_text(text.replace(old, new, count))


# League team: the season-total header pill should use exactly the same
# normalized player aggregate color as the Top-Team formation.
replace(
    'lib/screens/leagues/league_team_screen.dart',
    """  int _getStartingElevenAveragePoints() {
    int sum = 0;
    for (var p in _fieldPlayers) {
      if (p.id > 0 && p.matchCount > 0) {
        sum += (p.totalSeasonPoints / p.matchCount).round();
      }
    }
    return sum;
  }

  int _getStartingElevenMarketValue() {
""",
    """  int _getStartingElevenAveragePoints() {
    int sum = 0;
    for (var p in _fieldPlayers) {
      if (p.id > 0 && p.matchCount > 0) {
        sum += (p.totalSeasonPoints / p.matchCount).round();
      }
    }
    return sum;
  }

  double _getStartingElevenEquivalentRating() {
    final players = _fieldPlayers.where((p) => p.id > 0).toList();
    if (players.isEmpty) return 0;

    final equivalentTotal = players.fold<double>(0, (sum, player) {
      return sum +
          getAggregateEquivalentRating(
            player.totalSeasonPoints,
            _ratedRoundCount,
            _ratingColorDecayBase,
          );
    });
    return equivalentTotal / players.length;
  }

  int _getStartingElevenMarketValue() {
""",
)
replace(
    'lib/screens/leagues/league_team_screen.dart',
    """    final Color pointsColor =
        showOverallPoints
            ? Theme.of(context).primaryColor
            : getColorForRating(displayedPoints, 2500);
""",
    """    final Color pointsColor;
    if (!showOverallPoints) {
      pointsColor = getColorForRating(displayedPoints, 2500);
    } else if (_selectedDisplayMode == AvatarDisplayMode.seasonTotal) {
      pointsColor = getColorForRating(
        _getStartingElevenEquivalentRating(),
        singleMatchRatingMax,
      );
    } else {
      pointsColor = Theme.of(context).primaryColor;
    }
""",
)

# Club/team collapsed header: score is the sum of all displayed players, so its
# comparison maximum must be the same sum-scale instead of a single-player max.
replace(
    'lib/screens/team_screen.dart',
    """  Widget _buildCollapsedTeamBar() {
    final maxTotalScore = getAggregateRatingMaxValue(_ratedRoundCount, _ratingColorDecayBase);
    final teamScore = _totalSquadRating;
""",
    """  Widget _buildCollapsedTeamBar() {
    final playerAggregateMax = getAggregateRatingMaxValue(
      _ratedRoundCount,
      _ratingColorDecayBase,
    );
    final squadPlayerCount = _topPlayers.isEmpty ? 1 : _topPlayers.length;
    final maxTotalScore = playerAggregateMax * squadPlayerCount;
    final teamScore = _totalSquadRating;
""",
)
