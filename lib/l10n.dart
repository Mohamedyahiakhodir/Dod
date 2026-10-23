import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Current UI language ('ar' | 'en'). Strings are written inline as `L('عربي', 'English')`.
final ValueNotifier<String> appLang = ValueNotifier<String>('ar');

String L(String ar, String en) => appLang.value == 'ar' ? ar : en;

Future<void> loadLang() async {
  final p = await SharedPreferences.getInstance();
  appLang.value = p.getString('lang') ?? 'ar';
}

Future<void> setLang(String v) async {
  appLang.value = v;
  final p = await SharedPreferences.getInstance();
  await p.setString('lang', v);
}
