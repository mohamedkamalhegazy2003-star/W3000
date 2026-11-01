import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../core/strings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text(tr('settings'))), body: const SettingsBody());
  }
}

class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Directionality(
        textDirection: s.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(tr('language'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'ar', label: Text(tr('arabic'))),
                  ButtonSegment(value: 'en', label: Text(tr('english'))),
                ],
                selected: {s.locale.languageCode},
                onSelectionChanged: (v) => s.setLocale(v.first),
              ),
              const SizedBox(height: 24),
              Text(tr('theme'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(tr('system'))),
                  ButtonSegment(value: ThemeMode.light, label: Text(tr('light'))),
                  ButtonSegment(value: ThemeMode.dark, label: Text(tr('dark'))),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => s.setThemeMode(v.first),
              ),
              const SizedBox(height: 24),
              Text(tr('translateTo'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'ar', label: Text(tr('arabic'))),
                  ButtonSegment(value: 'en', label: Text(tr('english'))),
                ],
                selected: {s.translateTarget},
                onSelectionChanged: (v) => s.setTranslateTarget(v.first),
              ),
            ],
        ),
      ),
    );
  }
}
