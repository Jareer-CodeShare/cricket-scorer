/// Full scorecard of a match: for each innings the team total, wickets, overs,
/// batter statistics, bowler statistics and extras. Used for live matches and
/// to reopen saved matches from the history list.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/scoring_controller.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../domain/scorecard_text.dart';
import 'common.dart';

Route<void> scorecardRoute(int matchId) {
  return MaterialPageRoute<void>(
    builder: (context) => ChangeNotifierProvider<ScoringController>(
      create: (ctx) => ScoringController(
        ctx.read<MatchRepository>(),
        ctx.read<TeamRepository>(),
        ctx.read<PlayerRepository>(),
      )..load(matchId),
      child: const ScorecardScreen(),
    ),
  );
}

class ScorecardScreen extends StatelessWidget {
  const ScorecardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final match = c.match;
    return Scaffold(
      appBar: AppBar(title: Text(match?.name ?? 'Scorecard')),
      body: (match == null || c.loading)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _MatchHeader(c: c, match: match),
                for (final v in c.innings) _InningsSection(c: c, view: v),
              ],
            ),
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.c, required this.match});

  final ScoringController c;
  final MatchInfo match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.teamName(match.teamAId)} vs ${c.teamName(match.teamBId)}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('${formatDate(match.date)} · ${match.overs} overs a side'),
            const SizedBox(height: 8),
            Text(
              match.status == MatchStatus.completed
                  ? (match.resultText ?? 'Match complete')
                  : 'Match in progress',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _InningsSection extends StatelessWidget {
  const _InningsSection({required this.c, required this.view});

  final ScoringController c;
  final InningsView view;

  Widget _row(
    BuildContext context, {
    required Widget first,
    required List<String> cells,
    bool header = false,
  }) {
    final style = header
        ? Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(fontWeight: FontWeight.bold)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          for (final cell in cells)
            SizedBox(
              width: 44,
              child: Text(cell, textAlign: TextAlign.right, style: style),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = view.state;
    final teamName = c.teamName(view.info.battingTeamId);
    final didNotBat = view.config.battingIds
        .where((id) => !s.batters.containsKey(id))
        .map(c.playerName)
        .toList();

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${view.info.number == 1 ? '1st' : '2nd'} innings · $teamName',
              style: theme.textTheme.titleMedium,
            ),
            Text(
              '${s.runs}/${s.wickets}  (${s.oversText} ov)',
              style: theme.textTheme.headlineSmall,
            ),
            if (s.target != null) Text('Target ${s.target}'),
            const Divider(),
            _row(
              context,
              first: const Text('Batter',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              cells: const ['R', 'B', '4s', '6s', 'SR'],
              header: true,
            ),
            for (final b in s.batters.values)
              _row(
                context,
                first: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.playerName(b.playerId),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(dismissalText(b, c.playerName),
                        style: theme.textTheme.bodySmall),
                    Text('1s ${b.ones} · 2s ${b.twos} · 3s ${b.threes}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                cells: [
                  '${b.runs}',
                  '${b.balls}',
                  '${b.fours}',
                  '${b.sixes}',
                  formatStrikeRate(b.strikeRate),
                ],
              ),
            if (didNotBat.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Did not bat: ${didNotBat.join(', ')}',
                    style: theme.textTheme.bodySmall),
              ),
            const Divider(),
            Text(
              'Extras: ${s.extrasTotal} '
              '(wd ${s.wides}, nb ${s.noBalls}, b ${s.byes}, lb ${s.legByes})',
            ),
            Text(
              'Total: ${s.runs}/${s.wickets} in ${s.oversText} overs',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _row(
              context,
              first: const Text('Bowler',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              cells: const ['O', 'R', 'W', 'Econ'],
              header: true,
            ),
            for (final bw in s.bowlers.values)
              _row(
                context,
                first: Text(c.playerName(bw.playerId),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                cells: [
                  bw.oversText,
                  '${bw.runsConceded}',
                  '${bw.wickets}',
                  formatRate(bw.economy),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
