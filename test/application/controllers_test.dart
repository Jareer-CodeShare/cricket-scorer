// Tests for the application layer using in-memory storage: the full demo match
// scored through the controllers, and "close and reopen" checked by loading the
// saved data into brand-new controllers.
import 'package:cricket_scorer/application/scoring_controller.dart';
import 'package:cricket_scorer/application/setup_controller.dart';
import 'package:cricket_scorer/data/memory_repositories.dart';
import 'package:cricket_scorer/domain/errors.dart';
import 'package:cricket_scorer/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fresh "app": storage plus the controllers that sit on it.
class Env {
  Env() {
    final store = MemoryStore();
    teams = MemoryTeamRepository(store);
    players = MemoryPlayerRepository(store);
    matches = MemoryMatchRepository(store);
  }

  late final MemoryTeamRepository teams;
  late final MemoryPlayerRepository players;
  late final MemoryMatchRepository matches;

  SetupController setup() => SetupController(teams, players, matches);
  ScoringController scoring() => ScoringController(matches, teams, players);
}

/// Alpha = Ali, Bilal, Chand; Bravo = Dawood, Emad, Farhan (as in the unit
/// test of the demo match).
class Names {
  late int alpha, bravo, ali, bilal, chand, dawood, emad, farhan;
}

Future<Names> seed(SetupController setup) async {
  final n = Names();
  await setup.load();
  n.alpha = (await setup.createTeam('Alpha')).id;
  n.bravo = (await setup.createTeam('Bravo')).id;
  await setup.addPlayer(n.alpha, 'Ali');
  await setup.addPlayer(n.alpha, 'Bilal');
  await setup.addPlayer(n.alpha, 'Chand');
  await setup.addPlayer(n.bravo, 'Dawood');
  await setup.addPlayer(n.bravo, 'Emad');
  await setup.addPlayer(n.bravo, 'Farhan');
  int id(int team, String name) =>
      setup.playersOf(team).firstWhere((p) => p.name == name).id;
  n.ali = id(n.alpha, 'Ali');
  n.bilal = id(n.alpha, 'Bilal');
  n.chand = id(n.alpha, 'Chand');
  n.dawood = id(n.bravo, 'Dawood');
  n.emad = id(n.bravo, 'Emad');
  n.farhan = id(n.bravo, 'Farhan');
  return n;
}

Future<MatchInfo> startDemo(SetupController setup, Names n) => setup.startMatch(
      name: 'Demo match',
      date: DateTime(2026, 11, 9),
      overs: 2,
      teamAId: n.alpha,
      teamBId: n.bravo,
      battingFirstTeamId: n.alpha,
    );

Future<void> ball(
  ScoringController c, {
  int bat = 0,
  ExtraType extra = ExtraType.none,
  int extraRuns = 0,
  WicketType? wicket,
  int? out,
  int? fielder,
}) async {
  final message = await c.recordBall(
    runsOffBat: bat,
    extra: extra,
    extraRuns: extraRuns,
    wicket: wicket,
    dismissedId: out,
    fielderId: fielder,
  );
  expect(message, isNull);
}

/// Plays the whole demo match through the controller.
Future<void> playDemo(ScoringController c, Names n) async {
  // ---- first innings: Alpha bat ----
  c.pickStriker(n.ali);
  c.pickNonStriker(n.bilal);
  c.pickBowler(n.dawood);
  await ball(c, bat: 1);
  expect(c.strikerId, equals(n.bilal)); // odd run: strike changed
  await ball(c, extra: ExtraType.wide);
  await ball(c, bat: 4);
  await ball(c);
  await ball(c, extra: ExtraType.noBall, bat: 2);
  await ball(c, wicket: WicketType.caught, fielder: n.emad);
  expect(c.needsSelection, isTrue); // a new batter is needed
  expect(c.readyToScore, isFalse);
  expect(c.batterCandidates(forStriker: true), equals([n.chand]));
  c.pickStriker(n.chand);
  await ball(c, bat: 6);
  await ball(c, extra: ExtraType.bye, extraRuns: 1); // sixth legal ball
  expect(c.needsSelection, isTrue); // next bowler needed
  expect(c.bowlerCandidates(), equals([n.emad, n.farhan]));
  c.pickBowler(n.emad);
  await ball(c, bat: 1);
  await ball(c, extra: ExtraType.legBye, extraRuns: 2);
  await ball(c, bat: 1);
  await ball(c,
      wicket: WicketType.runOut, out: n.ali, bat: 1, fielder: n.farhan);

  expect(c.state!.isComplete, isTrue);
  expect(c.canStartSecondInnings, isTrue);

  // ---- second innings: Bravo chase 22 ----
  expect(await c.startSecondInnings(), isNull);
  expect(c.current!.info.number, equals(2));
  expect(c.state!.target, equals(22));
  c.pickStriker(n.dawood);
  c.pickNonStriker(n.emad);
  c.pickBowler(n.ali);
  await ball(c, bat: 6);
  await ball(c, bat: 6);
  await ball(c, bat: 4);
  await ball(c, wicket: WicketType.bowled);
  c.pickStriker(n.farhan);
  await ball(c, bat: 4);
  await ball(c, bat: 1);
  expect(c.bowlerCandidates().contains(n.ali), isFalse);
  c.pickBowler(n.bilal);
  await ball(c, bat: 1); // reaches the target
}

void main() {
  group('setup', () {
    test('teams and players are saved and reloaded by a new controller', () async {
      final env = Env();
      final n = await seed(env.setup());
      // "close and reopen the app": a brand-new controller on the same storage
      final reopened = env.setup();
      await reopened.load();
      expect(reopened.teams.map((t) => t.name).toList(),
          equals(['Alpha', 'Bravo']));
      expect(reopened.playersOf(n.alpha).map((p) => p.name).toList(),
          equals(['Ali', 'Bilal', 'Chand']));
    });

    test('rejects empty and duplicate names and oversize teams', () async {
      final env = Env();
      final setup = env.setup();
      await setup.load();
      await setup.createTeam('Alpha');
      expect(() => setup.createTeam('  '), throwsA(isA<SetupException>()));
      expect(() => setup.createTeam('alpha'), throwsA(isA<SetupException>()));
      final id = setup.teams.single.id;
      await setup.addPlayer(id, 'Ali');
      expect(() => setup.addPlayer(id, 'ALI'), throwsA(isA<SetupException>()));
      for (var i = 2; i <= 11; i++) {
        await setup.addPlayer(id, 'P$i');
      }
      expect(() => setup.addPlayer(id, 'P12'), throwsA(isA<SetupException>()));
    });

    test('an incomplete team cannot start a match', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final small = (await setup.createTeam('Small')).id;
      await setup.addPlayer(small, 'Solo');
      expect(setup.teamProblem(small), contains('at least 3'));
      final problems = setup.matchProblems(
          name: 'x', overs: 5, teamAId: n.alpha, teamBId: small);
      expect(problems.length, equals(1));
      expect(problems.single, contains('Small'));
      expect(
        () => setup.startMatch(
          name: 'x',
          date: DateTime(2026, 11, 9),
          overs: 5,
          teamAId: n.alpha,
          teamBId: small,
          battingFirstTeamId: n.alpha,
        ),
        throwsA(isA<SetupException>()),
      );
    });

    test('match details are validated', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      expect(setup.matchProblems(name: '', overs: 0, teamAId: n.alpha, teamBId: n.alpha).length,
          equals(3));
      expect(setup.matchProblems(name: 'Final', overs: 20, teamAId: n.alpha, teamBId: n.bravo),
          isEmpty);
    });

    test('players in a saved match cannot be removed', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      await startDemo(setup, n);
      final ali = setup.playersOf(n.alpha).first;
      expect(() => setup.removePlayer(ali), throwsA(isA<SetupException>()));
    });
  });

  group('scoring a whole match', () {
    test('the demo match through the controller ends with the right result',
        () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      await playDemo(c, n);

      expect(c.matchOver, isTrue);
      expect(c.match!.resultText, equals('Bravo won by 1 wicket'));
      expect(c.match!.summaryText,
          equals('Alpha 21/2 (1.4) · Bravo 22/1 (1.1)'));
      expect(c.innings[0].state.runs, equals(21));
      expect(c.innings[1].state.runs, equals(22));
      expect(c.readyToScore, isFalse); // nothing more can be scored
    });

    test('a finished match can be reopened by a new controller', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      await playDemo(c, n);

      // close and reopen: nothing is shared with `c` except the storage
      final reopened = env.scoring();
      await reopened.load(match.id);
      expect(reopened.matchOver, isTrue);
      expect(reopened.match!.resultText, equals('Bravo won by 1 wicket'));
      expect(reopened.innings.length, equals(2));
      expect(reopened.innings[0].state.runs, equals(21));
      expect(reopened.innings[0].state.wickets, equals(2));
      expect(reopened.innings[0].state.oversText, equals('1.4'));
      expect(reopened.innings[1].state.target, equals(22));
      expect(reopened.innings[1].state.batters[n.farhan]!.runs, equals(6));
      expect(reopened.playerName(n.chand), equals('Chand'));
      expect(reopened.teamName(n.bravo), equals('Bravo'));

      // and the history list shows it as completed
      final list = env.setup();
      await list.load();
      expect(list.matches.single.status, equals(MatchStatus.completed));
    });

    test('a match closed halfway can be resumed', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      c.pickStriker(n.ali);
      c.pickNonStriker(n.bilal);
      c.pickBowler(n.dawood);
      await ball(c, bat: 1);
      await ball(c, bat: 4);

      final resumed = env.scoring();
      await resumed.load(match.id);
      expect(resumed.state!.runs, equals(5));
      expect(resumed.state!.oversText, equals('0.2'));
      expect(resumed.readyToScore, isTrue);
      expect(resumed.strikerId, equals(n.bilal));
      expect(resumed.bowlerId, equals(n.dawood));
      await ball(resumed, bat: 6);
      expect(resumed.state!.runs, equals(11));
    });
  });

  group('rules enforced through the controller', () {
    test('nothing can be scored before the players are chosen', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      expect(c.needsSelection, isTrue);
      expect(await c.recordBall(runsOffBat: 1), contains('Choose'));
      expect(c.state!.deliveries, isEmpty);
    });

    test('an illegal ball is rejected with a message and not saved', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      c.pickStriker(n.ali);
      c.pickNonStriker(n.bilal);
      c.pickBowler(n.dawood);
      final message =
          await c.recordBall(wicket: WicketType.bowled, extra: ExtraType.noBall);
      expect(message, isNotNull);
      expect(c.state!.deliveries, isEmpty);
      final stored = await env.matches.deliveries(c.current!.info.id);
      expect(stored, isEmpty);
    });

    test('the same bowler cannot bowl two overs in a row', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      c.pickStriker(n.ali);
      c.pickNonStriker(n.bilal);
      c.pickBowler(n.dawood);
      for (var i = 0; i < 6; i++) {
        await ball(c);
      }
      expect(c.bowlerCandidates().contains(n.dawood), isFalse);
      c.pickBowler(n.dawood); // the UI never offers this, but the engine refuses it
      expect(await c.recordBall(), contains('same bowler'));
    });

    test('the second innings cannot start before the first is complete',
        () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      expect(c.canStartSecondInnings, isFalse);
      expect(await c.startSecondInnings(), isNotNull);
    });
  });

  group('undo', () {
    test('undo removes the last ball and rebuilds the innings', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      expect(await c.undo(), isNotNull); // nothing to undo yet
      c.pickStriker(n.ali);
      c.pickNonStriker(n.bilal);
      c.pickBowler(n.dawood);
      await ball(c, bat: 1);
      await ball(c, bat: 4);
      expect(c.state!.runs, equals(5));
      expect(await c.undo(), isNull);
      expect(c.state!.runs, equals(1));
      expect(c.strikerId, equals(n.bilal));
      final stored = await env.matches.deliveries(c.current!.info.id);
      expect(stored.length, equals(1)); // the saved copy changed too
    });

    test('undoing the winning ball reopens the match', () async {
      final env = Env();
      final setup = env.setup();
      final n = await seed(setup);
      final match = await startDemo(setup, n);
      final c = env.scoring();
      await c.load(match.id);
      await playDemo(c, n);
      expect(c.matchOver, isTrue);
      expect(await c.undo(), isNull);
      expect(c.matchOver, isFalse);
      expect(c.match!.resultText, isNull);
      expect(c.state!.runs, equals(21));
      // The winning ball was the first of a new over, so a bowler is needed.
      expect(c.needsSelection, isTrue);
      c.pickBowler(n.bilal);
      expect(c.readyToScore, isTrue);
      final reopened = env.scoring();
      await reopened.load(match.id);
      expect(reopened.matchOver, isFalse);
      expect(reopened.state!.runs, equals(21));
      // scoring the winning run again finishes the match again
      await ball(c, bat: 1);
      expect(c.matchOver, isTrue);
      expect(c.match!.resultText, equals('Bravo won by 1 wicket'));
    });
  });
}
