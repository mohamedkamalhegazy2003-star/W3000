import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// On-device translation (Arabic <-> English) powered by ML Kit.
class TranslateService {
  static final OnDeviceTranslatorModelManager _models = OnDeviceTranslatorModelManager();

  static TranslateLanguage _lang(String code) =>
      code == 'ar' ? TranslateLanguage.arabic : TranslateLanguage.english;

  /// Cheap script detection: Arabic letters vs everything else.
  static String detectLanguage(String text) {
    var ar = 0;
    var other = 0;
    for (final r in text.runes) {
      if (r >= 0x0600 && r <= 0x06FF) {
        ar++;
      } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
        other++;
      }
    }
    return ar > other ? 'ar' : 'en';
  }

  static Future<bool> modelsReady(String a, String b) async {
    final x = await _models.isModelDownloaded(_lang(a).bcpCode);
    final y = await _models.isModelDownloaded(_lang(b).bcpCode);
    return x && y;
  }

  static Future<void> ensureModels(String a, String b) async {
    for (final code in {a, b}) {
      final bcp = _lang(code).bcpCode;
      if (!await _models.isModelDownloaded(bcp)) {
        await _models.downloadModel(bcp, isWifiRequired: false);
      }
    }
  }

  /// Translates [text] into [target]; the source language is auto detected
  /// (Arabic <-> English only).
  static Future<String> translate(String text, String target) async {
    final source = detectLanguage(text);
    if (source == target) return text;
    await ensureModels(source, target);
    final translator = OnDeviceTranslator(
      sourceLanguage: _lang(source),
      targetLanguage: _lang(target),
    );
    try {
      // Translate paragraph by paragraph to keep the layout and stay under limits.
      final parts = text.split(RegExp(r'\n+'));
      final out = <String>[];
      for (final part in parts) {
        final t = part.trim();
        if (t.isEmpty) continue;
        out.add(await translator.translateText(t));
      }
      return out.join('\n\n');
    } finally {
      await translator.close();
    }
  }
}
