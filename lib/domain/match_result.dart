/// Works out the result of a two-innings limited-overs match.
library;

import 'innings.dart';

class MatchResult {
  const MatchResult({required this.text, this.winnerTeamId});

  final String text;

  /// Null for a tie.
  final int? winnerTeamId;

  bool get isTie => winnerTeamId == null;
}

/// Returns the result, or null while the match is still going.
///
/// * Chase completed: the chasing team wins by the wickets it had in hand.
/// * Chase ends (all out or overs finished) short of the target: the team that
///   batted first wins by the difference in runs, or the match is tied.
MatchResult? computeMatchResult({
  required int firstTeamId,
  required String firstTeamName,
  required int secondTeamId,
  required String secondTeamName,
  required InningsState first,
  required InningsState second,
}) {
  if (!first.isComplete) return null;

  if (second.status == InningsStatus.targetReached) {
    final left = second.config.wicketsLimit - second.wickets;
    return MatchResult(
      text: '$secondTeamName won by $left ${left == 1 ? 'wicket' : 'wickets'}',
      winnerTeamId: secondTeamId,
    );
  }
  if (!second.isComplete) return null;

  final margin = first.runs - second.runs;
  if (margin > 0) {
    return MatchResult(
      text: '$firstTeamName won by $margin ${margin == 1 ? 'run' : 'runs'}',
      winnerTeamId: firstTeamId,
    );
  }
  return const MatchResult(text: 'Match tied');
}
