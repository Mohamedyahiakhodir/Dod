import 'package:flutter/material.dart';

import '../l10n.dart';
import 'theme.dart';

class Section extends StatelessWidget {
  const Section(this.title, this.children, {super.key});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
              child: Text(title!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: .5)),
            ),
          ...children,
        ]),
      );
}

class FxSlider extends StatelessWidget {
  const FxSlider({super.key, required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.onEnd, this.fmt, this.divisions, this.def});
  final String label;
  final double value, min, max;
  final double? def;
  final int? divisions;
  final String Function(double)? fmt;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onEnd;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13.5)),
          GestureDetector(
            onDoubleTap: def == null ? null : () { onChanged(def!); onEnd?.call(def!); },
            child: Directionality(textDirection: TextDirection.ltr, child: Text(fmt != null ? fmt!(v) : v.toStringAsFixed(0), style: const TextStyle(color: C.accent, fontFeatures: [FontFeature.tabularFigures()]))),
          ),
        ]),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Slider(value: v, min: min, max: max, divisions: divisions, onChanged: onChanged, onChangeEnd: onEnd),
        ),
      ]),
    );
  }
}

class FxSwitch extends StatelessWidget {
  const FxSwitch(this.label, this.value, this.onChanged, {super.key, this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 14.5)),
                if (hint != null) Text(hint!, style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
            Switch(value: value, onChanged: onChanged),
          ]),
        ),
      );
}

class ChipRow<T> extends StatelessWidget {
  const ChipRow({super.key, required this.options, required this.value, required this.onChanged, this.scroll = false});
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final o in options)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8, bottom: 6),
          child: GestureDetector(
            onTap: () => onChanged(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: o.$1 == value ? C.accent : C.surface2, borderRadius: BorderRadius.circular(999), border: Border.all(color: o.$1 == value ? Colors.transparent : C.line)),
              child: Text(o.$2, style: TextStyle(fontSize: 13, fontWeight: o.$1 == value ? FontWeight.w700 : FontWeight.w400, color: o.$1 == value ? C.accentInk : C.text)),
            ),
          ),
        ),
    ];
    return scroll ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips)) : Wrap(children: chips);
  }
}

class PillButton extends StatelessWidget {
  const PillButton(this.label, this.onTap, {super.key, this.icon, this.primary = false, this.danger = false, this.small = false, this.block = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, danger, small, block;
  @override
  Widget build(BuildContext context) {
    final bg = primary ? C.accent : danger ? C.bad : C.surface2;
    final fg = primary ? C.accentInk : Colors.white;
    final btn = Material(
      color: bg,
      shape: StadiumBorder(side: primary || danger ? BorderSide.none : const BorderSide(color: C.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: small ? 38 : 46),
          padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
            Flexible(child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: small ? 13 : 14), textAlign: TextAlign.center)),
          ]),
        ),
      ),
    );
    return block ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class TileButton extends StatelessWidget {
  const TileButton(this.label, this.icon, this.onTap, {super.key, this.danger = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Material(
        color: C.surface2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 22, color: danger ? C.bad : Colors.white),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: danger ? C.bad : Colors.white)),
            ]),
          ),
        ),
      );
}

class TileGrid extends StatelessWidget {
  const TileGrid(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.45,
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        children: children,
      );
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6, bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2), child: Text(text, style: const TextStyle(fontSize: 12.5, color: C.muted)));
}

Future<String?> promptDialog(BuildContext context, String title, String initial) {
  final ctl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v.trim())),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          PillButton(L('إلغاء', 'Cancel'), () => Navigator.pop(c)),
          const SizedBox(width: 10),
          PillButton(L('حفظ', 'Save'), () => Navigator.pop(c, ctl.text.trim()), primary: true),
        ]),
      ]),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String msg, {String? ok, bool danger = false}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(msg, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          PillButton(L('إلغاء', 'Cancel'), () => Navigator.pop(c, false)),
          const SizedBox(width: 10),
          PillButton(ok ?? L('تأكيد', 'Confirm'), () => Navigator.pop(c, true), primary: !danger, danger: danger),
        ]),
      ]),
    ),
  );
  return r ?? false;
}

void showMsg(BuildContext context, String msg) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.center), duration: const Duration(milliseconds: 2400), margin: const EdgeInsets.fromLTRB(24, 0, 24, 90)));
}

String fmtTime(double s, {int dec = 0}) {
  if (!s.isFinite || s < 0) s = 0;
  final m = s ~/ 60, sec = s - m * 60;
  final secStr = dec > 0 ? sec.toStringAsFixed(dec).padLeft(3 + dec - 1, '0') : sec.floor().toString().padLeft(2, '0');
  return '${m.toString().padLeft(2, '0')}:$secStr';
}

String fmtDur(double s) {
  final t = s.round(), h = t ~/ 3600, m = (t % 3600) ~/ 60, sec = t % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
}

String fmtBytes(int b) => b < 1024 ? '$b B' : b < 1048576 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB';
