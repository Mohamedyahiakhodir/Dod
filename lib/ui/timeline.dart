import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/editor_controller.dart';
import 'theme.dart';
import 'widgets.dart';

const _nice = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0, 1800.0];

/// CapCut-style timeline: fixed playhead in the centre, drag to scrub, pinch to zoom.
class TimelineView extends StatefulWidget {
  const TimelineView(this.c, {super.key});
  final EditorController c;
  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  EditorController get c => widget.c;
  double _w = 360;
  double _startX = 0, _startCenter = 0, _startPps = 80;
  int _pc = 0;
  String _mode = 'pan';
  bool _fitted = false;

  double _xOf(double t) => _w / 2 + (t - c.center) * c.pps;
  double _tOf(double x) => c.center + (x - _w / 2) / c.pps;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, box) {
        _w = box.maxWidth;
        if (!_fitted) {
          _fitted = true;
          c.pps = ((_w / 2 - 24) / math.max(c.duration, 0.5)).clamp(8.0, 400.0);
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            _startX = d.localFocalPoint.dx;
            _startCenter = c.center;
            _startPps = c.pps;
            _pc = d.pointerCount;
            _mode = 'pan';
            if (c.hasSel && d.pointerCount == 1) {
              final da = (_startX - _xOf(c.selA!)).abs(), db = (_startX - _xOf(c.selB!)).abs();
              if (math.min(da, db) < 28) _mode = da < db ? 'a' : 'b';
            }
            if (_mode == 'pan') c.beginDrag();
          },
          onScaleUpdate: (d) {
            if (d.pointerCount != _pc) {
              _pc = d.pointerCount;
              _startPps = c.pps;
              _startX = d.localFocalPoint.dx;
              _startCenter = c.center;
            }
            if (d.pointerCount >= 2) {
              c.pps = (_startPps * d.scale).clamp(1.0, 4000.0);
              c.tick.ping();
              return;
            }
            final x = d.localFocalPoint.dx;
            if (_mode == 'pan') {
              c.scrub(_startCenter - (x - _startX) / c.pps);
            } else {
              final t = _tOf(x).clamp(0.0, c.duration);
              if (_mode == 'a') {
                c.setSel(t, c.selB);
              } else {
                c.setSel(c.selA, t);
              }
              c.tick.ping();
            }
          },
          onScaleEnd: (d) async {
            if (_mode == 'pan') {
              await c.endDrag();
            }
          },
          onTapUp: (d) {
            final t = _tOf(d.localPosition.dx).clamp(0.0, c.duration);
            c.seek(t);
          },
          child: ClipRect(
            child: CustomPaint(
              size: Size.infinite,
              painter: _TlPainter(c, repaint: Listenable.merge([c, c.tick])),
            ),
          ),
        );
      }),
    );
  }
}

class _TlPainter extends CustomPainter {
  _TlPainter(this.c, {required Listenable repaint}) : super(repaint: repaint);
  final EditorController c;

  static TextPainter _tp(String s, Color col, double size) =>
      TextPainter(text: TextSpan(text: s, style: TextStyle(color: col, fontSize: size)), textDirection: TextDirection.ltr)..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height, center = c.center, pps = c.pps, dur = c.duration;
    const rh = 26.0;
    final top = rh + 8, bot = H - 10, mid = (top + bot) / 2, amp = (bot - top) / 2;
    double xOf(double t) => W / 2 + (t - center) * pps;
    double tOf(double x) => center + (x - W / 2) / pps;

    // ruler
    var step = _nice.last;
    for (final s in _nice) {
      if (s * pps >= 80) {
        step = s;
        break;
      }
    }
    final tickP = Paint()..color = const Color(0x24FFFFFF)..strokeWidth = 1;
    final t0 = (tOf(0) / step).floorToDouble() * step;
    for (var t = t0; t <= tOf(W) + step; t += step) {
      if (t < -1e-6 || t > dur + step) continue;
      final x = xOf(t);
      canvas.drawLine(Offset(x, rh - 7), Offset(x, rh), tickP);
      _tp(step < 1 ? fmtTime(t, dec: 2) : fmtTime(t), C.muted, 11).paint(canvas, Offset(x + 4, 4));
      for (var k = 1; k < 5; k++) {
        final xs = x + k * step * pps / 5;
        canvas.drawLine(Offset(xs, rh - 3), Offset(xs, rh), tickP);
      }
    }
    final x0 = xOf(0), x1 = xOf(dur);

    // selection tint
    if (c.hasSel) {
      canvas.drawRect(Rect.fromLTRB(xOf(c.selA!), top - 4, xOf(c.selB!), bot + 4), Paint()..color = const Color(0x2925F4EE));
    }
    canvas.drawLine(Offset(math.max(0, x0), mid), Offset(math.min(W, x1), mid), Paint()..color = const Color(0x1FFFFFFF));

    // bars
    final pk = c.peaks, pcm = c.shown, sr = pcm.sr;
    const colW = 3.0;
    final paint = Paint();
    for (var x = 0.0; x < W; x += colW) {
      final ta = tOf(x), tb = tOf(x + colW);
      if (tb < 0 || ta > dur) continue;
      final p = pk.at(pcm, (ta * sr).floor(), (tb * sr).ceil());
      final hh = math.max(1.2, math.pow(math.min(1.0, p), 0.72) * amp);
      final played = x + colW / 2 < W / 2;
      final inSel = c.hasSel && ta >= c.selA! && tb <= c.selB!;
      paint.color = p >= 0.995 ? C.bad : inSel ? Colors.white : played ? C.accent : const Color(0x9EFFFFFF);
      canvas.drawRect(Rect.fromLTWH(x, mid - hh, colW - 1, hh * 2), paint);
    }
    final dim = Paint()..color = const Color(0x73000000);
    if (x0 > 0) canvas.drawRect(Rect.fromLTRB(0, top - 4, math.min(W, x0), bot + 4), dim);
    if (x1 < W) canvas.drawRect(Rect.fromLTRB(math.max(0, x1), top - 4, W, bot + 4), dim);

    // markers
    for (final m in c.project.markers) {
      final x = xOf(m.t);
      if (x < -80 || x > W + 80) continue;
      final mp = Paint()..color = const Color(0xFFFFD60A)..strokeWidth = 1.5;
      canvas.drawLine(Offset(x, rh), Offset(x, bot + 4), mp);
      canvas.drawPath(Path()..moveTo(x, rh)..lineTo(x + 7, rh + 5)..lineTo(x, rh + 10)..close(), Paint()..color = const Color(0xFFFFD60A));
      _tp(m.name, const Color(0xFFFFD60A), 10.5).paint(canvas, Offset(x + 9, rh + 1));
    }

    // selection handles
    if (c.hasSel) {
      final hp = Paint()..color = Colors.white;
      for (var i = 0; i < 2; i++) {
        final x = xOf(i == 0 ? c.selA! : c.selB!);
        canvas.drawRect(Rect.fromLTWH(x - 1.5, top - 6, 3, bot - top + 12), hp);
        final cx = i == 0 ? x - 8 : x + 8;
        canvas.drawCircle(Offset(cx, mid), 9, hp);
        final dk = Paint()..color = const Color(0xFF111111);
        canvas.drawRect(Rect.fromLTWH(cx - 3, mid - 4, 1.6, 8), dk);
        canvas.drawRect(Rect.fromLTWH(cx + 1.4, mid - 4, 1.6, 8), dk);
      }
    }

    // playhead
    canvas.drawRect(Rect.fromLTWH(W / 2 - 1, 0, 2, H), Paint()..color = Colors.white);
    canvas.drawPath(Path()..moveTo(W / 2 - 6, 0)..lineTo(W / 2 + 6, 0)..lineTo(W / 2, 8)..close(), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _TlPainter old) => true;
}
