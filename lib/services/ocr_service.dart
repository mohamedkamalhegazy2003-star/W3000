import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_tools.dart';

/// Arabic + English OCR on top of Tesseract (traineddata is bundled in assets
/// and read by the native side, see android MainActivity).
class OcrService {
  static const String langAraEng = 'ara+eng';
  static const MethodChannel _channel = MethodChannel('wpdf/ocr');

  /// Runs OCR on a PNG/JPG file path.
  static Future<String> recognizeFile(String imagePath, {String lang = langAraEng}) async {
    final text = await _channel.invokeMethod<String>('recognize', {'path': imagePath, 'lang': lang});
    return _clean(text ?? '');
  }

  /// Renders [page] at high resolution and recognizes its text.
  static Future<String> recognizePage(PdfPage page, {String lang = langAraEng}) async {
    final Uint8List? png = await PdfTools.renderPagePng(page, scale: 3.0);
    if (png == null) return '';
    final path = await PdfTools.writeTemp('ocr_${DateTime.now().microsecondsSinceEpoch}.png', png);
    try {
      return await recognizeFile(path, lang: lang);
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  /// Text that is already embedded in the PDF (no OCR needed), or '' if none.
  static Future<String> embeddedText(PdfPage page) async {
    try {
      final t = await page.loadText();
      return (t?.fullText ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  /// Embedded text if present, otherwise OCR.
  static Future<String> pageText(PdfPage page, {String lang = langAraEng}) async {
    final embedded = await embeddedText(page);
    if (embedded.length > 20) return embedded;
    return recognizePage(page, lang: lang);
  }

  static String _clean(String s) {
    return s.replaceAll('\r', '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
