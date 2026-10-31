import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'page_cache.dart';

/// A book-like reader with a real page flip (single page in portrait,
/// two page spread in landscape). Works for right-to-left books too.
class BookView extends StatefulWidget {
  const BookView({
    super.key,
    required this.doc,
    required this.initialPage,
    required this.rtl,
    required this.onPageChanged,
  });

  final PdfDocument doc;
  final int initialPage; // zero based
  final bool rtl;
  final ValueChanged<int> onPageChanged;

  @override
  State<BookView> createState() => BookViewState();
}

class BookViewState extends State<BookView> with SingleTickerProviderStateMixin {
  late final PageImageCache _cache = PageImageCache(widget.doc);
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late int _page = widget.initialPage.clamp(0, widget.doc.pages.length - 1);
  int _dir = 0; // 1 forward, -1 backward, 0 idle
  bool _spread = false;
  double _drag = 0;
  double _width = 1;

  int get _count => widget.doc.pages.length;
  int get _spreadIndex => (_page + 1) ~/ 2;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void goTo(int page) {
    if (_ctl.isAnimating) return;
    setState(() {
      _page = page.clamp(0, _count - 1);
      _dir = 0;
    });
    widget.onPageChanged(_page);
  }

  bool _canTurn(int dir) {
    if (_spread) {
      return dir > 0 ? (2 * _spreadIndex + 1) <= _count - 1 : _spreadIndex > 0;
    }
    return dir > 0 ? _page < _count - 1 : _page > 0;
  }

  void _commit() {
    if (_spread) {
      final s = _spreadIndex + _dir;
      _page = _dir > 0 ? math.min(2 * s, _count - 1) : 2 * s;
    } else {
      _page += _dir;
    }
    _dir = 0;
    _ctl.value = 0;
    widget.onPageChanged(_page);
  }

  Future<void> _finish({required bool complete}) async {
    if (complete) {
      await _ctl.animateTo(1, curve: Curves.easeOutCubic);
      if (!mounted) return;
      setState(_commit);
    } else {
      await _ctl.animateTo(0, curve: Curves.easeOutCubic);
      if (!mounted) return;
      setState(() => _dir = 0);
    }
  }

  Future<void> _turn(int dir) async {
    if (_ctl.isAnimating || !_canTurn(dir)) return;
    setState(() => _dir = dir);
    _ctl.value = 0;
    await _finish(complete: true);
  }

  // ---- gestures (all in layout space, already unmirrored for RTL) ----

  double _logicalDx(double dx) => widget.rtl ? -dx : dx;

  void _dragStart(DragStartDetails d) {
    if (_ctl.isAnimating) return;
    _drag = 0;
    _dir = 0;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_ctl.isAnimating) return;
    _drag += _logicalDx(d.delta.dx);
    if (_dir == 0) {
      if (_drag.abs() < 6) return;
      final want = _drag < 0 ? 1 : -1;
      if (!_canTurn(want)) return;
      setState(() => _dir = want);
    }
    final span = _spread ? _width * 0.6 : _width * 0.85;
    final moved = _dir > 0 ? -_drag : _drag;
    _ctl.value = (moved / span).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails d) {
    if (_dir == 0 || _ctl.isAnimating) return;
    final vx = _logicalDx(d.velocity.pixelsPerSecond.dx);
    final fling = _dir > 0 ? -vx : vx;
    _finish(complete: _ctl.value > 0.35 || fling > 700);
  }

  void _tap(TapUpDetails d) {
    final x = widget.rtl ? _width - d.localPosition.dx : d.localPosition.dx;
    if (x < _width * 0.3) {
      _turn(-1);
    } else if (x > _width * 0.7) {
      _turn(1);
    }
  }

  // ---- layout ----

  Size _fit(int index, double bw, double bh) {
    final i = index.clamp(0, _count - 1);
    final page = widget.doc.pages[i];
    final aspect = page.width / page.height;
    var w = bw;
    var h = w / aspect;
    if (h > bh) {
      h = bh;
      w = h * aspect;
    }
    return Size(w, h);
  }

  Widget _face(int index, Size size, {bool mirror = false}) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: PdfPageImage(cache: _cache, index: index, flipX: widget.rtl != mirror),
    );
  }

  bool _has(int i) => i >= 0 && i < _count;

  Widget _slot(int index, double bw, double bh, Alignment align) {
    if (!_has(index)) return const SizedBox.shrink();
    return Align(alignment: align, child: _face(index, _fit(index, bw, bh)));
  }

  Widget _leaf({
    required int front,
    required int back,
    required double s, // 0..1 (1 = fully turned)
    required double bw,
    required double bh,
    required bool rightSide,
  }) {
    final size = _fit(front, bw, bh);
    final showBack = s > 0.5 && _has(back);
    final angle = (rightSide ? 1 : -1) * math.pi * s;
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0011)
      ..rotateY(angle);
    final shade = (math.sin(math.pi * s)).abs() * 0.28;
    final face = showBack ? _face(back, size, mirror: true) : _face(front, size);
    return Align(
      alignment: rightSide ? Alignment.centerLeft : Alignment.centerRight,
      child: Transform(
        alignment: rightSide ? Alignment.centerLeft : Alignment.centerRight,
        transform: m,
        child: Stack(
          children: [
            face,
            Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: shade)))),
          ],
        ),
      ),
    );
  }

  Widget _spreadStage(double w, double h, double p) {
    final hw = w / 2;
    final s = _spreadIndex;
    final l = 2 * s - 1;
    final r = 2 * s;
    Widget left;
    Widget right;
    Widget? leaf;
    Alignment leafSide = Alignment.centerRight;
    if (_dir > 0) {
      left = _slot(l, hw, h, Alignment.centerRight);
      right = _slot(r + 2, hw, h, Alignment.centerLeft);
      leaf = _leaf(front: r, back: r + 1, s: p, bw: hw, bh: h, rightSide: true);
      leafSide = Alignment.centerRight;
    } else if (_dir < 0) {
      left = _slot(l - 2, hw, h, Alignment.centerRight);
      right = _slot(r, hw, h, Alignment.centerLeft);
      leaf = _leaf(front: l, back: l - 1, s: p, bw: hw, bh: h, rightSide: false);
      leafSide = Alignment.centerLeft;
    } else {
      left = _slot(l, hw, h, Alignment.centerRight);
      right = _slot(r, hw, h, Alignment.centerLeft);
    }
    return Stack(
      children: [
        Row(children: [Expanded(child: left), Expanded(child: right)]),
        if (leaf != null)
          Row(
            children: [
              if (leafSide == Alignment.centerRight) const Spacer() else Expanded(child: leaf),
              if (leafSide == Alignment.centerRight) Expanded(child: leaf) else const Spacer(),
            ],
          ),
        // spine shadow
        Center(
          child: IgnorePointer(
            child: Container(
              width: 26,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x00000000), Color(0x30000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _singleStage(double w, double h, double p) {
    if (_dir > 0) {
      return Stack(
        alignment: Alignment.center,
        children: [
          _slot(_page + 1, w, h, Alignment.center),
          _leaf(front: _page, back: -1, s: 0.5 * p, bw: w, bh: h, rightSide: true)
              .centerAligned(_fit(_page, w, h), w),
        ],
      );
    }
    if (_dir < 0) {
      return Stack(
        alignment: Alignment.center,
        children: [
          _slot(_page, w, h, Alignment.center),
          _leaf(front: _page - 1, back: -1, s: 0.5 * (1 - p), bw: w, bh: h, rightSide: true)
              .centerAligned(_fit(_page - 1, w, h), w),
        ],
      );
    }
    return _slot(_page, w, h, Alignment.center);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth;
        final spread = c.maxWidth >= 600 && c.maxWidth > c.maxHeight * 1.1;
        if (spread != _spread && _dir == 0) {
          _spread = spread;
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          onTapUp: _tap,
          child: Transform.flip(
            flipX: widget.rtl,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: AnimatedBuilder(
                animation: _ctl,
                builder: (context, _) {
                  final p = _ctl.value;
                  final h = c.maxHeight - 20;
                  return _spread ? _spreadStage(c.maxWidth, h, p) : _singleStage(c.maxWidth, h, p);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

extension on Widget {
  /// Places a leaf whose hinge is the left edge of a centered page of [pageSize].
  Widget centerAligned(Size pageSize, double boxWidth) {
    final dx = (boxWidth - pageSize.width) / 2;
    return Padding(padding: EdgeInsets.only(left: dx), child: this);
  }
}
