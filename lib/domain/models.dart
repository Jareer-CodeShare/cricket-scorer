/// Plain data classes shared by every layer. No Flutter, no SQLite.
library;

/// What kind of delivery was bowled.
enum ExtraType {
  none('Normal'),
  wide('Wide'),
  noBall('No-ball'),
  bye('Bye'),
  legBye('Leg-bye');

  const ExtraType(this.label);
  final String label;
}

/// How a batter was dismissed.
enum WicketType {
  bowled('Bowled', true),
  caught('Caught', true),
  lbw('LBW', true),
  stumped('Stumped', true),
  runOut('Run out', false);

  const WicketType(this.label, this.creditsBowler);
  final String label;

  /// Whether the wicket counts in the bowler's figures.
  final bool creditsBowler;
}

enum MatchStatus { inProgress, completed }

class Team {
  const Team({required this.id, required this.name});
  final int id;
  final String name;
}

class Player {
  const Player({required this.id, required this.teamId, required this.name});
  final int id;
  final int teamId;
  final String name;
}

/// A match between two saved teams. [id] is 0 until the repository saves it.
class MatchInfo {
  const MatchInfo({
    this.id = 0,
    required this.name,
    required this.date,
    required this.overs,
    required this.teamAId,
    required this.teamBId,
    required this.battingFirstTeamId,
    this.status = MatchStatus.inProgress,
    this.resultText,
    this.summaryText,
  });

  final int id;
  final String name;
  final DateTime date;
  final int overs;
  final int teamAId;
  final int teamBId;
  final int battingFirstTeamId;
  final MatchStatus status;
  final String? resultText;

  /// One-line score summary shown in the match history list.
  final String? summaryText;

  int get bowlingFirstTeamId =>
      battingFirstTeamId == teamAId ? teamBId : teamAId;

  MatchInfo copyWith({
    int? id,
    MatchStatus? status,
    String? resultText,
    String? summaryText,
    bool clearResult = false,
  }) {
    return MatchInfo(
      id: id ?? this.id,
      name: name,
      date: date,
      overs: overs,
      teamAId: teamAId,
      teamBId: teamBId,
      battingFirstTeamId: battingFirstTeamId,
      status: status ?? this.status,
      resultText: clearResult ? null : (resultText ?? this.resultText),
      summaryText: clearResult ? null : (summaryText ?? this.summaryText),
    );
  }
}

/// One innings of a match. [target] is set for the second innings only.
class InningsInfo {
  const InningsInfo({
    this.id = 0,
    required this.matchId,
    required this.number,
    required this.battingTeamId,
    required this.bowlingTeamId,
    this.target,
  });

  final int id;
  final int matchId;
  final int number;
  final int battingTeamId;
  final int bowlingTeamId;
  final int? target;

  InningsInfo copyWith({int? id}) => InningsInfo(
        id: id ?? this.id,
        matchId: matchId,
        number: number,
        battingTeamId: battingTeamId,
        bowlingTeamId: bowlingTeamId,
        target: target,
      );
}

/// What the human scorer enters for one ball: who was involved and what
/// happened. Everything else (totals, strike, overs, stats) is derived by the
/// rules engine.
class DeliveryInput {
  const DeliveryInput({
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    this.runsOffBat = 0,
    this.extra = ExtraType.none,
    this.extraRuns = 0,
    this.wicket,
    this.dismissedId,
    this.fielderId,
  });

  final int strikerId;
  final int nonStrikerId;
  final int bowlerId;

  /// Runs scored by the bat (also on a no-ball). Zero for wides, byes, leg-byes.
  final int runsOffBat;

  final ExtraType extra;

  /// Runs beyond the automatic one-run penalty: runs run on a wide, or the
  /// byes / leg-byes taken. Always zero for a normal ball or a no-ball.
  final int extraRuns;

  final WicketType? wicket;

  /// The batter who is out; null means the striker. Only a run out can
  /// dismiss the non-striker.
  final int? dismissedId;

  /// Fielder for a catch, stumping or run out (optional).
  final int? fielderId;

  /// A wide or a no-ball is not a legal delivery and is not counted in the over.
  bool get isLegal => extra != ExtraType.wide && extra != ExtraType.noBall;

  /// Runs added to the team total by this ball.
  int get teamRuns => switch (extra) {
        ExtraType.none => runsOffBat,
        ExtraType.wide => 1 + extraRuns,
        ExtraType.noBall => 1 + runsOffBat,
        ExtraType.bye || ExtraType.legBye => extraRuns,
      };

  /// Runs charged to the bowler: everything except byes and leg-byes.
  int get bowlerRuns => switch (extra) {
        ExtraType.bye || ExtraType.legBye => 0,
        _ => teamRuns,
      };

  int get dismissedPlayerId => dismissedId ?? strikerId;
}

/// One stored ball: the input plus its position in the innings. This is the
/// event log that every innings can be rebuilt from.
class Delivery {
  const Delivery({required this.seq, required this.input});

  /// 1-based order of the ball in the innings.
  final int seq;
  final DeliveryInput input;

  bool get isLegal => input.isLegal;

  /// Short label for the "this over" strip: "0", "4", "Wd", "Nb+2", "W", ...
  String get label {
    final i = input;
    final base = switch (i.extra) {
      ExtraType.none => '${i.runsOffBat}',
      ExtraType.wide => i.extraRuns == 0 ? 'Wd' : 'Wd+${i.extraRuns}',
      ExtraType.noBall => i.runsOffBat == 0 ? 'Nb' : 'Nb+${i.runsOffBat}',
      ExtraType.bye => 'B${i.extraRuns}',
      ExtraType.legBye => 'Lb${i.extraRuns}',
    };
    if (i.wicket == null) return base;
    return base == '0' ? 'W' : '$base+W';
  }
}
