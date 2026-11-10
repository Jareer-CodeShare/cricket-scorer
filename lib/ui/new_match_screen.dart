import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/setup_controller.dart';
import '../domain/errors.dart';
import 'common.dart';
import 'scoring_screen.dart';
import 'teams_screen.dart';

/// Match set-up: name/venue, date, number of overs, two teams and who bats
/// first. A team that is too small to play blocks the start button.
class NewMatchScreen extends StatefulWidget {
  const NewMatchScreen({super.key});

  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  final _name = TextEditingController();
  final _overs = TextEditingController(text: '5');
  DateTime _date = DateTime.now();
  int? _teamA;
  int? _teamB;
  int? _battingFirst;

  @override
  void dispose() {
    _name.dispose();
    _overs.dispose();
    super.dispose();
  }

  Future<void> _pickTeam({required bool first}) async {
    final setup = context.read<SetupController>();
    final id = await pickOne<int>(
      context,
      title: first ? 'Choose team A' : 'Choose team B',
      options: [
        for (final t in setup.teams)
          (t.id, '${t.name}  (${setup.playerCount(t.id)} players)'),
      ],
    );
    if (id == null) return;
    setState(() {
      if (first) {
        _teamA = id;
      } else {
        _teamB = id;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _start(int battingFirst) async {
    final setup = context.read<SetupController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final match = await setup.startMatch(
        name: _name.text,
        date: _date,
        overs: int.parse(_overs.text.trim()),
        teamAId: _teamA!,
        teamBId: _teamB!,
        battingFirstTeamId: battingFirst,
      );
      // Completes when the scoring screen is closed; refresh the match lists.
      await navigator.pushReplacement(scoringRoute(match.id));
      await setup.load();
    } on SetupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupController>();
    final overs = int.tryParse(_overs.text.trim());
    final problems = setup.matchProblems(
      name: _name.text,
      overs: overs,
      teamAId: _teamA,
      teamBId: _teamB,
    );
    final bothChosen = _teamA != null && _teamB != null && _teamA != _teamB;
    final batting =
        (_battingFirst == _teamA || _battingFirst == _teamB) && _battingFirst != null
            ? _battingFirst
            : _teamA;

    return Scaffold(
      appBar: AppBar(title: const Text('New match')),
      body: setup.teams.length < 2
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        'You need at least two saved teams, each with enough players.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const TeamsScreen()),
                      ),
                      child: const Text('Go to teams and players'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Match name or venue',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: const Text('Date'),
                  subtitle: Text(formatDate(_date)),
                  onTap: _pickDate,
                ),
                TextField(
                  controller: _overs,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Overs per side',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.groups),
                  title: const Text('Team A'),
                  subtitle: Text(_teamA == null
                      ? 'Tap to choose'
                      : setup.teamName(_teamA)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickTeam(first: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Team B'),
                  subtitle: Text(_teamB == null
                      ? 'Tap to choose'
                      : setup.teamName(_teamB)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickTeam(first: false),
                ),
                if (bothChosen) ...[
                  const SizedBox(height: 8),
                  const Text('Batting first'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final id in [_teamA!, _teamB!])
                        ChoiceChip(
                          label: Text(setup.teamName(id)),
                          selected: batting == id,
                          onSelected: (_) =>
                              setState(() => _battingFirst = id),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                for (final p in problems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(p)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: (problems.isEmpty && batting != null)
                      ? () => _start(batting)
                      : null,
                  child: const Text('Start match'),
                ),
              ],
            ),
    );
  }
}
