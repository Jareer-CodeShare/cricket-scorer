/// The live scoring screen. The scorer only says what happened on each ball;
/// every rule (legal balls, strike change, over end, wickets, innings end) is
/// applied by the rules engine through ScoringController.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/scoring_controller.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'common.dart';
import 'scorecard_screen.dart';

Route<void> scoringRoute(int matchId) {
  return MaterialPageRoute<void>(
    builder: (context) => ChangeNotifierProvider<ScoringController>(
      create: (ctx) => ScoringController(
        ctx.read<MatchRepository>(),
        ctx.read<TeamRepository>(),
        ctx.read<PlayerRepository>(),
      )..load(matchId),
      child: const ScoringScreen(),
    ),
  );
}

class ScoringScreen extends StatelessWidget {
  const ScoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final match = c.match;
    return Scaffold(
      appBar: AppBar(
        title: Text(match?.name ?? 'Match'),
        actions: [
          IconButton(
            tooltip: 'Scorecard',
            icon: const Icon(Icons.format_list_numbered),
            onPressed: match == null
                ? null
                : () => Navigator.of(context).push(scorecardRoute(match.id)),
          ),
        ],
      ),
      body: (c.state == null)
          ? const Center(child: CircularProgressIndicator())
          : _Body(c: c),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.c});

  final ScoringController c;

  @override
  Widget build(BuildContext context) {
    final s = c.state!;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ScoreHeader(c: c),
        const SizedBox(height: 8),
        _CreaseCard(c: c),
        const SizedBox(height: 8),
        _ThisOver(c: c),
        const SizedBox(height: 8),
        if (c.matchOver)
          _MatchOverCard(c: c)
        else if (c.canStartSecondInnings)
          _InningsBreakCard(c: c)
        else ...[
          if (c.needsSelection) _SelectionCard(c: c),
          if (c.readyToScore) _ScoringPad(c: c),
        ],
        if (s.deliveries.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _undo(context, c),
              icon: const Icon(Icons.undo),
              label: const Text('Undo last ball'),
            ),
          ),
      ],
    );
  }
}

Future<void> _undo(BuildContext context, ScoringController c) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await c.undo();
  if (message != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// ---- score header ---------------------------------------------------------

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.c});

  final ScoringController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = c.current!;
    final s = v.state;
    final rates = StringBuffer();
    if (s.runRate != null) {
      rates.write('Run rate ${s.runRate!.toStringAsFixed(2)}');
    }
    if (s.requiredRate != null && !s.isComplete) {
      rates.write(' · Required ${s.requiredRate!.toStringAsFixed(2)}');
    }
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${v.info.number == 1 ? '1st' : '2nd'} innings · '
              '${c.teamName(v.info.battingTeamId)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.runs}/${s.wickets}',
                    style: theme.textTheme.displaySmall),
                const SizedBox(width: 12),
                Text('(${s.oversText} / ${s.config.maxOvers} ov)',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            if (s.target != null)
              Text('Target ${s.target}', style: theme.textTheme.titleMedium),
            if (c.statusLine.isNotEmpty) Text(c.statusLine),
            if (rates.isNotEmpty) Text(rates.toString()),
          ],
        ),
      ),
    );
  }
}

// ---- batters and bowler at the crease -----------------------------------------

class _CreaseCard extends StatelessWidget {
  const _CreaseCard({required this.c});

  final ScoringController c;

  String _batter(int? id, {required bool onStrike}) {
    if (id == null) return 'not chosen';
    final b = c.state!.batters[id];
    final star = onStrike ? ' *' : '';
    return '${c.playerName(id)}$star   ${b?.runs ?? 0} (${b?.balls ?? 0})';
  }

  @override
  Widget build(BuildContext context) {
    final bowler = c.bowlerId;
    final spell = bowler == null ? null : c.state!.bowlers[bowler];
    final bowlerText = bowler == null
        ? 'not chosen'
        : '${c.playerName(bowler)}   '
            '${spell?.oversText ?? '0.0'}-${spell?.runsConceded ?? 0}-${spell?.wickets ?? 0}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.sports_cricket, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_batter(c.strikerId, onStrike: true),
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 26),
              Expanded(child: Text(_batter(c.nonStrikerId, onStrike: false))),
            ]),
            const Divider(),
            Row(children: [
              const Icon(Icons.sports_baseball, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(bowlerText)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ThisOver extends StatelessWidget {
  const _ThisOver({required this.c});

  final ScoringController c;

  @override
  Widget build(BuildContext context) {
    final balls = c.state!.thisOver;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('This over:'),
        if (balls.isEmpty) const Text('-'),
        for (final d in balls) Chip(label: Text(d.label)),
      ],
    );
  }
}

// ---- choosing players -------------------------------------------------------------

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({required this.c});

  final ScoringController c;

  Future<void> _chooseBatter(BuildContext context,
      {required bool forStriker}) async {
    final ids = c.batterCandidates(forStriker: forStriker);
    final id = await pickOne<int>(
      context,
      title: forStriker ? 'Choose the striker' : 'Choose the non-striker',
      options: [for (final i in ids) (i, c.playerName(i))],
    );
    if (id == null) return;
    if (forStriker) {
      c.pickStriker(id);
    } else {
      c.pickNonStriker(id);
    }
  }

  Future<void> _chooseBowler(BuildContext context) async {
    final id = await pickOne<int>(
      context,
      title: 'Choose the bowler',
      options: [for (final i in c.bowlerCandidates()) (i, c.playerName(i))],
    );
    if (id != null) c.pickBowler(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = c.state!;
    final String title;
    if (s.needsOpeners) {
      title = 'Start of innings: choose the openers and the first bowler';
    } else if (s.needsNewBatter && s.needsNewBowler) {
      title = 'Wicket and end of over: choose the next batter and bowler';
    } else if (s.needsNewBatter) {
      title = 'Wicket! Choose the next batter';
    } else {
      title = 'End of over: choose the next bowler';
    }

    String name(int? id) => id == null ? 'Tap to choose' : c.playerName(id);

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (s.striker == null)
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Striker'),
                subtitle: Text(name(c.strikerId)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseBatter(context, forStriker: true),
              ),
            if (s.nonStriker == null)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Non-striker'),
                subtitle: Text(name(c.nonStrikerId)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseBatter(context, forStriker: false),
              ),
            if (s.bowler == null)
              ListTile(
                leading: const Icon(Icons.sports_baseball),
                title: const Text('Bowler'),
                subtitle: Text(name(c.bowlerId)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseBowler(context),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- innings break and match over ---------------------------------------------------

class _InningsBreakCard extends StatelessWidget {
  const _InningsBreakCard({required this.c});

  final ScoringController c;

  @override
  Widget build(BuildContext context) {
    final first = c.innings.first;
    final s = first.state;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Innings complete',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${c.teamName(first.info.battingTeamId)} '
                '${s.runs}/${s.wickets} in ${s.oversText} overs'),
            Text('${c.teamName(first.info.bowlingTeamId)} need ${s.runs + 1} '
                'to win.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final message = await c.startSecondInnings();
                if (message != null) {
                  messenger.showSnackBar(SnackBar(content: Text(message)));
                }
              },
              child: const Text('Start second innings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchOverCard extends StatelessWidget {
  const _MatchOverCard({required this.c});

  final ScoringController c;

  @override
  Widget build(BuildContext context) {
    final match = c.match!;
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Match complete',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(match.resultText ?? '',
                style: Theme.of(context).textTheme.headlineSmall),
            if (match.summaryText != null) Text(match.summaryText!),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).push(scorecardRoute(match.id)),
                child: const Text('Full scorecard'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ---- the scoring pad ------------------------------------------------------------------

Future<void> _record(
  BuildContext context,
  ScoringController c, {
  int bat = 0,
  ExtraType extra = ExtraType.none,
  int extraRuns = 0,
  WicketType? wicket,
  int? dismissedId,
  int? fielderId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await c.recordBall(
    runsOffBat: bat,
    extra: extra,
    extraRuns: extraRuns,
    wicket: wicket,
    dismissedId: dismissedId,
    fielderId: fielderId,
  );
  if (message != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ScoringPad extends StatelessWidget {
  const _ScoringPad({required this.c});

  final ScoringController c;

  Future<void> _extra(BuildContext context, ExtraType type) async {
    final (String title, List<int> options) = switch (type) {
      ExtraType.wide => (
          'Wide: runs run besides the 1 penalty run',
          const [0, 1, 2, 3, 4]
        ),
      ExtraType.noBall => (
          'No-ball: runs off the bat besides the 1 penalty run',
          const [0, 1, 2, 3, 4, 6]
        ),
      ExtraType.bye => ('Byes: how many runs?', const [1, 2, 3, 4]),
      ExtraType.legBye => ('Leg-byes: how many runs?', const [1, 2, 3, 4]),
      ExtraType.none => ('Runs', const [0, 1, 2, 3, 4, 6]),
    };
    final runs = await pickOne<int>(
      context,
      title: title,
      options: [for (final r in options) (r, '$r')],
    );
    if (runs == null || !context.mounted) return;
    if (type == ExtraType.noBall) {
      await _record(context, c, extra: type, bat: runs);
    } else {
      await _record(context, c, extra: type, extraRuns: runs);
    }
  }

  Future<void> _wicket(BuildContext context) async {
    final choice = await showDialog<_WicketChoice>(
      context: context,
      builder: (_) => _WicketDialog(c: c),
    );
    if (choice == null || !context.mounted) return;
    final batRuns =
        choice.extra == ExtraType.none || choice.extra == ExtraType.noBall;
    await _record(
      context,
      c,
      bat: batRuns ? choice.runs : 0,
      extra: choice.extra,
      extraRuns: batRuns ? 0 : choice.runs,
      wicket: choice.type,
      dismissedId: choice.type == WicketType.runOut ? choice.outId : null,
      fielderId: choice.fielderId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Runs off the bat',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in const [0, 1, 2, 3, 4, 6])
                  SizedBox(
                    width: 72,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => _record(context, c, bat: r),
                      child: Text('$r', style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Extras', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in const [
                  ExtraType.wide,
                  ExtraType.noBall,
                  ExtraType.bye,
                  ExtraType.legBye,
                ])
                  OutlinedButton(
                    onPressed: () => _extra(context, type),
                    child: Text(type.label),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _wicket(context),
              icon: const Icon(Icons.sports_cricket),
              label: const Text('Wicket'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- wicket dialog ------------------------------------------------------------------------

class _WicketChoice {
  const _WicketChoice({
    required this.type,
    required this.extra,
    required this.runs,
    required this.outId,
    required this.fielderId,
  });

  final WicketType type;
  final ExtraType extra;

  /// Runs completed: off the bat (normal, no-ball) or as extras (wide, bye,
  /// leg-bye). Only a run out can have runs.
  final int runs;
  final int? outId;
  final int? fielderId;
}

class _WicketDialog extends StatefulWidget {
  const _WicketDialog({required this.c});

  final ScoringController c;

  @override
  State<_WicketDialog> createState() => _WicketDialogState();
}

class _WicketDialogState extends State<_WicketDialog> {
  WicketType _type = WicketType.bowled;
  ExtraType _extra = ExtraType.none;
  int _runs = 0;
  int? _out;
  int? _fielder;

  List<ExtraType> get _allowedExtras => switch (_type) {
        WicketType.stumped => const [ExtraType.none, ExtraType.wide],
        WicketType.runOut => const [
            ExtraType.none,
            ExtraType.wide,
            ExtraType.noBall,
            ExtraType.bye,
            ExtraType.legBye,
          ],
        _ => const [ExtraType.none],
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final outId = _out ?? c.strikerId;
    return AlertDialog(
      title: const Text('Wicket'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How out?'),
            Wrap(
              spacing: 8,
              children: [
                for (final t in WicketType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _extra = ExtraType.none;
                      _runs = 0;
                      _out = null;
                    }),
                  ),
              ],
            ),
            if (_type == WicketType.runOut) ...[
              const SizedBox(height: 12),
              const Text('Who is out?'),
              Wrap(
                spacing: 8,
                children: [
                  for (final id in [c.strikerId, c.nonStrikerId])
                    if (id != null)
                      ChoiceChip(
                        label: Text(c.playerName(id)),
                        selected: outId == id,
                        onSelected: (_) => setState(() => _out = id),
                      ),
                ],
              ),
            ],
            if (_allowedExtras.length > 1) ...[
              const SizedBox(height: 12),
              const Text('Type of delivery'),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in _allowedExtras)
                    ChoiceChip(
                      label: Text(e.label),
                      selected: _extra == e,
                      onSelected: (_) => setState(() => _extra = e),
                    ),
                ],
              ),
            ],
            if (_type == WicketType.runOut) ...[
              const SizedBox(height: 12),
              const Text('Runs completed before the run out'),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in const [0, 1, 2, 3])
                    ChoiceChip(
                      label: Text('$r'),
                      selected: _runs == r,
                      onSelected: (_) => setState(() => _runs = r),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text('Fielder (optional)'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _fielder == null,
                  onSelected: (_) => setState(() => _fielder = null),
                ),
                for (final id in c.fielderCandidates)
                  ChoiceChip(
                    label: Text(c.playerName(id)),
                    selected: _fielder == id,
                    onSelected: (_) => setState(() => _fielder = id),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_WicketChoice(
            type: _type,
            extra: _extra,
            runs: _runs,
            outId: outId,
            fielderId: _fielder,
          )),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
