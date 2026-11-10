import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/setup_controller.dart';
import '../domain/models.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';

/// Opens a saved match: an unfinished one resumes scoring, a finished one
/// shows its scorecard. Refreshes the match list when the user comes back.
Future<void> openMatch(BuildContext context, MatchInfo match) async {
  final setup = context.read<SetupController>();
  final route = match.status == MatchStatus.inProgress
      ? scoringRoute(match.id)
      : scorecardRoute(match.id);
  await Navigator.of(context).push(route);
  await setup.load();
}
