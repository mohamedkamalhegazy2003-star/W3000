import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/settings.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../services/ocr_service.dart';
import '../services/pdf_tools.dart';
import 'editor_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'text_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String _query = '';

  Future<List<String>> _pick(List<String> ext, {bool multi = true}) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ext,
      allowMultiple: multi,
    );
    return r?.files.map((f) => f.path).whereType<String>().toList() ?? [];
  }

  Future<void> _openPdf() async {
    final paths = await _pick(['pdf'], multi: false);
    if (paths.isEmpty || !mounted) return;
    await openReader(context, paths.first);
  }

  Future<void> _edit() async {
    final paths = await _pick(['pdf'], multi: false);
    if (paths.isEmpty || !mounted) return;
    await AppSettings.instance.addRecent(paths.first, p.basename(paths.first));
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => EditorScreen(path: paths.first, initialPage: 1)),
    );
  }

  Future<void> _merge() async {
    final paths = await _pick(['pdf']);
    if (paths.length < 2 || !mounted) return;
    final bytes = await runBusy(context, () => PdfTools.merge(paths));
    if (bytes != null && mounted) await saveOrShare(context, 'merged.pdf', bytes);
  }

  Future<void> _split() async {
    final paths = await _pick(['pdf'], multi: false);
    if (paths.isEmpty || !mounted) return;
    final doc = await PdfDocument.openFile(paths.first);
    final total = doc.pages.length;
    await doc.dispose();
    if (!mounted) return;
    final range = await askText(context, title: tr('extract'), hint: tr('pageRange'), initial: '1-$total');
    if (range == null || !mounted) return;
    final idx = PdfTools.parseRange(range, total);
    if (idx.isEmpty) return;
    final bytes = await runBusy(context, () => PdfTools.extract(paths.first, idx));
    if (bytes != null && mounted) {
      await saveOrShare(context, '${p.basenameWithoutExtension(paths.first)}_part.pdf', bytes);
    }
  }

  Future<void> _imagesToPdf() async {
    final paths = await _pick(['jpg', 'jpeg', 'png', 'webp', 'bmp']);
    if (paths.isEmpty || !mounted) return;
    final bytes = await runBusy(context, () => PdfTools.imagesToPdf(paths));
    if (bytes != null && mounted) await saveOrShare(context, 'images.pdf', bytes);
  }

  Future<void> _ocrImage() async {
    final paths = await _pick(['jpg', 'jpeg', 'png', 'webp', 'bmp'], multi: false);
    if (paths.isEmpty || !mounted) return;
    final text = await runBusy(context, () => OcrService.recognizeFile(paths.first));
    if (text == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TextScreen(title: tr('ocrTool'), text: text)),
    );
  }

  Future<void> _openRecent(RecentFile r) async {
    if (!File(r.path).existsSync()) {
      toast(context, tr('error'));
      AppSettings.instance.removeRecent(r.path);
      return;
    }
    await openReader(context, r.path);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Directionality(
        textDirection: s.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: switch (_tab) {
              0 => _homeTab(context),
              1 => _filesTab(context, favoritesOnly: false),
              2 => _filesTab(context, favoritesOnly: true),
              _ => const SettingsBody(),
            },
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          floatingActionButton: FloatingActionButton(
            onPressed: _openPdf,
            shape: const CircleBorder(),
            backgroundColor: kBrand,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add_rounded, size: 32),
          ),
          bottomNavigationBar: BottomAppBar(
            height: 68,
            shape: const CircularNotchedRectangle(),
            notchMargin: 8,
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                _navItem(0, Icons.home_rounded, tr('home')),
                _navItem(1, Icons.folder_rounded, tr('files')),
                const SizedBox(width: 64),
                _navItem(2, Icons.star_rounded, tr('favorites')),
                _navItem(3, Icons.settings_rounded, tr('settings')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final sel = _tab == i;
    final cs = Theme.of(context).colorScheme;
    final c = sel ? kBrand : cs.onSurface.withValues(alpha: 0.45);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- home

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/icon.png', width: 46, height: 46),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('WPDF', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(
                  tr('hello'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: tr('searchFiles'),
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: cs.onSurface.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBrand, kBrandDeep],
        ),
        boxShadow: [BoxShadow(color: kBrand.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('bannerTag'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tr('bannerTitle'),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(tr('bannerBody'), style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _ocrImage,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kBrand),
                icon: const Icon(Icons.document_scanner_rounded, size: 18),
                label: Text(tr('ocrTool')),
              ),
              OutlinedButton.icon(
                onPressed: _openPdf,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                icon: const Icon(Icons.translate_rounded, size: 18),
                label: Text(tr('translate')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickTools() {
    final items = [
      (Icons.edit_rounded, tr('edit'), const Color(0xFF2563EB), const Color(0xFFEFF4FF), _edit),
      (Icons.photo_library_rounded, tr('imagesToPdf'), const Color(0xFF9333EA), const Color(0xFFF6EEFF), _imagesToPdf),
      (Icons.merge_type_rounded, tr('merge'), const Color(0xFF16A34A), const Color(0xFFEAFBF0), _merge),
      (Icons.call_split_rounded, tr('split'), const Color(0xFFEA580C), const Color(0xFFFFF3EA), _split),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('quickTools'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in items)
                Expanded(
                  child: InkWell(
                    onTap: t.$5,
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark ? t.$3.withValues(alpha: 0.18) : t.$4,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(t.$1, color: t.$3, size: 28),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.$2,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<RecentFile> _filtered({bool favoritesOnly = false}) {
    final s = AppSettings.instance;
    return s.recents.where((r) {
      if (_query.isNotEmpty && !r.name.toLowerCase().contains(_query)) return false;
      if (favoritesOnly && s.bookmarksOf(r.path).isEmpty) return false;
      return true;
    }).toList();
  }

  String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return tr('justNow');
    final ar = AppSettings.instance.isArabic;
    String v;
    if (d.inMinutes < 60) {
      v = '${d.inMinutes} ${tr('minutes')}';
    } else if (d.inHours < 24) {
      v = '${d.inHours} ${tr('hours')}';
    } else {
      v = '${d.inDays} ${tr('days')}';
    }
    return ar ? '${tr('ago')} $v' : '$v ${tr('ago')}';
  }

  String _size(String path) {
    try {
      final b = File(path).lengthSync();
      if (b >= 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
      return '${(b / 1024).round()} KB';
    } catch (_) {
      return '';
    }
  }

  Widget _fileTile(RecentFile r) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: ListTile(
        onTap: () => _openRecent(r),
        contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEEE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE53935)),
        ),
        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${_size(r.path)} • ${_ago(r.openedAt)}',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            if (v == 'remove') AppSettings.instance.removeRecent(r.path);
          },
          itemBuilder: (_) => [PopupMenuItem(value: 'remove', child: Text(tr('delete')))],
        ),
      ),
    );
  }

  Widget _storageCard() {
    final s = AppSettings.instance;
    var total = 0;
    for (final r in s.recents) {
      try {
        total += File(r.path).lengthSync();
      } catch (_) {}
    }
    final mb = total / 1048576;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('storage'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            '${mb.toStringAsFixed(1)} MB • ${s.recents.length} ${tr('filesCount')}',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (mb / 500).clamp(0.02, 1.0),
              minHeight: 7,
              backgroundColor: Colors.white,
              color: const Color(0xFF93C5FD),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeTab(BuildContext context) {
    final list = _filtered();
    final shown = list.take(4).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        _header(),
        _searchBar(),
        _banner(),
        _quickTools(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Expanded(child: Text(tr('recent'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              if (list.length > shown.length)
                TextButton(onPressed: () => setState(() => _tab = 1), child: Text(tr('viewAll'))),
            ],
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(child: Opacity(opacity: 0.5, child: Text(tr('noRecent')))),
          )
        else
          for (final r in shown) _fileTile(r),
        _storageCard(),
      ],
    );
  }

  Widget _filesTab(BuildContext context, {required bool favoritesOnly}) {
    final list = _filtered(favoritesOnly: favoritesOnly);
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text(
            favoritesOnly ? tr('favorites') : tr('files'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        _searchBar(),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(child: Opacity(opacity: 0.5, child: Text(tr('noRecent')))),
          )
        else
          for (final r in list) _fileTile(r),
      ],
    );
  }
}
