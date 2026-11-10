import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/setup_controller.dart';
import '../domain/models.dart';
import 'common.dart';
import 'history_screen.dart';
import 'navigation.dart';
import 'new_match_screen.dart';
import 'teams_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupController>();
    final unfinished =
        setup.matches.where((m) => m.status == MatchStatus.inProgress).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Cricket Scorer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (unfinished.isNotEmpty) ...[
            Text('Resume a match',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final m in unfinished)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(m.name),
                  subtitle: Text(
                      '${setup.teamName(m.teamAId)} vs ${setup.teamName(m.teamBId)} · ${formatDate(m.date)}'),
                  onTap: () => openMatch(context, m),
                ),
              ),
            const SizedBox(height: 16),
          ],
          _MenuTile(
            icon: Icons.sports_cricket,
            title: 'New match',
            subtitle: 'Pick two saved teams and start scoring',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NewMatchScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.groups,
            title: 'Teams and players',
            subtitle: '${setup.teams.length} saved teams',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TeamsScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.history,
            title: 'Match history',
            subtitle: '${setup.matches.length} saved matches',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: onTap,
      ),
    );
  }
}
