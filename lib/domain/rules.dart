/// Constants and tiny pure helpers for the rules of the app.
library;

/// Legal balls in one over.
const int ballsPerOver = 6;

/// Practical team-size limits chosen by our group (the brief lets us define a
/// minimum for demonstration). An innings ends when (batting team size - 1)
/// wickets have fallen.
const int minPlayersPerTeam = 3;
const int maxPlayersPerTeam = 11;

/// Largest match length the set-up screen accepts.
const int maxOversPerMatch = 50;

/// Converts a count of legal balls to cricket over notation:
/// 10 legal balls -> "1.4", 36 -> "6.0".
String formatOvers(int legalBalls) =>
    '${legalBalls ~/ ballsPerOver}.${legalBalls % ballsPerOver}';

/// Returns a message if a team of [playerCount] players cannot start a match,
/// or null when the size is acceptable.
String? teamSizeProblem(int playerCount) {
  if (playerCount < minPlayersPerTeam) {
    return 'needs at least $minPlayersPerTeam players (has $playerCount)';
  }
  if (playerCount > maxPlayersPerTeam) {
    return 'has more than $maxPlayersPerTeam players (has $playerCount)';
  }
  return null;
}
