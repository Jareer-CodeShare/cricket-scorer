// The scripted demo match: one two-innings game that contains every edge case
// the brief requires - an over with a wide, an over with a no-ball, a boundary,
// a wicket, a strike change, an over ending and a successful chase.
//
// Teams: Alpha = players 1, 2, 3; Bravo = players 4, 5, 6. Two overs a side,
// so an innings ends after 2 wickets (team size 3 minus 1).
//
// The expected numbers below were worked out by hand from the rules tables.
import 'package:cricket_scorer/domain/innings.dart';
import 'package:cricket_scorer/domain/match_result.dart';
import 'package:cricket_scorer/domain/models.dart';
import 'package:cricket_scorer/domain/scorecard_text.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryInput d(
  int s,
  int n,
  int b, {
  int bat = 0,
  ExtraType extra = ExtraType.none,
  int extraRuns = 0,
  WicketType? wicket,
  int? out,
  int? fielder,
}) =>
    DeliveryInput(
      strikerId: s,
      nonStrikerId: n,
      bowlerId: b,
      runsOffBat: bat,
      extra: extra,
      extraRuns: extraRuns,
      wicket: wicket,
      dismissedId: out,
      fielderId: fielder,
    );

const alphaBatting = InningsConfig(
  battingIds: [1, 2, 3],
  bowlingIds: [4, 5, 6],
  maxOvers: 2,
);

final firstInningsBalls = <DeliveryInput>[
  // ---- over 1, bowler 4 ----
  d(1, 2, 4, bat: 1), //                            1 run, strike changes
  d(2, 1, 4, extra: ExtraType.wide), //             wide: not a legal ball
  d(2, 1, 4, bat: 4), //                            boundary, no strike change
  d(2, 1, 4), //                                    dot
  d(2, 1, 4, extra: ExtraType.noBall, bat: 2), //   no-ball + 2 off the bat
  d(2, 1, 4, wicket: WicketType.caught, fielder: 5), // wicket: caught
  d(3, 1, 4, bat: 6), //                            new batter hits a six
  d(3, 1, 4, extra: ExtraType.bye, extraRuns: 1), // bye ends the over
  // ---- over 2, bowler 5 (must differ from bowler 4) ----
  d(3, 1, 5, bat: 1),
  d(1, 3, 5, extra: ExtraType.legBye, extraRuns: 2),
  d(1, 3, 5, bat: 1),
  d(3, 1, 5, wicket: WicketType.runOut, out: 1, bat: 1, fielder: 6),
];

final secondInningsBalls = <DeliveryInput>[
  // ---- over 1, bowler 1 ----
  d(4, 5, 1, bat: 6),
  d(4, 5, 1, bat: 6),
  d(4, 5, 1, bat: 4),
  d(4, 5, 1, wicket: WicketType.bowled),
  d(6, 5, 1, bat: 4), // new batter 6 takes strike
  d(6, 5, 1, bat: 1), // last ball of the over
  // ---- over 2, bowler 2 ----
  d(6, 5, 2, bat: 1), // reaches the target
];

String name(int id) => switch (id) {
      1 => 'Ali',
      2 => 'Bilal',
      3 => 'Chand',
      4 => 'Dawood',
      5 => 'Emad',
      6 => 'Farhan',
      _ => '?',
    };

void main() {
  late InningsState first;
  late InningsState second;

  InningsState play(InningsConfig c, List<DeliveryInput> balls) {
    var s = InningsState.start(c);
    for (final b in balls) {
      s = s.apply(b);
    }
    return s;
  }

  first = play(alphaBatting, firstInningsBalls);
  second = play(
    InningsConfig(
      battingIds: const [4, 5, 6],
      bowlingIds: const [1, 2, 3],
      maxOvers: 2,
      target: first.runs + 1,
    ),
    secondInningsBalls,
  );

  group('first innings: Alpha bat', () {
    test('total, wickets, overs and how it ended', () {
      expect(first.runs, equals(21));
      expect(first.wickets, equals(2));
      expect(first.oversText, equals('1.4'));
      expect(first.status, equals(InningsStatus.allOut));
      expect(first.deliveries.length, equals(12));
    });

    test('extras', () {
      expect(first.wides, equals(1));
      expect(first.noBalls, equals(1));
      expect(first.byes, equals(1));
      expect(first.legByes, equals(2));
      expect(first.extrasTotal, equals(5));
    });

    test('the over with a wide and a no-ball took eight balls but only six '
        'counted', () {
      final overOne = first.deliveries.take(8).toList();
      expect(overOne.where((x) => x.isLegal).length, equals(6));
      expect(overOne.where((x) => !x.isLegal).length, equals(2));
    });

    test('batters', () {
      final a = first.batters[1]!;
      expect([a.runs, a.balls, a.ones], equals([2, 3, 2]));
      expect(a.wicket, equals(WicketType.runOut));
      final b = first.batters[2]!;
      expect([b.runs, b.balls, b.fours, b.twos], equals([6, 4, 1, 1]));
      expect(b.wicket, equals(WicketType.caught));
      final c = first.batters[3]!;
      expect([c.runs, c.balls, c.sixes, c.ones], equals([8, 4, 1, 2]));
      expect(c.isOut, isFalse);
      expect(a.runs + b.runs + c.runs + first.extrasTotal, equals(first.runs));
    });

    test('bowlers', () {
      final x = first.bowlers[4]!;
      expect([x.legalBalls, x.runsConceded, x.wickets], equals([6, 15, 1]));
      expect(x.oversText, equals('1.0'));
      final y = first.bowlers[5]!;
      expect([y.legalBalls, y.runsConceded, y.wickets], equals([4, 3, 0]));
      expect(y.oversText, equals('0.4'));
      // byes and leg-byes (3 runs) are not charged to either bowler
      expect(x.runsConceded + y.runsConceded + 3, equals(first.runs));
    });

    test('dismissal wording on the scorecard', () {
      expect(dismissalText(first.batters[2]!, name), equals('c Emad b Dawood'));
      expect(dismissalText(first.batters[1]!, name), equals('run out (Farhan)'));
      expect(dismissalText(first.batters[3]!, name), equals('not out'));
    });

    test('this-over strip shows the four balls of the second over', () {
      expect(first.thisOver.map((x) => x.label).toList(),
          equals(['1', 'Lb2', '1', '1+W']));
    });
  });

  group('second innings: Bravo chase', () {
    test('target is first-innings total plus one', () {
      expect(second.target, equals(22));
    });

    test('chase completes with one wicket down', () {
      expect(second.runs, equals(22));
      expect(second.wickets, equals(1));
      expect(second.oversText, equals('1.1'));
      expect(second.status, equals(InningsStatus.targetReached));
    });

    test('batters and bowlers', () {
      final four = second.batters[4]!;
      expect([four.runs, four.balls, four.fours, four.sixes],
          equals([16, 4, 1, 2]));
      expect(four.wicket, equals(WicketType.bowled));
      expect(dismissalText(four, name), equals('b Ali'));
      final six = second.batters[6]!;
      // 4 + 1, then the single that wins the match: 6 off 3 balls
      expect([six.runs, six.balls, six.fours, six.ones], equals([6, 3, 1, 2]));
      expect(four.runs + six.runs, equals(second.runs));
      final five = second.batters[5]!;
      expect([five.runs, five.balls, five.isOut], equals([0, 0, false]));
      final ali = second.bowlers[1]!;
      expect([ali.legalBalls, ali.runsConceded, ali.wickets],
          equals([6, 21, 1]));
      final bilal = second.bowlers[2]!;
      expect([bilal.legalBalls, bilal.runsConceded], equals([1, 1]));
    });

    test('strike and over-end handling in the chase', () {
      // after ball 6 (odd run on the last ball) Farhan (6) is back on strike
      final afterOver = InningsState.start(second.config);
      var s = afterOver;
      for (final b in secondInningsBalls.take(6)) {
        s = s.apply(b);
      }
      expect(s.striker, equals(6));
      expect(s.nonStriker, equals(5));
      expect(s.needsNewBowler, isTrue);
    });
  });

  group('result', () {
    test('Bravo win by one wicket', () {
      final r = computeMatchResult(
        firstTeamId: 1,
        firstTeamName: 'Alpha',
        secondTeamId: 2,
        secondTeamName: 'Bravo',
        first: first,
        second: second,
      )!;
      expect(r.text, equals('Bravo won by 1 wicket'));
      expect(r.winnerTeamId, equals(2));
    });
  });

  group('replay', () {
    test('rebuilding each innings from its stored deliveries gives the same '
        'scorecard', () {
      final again = replayInnings(
        alphaBatting,
        first.deliveries.map((x) => x.input),
      );
      expect(again.runs, equals(first.runs));
      expect(again.wickets, equals(first.wickets));
      expect(again.oversText, equals(first.oversText));
      expect(again.batters[3]!.runs, equals(first.batters[3]!.runs));
      expect(again.bowlers[4]!.runsConceded, equals(first.bowlers[4]!.runsConceded));
      final again2 = replayInnings(
        second.config,
        second.deliveries.map((x) => x.input),
      );
      expect(again2.runs, equals(second.runs));
      expect(again2.status, equals(second.status));
    });
  });
}
