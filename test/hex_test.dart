import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_altigen_blok/oyun_altigen_blok.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final rules = HexRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('şekiller: tekil, bağlı ve (0,0) ile başlar', () {
    expect(kHexShapes.length, greaterThan(20));
    for (final s in kHexShapes) {
      expect(s.first, [0, 0]);
      final set = {for (final c in s) '${c[0]},${c[1]}'};
      final seen = <String>{set.first};
      final st = [s.first];
      while (st.isNotEmpty) {
        final c = st.removeLast();
        for (final d in kHexDirs) {
          final k = '${c[0] + d[0]},${c[1] + d[1]}';
          if (set.contains(k) && seen.add(k)) st.add([c[0] + d[0], c[1] + d[1]]);
        }
      }
      expect(seen.length, set.length);
    }
  });

  test('tahta: 61 kare, 27 sıra; dolu sıra silinir', () {
    final l = rules.build(planner.spec(1)).puzzle;
    final g = HexGame(l);
    expect(g.grid.where((v) => v >= 0).length, 61);
    expect(g.lines.length, 27);
    final line = g.lines.firstWhere((li) => li.length == 5 && li.every((i) => g.grid[i] == HexCell.empty));
    for (final i in line.skip(1)) {
      g.grid[i] = 3;
    }
    g.tray[0] = const HexPiece(0, 2);
    final res = g.place(0, g.qOf(line.first), g.rOf(line.first));
    expect(res, isNotNull);
    expect(res!.lines, greaterThanOrEqualTo(1));
    for (final i in line) {
      expect(g.grid[i], HexCell.empty);
    }
  });

  test('kampanya bölümleri doğrulanır ve botla çözülür', () {
    for (final lv in [1, 12, 50, 99, 230, 777, 2500, 9999, 33333, 49999]) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv: ${gl.validation.reason}');
      final l = rules.finalize(gl);
      if (l.target > 0) {
        final m = simulateHexLevel(l);
        expect(m, greaterThan(0), reason: 'bölüm $lv');
        if (l.moveLimit > 0) expect(m, lessThanOrEqualTo(l.moveLimit));
      }
    }
  });

  test('aynı tohum aynı bölüm; kayıt geri yüklenir', () {
    final a = rules.build(planner.spec(321)).puzzle;
    final b = rules.build(planner.spec(321)).puzzle;
    expect(a.start, b.start);
    final g = HexGame(a);
    for (var k = 0; k < 7; k++) {
      final m = g.bestMove();
      if (m == null) break;
      g.place(m.$1, m.$2, m.$3);
    }
    final r = HexGame.restore(a, g.serialize());
    expect(r.grid, g.grid);
    expect(r.score, g.score);
    expect([for (final p in r.tray) p?.shape], [for (final p in g.tray) p?.shape]);
    final m1 = g.bestMove(), m2 = r.bestMove();
    expect(m1, m2);
    if (m1 != null) {
      g.place(m1.$1, m1.$2, m1.$3);
      r.place(m1.$1, m1.$2, m1.$3);
      expect([for (final p in r.tray) p?.shape], [for (final p in g.tray) p?.shape]);
    }
  });

  test('anchorCovering: kenardaki kareye de yerleşir', () {
    final l = rules.build(planner.spec(2, mode: GameModeId.endless)).puzzle;
    final g = HexGame(l);
    g.tray[0] = HexPiece(kHexShapes.indexWhere((s) => s.length == 4), 1);
    final a = g.anchorCovering(g.tray[0]!, 4, 0);
    expect(a, isNotNull);
  });

  test('her kip üretilir', () {
    for (final m in rules.modes) {
      final g = rules.build(planner.spec(44, mode: m));
      expect(g.validation.ok, isTrue);
    }
  });
}
