/// All non-destructive effect settings of a project.
class FxSettings {
  double gain = 0;

  // clean stage (cached, rendered in an isolate)
  bool dn = false;
  double dnAmount = 55;
  bool gate = false;
  double gateDb = -45, gateRange = -30;
  double deess = 0;

  bool hpfOn = false;
  double hpfF = 80;
  bool lpfOn = false;
  double lpfF = 12000;
  bool humOn = false;
  double humF = 50;

  bool eqOn = false;
  List<double> eq = List.filled(7, 0.0);

  bool warmOn = false;
  double warm = 25;

  bool compOn = false;
  double th = -24, ratio = 3, attack = 10, release = 200, knee = 12, makeup = 3;

  bool revOn = false;
  String revType = 'room';
  double revMix = 25, revDecay = 1.2, revPre = 15, revDamp = 50;

  bool echoOn = false;
  double echoTime = 320, echoFb = 35, echoMix = 25, echoTone = 5000;

  bool chorusOn = false;
  double chDepth = 50, chRate = 1.2, chMix = 40;

  bool ringOn = false;
  double ringF = 50;

  bool normOn = false;
  double normTarget = -16, normCeil = -1;

  double fadeIn = 0, fadeOut = 0;

  bool get cleanActive => dn || gate || deess > 0;
  String get cleanKey => '$dn|$dnAmount|$gate|$gateDb|$gateRange|$deess';

  FxSettings copy() => FxSettings.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'gain': gain, 'dn': dn, 'dnAmount': dnAmount, 'gate': gate, 'gateDb': gateDb, 'gateRange': gateRange, 'deess': deess,
        'hpfOn': hpfOn, 'hpfF': hpfF, 'lpfOn': lpfOn, 'lpfF': lpfF, 'humOn': humOn, 'humF': humF,
        'eqOn': eqOn, 'eq': eq, 'warmOn': warmOn, 'warm': warm,
        'compOn': compOn, 'th': th, 'ratio': ratio, 'attack': attack, 'release': release, 'knee': knee, 'makeup': makeup,
        'revOn': revOn, 'revType': revType, 'revMix': revMix, 'revDecay': revDecay, 'revPre': revPre, 'revDamp': revDamp,
        'echoOn': echoOn, 'echoTime': echoTime, 'echoFb': echoFb, 'echoMix': echoMix, 'echoTone': echoTone,
        'chorusOn': chorusOn, 'chDepth': chDepth, 'chRate': chRate, 'chMix': chMix,
        'ringOn': ringOn, 'ringF': ringF, 'normOn': normOn, 'normTarget': normTarget, 'normCeil': normCeil,
        'fadeIn': fadeIn, 'fadeOut': fadeOut,
      };

  FxSettings();

  factory FxSettings.fromJson(Map<String, dynamic>? j) {
    final f = FxSettings();
    if (j == null) return f;
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    bool b(String k) => j[k] == true;
    f.gain = d('gain', 0); f.dn = b('dn'); f.dnAmount = d('dnAmount', 55); f.gate = b('gate');
    f.gateDb = d('gateDb', -45); f.gateRange = d('gateRange', -30); f.deess = d('deess', 0);
    f.hpfOn = b('hpfOn'); f.hpfF = d('hpfF', 80); f.lpfOn = b('lpfOn'); f.lpfF = d('lpfF', 12000);
    f.humOn = b('humOn'); f.humF = d('humF', 50);
    f.eqOn = b('eqOn');
    final e = j['eq'];
    if (e is List && e.length == 7) f.eq = [for (final v in e) (v as num).toDouble()];
    f.warmOn = b('warmOn'); f.warm = d('warm', 25);
    f.compOn = b('compOn'); f.th = d('th', -24); f.ratio = d('ratio', 3); f.attack = d('attack', 10);
    f.release = d('release', 200); f.knee = d('knee', 12); f.makeup = d('makeup', 3);
    f.revOn = b('revOn'); f.revType = (j['revType'] as String?) ?? 'room'; f.revMix = d('revMix', 25);
    f.revDecay = d('revDecay', 1.2); f.revPre = d('revPre', 15); f.revDamp = d('revDamp', 50);
    f.echoOn = b('echoOn'); f.echoTime = d('echoTime', 320); f.echoFb = d('echoFb', 35);
    f.echoMix = d('echoMix', 25); f.echoTone = d('echoTone', 5000);
    f.chorusOn = b('chorusOn'); f.chDepth = d('chDepth', 50); f.chRate = d('chRate', 1.2); f.chMix = d('chMix', 40);
    f.ringOn = b('ringOn'); f.ringF = d('ringF', 50);
    f.normOn = b('normOn'); f.normTarget = d('normTarget', -16); f.normCeil = d('normCeil', -1);
    f.fadeIn = d('fadeIn', 0); f.fadeOut = d('fadeOut', 0);
    return f;
  }
}

class ReverbType {
  const ReverbType(this.ar, this.en, this.decay, this.damp, this.pre, this.size);
  final String ar, en;
  final double decay, damp, pre, size;
}

const reverbTypes = <String, ReverbType>{
  'room': ReverbType('غرفة', 'Room', 0.9, 55, 8, 0.7),
  'plate': ReverbType('استوديو (Plate)', 'Plate', 1.8, 25, 0, 0.9),
  'hall': ReverbType('قاعة', 'Hall', 2.8, 40, 20, 1.2),
  'mosque': ReverbType('مسجد / جامع', 'Mosque', 4.2, 35, 30, 1.5),
  'cave': ReverbType('كهف', 'Cave', 6.0, 60, 40, 1.9),
};

const eqFreqs = <double>[60, 150, 400, 1000, 3000, 6000, 12000];

class EqPreset {
  const EqPreset(this.id, this.ar, this.en, this.g);
  final String id, ar, en;
  final List<double> g;
}

const eqPresets = <EqPreset>[
  EqPreset('flat', 'مسطّح', 'Flat', [0, 0, 0, 0, 0, 0, 0]),
  EqPreset('voice', 'وضوح الصوت', 'Voice clarity', [-3, -1, -2, 1, 3, 2, 1]),
  EqPreset('warm', 'دافئ', 'Warm', [3, 3, 1, -1, -1, -2, -2]),
  EqPreset('bright', 'ساطع', 'Bright', [-2, -1, 0, 1, 2, 4, 5]),
  EqPreset('bass', 'تعزيز الجهير', 'Bass boost', [6, 4, 1, 0, 0, 0, 0]),
  EqPreset('mud', 'إزالة الاحتقان', 'De-mud', [-2, -2, -5, 0, 2, 1, 0]),
  EqPreset('podcast', 'بودكاست', 'Podcast', [-4, 1, -2, 1, 3, 1, 2]),
  EqPreset('quran', 'تلاوة', 'Recitation', [-2, 3, 2, 0, -1, 1, 2]),
  EqPreset('phone', 'هاتف', 'Telephone', [-12, -8, 0, 4, 2, -6, -12]),
];
