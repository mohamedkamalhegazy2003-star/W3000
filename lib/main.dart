import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

import 'core/settings.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  pdfrxFlutterInitialize();
  await AppSettings.instance.load();
  runApp(const WpdfApp());
}

class WpdfApp extends StatelessWidget {
  const WpdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => MaterialApp(
        title: 'WPDF',
        debugShowCheckedModeBanner: false,
        locale: s.locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: s.themeMode,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
