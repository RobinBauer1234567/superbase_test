import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/utils/season_order.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';

class SeasonPicker extends StatelessWidget {
  const SeasonPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TournamentViewModel>();
    return TextButton.icon(
      icon: const Icon(Icons.calendar_month),
      label: Text(
        vm.currentSeasonLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed:
          () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder:
                (sheetContext) => SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(sheetContext).height * .75,
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Turnier und Saison auswählen'),
                          subtitle: const Text(
                            'Historische Saisons sind zur Ansicht verfügbar.',
                          ),
                          trailing: IconButton(
                            tooltip: 'Aktualisieren',
                            icon: const Icon(Icons.refresh),
                            onPressed: vm.fetchTournaments,
                          ),
                        ),
                        Expanded(
                          child: Consumer<TournamentViewModel>(
                            builder: (context, model, _) {
                              if (model.isLoading)
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              if (model.error != null)
                                return Center(child: Text(model.error!));
                              return ListView(
                                children: [
                                  for (final tournament in model.allTournaments)
                                    ExpansionTile(
                                      key: ValueKey(
                                        'tournament-${tournament['id']}',
                                      ),
                                      initiallyExpanded:
                                          tournament['id'] ==
                                          model.currentTournamentId,
                                      title: Text(tournament['name']),
                                      children: [
                                        for (final season in sortedSeasons(
                                          tournament['season'],
                                        ))
                                          ListTile(
                                            key: ValueKey(
                                              'season-${season['id']}',
                                            ),
                                            title: Text(
                                              'Saison ${season['name']}',
                                            ),
                                            subtitle: Text(
                                              TournamentViewModel.seasonStatus(
                                                season,
                                              ),
                                            ),
                                            selected:
                                                season['id'] ==
                                                model.currentSeasonId,
                                            trailing:
                                                season['id'] ==
                                                        model.currentSeasonId
                                                    ? const Icon(Icons.check)
                                                    : null,
                                            onTap: () {
                                              model.selectTournament(
                                                tournament['id'],
                                                season['id'],
                                              );
                                              Navigator.pop(sheetContext);
                                            },
                                          ),
                                        if (sortedSeasons(
                                          tournament['season'],
                                        ).isEmpty)
                                          const ListTile(
                                            title: Text(
                                              'Noch keine Saison entdeckt',
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }
}
