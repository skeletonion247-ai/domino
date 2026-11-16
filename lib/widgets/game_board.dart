import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/domino_tile.dart';
import '../models/game_state.dart';
import 'domino_tile_widget.dart';

// Angle constants (matching the APK's Zo/ta/ia).
const double _angleH = 0.0; // 0°
const double _angleHRev = 180.0; // Zo
const double _angleVDown = 90.0; // ta
const double _angleVUp = -90.0; // ia
const String _sa = 'T';
const String _ea = 'B';

const double _tileW = 130.0;
const double _tileH = 60.0;

/// Is horizontal angle? (matches APK's aa: 0 or 180).
bool _aa(double angle) => angle == _angleH || angle == _angleHRev;

bool _isSentinel(List<String> id) =>
    (int.tryParse(id[0]) ?? 0) < 0 || (int.tryParse(id[1]) ?? 0) < 0;

/// Weighted tile count: doubles 0.5, singles 1.0 (matches APK's ua).
double _ua(List<List<String>> t, int i, [int e = 0]) {
  double h = 0;
  for (int n = e; n < i && n < t.length; n++) {
    h += t[n][0] == t[n][1] ? 0.5 : 1;
  }
  return h;
}

/// Count tiles until weighted sum EXCEEDS threshold (matches APK's ca).
int _ca(List<List<String>> t, int i, double s, [double e = 0]) {
  int h = 0;
  double n = e;
  for (int l = i; l < t.length; l++) {
    n += t[l][0] == t[l][1] ? 0.5 : 1;
    if (n > s) break;
    h += 1;
  }
  return h;
}

/// Count tiles until weighted sum >= threshold + 1 + extra (matches da).
int _da(List<List<String>> t, int i, double s, [double e = 0]) {
  int h = 0;
  double n = 0;
  for (int l = i; l < t.length; l++) {
    n += t[l][0] == t[l][1] ? 0.5 : 1;
    h += 1;
    if (n >= s + 1 + e) break;
  }
  return h;
}

/// Place tiles radiating along X (matches APK's ra).
/// `h` (goingRight) true moves the cursor LEFT (away from center on left side).
void _ra(
  List<List<String>> t,
  String i,
  Offset s,
  double e,
  bool h,
  Size n,
  List<_Pos> ha,
) {
  var l = i;
  var r = e;
  var o = s.dx;
  for (var u = 0; u < t.length; u++) {
    final id = t[u];
    final a = id[0] == l;
    var newAngle = _angleHRev;
    if (id[0] == id[1]) {
      newAngle = h ? _angleVDown : _angleVUp;
    } else {
      String tmp;
      if (r == _angleVDown || r == _angleH) {
        tmp = h ? _ea : _sa;
      } else {
        tmp = h ? _sa : _ea;
      }
      if (tmp + (a ? _ea : _sa) == _ea + _sa ||
          tmp + (a ? _ea : _sa) == _sa + _sa) {
        newAngle = h ? _angleVUp : _angleVDown;
      } else {
        newAngle = h ? _angleVDown : _angleVUp;
      }
    }
    final c =
        (_aa(r) ? n.width : n.height) / 2 +
        (_aa(newAngle) ? n.width : n.height) / 2;
    o = h ? o - c : o + c;
    ha.add(_Pos(id, o, s.dy, newAngle));
    l = a ? id[1] : id[0];
    r = newAngle;
  }
}

/// Place tiles continuing along Y (matches APK's la).
/// `h` (goingDown) true moves the cursor DOWN (+y).
void _la(
  List<List<String>> t,
  String i,
  Offset s,
  double e,
  bool h,
  Size n,
  double l,
  List<_Pos> ha,
) {
  var r = i;
  var o = e;
  var a = s.dy;
  for (var c = 0; c < t.length; c++) {
    final id = t[c];
    final u = id[0] == r;
    var newAngle = _angleHRev;
    if (id[0] == id[1]) {
      newAngle = h ? _angleHRev : _angleH;
    } else {
      String tmp;
      if (o == _angleVDown || o == _angleH) {
        tmp = h ? _sa : _ea;
      } else {
        tmp = h ? _ea : _sa;
      }
      if (tmp + (u ? _sa : _ea) == _ea + _sa ||
          tmp + (u ? _sa : _ea) == _sa + _sa) {
        newAngle = h ? _angleH : _angleHRev;
      } else {
        newAngle = h ? _angleHRev : _angleH;
      }
    }
    final d =
        (_aa(o) ? n.height : n.width) / 2 +
        (_aa(newAngle) ? n.height : n.width) / 2;
    a = h ? a + d : a - d;
    if (_isSentinel(id) && h) a += l;
    ha.add(_Pos(id, s.dx, a, newAngle));
    r = u ? id[1] : id[0];
    o = newAngle;
  }
}

/// A position produced by the layout algorithm (id = [minor, major]).
class _Pos {
  final List<String> id;
  double x;
  double y;
  double angle;

  _Pos(this.id, this.x, this.y, this.angle);
}

/// Faithful port of the APK's `na` function: computes 4-direction snake
/// positions. Chains are [minor, major] id pairs; `left`/`right` must already
/// include their sentinel ("left"/"-1" etc). `container` is the table area,
/// `centerRect` the scaled center-tile size, `clearance` = 12 * scale.
List<_Pos> _na(
  List<String> t,
  List<List<String>> i,
  List<List<String>> s,
  List<List<String>> e,
  List<List<String>> h,
  Size n,
  Size l,
  double r,
) {
  final ha = <_Pos>[_Pos(List.of(t), 0, 0, 0)];

  final a = i.length;
  final u = s.length;
  final c = h.length;
  final d = e.length;

  final pos = {
    'left': Offset.zero,
    'right': Offset.zero,
    'top': Offset.zero,
    'bottom': Offset.zero,
  };
  final f = {'left': 0.0, 'right': 0.0, 'top': 0.0, 'bottom': 0.0};
  final p = {
    'left': <String>['0', '0'],
    'right': <String>['0', '0'],
    'top': <String>['0', '0'],
    'bottom': <String>['0', '0'],
  };
  final v = {
    'left': [a, a, a],
    'right': [u, u, u],
    'top': [c, c, c],
    'bottom': [d, d, d],
  };

  final m = t[0] == t[1] ? 0.5 : 1.0;
  final g = t[0] == t[1] ? 1.0 : 0.5;
  final b = n.width / l.height - 0.5;
  final y = n.height / l.height - 1;
  final w = _ua(i, a) + m / 2;
  final k = _ua(s, u) + m / 2;
  final S = _ua(h, c) + g / 2;
  final x = _ua(e, d) + g / 2;

  var P = S > y / 2 ? 1.0 : 0.0;
  P = k > 1.5 * b ? P + 0.75 : P;
  var T = x > y / 2 ? 1.0 : 0.0;
  T = w > 1.5 * b ? T + 0.75 : T;
  var M = k > b / 2 ? 1.5 : 0.0;
  M = x > 1.5 * y ? M + 0.75 : M;
  var E = w > b / 2 ? 1.5 : 0.0;
  E = S > 1.5 * y ? E + 0.75 : E;

  // First segment counts (left/right).
  if (w > b / 2 - P || k > b / 2 - T) {
    if (w > b / 2 - P && k > b / 2 - T) {
      v['left']![0] = math.max(1, _ca(i, 0, b / 2 - P, m / 2));
      final t2 = b - _ua(i, v['left']![0]) - P;
      v['right']![0] = math.max(1, _ca(s, 0, t2 - T, m / 2));
      final e2 = math.max(0, b - _ua(s, v['right']![0]) - T);
      v['left']![0] = math.max(1, _ca(i, 0, e2 - P, m / 2));
    } else if (w > k) {
      v['left']![0] = math.max(1, _ca(i, 0, b - P - T - k, m / 2));
    } else {
      v['right']![0] = math.max(1, _ca(s, 0, b - P - T - w, m / 2));
    }
  }

  // First segment counts (top/bottom).
  if (S > y / 2 - M || x > y / 2 - E) {
    if (S > y / 2 - M && x > y / 2 - E) {
      v['top']![0] = math.max(1, _ca(h, 0, y / 2 - M, g / 2));
      final t3 = y - _ua(h, v['top']![0]) - M;
      v['bottom']![0] = math.max(1, _ca(e, 0, t3 - E, g / 2));
      final i3 = math.max(0, y - _ua(e, v['bottom']![0]) - E);
      v['top']![0] = math.max(1, _ca(h, 0, i3 - M, g / 2));
    } else if (S > x) {
      v['top']![0] = math.max(1, _ca(h, 0, y - M - E - x, g / 2));
    } else {
      v['bottom']![0] = math.max(1, _ca(e, 0, y - M - E - S, g / 2));
    }
  }

  v['left']![0] = math.min(v['left']![0], a);
  v['right']![0] = math.min(v['right']![0], u);
  v['top']![0] = math.min(v['top']![0], c);
  v['bottom']![0] = math.min(v['bottom']![0], d);

  final N = _ua(i, v['left']![0]);
  final O = _ua(s, v['right']![0]);
  final j = _ua(h, v['top']![0]);
  final C = _ua(e, v['bottom']![0]);
  final D = _da(i, v['left']![0], math.max(1.25, C));
  final A = _da(s, v['right']![0], math.max(1.25, j));
  final R = _da(h, v['top']![0], math.max(1.25, N));
  final I = _da(e, v['bottom']![0], math.max(1.25, O));
  final L = _ca(i, v['left']![0], y / 2, 1);
  final B = _ca(s, v['right']![0], y / 2, 1);
  final z = _ca(h, v['top']![0], b / 2, 1);
  final U = _ca(e, v['bottom']![0], b / 2, 1);

  v['left']![1] = math.min(v['left']![0] + math.max(D, L), a);
  v['right']![1] = math.min(v['right']![0] + math.max(A, B), u);
  v['top']![1] = math.min(v['top']![0] + math.max(R, z), c);
  v['bottom']![1] = math.min(v['bottom']![0] + math.max(I, U), d);

  final G = math.max(j, _ua(s, v['right']![1], v['right']![0]));
  final V = math.max(C, _ua(i, v['left']![1], v['left']![0]));
  final J = math.max(N, _ua(h, v['top']![1], v['top']![0]));
  final H = math.max(O, _ua(e, v['bottom']![1], v['bottom']![0]));

  if (G + V + 1 < y) {
    if (G > V) {
      final t4 = _ca(i, v['left']![0], y - G - 1, 1);
      v['left']![1] = math.max(v['left']![0] + t4, v['left']![1]);
    } else {
      final t4 = _ca(s, v['right']![0], y - V - 1, 1);
      v['right']![1] = math.max(v['right']![0] + t4, v['right']![1]);
    }
  }
  if (J + H + 1 < b) {
    if (J > H) {
      final t5 = _ca(e, v['bottom']![0], b - J - 1, 1);
      v['bottom']![1] = math.max(v['bottom']![0] + t5, v['bottom']![1]);
    } else {
      final t5 = _ca(h, v['top']![0], b - H - 1, 1);
      v['top']![1] = math.max(v['top']![0] + t5, v['top']![1]);
    }
  }

  final q = _ua(i, a, v['left']![1]);
  final W = _ua(s, u, v['right']![1]);
  final Y = _ua(h, c, v['top']![1]);
  final X = _ua(e, d, v['bottom']![1]);
  final K = _ua(i, v['left']![1], v['left']![0]);
  final dollar = _ua(s, v['right']![1], v['right']![0]);
  final Q = _ua(h, v['top']![1], v['top']![0]);
  final Z = _ua(e, v['bottom']![1], v['bottom']![0]);

  // Third segment counts.
  if (q > N + Z + m + 1 && q > N + O + m + 1) {
    final t6 = math.max(N + Z + m + 1, N + O + m + 1);
    v['left']![2] = v['left']![1] + _ca(i, v['left']![1], t6, 0);
  } else if (q >= N + O + m + 1) {
    v['left']![2] = v['left']![1] + _ca(i, v['left']![1], N + O + m + 1, 0);
  } else if (d == 0 && q > b / 2) {
    final t6 = _da(i, v['left']![1], b / 2, 0);
    final s2 = _ua(i, a, v['left']![1] + t6);
    if (_ua(i, v['left']![1], v['left']![0]) > s2) {
      v['left']![2] = v['left']![1] + t6;
    }
  }
  if (W > O + Q + m + 1 && W > N + O + m + 1) {
    final t6 = math.max(O + Q + m + 1, N + O + m + 1);
    v['right']![2] = v['right']![1] + _ca(s, v['right']![1], t6, 0);
  } else if (W >= N + O + m + 1) {
    v['right']![2] = v['right']![1] + _ca(s, v['right']![1], N + O + m + 1, 0);
  } else if (c == 0 && W > b / 2) {
    final t6 = _da(s, v['right']![1], b / 2, 0);
    final i2 = _ua(s, u, v['right']![1] + t6);
    if (_ua(s, v['right']![1], v['right']![0]) > i2) {
      v['right']![2] = v['right']![1] + t6;
    }
  }
  if (Y > C + K + g + 1 && Y > j + C + g + 1) {
    final t6 = math.max(C + K + g + 1, j + C + g + 1);
    v['top']![2] = v['top']![1] + _ca(h, v['top']![1], t6, 0);
  } else if (Y >= j + C + g + 1) {
    v['top']![2] = v['top']![1] + _ca(h, v['top']![1], j + C + g + 1, 0);
  } else if (a == 0 && Y > b / 2) {
    final t6 = _da(h, v['top']![1], y / 2, 0);
    final i2 = _ua(h, c, v['top']![1] + t6);
    if (_ua(h, v['top']![1], v['top']![0]) > i2) {
      v['top']![2] = v['top']![1] + t6;
    }
  }
  if (X > C + dollar + g + 1 && X > j + C + g + 1) {
    final t6 = math.max(C + dollar + g + 1, j + C + g + 1);
    v['bottom']![2] = v['bottom']![1] + _ca(e, v['bottom']![1], t6, 0);
  } else if (X >= j + C + g + 1) {
    v['bottom']![2] =
        v['bottom']![1] + _ca(e, v['bottom']![1], j + C + g + 1, 0);
  } else if (u == 0 && X > b / 2) {
    final t6 = _da(e, v['bottom']![1], y / 2, 0);
    final i2 = _ua(e, d, v['bottom']![1] + t6);
    if (_ua(e, v['bottom']![1], v['bottom']![0]) > i2) {
      v['bottom']![2] = v['bottom']![1] + t6;
    }
  }

  // ---- Phase 1: first segments, radiate X from center. ----
  final tt = i.sublist(0, v['left']![0]);
  final it = s.sublist(0, v['right']![0]);
  for (var F = 0; F < 2; F++) {
    final o = F == 1;
    String fromId;
    final chain = o ? it : tt;
    if (t[0] == t[1]) {
      fromId = t[0];
    } else {
      fromId = o ? t[1] : t[0];
      ha[0].angle = _angleVUp;
    }
    _ra(chain, fromId, Offset.zero, ha[0].angle, !o, l, ha);
    final last = ha[ha.length - 1];
    if (o) {
      f['right'] = last.angle;
      p['right'] = last.id;
      pos['right'] = Offset(
        _aa(f['right']!) ? last.x : last.x + l.height / 4,
        pos['right']!.dy,
      );
    } else {
      f['left'] = last.angle;
      p['left'] = last.id;
      pos['left'] = Offset(
        _aa(f['left']!) ? last.x : last.x - l.height / 4,
        pos['left']!.dy,
      );
    }
  }

  // ---- Phase 2: second segments, continue along Y. ----
  final st = i.sublist(v['left']![0], v['left']![1]);
  final et = s.sublist(v['right']![0], v['right']![1]);
  for (var F = 0; F < 2; F++) {
    final o = F == 1;
    final chain = o ? et : st;
    final fromId = o
        ? (f['right'] == _angleVDown ? p['right']![0] : p['right']![1])
        : (f['left'] == _angleVDown ? p['left']![1] : p['left']![0]);
    final start = o ? pos['right']! : pos['left']!;
    final ang = o ? f['right']! : f['left']!;
    _la(chain, fromId, start, ang, !o, l, r, ha);
    final last = ha[ha.length - 1];
    if (o) {
      f['right'] = last.angle;
      p['right'] = last.id;
      pos['right'] = Offset(
        pos['right']!.dx,
        _aa(f['right']!) ? last.y - l.height / 4 : last.y,
      );
    } else {
      f['left'] = last.angle;
      p['left'] = last.id;
      pos['left'] = Offset(
        pos['left']!.dx,
        _aa(f['left']!) ? last.y + l.height / 4 : last.y,
      );
    }
  }

  // ---- Phase 3: third segments, radiate X again. ----
  final ht = i.sublist(v['left']![1], v['left']![2]);
  final nt = s.sublist(v['right']![1], v['right']![2]);
  for (var F = 0; F < 2; F++) {
    final o = F == 1;
    final chain = o ? nt : ht;
    final fromId = o
        ? (f['right'] == _angleH ? p['right']![0] : p['right']![1])
        : (f['left'] == _angleH ? p['left']![1] : p['left']![0]);
    final start = o ? pos['right']! : pos['left']!;
    final ang = o ? f['right']! : f['left']!;
    _ra(chain, fromId, start, ang, o, l, ha);
    final last = ha[ha.length - 1];
    if (o) {
      f['right'] = last.angle;
      p['right'] = last.id;
      pos['right'] = Offset(
        _aa(f['right']!) ? last.x : last.x - l.height / 4,
        pos['right']!.dy,
      );
    } else {
      f['left'] = last.angle;
      p['left'] = last.id;
      pos['left'] = Offset(
        _aa(f['left']!) ? last.x : last.x + l.height / 4,
        pos['left']!.dy,
      );
    }
  }

  // ---- Phase 4: remaining left/right tiles, continue along Y. ----
  final rt = i.sublist(v['left']![2]);
  final ot = s.sublist(v['right']![2]);
  for (var F = 0; F < 2; F++) {
    final o = F == 1;
    final chain = o ? ot : rt;
    final fromId = o
        ? (f['right'] == _angleVDown ? p['right']![1] : p['right']![0])
        : (f['left'] == _angleVDown ? p['left']![0] : p['left']![1]);
    final start = o ? pos['right']! : pos['left']!;
    final ang = o ? f['right']! : f['left']!;
    _la(chain, fromId, start, ang, o, l, r, ha);
    final last = ha[ha.length - 1];
    if (o) {
      f['right'] = last.angle;
      p['right'] = last.id;
      pos['right'] = Offset(
        pos['right']!.dx,
        _aa(f['right']!) ? last.y + l.height / 4 : last.y,
      );
    } else {
      f['left'] = last.angle;
      p['left'] = last.id;
      pos['left'] = Offset(
        pos['left']!.dx,
        _aa(f['left']!) ? last.y - l.height / 4 : last.y,
      );
    }
  }

  // ---- Vertical chains: top (first), bottom (first). ----
  final at = h.sublist(0, v['top']![0]);
  final ut = e.sublist(0, v['bottom']![0]);
  for (var F = 0; F < 2; F++) {
    final lt = F == 1;
    final chain = lt ? at : ut;
    final fromId = lt ? t[0] : t[1];
    _la(chain, fromId, Offset.zero, ha[0].angle, !lt, l, r, ha);
    final last = ha[ha.length - 1];
    if (lt) {
      f['top'] = last.angle;
      p['top'] = last.id;
      pos['top'] = Offset(
        pos['top']!.dx,
        _aa(f['top']!) ? last.y - l.height / 4 : last.y,
      );
    } else {
      f['bottom'] = last.angle;
      p['bottom'] = last.id;
      pos['bottom'] = Offset(
        pos['bottom']!.dx,
        _aa(f['bottom']!) ? last.y + l.height / 4 : last.y,
      );
    }
  }

  // ---- Vertical chains: top/bottom second segments, radiate X. ----
  final ct = h.sublist(v['top']![0], v['top']![1]);
  final dt = e.sublist(v['bottom']![0], v['bottom']![1]);
  for (var F = 0; F < 2; F++) {
    final lt = F == 1;
    final chain = lt ? ct : dt;
    var ang = lt ? f['top']! : f['bottom']!;
    final sid = lt ? p['top']! : p['bottom']!;
    if (sid[0] == sid[1]) ang = _angleVUp;
    final fromId = (lt ? ang == _angleH : ang == _angleHRev) ? sid[0] : sid[1];
    final start = lt ? pos['top']! : pos['bottom']!;
    _ra(chain, fromId, start, ang, lt, l, ha);
    final last = ha[ha.length - 1];
    if (lt) {
      f['top'] = last.angle;
      p['top'] = last.id;
      pos['top'] = Offset(
        _aa(f['top']!) ? last.x : last.x - l.height / 4,
        last.y,
      );
    } else {
      f['bottom'] = last.angle;
      p['bottom'] = last.id;
      pos['bottom'] = Offset(
        _aa(f['bottom']!) ? last.x : last.x + l.height / 4,
        last.y,
      );
    }
  }

  // ---- Vertical chains: top/bottom third segments, continue Y. ----
  final top3 = h.sublist(v['top']![1], v['top']![2]);
  final ft = e.sublist(v['bottom']![1], v['bottom']![2]);
  for (var F = 0; F < 2; F++) {
    final lt = F == 1;
    final chain = lt ? top3 : ft;
    var ang = lt ? f['top']! : f['bottom']!;
    final sid = lt ? p['top']! : p['bottom']!;
    if (sid[0] == sid[1]) ang = _angleHRev;
    final fromId = (lt ? ang == _angleVDown : ang == _angleVUp)
        ? sid[1]
        : sid[0];
    final start = lt ? pos['top']! : pos['bottom']!;
    _la(chain, fromId, start, lt ? f['top']! : f['bottom']!, lt, l, r, ha);
    final last = ha[ha.length - 1];
    if (lt) {
      f['top'] = last.angle;
      p['top'] = last.id;
      pos['top'] = Offset(
        _aa(f['top']!) ? last.x : last.x - l.height / 4,
        last.y,
      );
    } else {
      f['bottom'] = last.angle;
      p['bottom'] = last.id;
      pos['bottom'] = Offset(
        _aa(f['bottom']!) ? last.x : last.x + l.height / 4,
        last.y,
      );
    }
  }

  return ha;
}

/// Result of building 4-direction chains from the board.
class ChainResult {
  final DominoTile center;
  final List<DominoTile> left;
  final List<DominoTile> right;
  final List<DominoTile> up;
  final List<DominoTile> down;

  ChainResult(this.center, this.left, this.right, this.up, this.down);
}

/// Rebuilds the board into 4-direction chains (left/right/up/down) from center.
/// Tiles are NOT pre-rotated: the layout algorithm computes orientation.
@visibleForTesting
ChainResult buildChain(List<PlacedTile> board) {
  final center = board.first.tile;
  final left = <DominoTile>[];
  final right = <DominoTile>[];
  final up = <DominoTile>[];
  final down = <DominoTile>[];

  for (int i = 1; i < board.length; i++) {
    final tile = board[i].tile;
    switch (board[i].side) {
      case 'left':
        left.add(tile);
        break;
      case 'right':
        right.add(tile);
        break;
      case 'top':
        up.add(tile);
        break;
      case 'bottom':
        down.add(tile);
        break;
    }
  }

  return ChainResult(center, left, right, up, down);
}

List<List<String>> _toIds(List<DominoTile> chain) {
  return [
    for (final t in chain) [t.minor.toString(), t.major.toString()],
  ];
}

DominoTile? _findTile(List<String> id, DominoTile center, ChainResult chain) {
  if (id[0] == center.minor.toString() && id[1] == center.major.toString()) {
    return center;
  }
  for (final tile in [
    ...chain.left,
    ...chain.right,
    ...chain.up,
    ...chain.down,
  ]) {
    if (id[0] == tile.minor.toString() && id[1] == tile.major.toString()) {
      return tile;
    }
  }
  return null;
}

class TilePlacement {
  final DominoTile tile;
  final Offset offset; // tile CENTER
  final bool horizontal;
  final bool isFlipped;
  final double angle;

  TilePlacement(
    this.tile,
    this.offset,
    this.horizontal,
    this.isFlipped,
    this.angle,
  );
}

class SnakeLayout {
  final List<TilePlacement> positions;
  final Rect bounds;
  final double scale;

  /// True when the smart layout was rejected (overlap) and the classic
  /// layout is being used instead.
  final bool fellBack;

  SnakeLayout(
    this.positions,
    this.bounds,
    this.scale, {
    this.fellBack = false,
  });
}

Rect _layoutBounds(List<_Pos> positions, double w, double h) {
  if (positions.isEmpty) return Rect.zero;
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in positions) {
    final pw = _aa(p.angle) ? w : h;
    final ph = _aa(p.angle) ? h : w;
    minX = math.min(minX, p.x - pw / 2);
    maxX = math.max(maxX, p.x + pw / 2);
    minY = math.min(minY, p.y - ph / 2);
    maxY = math.max(maxY, p.y + ph / 2);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Lays the chain out from the centre: segments turn after four tile-length
/// units (crosswise doubles count as half). Tiles stay inside the boundary;
/// if the whole thing can't fit, it zooms out.
SnakeLayout computeLayout(
  List<PlacedTile> board, {
  required double maxWidth,
  required double maxHeight,
  bool smart = false,
  double topRun = 3.0,
  double bottomRun = 3.0,
}) {
  if (board.isEmpty) return SnakeLayout(const [], Rect.zero, 1.0);

  const middleCount = 3;
  final middle = board.skip(1).take(middleCount - 1).toList();
  double segmentUnits(Iterable<PlacedTile> tiles) =>
      tiles.fold<double>(0, (sum, p) => sum + (p.tile.isDouble ? 0.5 : 1.0));
  final leftMiddle = segmentUnits(middle.where((p) => p.side == 'left'));
  final rightMiddle = segmentUnits(middle.where((p) => p.side == 'right'));

  final playedTiles = board.skip(1);
  final left = playedTiles.where((p) => p.side == 'left').toList();
  final right = playedTiles.where((p) => p.side == 'right').toList();
  final top = playedTiles.where((p) => p.side == 'top').toList();
  final bottom = playedTiles.where((p) => p.side == 'bottom').toList();
  final topMiddle = segmentUnits(middle.where((p) => p.side == 'top'));
  final bottomMiddle = segmentUnits(middle.where((p) => p.side == 'bottom'));

  List<TilePlacement> plan(double s, double topRun, double bottomRun,
      {bool capMiddle = false}) {
    final placements = <TilePlacement>[];
    final center = board.first.tile;
    final centerHorizontal = !center.isDouble;
    final centerW = (centerHorizontal ? _tileW : _tileH) * s;
    final centerH = (centerHorizontal ? _tileH : _tileW) * s;
    final centerHi = math.max(center.top, center.bottom);
    placements.add(
      TilePlacement(
        center,
        Offset.zero,
        centerHorizontal,
        centerHorizontal ? center.top != centerHi : false,
        centerHorizontal ? 0 : -90,
      ),
    );

    // Horizontal middle line: centre + the first run on each side. The 3rd
    // turn must get its vertical column past this line.
    double firstRunExtent(List<PlacedTile> chain, double units) {
      if (chain.isEmpty) return 0;
      var extent = 0.0;
      var n = 0;
      var u = 0.0;
      for (final p in chain) {
        final along = p.tile.isDouble ? _tileH * s : _tileW * s;
        extent += along + (n > 0 ? 2.0 : 0.0);
        n++;
        u += p.tile.isDouble ? 0.5 : 1.0;
        if (u >= units) break;
      }
      return extent;
    }

    // Practice caps the middle: each side lays only its first tile
    // horizontally, then the second tile turns. With a crossed centre that is
    // 0.5 + 1 + 1 = 2.5; with a horizontal centre it is 3.
    double firstTileUnits(List<PlacedTile> chain) =>
        chain.isEmpty ? 0 : (chain.first.tile.isDouble ? 0.5 : 1.0);
    final leftRun = capMiddle ? firstTileUnits(left) : leftMiddle;
    final rightRun = capMiddle ? firstTileUnits(right) : rightMiddle;

    final lineLeft =
        -centerW / 2 -
        (left.isNotEmpty ? 2.0 + firstRunExtent(left, leftRun) : 0.0);
    final lineRight =
        centerW / 2 +
        (right.isNotEmpty ? 2.0 + firstRunExtent(right, rightRun) : 0.0);

    _addSide(
      placements,
      left,
      0,
      centerW,
      s,
      leftRun,
      lineLimit: lineRight,
      linePassRight: true,
      vRun: topRun,
    );
    _addSide(
      placements,
      right,
      2,
      centerW,
      s,
      rightRun,
      lineLimit: lineLeft,
      linePassRight: false,
      vRun: bottomRun,
    );
    _addSide(placements, top, 1, centerH, s, topMiddle, vRun: 3.0);
    _addSide(placements, bottom, 3, centerH, s, bottomMiddle, vRun: 3.0);
    return placements;
  }

  // Build the original plan and let it settle to the board. [cap] is the
  // largest scale allowed: 0.75 keeps the classic look, 1.0 uses the full
  // native sprite resolution when the screen has room.
  SnakeLayout build(double cap, {bool capMiddle = false}) {
    var s = 0.75;
    var placements = plan(s, 3.0, 3.0, capMiddle: capMiddle);
    var bounds = _placementsBounds(placements, s);
    for (var pass = 0; pass < 3; pass++) {
      final fit = math.min(
        maxWidth * 0.94 / math.max(bounds.width, 1),
        maxHeight * 0.94 / math.max(bounds.height, 1),
      );
      final next = math.max(0.1, math.min(cap, s * fit));
      if ((next - s).abs() < 0.001) break;
      s = next;
      placements = plan(s, 3.0, 3.0, capMiddle: capMiddle);
      bounds = _placementsBounds(placements, s);
    }
    return SnakeLayout(placements, bounds, s);
  }

  // Original layout, exactly as it was: 0.75 cap, original turn pattern.
  // Practice also caps the middle row here, so the opening keeps the cap even
  // while it stays at the classic size.
  final classic = build(0.75, capMiddle: smart);
  if (!smart) return classic;

  // Smart path: plan the pattern once, then scale the whole shape to the
  // board. Planning once keeps the turn pattern identical at every scale
  // (it cannot reshuffle between moves), and scaling the finished shape fits
  // the screen exactly instead of re-planning with different gaps.
  SnakeLayout buildScaled(double cap, double topRun, double bottomRun) {
    const base = 0.75;
    final raw = plan(base, topRun, bottomRun, capMiddle: true);
    final rawBounds = _placementsBounds(raw, base);
    final fit = math.min(
      maxWidth * 0.94 / math.max(rawBounds.width, 1),
      maxHeight * 0.94 / math.max(rawBounds.height, 1),
    );
    final fitted = math.max(0.1, math.min(cap, base * fit));
    final k = fitted / base;
    return SnakeLayout(
      [
        for (final p in raw)
          TilePlacement(p.tile, p.offset * k, p.horizontal, p.isFlipped,
              p.angle),
      ],
      Rect.fromLTRB(rawBounds.left * k, rawBounds.top * k,
          rawBounds.right * k, rawBounds.bottom * k),
      fitted,
    );
  }

  // Practice: let the snake use the full native sprite size wherever the
  // screen has room. The turn pattern is unchanged, only the scale can grow.
  // The opening tiles stay exactly at the classic size, then the cap rises a
  // little per tile instead of jumping straight to native size, which looked
  // like a sudden zoom-in.
  // If the larger shape would overlap a tile, fall back to the classic
  // layout instead of letting tiles hide.
  if (board.length <= 8) return classic;
  final grow = math.min(1.0, 0.75 + (board.length - 8) * 0.02);
  final wide = buildScaled(grow, topRun, bottomRun);
  if (!_placementsOverlap(wide.positions, wide.scale)) return wide;
  return SnakeLayout(
    classic.positions,
    classic.bounds,
    classic.scale,
    fellBack: true,
  );
}

/// Which horizontal rows are already full (at least four tiles) with the
/// classic 3-tile vertical runs: [top] is the 2nd line above the middle,
/// [bottom] is the 3rd line below it. A vertical run may only grow on a side
/// whose row is already laid.
({bool top, bool bottom}) fullHorizontalRows(
  List<PlacedTile> board, {
  required double maxWidth,
  required double maxHeight,
}) {
  if (board.length < 5) return (top: false, bottom: false);
  final layout = computeLayout(
    board,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    smart: true,
  );
  final threshold = _tileH * layout.scale * 0.5;
  final rows = <double, int>{};
  for (final p in layout.positions) {
    // Same row tiles share the same centre line; round to half a pixel so
    // tiny floating point differences cannot split a row.
    final key = (p.offset.dy * 2).roundToDouble() / 2;
    rows[key] = (rows[key] ?? 0) + 1;
  }
  var top = false;
  var bottom = false;
  for (final row in rows.entries) {
    if (row.value < 4) continue;
    if (row.key < -threshold) top = true;
    if (row.key > threshold) bottom = true;
  }
  return (top: top, bottom: bottom);
}

/// Decides whether a side's vertical run may grow from 3 to 4 so the snake
/// uses the free space on tall screens instead of shrinking.
///
/// Shared by practice and online so both boards lay out identically.
({double top, double bottom}) growVerticalRuns({
  required List<PlacedTile> board,
  required Size size,
  required double top,
  required double bottom,
}) {
  if (top == 4 && bottom == 4) return (top: top, bottom: bottom);
  if (size.width >= size.height) return (top: top, bottom: bottom);

  // Never grow a vertical run before its own horizontal row is already laid.
  final full = fullHorizontalRows(
    board,
    maxWidth: size.width,
    maxHeight: size.height,
  );
  if ((top == 4 || !full.top) && (bottom == 4 || !full.bottom)) {
    return (top: top, bottom: bottom);
  }

  SnakeLayout at(double t, double b) => computeLayout(
        board,
        maxWidth: size.width,
        maxHeight: size.height,
        smart: true,
        topRun: t,
        bottomRun: b,
      );

  var t = top;
  var b = bottom;
  var current = at(t, b);

  if (t == 3 && full.top) {
    final next = at(4, b);
    if (!next.fellBack && next.scale >= current.scale - 0.001) {
      t = 4;
      current = next;
    }
  }
  if (b == 3 && full.bottom) {
    final next = at(t, 4);
    if (!next.fellBack && next.scale >= current.scale - 0.001) {
      b = 4;
    }
  }
  return (top: t, bottom: b);
}

void _addSide(
  List<TilePlacement> out,
  List<PlacedTile> tiles,
  int initialDir,
  double centerW,
  double s,
  double middleN, {
  double? lineLimit,
  bool linePassRight = true,
  double vRun = 3.0,
}) {
  if (tiles.isEmpty) return;
  final tileW = _tileW * s;
  final tileH = _tileH * s;
  const gap = 2.0;
  const dirs = [Offset(-1, 0), Offset(0, -1), Offset(1, 0), Offset(0, 1)];

  var lastCenter = const Offset(0, 0);
  var prevDir = initialDir;
  var dir = prevDir;
  var segLeft = middleN;
  var turns = 0;
  var prevAlong = centerW;
  var prevPerp = tileH;
  Offset? tileCenter;

  // True while the vertical run would still cross the horizontal middle line.
  // [lineLimit] is the far end of that line (B) and the run must get past it.
  bool stillCrossesLine(int nextDir, PlacedTile placed) {
    if (lineLimit == null || nextDir == 0 || nextDir == 2) return false;
    final tile = placed.tile;
    final horizontal = tile.isDouble;
    final along = horizontal ? tileH : tileW;
    final perp = horizontal ? tileW : tileH;
    final slide = tile.isDouble ? perp / 4 : 0.0;
    final center =
        lastCenter +
        dirs[prevDir] * ((prevAlong - perp) / 2 + slide) +
        dirs[nextDir] * (prevPerp / 2 + along / 2 + gap);
    final half = perp / 2;
    final columnLeft = center.dx - half;
    final columnRight = center.dx + half;
    final clearance = tileH + gap;
    return linePassRight
        ? columnLeft < lineLimit + clearance
        : columnRight > lineLimit - clearance;
  }

  for (var i = 0; i < tiles.length; i++) {
    // Turns 1 and 2 keep the 4-unit count. The 3rd (vertical) turn only
    // happens once the run has passed the end of the horizontal middle line.
    if (i > 0) {
      final nextDir = (dir + 1) % 4;
      var turning = false;
      if (turns < 3) {
        if (turns == 2) {
          final blocked = stillCrossesLine(nextDir, tiles[i]);
          if (!blocked) {
            turning = true;
          } else if (segLeft <= 0) {
            segLeft = tiles[i].tile.isDouble ? 0.5 : 1.0;
          }
        } else if (segLeft <= 0) {
          turning = true;
        }
      } else if (segLeft <= 0) {
        segLeft = 4.0;
      }
      if (turning) {
        dir = nextDir;
        turns++;
        // Vertical runs default to 3 tiles; horizontal runs stay 4.
        segLeft = (nextDir == 1 || nextDir == 3) ? vRun : 4.0;
      }
    }

    final p = tiles[i];
    final tile = p.tile;
    final chainHorizontal = dir == 0 || dir == 2;
    // Doubles cross the chain; ordinary tiles follow its direction.
    final horizontal = tile.isDouble ? !chainHorizontal : chainHorizontal;
    final along = (horizontal == chainHorizontal) ? tileW : tileH;
    final perp = (horizontal == chainHorizontal) ? tileH : tileW;

    if (i == 0) {
      tileCenter = dirs[dir] * (centerW / 2 + gap + along / 2);
    } else if (dir == prevDir) {
      tileCenter = lastCenter + dirs[dir] * (prevAlong / 2 + gap + along / 2);
    } else {
      // At a turn, align the new tile with the previous tile's end and leave
      // the same clearance as a straight connection. A double at the bend
      // slides a quarter of its crosswise edge toward the previous run, so
      // only half of its outer half lines up with that run (as in fix.png).
      final doubleCornerSlide = tile.isDouble ? perp / 4 : 0.0;
      tileCenter =
          lastCenter +
          dirs[prevDir] * ((prevAlong - perp) / 2 + doubleCornerSlide) +
          dirs[dir] * (prevPerp / 2 + along / 2 + gap);
    }

    final hi = math.max(tile.top, tile.bottom);
    bool flipped;
    if (horizontal) {
      flipped = lastCenter.dx > tileCenter.dx
          ? p.connectedEnd == hi
          : p.connectedEnd != hi;
    } else {
      flipped = lastCenter.dy > tileCenter.dy
          ? p.connectedEnd != hi
          : p.connectedEnd == hi;
    }

    out.add(TilePlacement(tile, tileCenter, horizontal, flipped, 0));
    lastCenter = tileCenter;
    prevDir = dir;
    prevAlong = along;
    prevPerp = perp;
    // Crosswise doubles use about half the path length, so count as 0.5.
    segLeft -= tile.isDouble ? 0.5 : 1.0;
  }
}

Rect _placementsBounds(List<TilePlacement> placements, double s) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in placements) {
    final w = (p.horizontal ? _tileW : _tileH) * s;
    final h = (p.horizontal ? _tileH : _tileW) * s;
    minX = math.min(minX, p.offset.dx - w / 2);
    maxX = math.max(maxX, p.offset.dx + w / 2);
    minY = math.min(minY, p.offset.dy - h / 2);
    maxY = math.max(maxY, p.offset.dy + h / 2);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// True when any two placed tiles visibly overlap. Used to reject a wider
/// layout instead of letting tiles hide behind each other.
bool _placementsOverlap(List<TilePlacement> placements, double s) {
  final rects = [
    for (final p in placements)
      Rect.fromCenter(
        center: p.offset,
        width: (p.horizontal ? _tileW : _tileH) * s,
        height: (p.horizontal ? _tileH : _tileW) * s,
      ),
  ];
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final inter = rects[i].intersect(rects[j]);
      if (inter.isEmpty) continue;
      if (inter.width * inter.height > 1.0) return true;
    }
  }
  return false;
}

bool _hasOverlap(List<_Pos> positions, double w, double h) {
  final rects = [
    for (final p in positions)
      Rect.fromCenter(
        center: Offset(p.x, p.y),
        width: _aa(p.angle) ? w : h,
        height: _aa(p.angle) ? h : w,
      ),
  ];
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final inter = rects[i].intersect(rects[j]);
      if (inter.isEmpty) continue;
      if (inter.width * inter.height > 0.5) return true;
    }
  }
  return false;
}

class GameBoard extends StatelessWidget {
  final List<PlacedTile> board;

  /// Lets a grown snake use the full native sprite size (practice mode).
  /// Online leaves it off so its layout is untouched.
  final bool smart;

  /// Vertical run length for the top line (3 keeps the classic snake; 4
  /// fills the free band above on tall screens).
  final double topRun;

  /// Vertical run length for the bottom line, independent of [topRun].
  final double bottomRun;

  /// Builds the visual for a placed tile. When omitted the code-drawn
  /// [DominoTileWidget] is used.
  final Widget Function(
    DominoTile tile, {
    required bool horizontal,
    required bool isFlipped,
    required double scale,
  })?
  tileBuilder;

  const GameBoard({
    super.key,
    required this.board,
    this.smart = false,
    this.topRun = 3.0,
    this.bottomRun = 3.0,
    this.tileBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (board.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.casino_rounded,
              color: Colors.white.withValues(alpha: 0.15),
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              'Place the first tile',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = computeLayout(
          board,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          smart: smart,
          topRun: topRun,
          bottomRun: bottomRun,
        );
        final bounds = layout.bounds;
        final scale = layout.scale;
        final seenTileIds = <String, int>{};
        final positionKeys = <Key>[];
        for (final pos in layout.positions) {
          final id = '${pos.tile.top}-${pos.tile.bottom}';
          final occurrence = seenTileIds[id] ?? 0;
          seenTileIds[id] = occurrence + 1;
          positionKeys.add(ValueKey('$id-$occurrence'));
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // DEBUG: boundary guide — remove once the snake is approved.
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0x332E94EA),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < layout.positions.length; i++)
              _buildAnimatedTile(
                layout.positions[i],
                positionKeys[i],
                bounds,
                scale,
                constraints,
                tileBuilder,
              ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedTile(
    TilePlacement pos,
    Key key,
    Rect bounds,
    double scale,
    BoxConstraints constraints,
    Widget Function(
      DominoTile tile, {
      required bool horizontal,
      required bool isFlipped,
      required double scale,
    })?
    tileBuilder,
  ) {
    return AnimatedPositioned(
      key: key,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      left:
          (constraints.maxWidth - bounds.width) / 2 +
          pos.offset.dx -
          bounds.left -
          (pos.horizontal ? _tileW : _tileH) * scale / 2,
      top:
          (constraints.maxHeight - bounds.height) / 2 +
          pos.offset.dy -
          bounds.top -
          (pos.horizontal ? _tileH : _tileW) * scale / 2,
      width: (pos.horizontal ? _tileW : _tileH) * scale,
      height: (pos.horizontal ? _tileH : _tileW) * scale,
      child:
          tileBuilder?.call(
            pos.tile,
            horizontal: pos.horizontal,
            isFlipped: pos.isFlipped,
            scale: scale,
          ) ??
          DominoTileWidget(
            tile: pos.tile,
            horizontal: pos.horizontal,
            isFlipped: pos.isFlipped,
            scale: scale,
          ),
    );
  }
}
