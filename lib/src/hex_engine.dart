import 'dart:convert';

import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Altıgen Blok: altıgen tahtaya parça yerleştir; üç yöndeki dolu sıralar
/// silinir. Eksenel (q, r) koordinat, sivri tepeli altıgenler.

const List<List<int>> kHexDirs = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];

/// Temel şekiller; döndürülmüş halleri aşağıda üretilir.
const List<List<List<int>>> _baseHex = [
  [[0, 0]],
  [[0, 0], [1, 0]],
  [[0, 0], [1, 0], [2, 0]],
  [[0, 0], [1, 0], [0, 1]], // üçgen
  [[0, 0], [1, 0], [2, -1]], // kıvrık üçlü
  [[0, 0], [1, 0], [2, 0], [3, 0]],
  [[0, 0], [1, 0], [0, 1], [1, 1]], // eşkenar dörtgen
  [[0, 0], [1, 0], [-1, 1], [0, -1]], // pervane
  [[0, 0], [1, 0], [2, 0], [2, -1]], // çengel
  [[0, 0], [1, 0], [2, 0], [1, 1]], // kemer
];

List<List<int>> _normalize(List<List<int>> cells) {
  var mq = 99, mr = 99;
  for (final c in cells) {
    if (c[1] < mr || (c[1] == mr && c[0] < mq)) {
      mr = c[1];
      mq = c[0];
    }
  }
  final out = [for (final c in cells) [c[0] - mq, c[1] - mr]];
  out.sort((a, b) => a[1] != b[1] ? a[1] - b[1] : a[0] - b[0]);
  return out;
}

/// Bütün döndürmeler; aynı olanlar tekilleştirilir. İlk kare hep (0,0).
final List<List<List<int>>> kHexShapes = () {
  final seen = <String>{};
  final out = <List<List<int>>>[];
  for (final b in _baseHex) {
    var cur = b;
    for (var k = 0; k < 6; k++) {
      final n = _normalize(cur);
      if (seen.add(jsonEncode(n))) out.add(n);
      cur = [for (final c in cur) [-c[1], c[0] + c[1]]];
    }
  }
  return out;
}();

class HexCell {
  static const empty = 0;
  static const stone = 20;
}

class HexPiece {
  final int shape;
  final int color;
  const HexPiece(this.shape, this.color);
  List<List<int>> get cells => kHexShapes[shape];
  int get size => cells.length;
}

enum HexGoalType { score, lines }

class HexLevel {
  final int radius;
  final List<int> start; // (2R+1)^2, -1 tahta dışı
  final HexGoalType goalType;
  final int target; // 0 = hedefsiz
  final int seed;
  final int difficulty;
  final bool zen;
  final int timeLimit;
  final int aiMoves;
  final int moveLimit;

  const HexLevel({
    required this.radius,
    required this.start,
    required this.goalType,
    required this.target,
    required this.seed,
    required this.difficulty,
    required this.zen,
    required this.timeLimit,
    this.aiMoves = 0,
    this.moveLimit = 0,
  });

  int get span => 2 * radius + 1;

  HexLevel withAi(int ai, int limit) => HexLevel(
        radius: radius,
        start: start,
        goalType: goalType,
        target: target,
        seed: seed,
        difficulty: difficulty,
        zen: zen,
        timeLimit: timeLimit,
        aiMoves: ai,
        moveLimit: limit,
      );
}

bool onBoard(int radius, int q, int r) => q.abs() <= radius && r.abs() <= radius && (q + r).abs() <= radius;

HexLevel generateHexLevel(LevelSpec spec) {
  final r = SeededRandom(mixSeed([spec.seed, 6161]));
  final d = spec.difficulty.clamp(1, 10);
  final radius = spec.has('big_board') ? 5 : 4;
  final span = 2 * radius + 1;
  final zen = spec.mode == GameModeId.zen;
  final endless = zen || spec.mode == GameModeId.endless || spec.mode == GameModeId.timeAttack;
  final cells = List<int>.filled(span * span, -1);
  final all = <int>[];
  for (var q = -radius; q <= radius; q++) {
    for (var rr = -radius; rr <= radius; rr++) {
      if (onBoard(radius, q, rr)) {
        final i = (q + radius) * span + (rr + radius);
        cells[i] = HexCell.empty;
        all.add(i);
      }
    }
  }
  if (!endless) {
    final stones = spec.has('obstacle') ? 2 + d : (d >= 5 ? d - 3 : 0);
    final rubble = d >= 6 ? d + 2 : 0;
    r.shuffle(all);
    var k = 0;
    for (var n = 0; n < stones + rubble && k < all.length; k++) {
      final i = all[k];
      final q = i ~/ span - radius, rr = i % span - radius;
      if (q.abs() <= 1 && rr.abs() <= 1 && (q + rr).abs() <= 1) continue; // orta boş kalsın
      cells[i] = n < stones ? HexCell.stone : 1 + r.nextInt(8);
      n++;
    }
    // Hazır dolu sıra kalmasın.
    final g = HexGame._bare(radius, cells);
    for (final line in g.lines) {
      if (line.every((i) => cells[i] != HexCell.empty)) cells[line[r.nextInt(line.length)]] = HexCell.empty;
    }
  }
  final lines = r.chance(0.5);
  return HexLevel(
    radius: radius,
    start: cells,
    goalType: lines ? HexGoalType.lines : HexGoalType.score,
    target: endless ? 0 : (lines ? 3 + d * 2 : 80 + d * 70),
    seed: spec.seed,
    difficulty: d,
    zen: zen,
    timeLimit: spec.mode == GameModeId.timeAttack ? 120 : (spec.has('timer') ? 150 + (10 - d) * 15 : 0),
  );
}

class HexPlace {
  final int lines;
  final int points;
  final List<int> cleared;
  const HexPlace(this.lines, this.points, this.cleared);
}

class HexGame {
  final HexLevel? level;
  final int radius;
  final int span;
  late List<int> grid;
  final List<HexPiece?> tray = [null, null, null];
  late SeededRandom _rng;
  int _draws = 0;
  int score = 0, linesCleared = 0, moves = 0, combo = 0, bestCombo = 0, placed = 0;

  /// Tahtadaki bütün sıralar (üç yön).
  late final List<List<int>> lines;

  /// Her karenin içinde bulunduğu sıraların numaraları.
  late final List<List<int>> linesOf;

  HexGame(HexLevel l)
      : level = l,
        radius = l.radius,
        span = l.span {
    grid = List<int>.of(l.start);
    _rng = SeededRandom(mixSeed([l.seed, 9090]));
    _buildLines();
    _refill();
  }

  HexGame._bare(this.radius, List<int> cells)
      : level = null,
        span = 2 * radius + 1 {
    grid = cells;
    _buildLines();
  }

  int idx(int q, int r) => (q + radius) * span + (r + radius);
  int qOf(int i) => i ~/ span - radius;
  int rOf(int i) => i % span - radius;
  bool inside(int q, int r) => onBoard(radius, q, r);

  void _buildLines() {
    final ls = <List<int>>[];
    for (var k = -radius; k <= radius; k++) {
      final a = <int>[], b = <int>[], c = <int>[];
      for (var t = -radius; t <= radius; t++) {
        if (inside(k, t)) a.add(idx(k, t)); // q sabit
        if (inside(t, k)) b.add(idx(t, k)); // r sabit
        final q = t, r = -k - t; // s sabit
        if (inside(q, r)) c.add(idx(q, r));
      }
      ls..add(a)..add(b)..add(c);
    }
    lines = ls;
    linesOf = List.generate(span * span, (_) => <int>[]);
    for (var li = 0; li < ls.length; li++) {
      for (final i in ls[li]) {
        linesOf[i].add(li);
      }
    }
  }

  HexPiece _draw() {
    _draws++;
    final d = level!.difficulty;
    final w = List<int>.generate(kHexShapes.length, (i) {
      final n = kHexShapes[i].length;
      if (n == 1) return (8 - d ~/ 2).clamp(2, 8);
      if (n == 2) return 6;
      if (n == 3) return 4;
      return 2 + d ~/ 3;
    });
    return HexPiece(_rng.weighted(w), 1 + _rng.nextInt(8));
  }

  void _refill() {
    for (var i = 0; i < 3; i++) {
      tray[i] = _draw();
    }
  }

  bool canPlace(HexPiece p, int q, int r) {
    for (final c in p.cells) {
      final cq = q + c[0], cr = r + c[1];
      if (!inside(cq, cr) || grid[idx(cq, cr)] != HexCell.empty) return false;
    }
    return true;
  }

  /// Dokunulan kare parçanın herhangi bir karesi olabilir.
  (int, int)? anchorCovering(HexPiece p, int q, int r) {
    for (final c in p.cells) {
      if (canPlace(p, q - c[0], r - c[1])) return (q - c[0], r - c[1]);
    }
    return null;
  }

  bool get hasMove {
    for (final p in tray) {
      if (p == null) continue;
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] == HexCell.empty && canPlace(p, qOf(i), rOf(i))) return true;
      }
    }
    return false;
  }

  HexPlace? place(int t, int q, int r) {
    final p = tray[t];
    if (p == null || !canPlace(p, q, r)) return null;
    final touched = <int>{};
    for (final c in p.cells) {
      final i = idx(q + c[0], r + c[1]);
      grid[i] = p.color;
      touched.addAll(linesOf[i]);
    }
    tray[t] = null;
    moves++;
    placed += p.size;
    final full = [for (final li in touched) if (lines[li].every((i) => grid[i] != HexCell.empty)) li];
    final cleared = <int>{for (final li in full) ...lines[li]};
    for (final i in cleared) {
      grid[i] = HexCell.empty;
    }
    var pts = p.size;
    if (full.isNotEmpty) {
      combo++;
      if (combo > bestCombo) bestCombo = combo;
      pts += cleared.length * 2 + (full.length - 1) * 30 + (combo - 1) * 10;
    } else {
      combo = 0;
    }
    score += pts;
    linesCleared += full.length;
    if (tray.every((e) => e == null)) _refill();
    if (level!.zen && !hasMove) {
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] > 0) grid[i] = HexCell.empty;
      }
    }
    return HexPlace(full.length, pts, cleared.toList());
  }

  bool get won {
    final l = level!;
    if (l.target == 0) return false;
    return l.goalType == HexGoalType.lines ? linesCleared >= l.target : score >= l.target;
  }

  int get progressValue => level!.goalType == HexGoalType.lines ? linesCleared : score;

  bool get outOfMoves => level!.moveLimit > 0 && moves >= level!.moveLimit;

  /// Basit ve hızlı en iyi hamle seçimi (ipucu ve doğrulama için).
  (int, int, int)? bestMove() {
    (int, int, int)? best;
    var bestV = -1 << 30;
    for (var t = 0; t < 3; t++) {
      final p = tray[t];
      if (p == null) continue;
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] != HexCell.empty) continue;
        final q = qOf(i), r = rOf(i);
        if (!canPlace(p, q, r)) continue;
        final v = _value(p, q, r) * 8 + (p.size * 3) - t;
        if (v > bestV) {
          bestV = v;
          best = (t, q, r);
        }
      }
    }
    return best;
  }

  int _value(HexPiece p, int q, int r) {
    final cells = [for (final c in p.cells) idx(q + c[0], r + c[1])];
    for (final i in cells) {
      grid[i] = 99;
    }
    var v = 0;
    final touched = <int>{for (final i in cells) ...linesOf[i]};
    for (final li in touched) {
      final line = lines[li];
      var empty = 0;
      for (final i in line) {
        if (grid[i] == HexCell.empty) empty++;
      }
      if (empty == 0) {
        v += 40;
      } else if (empty <= 2) {
        v += 6 - empty * 2;
      }
    }
    // Komşuluk: boşluk bırakmayan yerleştirmeyi ödüllendir.
    for (final i in cells) {
      final q0 = qOf(i), r0 = rOf(i);
      for (final dd in kHexDirs) {
        final q1 = q0 + dd[0], r1 = r0 + dd[1];
        if (!inside(q1, r1) || grid[idx(q1, r1)] != HexCell.empty) v += 1;
      }
    }
    for (final i in cells) {
      grid[i] = HexCell.empty;
    }
    return v;
  }

  // ---- Kayıt ----
  String serialize() => jsonEncode({
        'g': grid,
        't': [for (final p in tray) p == null ? null : [p.shape, p.color]],
        'd': _draws,
        's': [score, linesCleared, moves, combo, bestCombo, placed],
      });

  static HexGame restore(HexLevel l, String snap) {
    final g = HexGame(l);
    final j = jsonDecode(snap) as Map<String, dynamic>;
    g.grid = [for (final v in j['g'] as List) (v as num).toInt()];
    final t = j['t'] as List;
    for (var i = 0; i < 3; i++) {
      final e = t[i] as List?;
      g.tray[i] = e == null ? null : HexPiece((e[0] as num).toInt(), (e[1] as num).toInt());
    }
    final draws = (j['d'] as num).toInt();
    g._rng = SeededRandom(mixSeed([l.seed, 9090]));
    g._draws = 0;
    while (g._draws < draws) {
      g._draw();
    }
    final s = [for (final v in j['s'] as List) (v as num).toInt()];
    g
      ..score = s[0]
      ..linesCleared = s[1]
      ..moves = s[2]
      ..combo = s[3]
      ..bestCombo = s[4]
      ..placed = s[5];
    return g;
  }
}

/// Botla oynatır; hedefe kaç hamlede ulaştığını, ulaşamazsa -1 döner.
int simulateHexLevel(HexLevel l, {int maxMoves = 200}) {
  final g = HexGame(l);
  while (g.moves < maxMoves) {
    if (g.won) return g.moves;
    final m = g.bestMove();
    if (m == null) return -1;
    g.place(m.$1, m.$2, m.$3);
  }
  return g.won ? g.moves : -1;
}
