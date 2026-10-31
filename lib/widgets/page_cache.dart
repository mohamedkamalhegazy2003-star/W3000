import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Renders PDF pages to [ui.Image]s and keeps the most recent ones.
class PageImageCache {
  PageImageCache(this.doc);

  final PdfDocument doc;
  final Map<String, ui.Image> _cache = {};
  final Map<String, Future<ui.Image?>> _pending = {};
  final List<String> _order = [];

  Future<ui.Image?> get(int index, int widthPx) {
    final key = '$index@$widthPx';
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    return _pending[key] ??= _render(index, widthPx, key);
  }

  ui.Image? peek(int index, int widthPx) => _cache['$index@$widthPx'];

  Future<ui.Image?> _render(int index, int widthPx, String key) async {
    try {
      final page = doc.pages[index];
      final h = (widthPx * page.height / page.width).round();
      final pageImage = await page.render(width: widthPx, height: h);
      if (pageImage == null) return null;
      final image = await pageImage.createImage();
      pageImage.dispose();
      _cache[key] = image;
      _order.add(key);
      while (_order.length > 18) {
        _cache.remove(_order.removeAt(0));
      }
      return image;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(key);
    }
  }
}

/// One rendered PDF page, sized by its parent (the parent decides the box).
class PdfPageImage extends StatefulWidget {
  const PdfPageImage({super.key, required this.cache, required this.index, this.flipX = false});

  final PageImageCache cache;
  final int index;
  final bool flipX;

  @override
  State<PdfPageImage> createState() => _PdfPageImageState();
}

class _PdfPageImageState extends State<PdfPageImage> {
  ui.Image? _image;
  int _width = 0;

  void _request(int widthPx) {
    if (widthPx == _width && _image != null) return;
    _width = widthPx;
    final quick = widget.cache.peek(widget.index, widthPx);
    if (quick != null) {
      _image = quick;
      return;
    }
    final idx = widget.index;
    widget.cache.get(idx, widthPx).then((img) {
      if (!mounted || idx != widget.index || widthPx != _width) return;
      if (img != null) setState(() => _image = img);
    });
  }

  @override
  void didUpdateWidget(covariant PdfPageImage old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _image = null;
      _width = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, c) {
        final target = (((c.maxWidth * dpr) / 64).ceil() * 64).clamp(256, 2600);
        _request(target);
        Widget child = _image == null
            ? const ColoredBox(color: Colors.white)
            : RawImage(image: _image, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
        if (widget.flipX) child = Transform.flip(flipX: true, child: child);
        return child;
      },
    );
  }
}
