import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/settings.dart';
import '../core/strings.dart';
import '../core/ui.dart';
import '../services/ocr_service.dart';
import '../services/pdf_tools.dart';
import '../widgets/book_view.dart';
import 'editor_screen.dart';
import 'pages_screen.dart';
import 'text_screen.dart';

Future<void> openReader(BuildContext context, String path) async {
  await AppSettings.instance.addRecent(path, p.basename(path));
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ReaderScreen(path: path)),
  );
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.path});

  final String path;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  final _bookKey = GlobalKey<BookViewState>();
  PdfDocument? _doc;
  Object? _error;
  bool _bookMode = true;
  bool _night = false;
  bool _chrome = true;
  bool _rtlBook = false;
  int _page = 1; // one based
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await PdfDocument.openFile(widget.path);
      if (!mounted) {
        await d.dispose();
        return;
      }
      final last = AppSettings.instance.lastPageOf(widget.path).clamp(1, d.pages.length);
      final firstText = await OcrService.embeddedText(d.pages.first);
      setState(() {
        _doc = d;
        _page = last;
        _rtlBook = TranslateHint.isArabic(firstText);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  void _onPage(int onebased) {
    _page = onebased;
    AppSettings.instance.saveLastPage(widget.path, onebased);
    if (mounted) setState(() {});
  }

  void _jump(int onebased) {
    final n = onebased.clamp(1, _doc!.pages.length);
    if (_bookMode) {
      _bookKey.currentState?.goTo(n - 1);
    } else {
      _controller.goToPage(pageNumber: n);
    }
    _onPage(n);
  }

  Future<void> _goToDialog() async {
    final v = await askText(context, title: tr('goToPage'), hint: '1 - ${_doc!.pages.length}');
    final n = int.tryParse(v ?? '');
    if (n != null) _jump(n);
  }

  Future<void> _pageText({required bool translate}) async {
    final doc = _doc!;
    final text = await runBusy(context, () => OcrService.pageText(doc.pages[_page - 1]));
    if (text == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TextScreen(
          title: '${tr('page')} $_page',
          text: text,
          autoTranslate: translate,
        ),
      ),
    );
  }

  Future<void> _search() async {
    final doc = _doc!;
    final q = await askText(context, title: tr('search'), hint: tr('searchHint'));
    if (q == null || q.trim().isEmpty || !mounted) return;
    final needle = q.trim().toLowerCase();
    final hits = await runBusy(context, () async {
      final out = <MapEntry<int, String>>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final t = (await OcrService.embeddedText(doc.pages[i]));
        final low = t.toLowerCase();
        final at = low.indexOf(needle);
        if (at >= 0) {
          final s = (at - 30).clamp(0, t.length);
          final e = (at + needle.length + 50).clamp(0, t.length);
          out.add(MapEntry(i + 1, t.substring(s, e).replaceAll('\n', ' ')));
        }
      }
      return out;
    });
    if (hits == null || !mounted) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => hits.isEmpty
          ? Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('noResults'))))
          : ListView(
              shrinkWrap: true,
              children: [
                for (final h in hits)
                  ListTile(
                    leading: CircleAvatar(child: Text('${h.key}')),
                    title: Text(h.value, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, h.key),
                  ),
              ],
            ),
    );
    if (chosen != null) _jump(chosen);
  }

  Future<void> _showBookmarks() async {
    final s = AppSettings.instance;
    final list = s.bookmarksOf(widget.path);
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => list.isEmpty
          ? Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('noResults'))))
          : ListView(
              shrinkWrap: true,
              children: [
                for (final b in list)
                  ListTile(
                    leading: const Icon(Icons.bookmark_rounded),
                    title: Text('${tr('page')} $b'),
                    onTap: () => Navigator.pop(ctx, b),
                  ),
              ],
            ),
    );
    if (chosen != null) _jump(chosen);
  }

  Future<void> _openEditor() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => EditorScreen(path: widget.path, initialPage: _page),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _openPages() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => PagesScreen(path: widget.path)),
    );
    if (changed == true) await _reload();
  }

  Future<void> _reload() async {
    final old = _doc;
    setState(() {
      _doc = null;
      _revision++;
    });
    await old?.dispose();
    await _load();
  }

  static const _invert = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final doc = _doc;
    final bookmarked = s.bookmarksOf(widget.path).contains(_page);
    Widget body;
    if (_error != null) {
      body = Center(child: Text('${tr('error')}: $_error'));
    } else if (doc == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_bookMode) {
      body = BookView(
        key: _bookKey,
        doc: doc,
        initialPage: _page - 1,
        rtl: _rtlBook,
        onPageChanged: (i) => _onPage(i + 1),
      );
    } else {
      body = PdfViewer.file(
        widget.path,
        key: ValueKey('v$_revision'),
        controller: _controller,
        initialPageNumber: _page,
        params: PdfViewerParams(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1B1B1B)
              : const Color(0xFFE9E9EE),
          onPageChanged: (n) {
            if (n != null) _onPage(n);
          },
        ),
      );
    }
    if (_night) body = ColorFiltered(colorFilter: _invert, child: body);

    return Directionality(
      textDirection: s.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        extendBodyBehindAppBar: false,
        appBar: _chrome
            ? AppBar(
                title: Text(p.basename(widget.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  IconButton(
                    tooltip: tr('search'),
                    icon: const Icon(Icons.search_rounded),
                    onPressed: doc == null ? null : _search,
                  ),
                  IconButton(
                    tooltip: tr('bookmark'),
                    icon: Icon(bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                    onPressed: doc == null
                        ? null
                        : () async {
                            await s.toggleBookmark(widget.path, _page);
                            if (mounted) setState(() {});
                          },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'mode':
                          setState(() => _bookMode = !_bookMode);
                        case 'night':
                          setState(() => _night = !_night);
                        case 'rtl':
                          setState(() => _rtlBook = !_rtlBook);
                        case 'marks':
                          _showBookmarks();
                        case 'goto':
                          _goToDialog();
                        case 'pages':
                          _openPages();
                        case 'share':
                          PdfTools.writeTemp(p.basename(widget.path), File(widget.path).readAsBytesSync())
                              .then((path) => saveOrShare(context, p.basename(path), File(path).readAsBytesSync()));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'mode', child: Text(_bookMode ? tr('scrollMode') : tr('bookMode'))),
                      PopupMenuItem(value: 'night', child: Text(tr('nightMode'))),
                      const PopupMenuItem(value: 'rtl', child: Text('RTL / LTR')),
                      PopupMenuItem(value: 'marks', child: Text(tr('bookmarks'))),
                      PopupMenuItem(value: 'goto', child: Text(tr('goToPage'))),
                      PopupMenuItem(value: 'pages', child: Text(tr('pages'))),
                      PopupMenuItem(value: 'share', child: Text(tr('share'))),
                    ],
                  ),
                ],
              )
            : null,
        body: GestureDetector(
          onDoubleTap: () => setState(() => _chrome = !_chrome),
          child: body,
        ),
        bottomNavigationBar: _chrome && doc != null
            ? BottomAppBar(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      tooltip: tr('ocr'),
                      icon: const Icon(Icons.document_scanner_rounded),
                      onPressed: () => _pageText(translate: false),
                    ),
                    IconButton(
                      tooltip: tr('translate'),
                      icon: const Icon(Icons.translate_rounded),
                      onPressed: () => _pageText(translate: true),
                    ),
                    InkWell(
                      onTap: _goToDialog,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Text('$_page ${tr('of')} ${doc.pages.length}'),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('edit'),
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: _openEditor,
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

class TranslateHint {
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
