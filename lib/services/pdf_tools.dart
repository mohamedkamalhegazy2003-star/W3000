import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdfw;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

class PdfTools {
  /// Parses "1-3,5,8-" into zero based page indexes.
  static List<int> parseRange(String input, int total) {
    final out = <int>[];
    for (final part in input.split(RegExp(r'[,\s]+'))) {
      if (part.trim().isEmpty) continue;
      if (part.contains('-')) {
        final ab = part.split('-');
        final a = int.tryParse(ab[0].trim()) ?? 1;
        final b = ab[1].trim().isEmpty ? total : (int.tryParse(ab[1].trim()) ?? total);
        for (var i = a; i <= b; i++) {
          if (i >= 1 && i <= total) out.add(i - 1);
        }
      } else {
        final n = int.tryParse(part.trim());
        if (n != null && n >= 1 && n <= total) out.add(n - 1);
      }
    }
    return out;
  }

  static Future<Uint8List> merge(List<String> paths) async {
    final docs = <PdfDocument>[];
    final out = await PdfDocument.createNew(sourceName: 'merged.pdf');
    try {
      final pages = <PdfPage>[];
      for (final path in paths) {
        final d = await PdfDocument.openFile(path);
        docs.add(d);
        pages.addAll(d.pages);
      }
      out.pages = pages;
      return await out.encodePdf();
    } finally {
      for (final d in docs) {
        await d.dispose();
      }
      await out.dispose();
    }
  }

  static Future<Uint8List> extract(String path, List<int> indexes) async {
    final src = await PdfDocument.openFile(path);
    final out = await PdfDocument.createNew(sourceName: 'extract.pdf');
    try {
      out.pages = [for (final i in indexes) src.pages[i]];
      return await out.encodePdf();
    } finally {
      await src.dispose();
      await out.dispose();
    }
  }

  /// Applies [transform] to the page list of the document and returns new bytes.
  static Future<Uint8List> editPages(
    String path,
    List<PdfPage> Function(List<PdfPage> pages) transform,
  ) async {
    final src = await PdfDocument.openFile(path);
    final out = await PdfDocument.createNew(sourceName: 'edited.pdf');
    try {
      out.pages = transform(List<PdfPage>.of(src.pages));
      return await out.encodePdf();
    } finally {
      await src.dispose();
      await out.dispose();
    }
  }

  static Future<Uint8List> rotatePages(String path, Set<int> indexes, {bool clockwise = true}) {
    return editPages(path, (pages) {
      return [
        for (var i = 0; i < pages.length; i++)
          indexes.contains(i) ? (clockwise ? pages[i].rotatedCW90() : pages[i].rotatedCCW90()) : pages[i],
      ];
    });
  }

  static Future<Uint8List> deletePages(String path, Set<int> indexes) {
    return editPages(path, (pages) {
      return [
        for (var i = 0; i < pages.length; i++)
          if (!indexes.contains(i)) pages[i],
      ];
    });
  }

  static Future<Uint8List> movePage(String path, int from, int to) {
    return editPages(path, (pages) {
      final page = pages.removeAt(from);
      pages.insert(to, page);
      return pages;
    });
  }

  /// Builds a PDF where every image is one page sized to the image.
  static Future<Uint8List> imagesToPdf(List<String> imagePaths) async {
    final doc = pw.Document();
    for (final path in imagePaths) {
      final raw = await File(path).readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) continue;
      final oriented = img.bakeOrientation(decoded);
      final jpg = Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
      final w = oriented.width.toDouble();
      final h = oriented.height.toDouble();
      // Scale so the longer side is about A4 length in points.
      final scale = 842 / (w > h ? w : h);
      final format = pdfw.PdfPageFormat(w * scale, h * scale, marginAll: 0);
      final image = pw.MemoryImage(jpg);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.FullPage(ignoreMargins: true, child: pw.Image(image, fit: pw.BoxFit.fill)),
        ),
      );
    }
    return doc.save();
  }

  /// Renders a page to PNG bytes at the given [scale] (1 = 72 dpi).
  static Future<Uint8List?> renderPagePng(PdfPage page, {double scale = 2.5}) async {
    final w = (page.width * scale).round();
    final h = (page.height * scale).round();
    final pageImage = await page.render(width: w, height: h);
    if (pageImage == null) return null;
    try {
      final image = await pageImage.createImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } finally {
      pageImage.dispose();
    }
  }

  static Future<Directory> workDir() async {
    final base = await getTemporaryDirectory();
    final d = Directory(p.join(base.path, 'wpdf'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> writeTemp(String name, List<int> bytes) async {
    final d = await workDir();
    final f = File(p.join(d.path, name));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }
}
