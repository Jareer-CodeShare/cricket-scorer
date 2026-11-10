// Unit tests for the rules engine (lib/domain). Every row of the scoring and
// dismissal tables in README.md is covered here.
import 'package:cricket_scorer/domain/errors.dart';
import 'package:cricket_scorer/domain/innings.dart';
import 'package:cricket_scorer/domain/match_result.dart';
import 'package:cricket_scorer/domain/models.dart';
import 'package:cricket_scorer/domain/scorecard_text.dart';
import 'package:flutter_test/flutter_test.dart';

// Batting team ids 1..4, bowling team ids 11..14.
InningsConfig config({
  int overs = 5,
  int? target,
  List<int> batting = const [1, 2, 3, 4],
}) =>
    InningsConfig(
      battingIds: batting,
      bowlingIds: const [11, 12, 13, 14],
      maxOvers: overs,
      target: target,
    );

InningsState fresh({int overs = 5, int? target, List<int>? batting}) =>
    InningsState.start(config(
      overs: overs,
      target: target,
      batting: batting ?? const [1, 2, 3, 4],
    ));

/// Applies one ball. Anything not given is taken from the state: the expected
/// striker / non-striker / bowler, the next batter who has not batted yet, and
/// the other bowler after an over.
InningsState go(
  InningsState st, {
  int bat = 0,
  ExtraType extra = ExtraType.none,
  int extraRuns = 0,
  WicketType? wicket,
  int? out,
  int? fielder,
  int? striker,
  int? nonStriker,
  int? bowler,
}) {
  int next(Set<int> exclude) => st.config.battingIds
      .firstWhere((id) => !st.batters.containsKey(id) && !exclude.contains(id));
  final s = striker ?? st.striker ?? next({nonStriker ?? st.nonStriker ?? -1});
  final n = nonStriker ?? st.nonStriker ?? next({s});
  final b = bowler ?? st.bowler ?? (st.lastBowlerId == 11 ? 12 : 11);
  return st.apply(DeliveryInput(
    strikerId: s,
    nonStrikerId: n,
    bowlerId: b,
    runsOffBat: bat,
    extra: extra,
    extraRuns: extraRuns,
    wicket: wicket,
    dismissedId: out,
    fielderId: fielder,
  ));
}

InningsState dots(InningsState st, int count) {
  var s = st;
  for (var i = 0; i < count; i++) {
    s = go(s);
  }
  return s;
}

void expectRule(void Function() action) =>
    expect(action, throwsA(isA<ScoringException>()));

void main() {
  group('runs off the bat', () {
    test('runs go to the team, the batter and the bowler', () {
      final s = go(fresh(), bat: 4);
      expect(s.runs, equals(4));
      expect(s.legalBalls, equals(1));
      expect(s.batters[1]!.runs, equals(4));
      expect(s.batters[1]!.balls, equals(1));
      expect(s.bowlers[11]!.runsConceded, equals(4));
      expect(s.bowlers[11]!.legalBalls, equals(1));
    });

    test('0, 1, 2, 3, 4 and 6 are counted in the right buckets', () {
      var s = fresh();
      s = go(s, bat: 0); // striker 1
      s = go(s, bat: 1); // striker 1, then strike changes to 2
      s = go(s, bat: 2); // striker 2
      s = go(s, bat: 3); // striker 2, then strike changes to 1
      s = go(s, bat: 4); // striker 1
      s = go(s, bat: 6); // striker 1
      final a = s.batters[1]!;
      final b = s.batters[2]!;
      expect(a.runs, equals(11));
      expect(a.balls, equals(4));
      expect([a.ones, a.twos, a.threes, a.fours, a.sixes],
          equals([1, 0, 0, 1, 1]));
      expect(b.runs, equals(5));
      expect(b.balls, equals(2));
      expect([b.ones, b.twos, b.threes, b.fours, b.sixes],
          equals([0, 1, 1, 0, 0]));
      expect(s.runs, equals(16));
    });

    test('strike rate and economy', () {
      final s = go(go(fresh(), bat: 4), bat: 2);
      expect(s.batters[1]!.strikeRate, closeTo(300, 0.001));
      expect(s.bowlers[11]!.economy, closeTo(18, 0.001));
    });
  });

  group('extras', () {
    test('a wide adds a run, is not a legal ball and the batter does not face it',
        () {
      final s = go(fresh(), extra: ExtraType.wide);
      expect(s.runs, equals(1));
      expect(s.wides, equals(1));
      expect(s.legalBalls, equals(0));
      expect(s.oversText, equals('0.0'));
      expect(s.batters[1]!.balls, equals(0));
      expect(s.bowlers[11]!.runsConceded, equals(1));
      expect(s.bowlers[11]!.legalBalls, equals(0));
      expect(s.thisOver.single.label, equals('Wd'));
    });

    test('runs run on a wide are added to the penalty run', () {
      final two = go(fresh(), extra: ExtraType.wide, extraRuns: 2);
      expect(two.runs, equals(3));
      expect(two.wides, equals(3));
      expect(two.striker, equals(1)); // even runs: no strike change
      final one = go(fresh(), extra: ExtraType.wide, extraRuns: 1);
      expect(one.runs, equals(2));
      expect(one.striker, equals(2)); // odd runs: strike changes
    });

    test('a no-ball is not legal, but the batter faces it and keeps the runs',
        () {
      final s = go(fresh(), extra: ExtraType.noBall, bat: 4);
      expect(s.runs, equals(5));
      expect(s.noBalls, equals(1));
      expect(s.legalBalls, equals(0));
      expect(s.batters[1]!.runs, equals(4));
      expect(s.batters[1]!.balls, equals(1));
      expect(s.batters[1]!.fours, equals(1));
      expect(s.bowlers[11]!.runsConceded, equals(5));
      expect(s.bowlers[11]!.legalBalls, equals(0));
      expect(s.extrasTotal, equals(1));
      expect(s.thisOver.single.label, equals('Nb+4'));
    });

    test('byes and leg-byes: legal, team runs, no batter runs, not the bowler',
        () {
      var s = go(fresh(), extra: ExtraType.bye, extraRuns: 2);
      expect(s.runs, equals(2));
      expect(s.byes, equals(2));
      expect(s.legalBalls, equals(1));
      expect(s.batters[1]!.runs, equals(0));
      expect(s.batters[1]!.balls, equals(1));
      expect(s.bowlers[11]!.runsConceded, equals(0));
      expect(s.striker, equals(1)); // two runs: no strike change
      s = go(s, extra: ExtraType.legBye, extraRuns: 1);
      expect(s.runs, equals(3));
      expect(s.legByes, equals(1));
      expect(s.legalBalls, equals(2));
      expect(s.bowlers[11]!.runsConceded, equals(0));
      expect(s.striker, equals(2)); // one run: strike changes
      expect(s.extrasTotal, equals(3));
    });
  });

  group('overs', () {
    test('over notation counts legal balls only', () {
      var s = dots(fresh(), 3);
      expect(s.oversText, equals('0.3'));
      s = go(s, extra: ExtraType.wide);
      s = go(s, extra: ExtraType.noBall);
      expect(s.oversText, equals('0.3'));
      s = dots(s, 2);
      expect(s.oversText, equals('0.5'));
      s = go(s);
      expect(s.oversText, equals('1.0'));
    });

    test('an over containing a wide and a no-ball takes eight deliveries', () {
      var s = fresh();
      s = go(s, extra: ExtraType.wide);
      s = dots(s, 3);
      s = go(s, extra: ExtraType.noBall);
      s = dots(s, 3); // six legal balls in total
      expect(s.deliveries.length, equals(8));
      expect(s.legalBalls, equals(6));
      expect(s.needsNewBowler, isTrue);
    });

    test('strike changes on odd runs and not on boundaries', () {
      var s = go(fresh(), bat: 1);
      expect(s.striker, equals(2));
      s = go(s, bat: 3);
      expect(s.striker, equals(1));
      s = go(s, bat: 4);
      expect(s.striker, equals(1));
      s = go(s, bat: 6);
      expect(s.striker, equals(1));
      s = go(s, bat: 2);
      expect(s.striker, equals(1));
    });

    test('strike changes at the end of an over', () {
      final s = dots(fresh(), 6);
      expect(s.striker, equals(2));
      expect(s.nonStriker, equals(1));
    });

    test('an odd run off the last ball cancels with the end-of-over change', () {
      var s = dots(fresh(), 5);
      s = go(s, bat: 1);
      expect(s.striker, equals(1));
      expect(s.nonStriker, equals(2));
    });

    test('the next bowler must be chosen and cannot be the previous bowler', () {
      final s = dots(fresh(), 6);
      expect(s.bowler, isNull);
      expect(s.needsNewBowler, isTrue);
      expectRule(() => go(s, bowler: 11));
      final next = go(s, bowler: 12);
      expect(next.bowler, equals(12));
      expect(next.bowlers.keys.toList(), equals([11, 12]));
    });

    test('the bowler cannot change in the middle of an over', () {
      final s = dots(fresh(), 2);
      expectRule(() => go(s, bowler: 12));
    });

    test('this-over strip resets after six legal balls', () {
      var s = dots(fresh(), 6);
      expect(s.thisOver, isEmpty);
      s = go(s, bat: 2);
      expect(s.thisOver.length, equals(1));
    });
  });

  group('wickets', () {
    test('bowled: bowler is credited, batter is out, new batter takes strike',
        () {
      var s = go(fresh(), wicket: WicketType.bowled);
      expect(s.wickets, equals(1));
      expect(s.batters[1]!.isOut, isTrue);
      expect(s.batters[1]!.wicket, equals(WicketType.bowled));
      expect(s.batters[1]!.bowlerId, equals(11));
      expect(s.bowlers[11]!.wickets, equals(1));
      expect(s.runs, equals(0));
      expect(s.striker, isNull);
      expect(s.nonStriker, equals(2));
      expect(s.needsNewBatter, isTrue);
      expectRule(() => go(s, striker: 1)); // the dismissed batter cannot return
      s = go(s); // helper picks the next batter who has not batted: 3
      expect(s.batters.keys.toList(), equals([1, 2, 3]));
      expect(s.batters[3]!.balls, equals(1));
      expect(s.needsNewBatter, isFalse);
    });

    test('caught records the fielder; LBW is credited to the bowler', () {
      final c = go(fresh(), wicket: WicketType.caught, fielder: 12);
      expect(c.batters[1]!.fielderId, equals(12));
      expect(c.bowlers[11]!.wickets, equals(1));
      final l = go(fresh(), wicket: WicketType.lbw);
      expect(l.batters[1]!.wicket, equals(WicketType.lbw));
      expect(l.bowlers[11]!.wickets, equals(1));
    });

    test('stumped is allowed on a legal ball and on a wide, not on a no-ball',
        () {
      final legal = go(fresh(), wicket: WicketType.stumped, fielder: 12);
      expect(legal.wickets, equals(1));
      final wide =
          go(fresh(), wicket: WicketType.stumped, extra: ExtraType.wide);
      expect(wide.wickets, equals(1));
      expect(wide.runs, equals(1));
      expect(wide.legalBalls, equals(0));
      expect(wide.batters[1]!.balls, equals(0));
      expectRule(() => go(fresh(),
          wicket: WicketType.stumped, extra: ExtraType.noBall));
    });

    test('bowled, caught and LBW are impossible on extras or with runs', () {
      expectRule(() =>
          go(fresh(), wicket: WicketType.bowled, extra: ExtraType.wide));
      expectRule(() =>
          go(fresh(), wicket: WicketType.caught, extra: ExtraType.noBall));
      expectRule(() => go(fresh(), wicket: WicketType.lbw, bat: 1));
    });

    test('run out: no bowler credit, either batter can be out, runs count', () {
      final s = go(fresh(),
          wicket: WicketType.runOut, out: 2, bat: 1, fielder: 12);
      expect(s.wickets, equals(1));
      expect(s.runs, equals(1));
      expect(s.batters[2]!.isOut, isTrue);
      expect(s.batters[2]!.bowlerId, isNull);
      expect(s.bowlers[11]!.wickets, equals(0));
      expect(s.batters[1]!.runs, equals(1));
      // New batter takes the dismissed batter's place, then the odd run swaps.
      expect(s.striker, isNull);
      expect(s.nonStriker, equals(1));
      expect(s.needsNewBatter, isTrue);
    });

    test('run out of the striker with no runs leaves the other batter at the '
        'non-striker end', () {
      final s = go(fresh(), wicket: WicketType.runOut);
      expect(s.striker, isNull);
      expect(s.nonStriker, equals(2));
    });

    test('run out is possible on a wide', () {
      final s = go(fresh(),
          wicket: WicketType.runOut, extra: ExtraType.wide, out: 2);
      expect(s.wickets, equals(1));
      expect(s.runs, equals(1));
    });

    test('the dismissed batter and fielder must be valid', () {
      expectRule(() => go(fresh(), wicket: WicketType.runOut, out: 99));
      expectRule(() => go(fresh(), wicket: WicketType.bowled, out: 2));
      expectRule(
          () => go(fresh(), wicket: WicketType.caught, fielder: 3)); // own team
    });

    test('a wicket on the sixth ball: over ends and the new batter is needed',
        () {
      var s = dots(fresh(), 5);
      s = go(s, wicket: WicketType.bowled);
      expect(s.legalBalls, equals(6));
      expect(s.needsNewBowler, isTrue);
      expect(s.needsNewBatter, isTrue);
      expect(s.striker, equals(2)); // end-of-over change: 2 takes strike
      expect(s.nonStriker, isNull);
    });
  });

  group('innings end', () {
    test('all out when batting team size minus one wickets have fallen', () {
      var s = fresh(batting: const [1, 2, 3]);
      s = go(s, wicket: WicketType.bowled);
      expect(s.isComplete, isFalse);
      s = go(s, wicket: WicketType.bowled);
      expect(s.status, equals(InningsStatus.allOut));
      expect(s.wickets, equals(2));
      expectRule(() => go(s, striker: 3, nonStriker: 2));
    });

    test('overs complete', () {
      final s = dots(fresh(overs: 1), 6);
      expect(s.status, equals(InningsStatus.oversComplete));
      expect(s.oversText, equals('1.0'));
      expectRule(() => go(s));
    });

    test('wides and no-balls do not use up the overs', () {
      var s = dots(fresh(overs: 1), 5);
      s = go(s, extra: ExtraType.wide);
      s = go(s, extra: ExtraType.noBall);
      expect(s.isComplete, isFalse);
      s = go(s);
      expect(s.status, equals(InningsStatus.oversComplete));
    });

    test('chase completes as soon as the target is reached', () {
      var s = fresh(target: 10);
      s = go(s, bat: 6);
      expect(s.runsRequired, equals(4));
      expect(s.isComplete, isFalse);
      s = go(s, bat: 4);
      expect(s.status, equals(InningsStatus.targetReached));
      expect(s.runs, equals(10));
      expectRule(() => go(s));
    });

    test('required and current run rates', () {
      var s = fresh(overs: 2, target: 13);
      s = go(s, bat: 4);
      expect(s.runRate, closeTo(24, 0.001));
      expect(s.requiredRate, closeTo(9 * 6 / 11, 0.001));
    });
  });

  group('input checks', () {
    test('striker and non-striker must differ and belong to the batting team',
        () {
      expectRule(() => go(fresh(), striker: 1, nonStriker: 1));
      expectRule(() => go(fresh(), striker: 1, nonStriker: 11));
      expectRule(() => go(fresh(), bowler: 1));
    });

    test('runs must fit the delivery type', () {
      expectRule(() => go(fresh(), extraRuns: 1));
      expectRule(() => go(fresh(), extra: ExtraType.wide, bat: 1));
      expectRule(() => go(fresh(), extra: ExtraType.noBall, extraRuns: 1));
      expectRule(() => go(fresh(), extra: ExtraType.bye, bat: 1));
      expectRule(() => go(fresh(), bat: 7));
    });

    test('batters cannot be swapped around in the middle of play', () {
      final s = go(fresh(), bat: 0);
      expectRule(() => go(s, striker: 2, nonStriker: 1));
    });

    test('a new batter must not have batted already', () {
      var s = go(fresh(), bat: 1); // striker 2, non-striker 1
      s = go(s, wicket: WicketType.bowled); // striker 2 is out
      expectRule(() => go(s, striker: 1, nonStriker: 1));
      expectRule(() => go(s, striker: 2));
    });
  });

  group('replay and undo', () {
    final inputs = <DeliveryInput>[
      const DeliveryInput(strikerId: 1, nonStrikerId: 2, bowlerId: 11, runsOffBat: 1),
      const DeliveryInput(strikerId: 2, nonStrikerId: 1, bowlerId: 11, extra: ExtraType.wide),
      const DeliveryInput(strikerId: 2, nonStrikerId: 1, bowlerId: 11, runsOffBat: 4),
      const DeliveryInput(strikerId: 2, nonStrikerId: 1, bowlerId: 11, wicket: WicketType.caught, fielderId: 12),
      const DeliveryInput(strikerId: 3, nonStrikerId: 1, bowlerId: 11, extra: ExtraType.bye, extraRuns: 1),
    ];

    test('replaying the stored deliveries gives the same state', () {
      var live = fresh();
      for (final i in inputs) {
        live = live.apply(i);
      }
      final rebuilt = replayInnings(config(), live.deliveries.map((d) => d.input));
      expect(rebuilt.runs, equals(live.runs));
      expect(rebuilt.wickets, equals(live.wickets));
      expect(rebuilt.legalBalls, equals(live.legalBalls));
      expect(rebuilt.striker, equals(live.striker));
      expect(rebuilt.nonStriker, equals(live.nonStriker));
      expect(rebuilt.extrasTotal, equals(live.extrasTotal));
      expect(rebuilt.batters.keys.toList(), equals(live.batters.keys.toList()));
      expect(rebuilt.batters[2]!.runs, equals(live.batters[2]!.runs));
    });

    test('undo is a replay of all but the last delivery', () {
      var live = fresh();
      for (final i in inputs) {
        live = live.apply(i);
      }
      final before = replayInnings(
          config(), live.deliveries.take(4).map((d) => d.input));
      final undone = replayInnings(config(),
          live.deliveries.sublist(0, live.deliveries.length - 1).map((d) => d.input));
      expect(undone.runs, equals(before.runs));
      expect(undone.runs, equals(6)); // 1 + wide 1 + 4 + caught 0 (bye undone)
      expect(undone.wickets, equals(1));
      expect(undone.needsNewBatter, isTrue);
    });

    test('apply never changes the state it is called on', () {
      final s0 = fresh();
      final s1 = go(s0, bat: 6);
      expect(s0.runs, equals(0));
      expect(s0.deliveries, isEmpty);
      expect(s1.runs, equals(6));
    });
  });

  group('result', () {
    InningsState firstInnings(int runs) {
      // Score exactly [runs] using sixes, then ones, then a single, with the
      // full 10 overs available.
      var s = InningsState.start(config(overs: 10));
      var left = runs;
      while (left >= 6) {
        s = go(s, bat: 6);
        left -= 6;
      }
      while (left > 0) {
        s = go(s, bat: 1);
        left--;
      }
      // finish the innings by running out the overs with dot balls
      while (!s.isComplete) {
        s = go(s);
      }
      return s;
    }

    MatchResult? result(InningsState first, InningsState second) =>
        computeMatchResult(
          firstTeamId: 1,
          firstTeamName: 'Alpha',
          secondTeamId: 2,
          secondTeamName: 'Bravo',
          first: first,
          second: second,
        );

    test('chasing team wins by wickets in hand', () {
      final first = firstInnings(7);
      var second = InningsState.start(config(overs: 10, target: first.runs + 1));
      second = go(second, bat: 6);
      second = go(second, bat: 2);
      final r = result(first, second)!;
      expect(r.text, equals('Bravo won by 3 wickets'));
      expect(r.winnerTeamId, equals(2));
    });

    test('team batting first wins by runs when the chase falls short', () {
      final first = firstInnings(12);
      var second = InningsState.start(config(overs: 10, target: first.runs + 1));
      second = go(second, bat: 4);
      while (!second.isComplete) {
        second = go(second);
      }
      final r = result(first, second)!;
      expect(r.text, equals('Alpha won by 8 runs'));
      expect(r.winnerTeamId, equals(1));
    });

    test('equal scores are a tie', () {
      final first = firstInnings(6);
      var second = InningsState.start(config(overs: 10, target: first.runs + 1));
      second = go(second, bat: 6);
      while (!second.isComplete) {
        second = go(second);
      }
      final r = result(first, second)!;
      expect(r.text, equals('Match tied'));
      expect(r.isTie, isTrue);
    });

    test('no result while the second innings is still going', () {
      final first = firstInnings(30);
      final second = go(InningsState.start(config(overs: 10, target: 31)), bat: 1);
      expect(result(first, second), isNull);
    });

    test('singular wording', () {
      final first = firstInnings(5);
      var second = InningsState.start(config(
          overs: 10, target: first.runs + 1, batting: const [1, 2, 3]));
      second = go(second, wicket: WicketType.bowled);
      second = go(second, bat: 6);
      expect(result(first, second)!.text, equals('Bravo won by 1 wicket'));
    });
  });

  group('scorecard text', () {
    String name(int id) => 'P$id';
    BatterInnings out(WicketType w, {int? bowler, int? fielder}) =>
        BatterInnings(1)
          ..isOut = true
          ..wicket = w
          ..bowlerId = bowler
          ..fielderId = fielder;

    test('dismissal wording', () {
      expect(dismissalText(BatterInnings(1), name), equals('not out'));
      expect(dismissalText(out(WicketType.bowled, bowler: 11), name),
          equals('b P11'));
      expect(dismissalText(out(WicketType.lbw, bowler: 11), name),
          equals('lbw b P11'));
      expect(
          dismissalText(out(WicketType.caught, bowler: 11, fielder: 12), name),
          equals('c P12 b P11'));
      expect(
          dismissalText(out(WicketType.caught, bowler: 11, fielder: 11), name),
          equals('c & b P11'));
      expect(
          dismissalText(out(WicketType.stumped, bowler: 11, fielder: 12), name),
          equals('st P12 b P11'));
      expect(dismissalText(out(WicketType.runOut, fielder: 12), name),
          equals('run out (P12)'));
      expect(dismissalText(out(WicketType.runOut), name), equals('run out'));
    });
  });
}
