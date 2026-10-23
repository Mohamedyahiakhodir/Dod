import 'dart:math' as math;
import 'dart:typed_data';

import '../models/fx.dart';
import 'biquad.dart';
import 'dynamics.dart';
import 'effects.dart';
import 'loudness.dart';
import 'pcm.dart';
import 'wav.dart';

double fxTailSeconds(FxSettings fx) {
  var t = 0.05;
  if (fx.revOn) t = math.max(t, fx.revDecay + fx.revPre / 1000 + 0.2);
  if (fx.echoOn) {
    final fb = (fx.echoFb / 100).clamp(0.05, 0.92);
    t = math.max(t, math.min(8.0, fx.echoTime / 1000 * (math.log(0.01) / math.log(fb)).ceil()));
  }
  return math.min(t, 10);
}

/// Apply the live (non-clean) part of the effects chain. Returns a new [Pcm].
Pcm applyFx(Pcm src, FxSettings fx, {bool withTail = true}) {
  final sr = src.sr;
  final tail = withTail ? (fxTailSeconds(fx) * sr).round() : 0;
  var chs = [
    for (final c in src.ch)
      () {
        final o = Float32List(c.length + tail);
        o.setRange(0, c.length, c);
        return o;
      }()
  ];
  if (fx.gain != 0) {
    final g = dbToGain(fx.gain);
    for (final c in chs) {
      for (var i = 0; i < c.length; i++) {
        c[i] *= g;
      }
    }
  }
  for (final c in chs) {
    if (fx.hpfOn) {
      Biquad(BqType.highpass, fx.hpfF, 0.707, 0, sr).process(c);
      Biquad(BqType.highpass, fx.hpfF, 0.707, 0, sr).process(c);
    }
    if (fx.lpfOn) Biquad(BqType.lowpass, fx.lpfF, 0.707, 0, sr).process(c);
    if (fx.humOn) {
      for (var k = 1; k <= 3; k++) {
        if (fx.humF * k < sr / 2.2) Biquad(BqType.notch, fx.humF * k, 30, 0, sr).process(c);
      }
    }
    if (fx.eqOn) {
      for (var i = 0; i < 7; i++) {
        if (fx.eq[i].abs() < 0.05) continue;
        final type = i == 0 ? BqType.lowshelf : i == 6 ? BqType.highshelf : BqType.peaking;
        Biquad(type, eqFreqs[i], i == 0 || i == 6 ? 0.7 : 1.0, fx.eq[i], sr).process(c);
      }
    }
  }
  if (fx.warmOn) saturate(chs, fx.warm);
  if (fx.compOn) {
    compress(chs, sr, threshold: fx.th, ratio: fx.ratio, attackMs: fx.attack, releaseMs: fx.release, knee: fx.knee, makeupDb: fx.makeup);
  }
  if (fx.ringOn) ringMod(chs, sr, fx.ringF);

  final wantStereo = chs.length == 1 && (fx.revOn || fx.chorusOn);
  if (wantStereo) chs = [chs[0], Float32List.fromList(chs[0])];
  if (fx.revOn || fx.echoOn || fx.chorusOn) {
    final dry = [for (final c in chs) Float32List.fromList(c)];
    Float32List mono() {
      final m = Float32List(dry[0].length);
      for (final d in dry) {
        for (var i = 0; i < m.length; i++) {
          m[i] += d[i] / dry.length;
        }
      }
      return m;
    }

    if (fx.echoOn) {
      final k = fx.echoMix / 100;
      for (var ci = 0; ci < chs.length; ci++) {
        final w = echoWet(dry[ci], sr, fx.echoTime, fx.echoFb, fx.echoTone);
        for (var i = 0; i < w.length; i++) {
          chs[ci][i] += w[i] * k;
        }
      }
    }
    if (fx.chorusOn) {
      final w = chorusWet(mono(), sr, fx.chDepth, fx.chRate), k = fx.chMix / 100;
      for (var ci = 0; ci < chs.length; ci++) {
        final ww = w[ci % 2];
        for (var i = 0; i < ww.length; i++) {
          chs[ci][i] += ww[i] * k;
        }
      }
    }
    if (fx.revOn) {
      final w = reverbWet(mono(), sr, fx), k = fx.revMix / 100 * 1.3;
      for (var ci = 0; ci < chs.length; ci++) {
        final ww = w[ci % 2];
        for (var i = 0; i < ww.length; i++) {
          chs[ci][i] += ww[i] * k;
        }
      }
    }
  }
  return Pcm(chs, sr);
}

class RenderOut {
  RenderOut(this.pcm, this.loudness);
  final Pcm pcm;
  final Loudness loudness;
}

/// Loudness normalisation + limiter + fades. Modifies [p] in place.
Loudness finalizeAudio(Pcm p, FxSettings fx) {
  if (fx.normOn) {
    final info = measureLoudness(p);
    if (info.lufs.isFinite) {
      final g = dbToGain((fx.normTarget - info.lufs).clamp(-30.0, 30.0));
      for (final c in p.ch) {
        for (var i = 0; i < c.length; i++) {
          c[i] *= g;
        }
      }
    }
  }
  limit(p.ch, p.sr, fx.normOn ? fx.normCeil : -0.3);
  applyFades(p.ch, p.sr, fx.fadeIn, fx.fadeOut);
  return measureLoudness(p);
}

class RenderJob {
  RenderJob(this.src, this.fx, {this.bits = 16, this.wantWav = true, this.selStart = -1, this.selEnd = -1});
  final Pcm src;
  final FxSettings fx;
  final int bits;
  final bool wantWav;
  final int selStart, selEnd;
}

class RenderResult {
  RenderResult(this.pcm, this.loudness, this.wav);
  final Pcm pcm;
  final Loudness loudness;
  final Uint8List? wav;
}

/// Full pipeline (isolate entry point): chain -> normalise -> limit -> fades -> WAV bytes.
RenderResult runRender(RenderJob j) {
  var src = j.src;
  if (j.selStart >= 0 && j.selEnd > j.selStart) src = src.sliceSamples(j.selStart, j.selEnd);
  final p = applyFx(src, j.fx);
  final info = finalizeAudio(p, j.fx);
  return RenderResult(p, info, j.wantWav ? encodeWav(p, bits: j.bits) : null);
}
