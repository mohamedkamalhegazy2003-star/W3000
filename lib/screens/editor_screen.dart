import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/strings.dart';
import '../core/ui.dart';
import '../services/ocr_service.dart';
import '../services/pdf_tools.dart';
import 'text_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../core/theme.dart';

enum _Tool { highlight, draw, text, signature, image, eraser }

class _Mark {
  _Mark(this.tool, this.color, this.width);

  final _Tool tool;
  final Color color;
  final double width;
  final List<Offset> points = []; // normalized 0..1
  String text = '';
  double size = 0.03; // text size relative to page width
  ui.Image? image;
  double imageWidth = 0.4; // relative to page width
}

/// Annotation editor: highlight, draw, Arabic/English text, signature.
/// Marks are flattened onto the page when saving (Flutter shapes Arabic text).
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.path, required this.initialPage});

  final String path;
  final int initialPage;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  PdfDocument? _doc;
  int _page = 0;
  ui.Image? _bg;
  _Tool _tool = _Tool.highlight;
  Color _color = const Color(0xFFFFC107);
  double _thick = 0.5; // 0..1 slider
  final Map<int, List<_Mark>> _marks = {};
  _Mark? _current;

  List<_Mark> get _list => _marks.putIfAbsent(_page, () => []);

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage - 1;
    _open();
  }

  Future<void> _open() async {
    final d = await PdfDocument.openFile(widget.path);
    _doc = d;
    _page = _page.clamp(0, d.pages.length - 1);
    await _renderBg();
  }

  Future<void> _renderBg() async {
    final page = _doc!.pages[_page];
    const w = 1400;
    final h = (w * page.height / page.width).round();
    final pi = await page.render(width: w, height: h);
    if (pi == null) return;
    final img = await pi.createImage();
    pi.dispose();
    if (mounted) setState(() => _bg = img);
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  Future<void> _changePage(int d) async {
    final n = _page + d;
    if (n < 0 || n >= _doc!.pages.length) return;
    setState(() {
      _page = n;
      _bg = null;
    });
    await _renderBg();
  }

  Offset _norm(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0, 1), (local.dy / size.height).clamp(0, 1));

  Future<void> _tapText(Offset pos) async {
    final t = await askText(context, title: tr('text'), hint: tr('enterText'), multiline: true);
    if (t == null || t.trim().isEmpty) return;
    final m = _Mark(_Tool.text, _color, 0)..text = t;
    m.points.add(pos);
    setState(() => _list.add(m));
  }

  void _start(Offset local, Size size) {
    final n = _norm(local, size);
    if (_tool == _Tool.text) {
      _tapText(n);
      return;
    }
    if (_tool == _Tool.eraser) {
      _erase(n);
      return;
    }
    if (_tool == _Tool.image) {
      _placeImage(n);
      return;
    }
    final w = switch (_tool) {
      _Tool.highlight => 0.012 + 0.04 * _thick,
      _Tool.signature => 0.003 + 0.006 * _thick,
      _ => 0.002 + 0.012 * _thick,
    };
    final c = switch (_tool) {
      _Tool.highlight => _color.withValues(alpha: 0.4),
      _Tool.signature => const Color(0xFF1A237E),
      _ => _color,
    };
    _current = _Mark(_tool, c, w)..points.add(n);
    setState(() {});
  }

  Future<void> _placeImage(Offset pos) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = r?.files.single.bytes;
    if (bytes == null) return;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 900);
    final frame = await codec.getNextFrame();
    final m = _Mark(_Tool.image, Colors.white, 0)..image = frame.image;
    m.points.add(pos);
    if (mounted) setState(() => _list.add(m));
  }

  Future<void> _ocrCard({required bool translate}) async {
    final doc = _doc!;
    final text = await runBusy(context, () => OcrService.pageText(doc.pages[_page]));
    if (text == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TextScreen(title: '${tr('page')} ${_page + 1}', text: text, autoTranslate: translate),
      ),
    );
  }

  void _update(Offset local, Size size) {
    final n = _norm(local, size);
    if (_tool == _Tool.eraser) {
      _erase(n);
      return;
    }
    if (_current == null) return;
    setState(() => _current!.points.add(n));
  }

  void _end() {
    if (_current != null) {
      setState(() {
        _list.add(_current!);
        _current = null;
      });
    }
  }

  void _erase(Offset n) {
    final before = _list.length;
    _list.removeWhere((m) => m.points.any((q) => (q - n).distance < 0.03));
    if (_list.length != before) setState(() {});
  }

  // ---- flatten + save ----

  static void paintMarks(Canvas canvas, Size size, List<_Mark> marks) {
    for (final m in marks) {
      if (m.tool == _Tool.image && m.image != null) {
        final img = m.image!;
        final w = size.width * m.imageWidth;
        final h = w * img.height / img.width;
        final c = Offset(m.points.first.dx * size.width, m.points.first.dy * size.height);
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCenter(center: c, width: w, height: h),
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else if (m.tool == _Tool.text) {
        final tp = TextPainter(
          text: TextSpan(
            text: m.text,
            style: TextStyle(color: m.color, fontSize: size.width * m.size, height: 1.3),
          ),
          textDirection: _detectDir(m.text),
          textAlign: TextAlign.start,
        )..layout(maxWidth: size.width * 0.9);
        final o = Offset(m.points.first.dx * size.width, m.points.first.dy * size.height);
        final dx = _detectDir(m.text) == TextDirection.rtl ? o.dx - tp.width : o.dx;
        tp.paint(canvas, Offset(dx.clamp(0, size.width - 1), o.dy));
      } else {
        final paint = Paint()
          ..color = m.color
          ..style = PaintingStyle.stroke
          ..strokeCap = m.tool == _Tool.highlight ? StrokeCap.butt : StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = m.width * size.width;
        final path = Path();
        for (var i = 0; i < m.points.length; i++) {
          final o = Offset(m.points[i].dx * size.width, m.points[i].dy * size.height);
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
            path.lineTo(o.dx + 0.01, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  static TextDirection _detectDir(String t) =>
      TranslateHint2.isArabic(t) ? TextDirection.rtl : TextDirection.ltr;

  Future<Uint8List> _flatten(int index) async {
    final page = _doc!.pages[index];
    const w = 1800;
    final h = (w * page.height / page.width).round();
    final pi = await page.render(width: w, height: h);
    final bg = await pi!.createImage();
    pi.dispose();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawImage(bg, Offset.zero, Paint());
    paintMarks(canvas, Size(w.toDouble(), h.toDouble()), _marks[index] ?? []);
    final img = await rec.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _save() async {
    final edited = _marks.entries.where((e) => e.value.isNotEmpty).map((e) => e.key).toList();
    if (edited.isEmpty) return;
    final bytes = await runBusy(context, () async {
      final flat = <int, PdfDocument>{};
      final src = _doc!;
      final out = await PdfDocument.createNew(sourceName: 'edited.pdf');
      try {
        for (final i in edited) {
          final png = await _flatten(i);
          final path = await PdfTools.writeTemp('flat_$i.png', png);
          final pdfBytes = await PdfTools.imagesToPdf([path]);
          flat[i] = await PdfDocument.openData(pdfBytes);
        }
        out.pages = [
          for (var i = 0; i < src.pages.length; i++) flat.containsKey(i) ? flat[i]!.pages.first : src.pages[i],
        ];
        return await out.encodePdf();
      } finally {
        await out.dispose();
        for (final d in flat.values) {
          await d.dispose();
        }
      }
    });
    if (bytes == null || !mounted) return;
    // Save over the original so reopening shows the edits, keep a share option.
    await File(widget.path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    toast(context, tr('saved'));
    await saveOrShare(context, p.basename(widget.path), bytes);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _ocrEditText() async {
    final doc = _doc!;
    final text = await runBusy(context, () => OcrService.pageText(doc.pages[_page]));
    if (text == null || !mounted) return;
    final edited = await askText(context, title: tr('editText'), initial: text, multiline: true);
    if (edited == null || edited.trim().isEmpty) return;
    // Place the edited text as a white-backed block over the top of the page.
    final m = _Mark(_Tool.text, Colors.black, 0)..text = edited;
    m.size = 0.028;
    m.points.add(const Offset(0.06, 0.05));
    setState(() => _list.add(m));
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dirty = _marks.values.any((l) => l.isNotEmpty);
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF1B1B1B) : const Color(0xFFE5E7EB),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.basename(widget.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(
              '${tr('page')} ${_page + 1} ${tr('of')} ${doc?.pages.length ?? '-'}',
              style: const TextStyle(fontSize: 11.5, color: kBrand),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              onPressed: dirty ? _save : null,
              style: FilledButton.styleFrom(backgroundColor: kBrand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(tr('save')),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'ocrEdit') _ocrEditText();
            },
            itemBuilder: (_) => [PopupMenuItem(value: 'ocrEdit', child: Text(tr('editText')))],
          ),
        ],
      ),
      body: _bg == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _bg!.width / _bg!.height,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final size = Size(c.maxWidth, c.maxHeight);
                          return GestureDetector(
                            onPanStart: (d) => _start(d.localPosition, size),
                            onPanUpdate: (d) => _update(d.localPosition, size),
                            onPanEnd: (_) => _end(),
                            onTapUp: (d) {
                              if (_tool == _Tool.text || _tool == _Tool.image) _start(d.localPosition, size);
                            },
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))],
                              ),
                              child: CustomPaint(
                                painter: _PagePainter(_bg!, [..._list, if (_current != null) _current!]),
                                size: size,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 10,
                  end: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('ocrDetected'), style: TextStyle(fontSize: 10.5, color: cs.onSurface.withValues(alpha: 0.5))),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _ocrCard(translate: false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.document_scanner_rounded, size: 16, color: kBrand),
                              const SizedBox(width: 6),
                              Text(tr('extractText'), style: const TextStyle(color: kBrand, fontSize: 12.5, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                        InkWell(
                          onTap: () => _ocrCard(translate: true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.translate_rounded, size: 16, color: kBrand),
                              const SizedBox(width: 6),
                              Text(tr('smartTranslate'), style: const TextStyle(color: kBrand, fontSize: 12.5, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _toolbar(),
    );
  }

  Widget _toolbar() {
    final cs = Theme.of(context).colorScheme;
    Widget tool(_Tool t, IconData icon, String label) {
      final sel = _tool == t;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tool = t),
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: sel ? kBrand.withValues(alpha: 0.12) : cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: sel ? kBrand : cs.onSurface.withValues(alpha: 0.45)),
              ),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 10.5, color: sel ? kBrand : cs.onSurface.withValues(alpha: 0.55))),
            ],
          ),
        ),
      );
    }

    const colors = [Color(0xFFFFC107), Color(0xFF22C55E), Color(0xFFEF4444), Color(0xFF3B82F6)];
    return Material(
      color: cs.surface,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  tool(_Tool.highlight, Icons.highlight_rounded, tr('highlight')),
                  tool(_Tool.draw, Icons.edit_rounded, tr('pen')),
                  tool(_Tool.text, Icons.text_fields_rounded, tr('text')),
                  tool(_Tool.signature, Icons.draw_rounded, tr('signature')),
                  tool(_Tool.image, Icons.image_rounded, tr('image')),
                  tool(_Tool.eraser, Icons.cleaning_services_rounded, tr('eraser')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: tr('undo'),
                    onPressed: _list.isEmpty ? null : () => setState(_list.removeLast),
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton(onPressed: () => _changePage(-1), icon: const Icon(Icons.chevron_left_rounded)),
                  IconButton(onPressed: () => _changePage(1), icon: const Icon(Icons.chevron_right_rounded)),
                  Expanded(
                    child: Slider(
                      value: _thick,
                      onChanged: (v) => setState(() => _thick = v),
                    ),
                  ),
                  for (final c in colors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? kBrand : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.bg, this.marks);

  final ui.Image bg;
  final List<_Mark> marks;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      bg,
      Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    _EditorScreenState.paintMarks(canvas, size, marks);
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) => true;
}

class TranslateHint2 {
  static bool isArabic(String text) {
    var ar = 0;
    var other = 0;
    for (final r in text.runes) {
      if (r >= 0x0600 && r <= 0x06FF) {
        ar++;
      } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
        other++;
      }
    }
    return ar > other;
  }
}
