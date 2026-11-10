import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/setup_controller.dart';
import '../domain/models.dart';
import 'common.dart';
import 'navigation.dart';

/// Saved matches, newest first. A finished match reopens as a scorecard; an
/// unfinished one resumes scoring.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Match history')),
      body: setup.matches.isEmpty
          ? const Center(child: Text('No matches yet.'))
          : ListView(
              children: [
                for (final m in setup.matches)
                  ListTile(
                    leading: Icon(m.status == MatchStatus.completed
                        ? Icons.emoji_events_outlined
                        : Icons.play_circle_outline),
                    title: Text(m.name),
                    subtitle: Text(
                      '${formatDate(m.date)} · '
                      '${setup.teamName(m.teamAId)} vs ${setup.teamName(m.teamBId)}\n'
                      '${m.status == MatchStatus.completed ? '${m.summaryText ?? ''}\n${m.resultText ?? ''}' : 'In progress: tap to continue scoring'}',
                    ),
                    isThreeLine: true,
                    onTap: () => openMatch(context, m),
                  ),
              ],
            ),
    );
  }
}
