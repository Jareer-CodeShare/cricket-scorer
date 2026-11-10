/// Text helpers for the scorecard.
library;

import 'innings.dart';
import 'models.dart';

/// Standard scorecard wording for how a batter was dismissed, e.g.
/// "c Rana b Ali", "b Ali", "lbw b Ali", "st Khan b Ali", "run out (Rana)".
/// [nameOf] turns a player id into a display name.
String dismissalText(BatterInnings b, String Function(int id) nameOf) {
  final w = b.wicket;
  if (!b.isOut || w == null) return 'not out';
  final bowler = b.bowlerId == null ? '' : nameOf(b.bowlerId!);
  final fielder = b.fielderId == null ? null : nameOf(b.fielderId!);
  switch (w) {
    case WicketType.bowled:
      return 'b $bowler';
    case WicketType.lbw:
      return 'lbw b $bowler';
    case WicketType.caught:
      if (fielder == null) return 'caught b $bowler';
      return b.fielderId == b.bowlerId ? 'c & b $bowler' : 'c $fielder b $bowler';
    case WicketType.stumped:
      return fielder == null ? 'st b $bowler' : 'st $fielder b $bowler';
    case WicketType.runOut:
      return fielder == null ? 'run out' : 'run out ($fielder)';
  }
}

/// "1.2" style helper for a nullable rate: "-" when undefined.
String formatRate(double? value) =>
    value == null ? '-' : value.toStringAsFixed(2);

/// Strike rate with one decimal: "133.3", or "-" for a batter with no balls.
String formatStrikeRate(double? value) =>
    value == null ? '-' : value.toStringAsFixed(1);
