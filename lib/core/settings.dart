import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentFile {
  RecentFile({required this.path, required this.name, required this.openedAt, this.lastPage = 1});

  final String path;
  final String name;
  final int openedAt;
  int lastPage;

  Map<String, dynamic> toJson() =>
      {'path': path, 'name': name, 'openedAt': openedAt, 'lastPage': lastPage};

  factory RecentFile.fromJson(Map<String, dynamic> j) => RecentFile(
        path: j['path'] as String,
        name: j['name'] as String,
        openedAt: (j['openedAt'] as num).toInt(),
        lastPage: (j['lastPage'] as num?)?.toInt() ?? 1,
      );
}

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  late SharedPreferences _prefs;

  Locale locale = const Locale('ar');
  ThemeMode themeMode = ThemeMode.system;
  String translateTarget = 'ar';
  final List<RecentFile> recents = [];
  final Map<String, List<int>> bookmarks = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    locale = Locale(_prefs.getString('locale') ?? 'ar');
    themeMode = ThemeMode.values[_prefs.getInt('theme') ?? 0];
    translateTarget = _prefs.getString('translateTarget') ?? 'ar';
    final r = _prefs.getString('recents');
    if (r != null) {
      for (final e in jsonDecode(r) as List) {
        recents.add(RecentFile.fromJson(e as Map<String, dynamic>));
      }
    }
    final b = _prefs.getString('bookmarks');
    if (b != null) {
      (jsonDecode(b) as Map<String, dynamic>).forEach((k, v) {
        bookmarks[k] = (v as List).map((e) => (e as num).toInt()).toList();
      });
    }
  }

  bool get isArabic => locale.languageCode == 'ar';

  Future<void> setLocale(String code) async {
    locale = Locale(code);
    await _prefs.setString('locale', code);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setInt('theme', m.index);
    notifyListeners();
  }

  Future<void> setTranslateTarget(String code) async {
    translateTarget = code;
    await _prefs.setString('translateTarget', code);
    notifyListeners();
  }

  Future<void> _saveRecents() async {
    await _prefs.setString('recents', jsonEncode(recents.map((e) => e.toJson()).toList()));
  }

  Future<void> addRecent(String path, String name) async {
    final old = recents.where((e) => e.path == path).toList();
    final page = old.isNotEmpty ? old.first.lastPage : 1;
    recents.removeWhere((e) => e.path == path);
    recents.insert(
      0,
      RecentFile(path: path, name: name, openedAt: DateTime.now().millisecondsSinceEpoch, lastPage: page),
    );
    if (recents.length > 50) recents.removeRange(50, recents.length);
    await _saveRecents();
    notifyListeners();
  }

  int lastPageOf(String path) {
    for (final e in recents) {
      if (e.path == path) return e.lastPage;
    }
    return 1;
  }

  Future<void> saveLastPage(String path, int page) async {
    for (final e in recents) {
      if (e.path == path) e.lastPage = page;
    }
    await _saveRecents();
  }

  Future<void> removeRecent(String path) async {
    recents.removeWhere((e) => e.path == path);
    await _saveRecents();
    notifyListeners();
  }

  List<int> bookmarksOf(String path) => bookmarks[path] ?? [];

  Future<void> toggleBookmark(String path, int page) async {
    final list = bookmarks.putIfAbsent(path, () => []);
    if (list.contains(page)) {
      list.remove(page);
    } else {
      list.add(page);
      list.sort();
    }
    await _prefs.setString('bookmarks', jsonEncode(bookmarks));
    notifyListeners();
  }
}
