/// The rules engine: turns the balls a human scorer enters into totals, overs,
/// strike changes, batter and bowler statistics and the end of the innings.
///
/// Pure Dart (no Flutter, no SQLite) so it can be unit-tested in milliseconds.
/// The key idea: an innings is nothing more than an ordered list of
/// deliveries. [InningsState.apply] folds one delivery into a state, and
/// [replayInnings] rebuilds any innings from its stored deliveries. Saving,
/// reopening and undo all use that one mechanism.
library;

import 'errors.dart';
import 'models.dart';
import 'rules.dart';

enum InningsStatus { inProgress, allOut, oversComplete, targetReached }

/// Fixed facts about an innings.
class InningsConfig {
  const InningsConfig({
    required this.battingIds,
    required this.bowlingIds,
    required this.maxOvers,
    this.target,
  });

  /// Everyone in the batting team (the squad).
  final List<int> battingIds;

  /// Everyone in the bowling team.
  final List<int> bowlingIds;
  final int maxOvers;

  /// Runs needed to win (second innings only): first-innings total + 1.
  final int? target;

  /// The innings is over when this many wickets have fallen.
  int get wicketsLimit => battingIds.length - 1;

  int get maxBalls => maxOvers * ballsPerOver;
}

/// One batter's statistics in one innings.
class BatterInnings {
  BatterInnings(this.playerId);

  final int playerId;
  int runs = 0;
  int balls = 0;
  int ones = 0;
  int twos = 0;
  int threes = 0;
  int fours = 0;
  int sixes = 0;
  bool isOut = false;
  WicketType? wicket;

  /// Bowler credited with the wicket; null for a run out or while not out.
  int? bowlerId;
  int? fielderId;

  double? get strikeRate => balls == 0 ? null : runs * 100 / balls;

  BatterInnings clone() => BatterInnings(playerId)
    ..runs = runs
    ..balls = balls
    ..ones = ones
    ..twos = twos
    ..threes = threes
    ..fours = fours
    ..sixes = sixes
    ..isOut = isOut
    ..wicket = wicket
    ..bowlerId = bowlerId
    ..fielderId = fielderId;
}

/// One bowler's statistics in one innings.
class BowlerSpell {
  BowlerSpell(this.playerId);

  final int playerId;
  int legalBalls = 0;
  int runsConceded = 0;
  int wickets = 0;

  String get oversText => formatOvers(legalBalls);

  double? get economy =>
      legalBalls == 0 ? null : runsConceded * ballsPerOver / legalBalls;

  BowlerSpell clone() => BowlerSpell(playerId)
    ..legalBalls = legalBalls
    ..runsConceded = runsConceded
    ..wickets = wickets;
}

/// The complete state of an innings after some number of deliveries.
///
/// Treat every field as read-only: [apply] never changes this object, it
/// returns a new one.
class InningsState {
  InningsState.start(this.config)
      : batters = {},
        bowlers = {},
        deliveries = [];

  InningsState._(this.config, this.batters, this.bowlers, this.deliveries);

  final InningsConfig config;

  /// Batters in the order they first came to the crease.
  final Map<int, BatterInnings> batters;

  /// Bowlers in the order they first bowled.
  final Map<int, BowlerSpell> bowlers;

  /// The event log: every ball so far, in order.
  final List<Delivery> deliveries;

  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  int wides = 0;
  int noBalls = 0;
  int byes = 0;
  int legByes = 0;
  InningsStatus status = InningsStatus.inProgress;

  /// Who is expected to face / be at the other end / bowl the NEXT ball.
  /// Null means the scorer must choose (opening pair, a new batter after a
  /// wicket, a new bowler after an over).
  int? striker;
  int? nonStriker;
  int? bowler;

  /// Bowler of the most recent ball; they may not bowl the next over.
  int? lastBowlerId;

  // ---- derived values ----------------------------------------------------

  bool get isComplete => status != InningsStatus.inProgress;
  bool get needsOpeners => deliveries.isEmpty;
  bool get needsNewBatter =>
      !isComplete &&
      deliveries.isNotEmpty &&
      (striker == null || nonStriker == null);
  bool get needsNewBowler => !isComplete && bowler == null;

  int get extrasTotal => wides + noBalls + byes + legByes;
  String get oversText => formatOvers(legalBalls);
  int? get target => config.target;

  /// Runs still needed in a chase (may be zero or negative once passed).
  int? get runsRequired => target == null ? null : target! - runs;
  int get ballsRemaining => config.maxBalls - legalBalls;
  double? get runRate =>
      legalBalls == 0 ? null : runs * ballsPerOver / legalBalls;
  double? get requiredRate {
    final need = runsRequired;
    if (need == null || ballsRemaining <= 0) return null;
    return need * ballsPerOver / ballsRemaining;
  }

  /// The balls of the over in progress (empty right after an over ends).
  List<Delivery> get thisOver {
    final out = <Delivery>[];
    var legal = 0;
    for (final d in deliveries) {
      out.add(d);
      if (d.isLegal) {
        legal++;
        if (legal % ballsPerOver == 0) out.clear();
      }
    }
    return out;
  }

  // ---- the rules -----------------------------------------------------------

  /// Applies one delivery and returns the new state.
  /// Throws [ScoringException] if the input breaks a rule.
  InningsState apply(DeliveryInput d) {
    _validate(d);
    final s = _copy();
    final legal = d.isLegal;

    // 1. Team total and extras.
    s.runs += d.teamRuns;
    switch (d.extra) {
      case ExtraType.wide:
        s.wides += 1 + d.extraRuns;
      case ExtraType.noBall:
        s.noBalls += 1;
      case ExtraType.bye:
        s.byes += d.extraRuns;
      case ExtraType.legBye:
        s.legByes += d.extraRuns;
      case ExtraType.none:
        break;
    }

    // 2. Batter: runs off the bat; a ball is faced on everything but a wide.
    final onStrike = s._batter(d.strikerId);
    s._batter(d.nonStrikerId); // both batters now appear on the scorecard
    if (d.extra != ExtraType.wide) onStrike.balls++;
    onStrike.runs += d.runsOffBat;
    switch (d.runsOffBat) {
      case 1:
        onStrike.ones++;
      case 2:
        onStrike.twos++;
      case 3:
        onStrike.threes++;
      case 4:
        onStrike.fours++;
      case 6:
        onStrike.sixes++;
    }

    // 3. Bowler: charged runs (not byes), a legal ball only if the ball counts.
    final bowling = s._bowler(d.bowlerId);
    bowling.runsConceded += d.bowlerRuns;
    if (legal) {
      bowling.legalBalls++;
      s.legalBalls++;
    }

    // 4. Wicket.
    int? strikerAfter = d.strikerId;
    int? nonStrikerAfter = d.nonStrikerId;
    final w = d.wicket;
    if (w != null) {
      final out = s._batter(d.dismissedPlayerId);
      out
        ..isOut = true
        ..wicket = w
        ..bowlerId = w.creditsBowler ? d.bowlerId : null
        ..fielderId = d.fielderId;
      s.wickets++;
      if (w.creditsBowler) bowling.wickets++;
      // The new batter will take the dismissed batter's place (striker or
      // non-striker position), so empty that slot for now.
      if (d.dismissedPlayerId == d.strikerId) {
        strikerAfter = null;
      } else {
        nonStrikerAfter = null;
      }
    }

    // 5. Strike change for runs that were actually run. A 4 or a 6 is a
    //    boundary, so the batters do not cross.
    if (_runsRun(d).isOdd) {
      final t = strikerAfter;
      strikerAfter = nonStrikerAfter;
      nonStrikerAfter = t;
    }

    // 6. End of over: the batters swap ends again and a new bowler is needed.
    int? bowlerAfter = d.bowlerId;
    if (legal && s.legalBalls % ballsPerOver == 0) {
      final t = strikerAfter;
      strikerAfter = nonStrikerAfter;
      nonStrikerAfter = t;
      bowlerAfter = null;
    }

    s.striker = strikerAfter;
    s.nonStriker = nonStrikerAfter;
    s.bowler = bowlerAfter;
    s.lastBowlerId = d.bowlerId;
    s.deliveries.add(Delivery(seq: deliveries.length + 1, input: d));

    // 7. Is the innings over?
    s.status = s._computeStatus();
    return s;
  }

  InningsStatus _computeStatus() {
    final t = target;
    if (t != null && runs >= t) return InningsStatus.targetReached;
    if (wickets >= config.wicketsLimit) return InningsStatus.allOut;
    if (legalBalls >= config.maxBalls) return InningsStatus.oversComplete;
    return InningsStatus.inProgress;
  }

  /// Runs the batters physically ran (they decide the strike change).
  static int _runsRun(DeliveryInput d) {
    final run = switch (d.extra) {
      ExtraType.none || ExtraType.noBall => d.runsOffBat,
      ExtraType.wide || ExtraType.bye || ExtraType.legBye => d.extraRuns,
    };
    return (run == 4 || run == 6) ? 0 : run;
  }

  void _validate(DeliveryInput d) {
    if (isComplete) {
      throw ScoringException('The innings is already over.');
    }
    if (d.strikerId == d.nonStrikerId) {
      throw ScoringException(
          'Striker and non-striker must be two different players.');
    }
    for (final id in [d.strikerId, d.nonStrikerId]) {
      if (!config.battingIds.contains(id)) {
        throw ScoringException('A selected batter is not in the batting team.');
      }
      if (batters[id]?.isOut ?? false) {
        throw ScoringException('A selected batter is already out.');
      }
    }
    if (!config.bowlingIds.contains(d.bowlerId)) {
      throw ScoringException('The bowler is not in the bowling team.');
    }

    // Batters: an occupied position cannot change; an empty one needs a batter
    // who has not batted yet.
    if (striker != null && d.strikerId != striker) {
      throw ScoringException('The striker cannot change in the middle of play.');
    }
    if (nonStriker != null && d.nonStrikerId != nonStriker) {
      throw ScoringException(
          'The non-striker cannot change in the middle of play.');
    }
    if (striker == null && batters.containsKey(d.strikerId)) {
      throw ScoringException('Choose a batter who has not batted yet.');
    }
    if (nonStriker == null && batters.containsKey(d.nonStrikerId)) {
      throw ScoringException('Choose a batter who has not batted yet.');
    }

    // Bowler: fixed during an over; a different bowler is needed for the next.
    if (bowler != null) {
      if (d.bowlerId != bowler) {
        throw ScoringException('The bowler can only change at the end of an over.');
      }
    } else if (deliveries.isNotEmpty && d.bowlerId == lastBowlerId) {
      throw ScoringException(
          'The same bowler cannot bowl two overs in a row.');
    }

    // Runs must fit the delivery type.
    final bat = d.runsOffBat;
    final ex = d.extraRuns;
    if (bat < 0 || bat > 6 || ex < 0 || ex > 6) {
      throw ScoringException('Runs must be between 0 and 6.');
    }
    switch (d.extra) {
      case ExtraType.none:
        if (ex != 0) throw ScoringException('Extra runs need an extra type.');
      case ExtraType.wide:
        if (bat != 0) {
          throw ScoringException('A wide cannot have runs off the bat.');
        }
      case ExtraType.noBall:
        if (ex != 0) {
          throw ScoringException('Enter no-ball runs as runs off the bat.');
        }
      case ExtraType.bye || ExtraType.legBye:
        if (bat != 0) {
          throw ScoringException('Byes and leg-byes are not runs off the bat.');
        }
    }

    // Wicket rules.
    final w = d.wicket;
    if (w != null) {
      final out = d.dismissedPlayerId;
      if (out != d.strikerId && out != d.nonStrikerId) {
        throw ScoringException('The dismissed batter must be at the crease.');
      }
      if (w != WicketType.runOut) {
        if (out != d.strikerId) {
          throw ScoringException('${w.label} can only dismiss the striker.');
        }
        if (bat != 0 || ex != 0) {
          throw ScoringException('No runs count when a batter is ${w.label.toLowerCase()}.');
        }
        final allowed = w == WicketType.stumped
            ? const [ExtraType.none, ExtraType.wide]
            : const [ExtraType.none];
        if (!allowed.contains(d.extra)) {
          throw ScoringException(
              '${w.label} is not possible on a ${d.extra.label.toLowerCase()}.');
        }
      }
      final f = d.fielderId;
      if (f != null && !config.bowlingIds.contains(f)) {
        throw ScoringException('The fielder must be in the bowling team.');
      }
    }
  }

  BatterInnings _batter(int id) =>
      batters.putIfAbsent(id, () => BatterInnings(id));

  BowlerSpell _bowler(int id) => bowlers.putIfAbsent(id, () => BowlerSpell(id));

  InningsState _copy() {
    final s = InningsState._(
      config,
      {for (final e in batters.entries) e.key: e.value.clone()},
      {for (final e in bowlers.entries) e.key: e.value.clone()},
      List.of(deliveries),
    )
      ..runs = runs
      ..wickets = wickets
      ..legalBalls = legalBalls
      ..wides = wides
      ..noBalls = noBalls
      ..byes = byes
      ..legByes = legByes
      ..status = status
      ..striker = striker
      ..nonStriker = nonStriker
      ..bowler = bowler
      ..lastBowlerId = lastBowlerId;
    return s;
  }
}

/// Rebuilds an innings from its stored deliveries. This is why a delivery-level
/// record is enough to save, reopen and undo.
InningsState replayInnings(
  InningsConfig config,
  Iterable<DeliveryInput> inputs,
) {
  var state = InningsState.start(config);
  for (final input in inputs) {
    state = state.apply(input);
  }
  return state;
}
