# Cricket Scorer (EF101-P02)

An offline Android cricket scoring app built with Flutter. A human scorer enters
only what happened on each ball; the software applies the rules of cricket:
legal balls, overs, strike changes, extras, wickets, innings end, target and
result. All data is stored on the device in SQLite, so it works with no Internet.

## Run it

```bash
cd cricket_scorer
flutter create --platforms=android --project-name cricket_scorer .   # adds the android/ folder (once)
flutter pub get
flutter analyze
flutter test          # 69 unit tests for the rules and controllers
flutter run           # on a phone or emulator
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

If `flutter create` adds `test/widget_test.dart`, delete that file (it tests the
default counter app, not this one).

## How to use it

1. **Teams and players**: create two teams and add at least 3 players to each
   (maximum 11). Teams are saved on the device and reused.
2. **New match**: enter a name or venue, the date, overs per side, pick the two
   teams and who bats first. A team with fewer than 3 players blocks the start.
3. **Score**: choose the two openers and the first bowler, then tap what
   happened on each ball (runs 0, 1, 2, 3, 4, 6, extras, or a wicket). After a
   wicket choose the next batter; after each over choose the next bowler.
4. When the first innings ends, tap *Start second innings*. The target and the
   required rate are shown. The match ends with a result.
5. **Match history**: every match is saved. Finished matches reopen as a full
   scorecard; an unfinished match resumes where you left it.

## Architecture

```
lib/
  domain/        pure Dart, no Flutter or SQLite: the rules engine
    models.dart        Team, Player, MatchInfo, InningsInfo, DeliveryInput, Delivery
    innings.dart       InningsState.apply / replayInnings: ALL scoring rules
    match_result.dart  target and result
    scorecard_text.dart dismissal wording
    repositories.dart  storage interfaces
    rules.dart         constants (6 balls, team size limits)
  data/          SQLite and in-memory implementations of the interfaces
  application/   ChangeNotifier controllers: SetupController, ScoringController
  ui/            Flutter screens (only talk to controllers)
test/            unit tests for domain and application
```

Dependencies point one way: `ui -> application -> domain <- data`. The domain
layer imports nothing from Flutter or SQLite, so the rules are tested in
milliseconds without a phone.

**Key idea: the delivery log is the single source of truth.** An innings is an
ordered list of deliveries. `InningsState.apply(delivery)` folds one ball into
a state and returns a new state; `replayInnings(config, deliveries)` rebuilds an
innings from its stored deliveries. Saving a ball, reopening a match and undo
all use that one mechanism, and no total is stored twice, so totals can never
disagree with the log.

### Data model

| Entity | Stored? | Fields |
| --- | --- | --- |
| Team | table `teams` | id, name |
| Player | table `players` | id, team_id, name |
| Match | table `matches` | id, name, date, overs, team A, team B, batting first, status, result, summary |
| (squads) | table `match_squads` | snapshot of both squads when the match began |
| Innings | table `innings` | id, match, number (1 or 2), batting team, bowling team, target |
| Delivery | table `deliveries` | innings, seq, striker, non-striker, bowler, runs off bat, extra type, extra runs, is_legal, wicket type, dismissed, fielder |
| BatterInnings | derived by replay | runs, balls, 1s, 2s, 3s, 4s, 6s, how out |
| BowlerSpell | derived by replay | legal balls, runs conceded, wickets |

## Scoring rules

| Event | Team runs | Batter credited | Bowler concedes | Legal ball | Batter faces a ball | Strike swaps |
| --- | --- | --- | --- | --- | --- | --- |
| 0, 1, 2, 3, 4, 6 off the bat | runs | runs (and the 1s/2s/3s/4s/6s count) | runs | Yes | Yes | Odd runs only (a 4 or 6 never swaps) |
| Wide (+ runs run) | 1 + runs | nothing | 1 + runs | **No** | **No** | If the runs run are odd |
| No-ball (+ runs off the bat) | 1 + bat runs | bat runs | 1 + bat runs | **No** | Yes | If the bat runs are odd |
| Bye | runs | nothing | 0 | Yes | Yes | Odd runs only |
| Leg-bye | runs | nothing | 0 | Yes | Yes | Odd runs only |
| Sixth legal ball | | | | ends the over | | Swaps again; the next bowler must be chosen and cannot be the one who just bowled |

Overs are shown as completed overs plus legal balls: 10 legal balls = `1.4`.
The innings ends when all out (wickets = team size - 1), when the overs are
used up, or, in the second innings, as soon as the target (first innings total
+ 1) is reached.

## Dismissals

| Wicket | Bowler gets the wicket | Batter status shown | Allowed on | Who is out |
| --- | --- | --- | --- | --- |
| Bowled | Yes | b Bowler | legal balls only | striker |
| Caught | Yes | c Fielder b Bowler (c & b if the bowler caught it) | legal balls only | striker |
| LBW | Yes | lbw b Bowler | legal balls only | striker |
| Stumped | Yes | st Fielder b Bowler | legal balls and wides, never no-balls | striker |
| Run out | **No** | run out (Fielder) | any delivery, including wides and no-balls | striker or non-striker; runs completed still count |

After a wicket the new batter takes the dismissed batter's place (striker or
non-striker position), then the usual odd-run and end-of-over swaps are applied.
The wicket is added to the team total; the next ball is blocked until a new
batter is chosen.

## Required edge cases and where they are shown

| Required | Unit test | In the app demo |
| --- | --- | --- |
| An over containing a wide | `engine_test.dart` (extras, overs), `demo_match_test.dart` | over 1 ball 2 |
| An over containing a no-ball | same | over 1 ball 5 (no-ball + 2) |
| A boundary | `engine_test.dart` | over 1 ball 3 (4) and ball 7 (6) |
| A wicket | `engine_test.dart` (wickets), demo | over 1 ball 6 (caught), over 2 ball 4 (run out) |
| A strike change | `engine_test.dart` (overs) | after the first single |
| An over ending | `engine_test.dart` (overs) | after over 1 the app asks for the next bowler |
| A successful chase | `demo_match_test.dart`, `controllers_test.dart` | second innings reaches 22 |
| Saved teams survive closing and reopening | `controllers_test.dart` (setup) | force-stop the app, reopen, open Teams |

### Demo match script (2 overs a side, 3 players each)

Teams *Alpha* (Ali, Bilal, Chand) and *Bravo* (Dawood, Emad, Farhan). Alpha bat.

**Over 1, Dawood:** `1`, Wide, `4`, `0`, No-ball +2, Wicket (Caught, fielder Emad), choose Chand, `6`, Bye 1.
**Over 2, Emad:** `1`, Leg-bye 2, `1`, Wicket (Run out, Ali, 1 run, fielder Farhan).
Alpha 21/2 in 1.4 overs. Target 22.

**Bravo chase, over 1, Ali:** `6`, `6`, `4`, Wicket (Bowled), choose Farhan, `4`, `1`.
**Over 2, Bilal:** `1`. Bravo 22/1: *Bravo won by 1 wicket*.

## Testing

```
flutter test
```

* `test/domain/engine_test.dart`: every row of the scoring and dismissal tables, input validation, innings end, replay and undo, result calculation.
* `test/domain/demo_match_test.dart`: the scripted two-innings match above, checked against hand-worked figures.
* `test/application/controllers_test.dart`: the full match through the controllers with in-memory storage, "close and reopen" by loading into brand-new controllers, undo, and set-up validation.

## Assumptions and known limitations

* Team size: 3 to 11 players; the whole saved team plays.
* A boundary (4 or 6 off the bat, or as byes) never swaps strike. A "run 4" that was actually run is entered as 4.
* A bowler may bowl any number of overs (no per-bowler over limit); a bowler cannot bowl two overs in a row; no mid-over bowler changes.
* No penalty runs, retired batters, substitutes, super over, Duckworth-Lewis-Stern, or byes off a no-ball.
* Only one device; no cloud sync.

## AI tools

This project was built with Claude Code. The architecture, the rules tables and
the tests were reviewed by the group; every member can explain every layer.
