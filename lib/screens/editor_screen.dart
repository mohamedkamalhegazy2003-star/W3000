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

enum _Tool { highlight, draw, text, signature, eraser }

class _Mark {
  _Mark(this.tool, this.color, this.width);

  final _Tool tool;
  final Color color;
  final double width;
  final List<Offset> points = []; // normalized 0..1
  String text = '';
  double size = 0.03; // text size relative to page width
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
  _Tool _tool = _Tool.draw;
  Color _color = const Color(0xFFE53935);
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
    final w = switch (_tool) {
      _Tool.highlight => 0.028,
      _Tool.signature => 0.004,
      _ => 0.004,
    };
    final c = switch (_tool) {
      _Tool.highlight => const Color(0x66FFEB3B),
      _Tool.signature => const Color(0xFF1A237E),
      _ => _color,
    };
    _current = _Mark(_tool, c, w)..points.add(n);
    setState(() {});
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
      if (m.tool == _Tool.text) {
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
    return Scaffold(
      appBar: AppBar(
        title: Text('${tr('edit')} ${_page + 1}${doc == null ? '' : ' / ${doc.pages.length}'}'),
        actions: [
          IconButton(
            tooltip: tr('undo'),
            icon: const Icon(Icons.undo_rounded),
            onPressed: _list.isEmpty ? null : () => setState(_list.removeLast),
          ),
          IconButton(
            tooltip: tr('editText'),
            icon: const Icon(Icons.text_snippet_rounded),
            onPressed: doc == null ? null : _ocrEditText,
          ),
          IconButton(
            tooltip: tr('save'),
            icon: const Icon(Icons.check_rounded),
            onPressed: _marks.values.any((l) => l.isNotEmpty) ? _save : null,
          ),
        ],
      ),
      body: _bg == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                      panEnabled: false,
                      scaleEnabled: false,
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
                                if (_tool == _Tool.text) _start(d.localPosition, size);
                              },
                              child: CustomPaint(
                                painter: _PagePainter(_bg!, [..._list, if (_current != null) _current!]),
                                size: size,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                _toolbar(),
              ],
            ),
    );
  }

  Widget _toolbar() {
    Widget tool(_Tool t, IconData icon, String label) => ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          selected: _tool == t,
          onSelected: (_) => setState(() => _tool = t),
        );
    final colors = [const Color(0xFFE53935), const Color(0xFF1E88E5), const Color(0xFF43A047), Colors.black];
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 6,
                children: [
                  tool(_Tool.draw, Icons.edit_rounded, tr('draw')),
                  tool(_Tool.highlight, Icons.highlight_rounded, tr('highlight')),
                  tool(_Tool.text, Icons.text_fields_rounded, tr('text')),
                  tool(_Tool.signature, Icons.draw_rounded, tr('signature')),
                  tool(_Tool.eraser, Icons.cleaning_services_rounded, tr('eraser')),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(onPressed: () => _changePage(-1), icon: const Icon(Icons.chevron_left_rounded)),
                for (final c in colors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(onPressed: () => _changePage(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
          ],
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
