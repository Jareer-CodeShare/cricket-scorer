import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/setup_controller.dart';
import '../domain/errors.dart';
import '../domain/rules.dart';
import 'common.dart';

/// Saved teams. Teams and their players are stored locally for later reuse.
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  Future<void> _newTeam(BuildContext context) async {
    final setup = context.read<SetupController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await askText(context,
        title: 'New team', label: 'Team name', confirm: 'Create');
    if (name == null) return;
    try {
      final team = await setup.createTeam(name);
      await navigator.push(MaterialPageRoute<void>(
        builder: (_) => TeamDetailScreen(teamId: team.id),
      ));
    } on SetupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Teams and players')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newTeam(context),
        icon: const Icon(Icons.add),
        label: const Text('New team'),
      ),
      body: setup.teams.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'No teams yet. Create two teams and add players to them, then start a match.'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final t in setup.teams)
                  ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(t.name),
                    subtitle: Text(setup.teamProblem(t.id) == null
                        ? '${setup.playerCount(t.id)} players'
                        : '${setup.playerCount(t.id)} players · not ready (needs $minPlayersPerTeam)'),
                    trailing: setup.teamProblem(t.id) == null
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.warning_amber_outlined),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TeamDetailScreen(teamId: t.id),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final int teamId;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final setup = context.read<SetupController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setup.addPlayer(widget.teamId, _name.text);
      _name.clear();
    } on SetupException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupController>();
    final players = setup.playersOf(widget.teamId);
    final problem = setup.teamProblem(widget.teamId);
    return Scaffold(
      appBar: AppBar(title: Text(setup.teamName(widget.teamId))),
      body: Column(
        children: [
          if (problem != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text('This team $problem, so it cannot start a match yet.'),
            ),
          Expanded(
            child: players.isEmpty
                ? const Center(child: Text('No players yet. Add some below.'))
                : ListView(
                    children: [
                      for (final p in players)
                        ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(p.name),
                          trailing: IconButton(
                            tooltip: 'Remove ${p.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await setup.removePlayer(p);
                              } on SetupException catch (e) {
                                messenger.showSnackBar(
                                    SnackBar(content: Text(e.message)));
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Player name',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _add, child: const Text('Add')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
