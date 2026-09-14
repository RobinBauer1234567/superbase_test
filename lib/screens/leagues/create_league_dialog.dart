import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/utils/league_creation_options.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';

class CreatedLeagueResult {
  final int leagueId;
  final String leagueName;
  final double startingBudget;
  const CreatedLeagueResult(this.leagueId, this.leagueName, this.startingBudget);
}

Future<CreatedLeagueResult?> showCreateLeagueDialog(BuildContext context) async {
  final vm = context.read<TournamentViewModel>();
  final targets = leagueCreationTargets(vm.allTournaments);
  LeagueCreationTarget? target = preferredLeagueCreationTarget(
    targets,
    vm.currentTournamentId,
  );
  if (target == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Keine aktive und initialisierte Saison verfügbar.')),
    );
    return null;
  }

  final formKey = GlobalKey<FormState>();
  String leagueName = '';
  double startingBudget = 50;
  bool isPublic = false;
  bool squadLimitEnabled = false;
  double squadLimit = 15;
  double numPlayers = 11;
  double teamValue = 110;
  bool saving = false;

  return showDialog<CreatedLeagueResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final minValue = numPlayers > 0 ? numPlayers * 5 : 0.0;
        final maxValue = numPlayers > 0 ? numPlayers * 15 : 0.0;
        if (teamValue < minValue) teamValue = minValue;
        if (teamValue > maxValue) teamValue = maxValue;
        if (numPlayers == 0) teamValue = 0;

        Future<void> create() async {
          if (saving || !formKey.currentState!.validate()) return;
          formKey.currentState!.save();
          setState(() => saving = true);
          try {
            final service = dialogContext.read<DataManagement>().supabaseService;
            final budgetEuro = startingBudget * 1000000;
            final id = await service.createLeague(
              name: leagueName,
              startingBudget: budgetEuro,
              seasonId: target!.seasonId,
              isPublic: isPublic,
              squadLimit: squadLimitEnabled ? squadLimit.round() : null,
              numStartingPlayers: numPlayers.round(),
              startingTeamValue: teamValue * 1000000,
            );
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(
                CreatedLeagueResult(id, leagueName, budgetEuro),
              );
            }
          } catch (e) {
            if (!dialogContext.mounted) return;
            setState(() => saving = false);
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
            );
          }
        }

        return AlertDialog(
          title: const Text('Neue Liga gründen'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<LeagueCreationTarget>(
                      value: target,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Liga / Wettbewerb',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.emoji_events_outlined),
                      ),
                      items: targets
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.label, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value != null) setState(() => target = value);
                            },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Nur aktive, initialisierte und noch nicht beendete Saisons. Die aktuell ausgewählte Liga ist vorausgewählt.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Name der Liga',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Bitte Namen eingeben'
                          : null,
                      onSaved: (v) => leagueName = v!.trim(),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Öffentliche Liga'),
                      value: isPublic,
                      onChanged: saving ? null : (v) => setState(() => isPublic = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kaderbegrenzung'),
                      value: squadLimitEnabled,
                      onChanged: saving
                          ? null
                          : (v) => setState(() => squadLimitEnabled = v),
                    ),
                    if (squadLimitEnabled) ...[
                      Text('Max. Spieleranzahl: ${squadLimit.round()}'),
                      Slider(
                        value: squadLimit,
                        min: 11,
                        max: 25,
                        divisions: 14,
                        onChanged: saving
                            ? null
                            : (v) => setState(() => squadLimit = v),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextFormField(
                      enabled: !saving,
                      initialValue: '50',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Startbudget',
                        suffixText: 'Mio. €',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null ||
                              double.tryParse(v.replaceAll(',', '.')) == null
                          ? 'Zahl eingeben'
                          : null,
                      onSaved: (v) => startingBudget =
                          double.parse(v!.replaceAll(',', '.')),
                    ),
                    const SizedBox(height: 16),
                    Text('Zugeloste Spieler: ${numPlayers.round()}'),
                    Slider(
                      value: numPlayers,
                      min: 0,
                      max: 15,
                      divisions: 15,
                      onChanged: saving
                          ? null
                          : (v) => setState(() {
                                numPlayers = v;
                                teamValue = v > 0 ? v * 10 : 0;
                              }),
                    ),
                    Text(
                      'Ziel-Teamwert (Gesamt): ${teamValue.toStringAsFixed(1)} Mio. €',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: teamValue,
                      min: minValue,
                      max: maxValue,
                      divisions: maxValue > minValue
                          ? ((maxValue - minValue) * 2).toInt()
                          : 1,
                      label: '${teamValue.toStringAsFixed(1)} Mio. €',
                      onChanged: saving || numPlayers == 0
                          ? null
                          : (v) => setState(() => teamValue = v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${minValue.round()} Mio', style: const TextStyle(fontSize: 11)),
                        Text('${maxValue.round()} Mio', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Die Zulosung wird auf diesen Gesamtwert optimiert und darf höchstens 1 Mio. € davon abweichen.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: saving ? null : create,
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('LIGA GRÜNDEN'),
            ),
          ],
        );
      },
    ),
  );
}
