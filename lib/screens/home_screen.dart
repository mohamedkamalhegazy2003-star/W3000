import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/settings.dart';
import '../core/strings.dart';
import '../core/ui.dart';
import '../services/ocr_service.dart';
import '../services/pdf_tools.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'text_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openPdf(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = r?.files.single.path;
    if (path == null || !context.mounted) return;
    await openReader(context, path);
  }

  Future<List<String>> _pick(List<String> ext, {bool multi = true}) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ext,
      allowMultiple: multi,
    );
    return r?.files.map((f) => f.path).whereType<String>().toList() ?? [];
  }

  Future<void> _merge(BuildContext context) async {
    final paths = await _pick(['pdf']);
    if (paths.length < 2 || !context.mounted) return;
    final bytes = await runBusy(context, () => PdfTools.merge(paths));
    if (bytes != null && context.mounted) await saveOrShare(context, 'merged.pdf', bytes);
  }

  Future<void> _split(BuildContext context) async {
    final paths = await _pick(['pdf'], multi: false);
    if (paths.isEmpty || !context.mounted) return;
    final doc = await PdfDocument.openFile(paths.first);
    final total = doc.pages.length;
    await doc.dispose();
    if (!context.mounted) return;
    final range = await askText(context, title: tr('extract'), hint: tr('pageRange'), initial: '1-$total');
    if (range == null || !context.mounted) return;
    final idx = PdfTools.parseRange(range, total);
    if (idx.isEmpty) return;
    final bytes = await runBusy(context, () => PdfTools.extract(paths.first, idx));
    if (bytes != null && context.mounted) {
      await saveOrShare(context, '${p.basenameWithoutExtension(paths.first)}_part.pdf', bytes);
    }
  }

  Future<void> _imagesToPdf(BuildContext context) async {
    final paths = await _pick(['jpg', 'jpeg', 'png', 'webp', 'bmp']);
    if (paths.isEmpty || !context.mounted) return;
    final bytes = await runBusy(context, () => PdfTools.imagesToPdf(paths));
    if (bytes != null && context.mounted) await saveOrShare(context, 'images.pdf', bytes);
  }

  Future<void> _ocrImage(BuildContext context) async {
    final paths = await _pick(['jpg', 'jpeg', 'png', 'webp', 'bmp'], multi: false);
    if (paths.isEmpty || !context.mounted) return;
    final text = await runBusy(context, () => OcrService.recognizeFile(paths.first));
    if (text == null || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TextScreen(title: tr('ocrTool'), text: text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final cs = Theme.of(context).colorScheme;
    final tools = <_Tool>[
      _Tool(Icons.merge_type_rounded, tr('merge'), () => _merge(context)),
      _Tool(Icons.call_split_rounded, tr('split'), () => _split(context)),
      _Tool(Icons.image_rounded, tr('imagesToPdf'), () => _imagesToPdf(context)),
      _Tool(Icons.document_scanner_rounded, tr('ocrTool'), () => _ocrImage(context)),
    ];
    return Directionality(
      textDirection: s.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/icon.png', width: 32, height: 32),
              ),
              const SizedBox(width: 10),
              const Text('WPDF', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openPdf(context),
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(tr('open')),
        ),
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(tr('tools'), style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.4,
                  children: [
                    for (final t in tools)
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: t.onTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(t.icon, color: cs.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(t.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(tr('recent'), style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              if (s.recents.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Opacity(
                      opacity: 0.5,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.picture_as_pdf_rounded, size: 56),
                          const SizedBox(height: 8),
                          Text(tr('noRecent')),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: s.recents.length,
                  itemBuilder: (context, i) {
                    final r = s.recents[i];
                    return Dismissible(
                      key: ValueKey(r.path),
                      onDismissed: (_) => s.removeRecent(r.path),
                      background: Container(color: cs.errorContainer),
                      child: ListTile(
                        leading: Icon(Icons.picture_as_pdf_rounded, color: cs.primary, size: 34),
                        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${tr('page')} ${r.lastPage}'),
                        onTap: () async {
                          if (!File(r.path).existsSync()) {
                            toast(context, tr('error'));
                            s.removeRecent(r.path);
                            return;
                          }
                          await openReader(context, r.path);
                        },
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool {
  _Tool(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
