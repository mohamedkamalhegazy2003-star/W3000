import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/strings.dart';
import '../core/ui.dart';
import '../services/pdf_tools.dart';

/// Page manager: thumbnails with rotate / delete / move.
class PagesScreen extends StatefulWidget {
  const PagesScreen({super.key, required this.path});

  final String path;

  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends State<PagesScreen> {
  int _rev = 0;
  int _count = 0;
  bool _changed = false;
  final Map<String, Uint8List?> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _countPages();
  }

  Future<void> _countPages() async {
    final d = await PdfDocument.openFile(widget.path);
    final n = d.pages.length;
    await d.dispose();
    if (mounted) setState(() => _count = n);
  }

  Future<Uint8List?> _thumb(int i) async {
    final key = '$_rev:$i';
    if (_thumbs.containsKey(key)) return _thumbs[key];
    final d = await PdfDocument.openFile(widget.path);
    try {
      final png = await PdfTools.renderPagePng(d.pages[i], scale: 0.6);
      _thumbs[key] = png;
      return png;
    } finally {
      await d.dispose();
    }
  }

  Future<void> _apply(Future<Uint8List> Function() job) async {
    final bytes = await runBusy(context, job);
    if (bytes == null) return;
    await File(widget.path).writeAsBytes(bytes, flush: true);
    _changed = true;
    _rev++;
    _thumbs.clear();
    await _countPages();
  }

  Future<void> _menu(int i) async {
    final c = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.rotate_right_rounded),
              title: Text(tr('rotate')),
              onTap: () => Navigator.pop(ctx, 'rot'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: const Text('◀'),
              onTap: () => Navigator.pop(ctx, 'left'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_forward_rounded),
              title: const Text('▶'),
              onTap: () => Navigator.pop(ctx, 'right'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded),
              title: Text(tr('deletePage')),
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
          ],
        ),
      ),
    );
    switch (c) {
      case 'rot':
        await _apply(() => PdfTools.rotatePages(widget.path, {i}));
      case 'left':
        if (i > 0) await _apply(() => PdfTools.movePage(widget.path, i, i - 1));
      case 'right':
        if (i < _count - 1) await _apply(() => PdfTools.movePage(widget.path, i, i + 1));
      case 'del':
        if (_count > 1) await _apply(() => PdfTools.deletePages(widget.path, {i}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr('pages'))),
        body: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            childAspectRatio: 0.7,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: _count,
          itemBuilder: (context, i) => InkWell(
            onTap: () => _menu(i),
            child: Column(
              children: [
                Expanded(
                  child: FutureBuilder<Uint8List?>(
                    key: ValueKey('$_rev:$i'),
                    future: _thumb(i),
                    builder: (_, s) => Container(
                      color: Colors.white,
                      width: double.infinity,
                      child: s.data == null ? null : Image.memory(s.data!, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${i + 1}'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
