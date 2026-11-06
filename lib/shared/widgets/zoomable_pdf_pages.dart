import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Use as: PdfPreviewCustom(pagesBuilder: zoomablePagesBuilder, ...)
Widget zoomablePagesBuilder(
        BuildContext context, List<PdfPreviewPageData> pages) =>
    ZoomablePdfPages(pages: pages);

class ZoomablePdfPages extends StatefulWidget {
  const ZoomablePdfPages({super.key, required this.pages});

  final List<PdfPreviewPageData> pages;

  @override
  State<ZoomablePdfPages> createState() => _ZoomablePdfPagesState();
}

class _ZoomablePdfPagesState extends State<ZoomablePdfPages> {
  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;
  static const double _step = 1.25;
  static const double _gap = 16;
  static const double _pad = 16;

  final TransformationController _ctrl = TransformationController();
  Size _viewport = Size.zero;

  double get _scale => _ctrl.value.getMaxScaleOnAxis();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Zoom around the centre of the viewport.
  void _zoomTo(double target) {
    target = target.clamp(_minScale, _maxScale).toDouble();
    if (target <= _minScale + 0.001 || _viewport.isEmpty) {
      _ctrl.value = Matrix4.identity();
      return;
    }
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final scenePoint = _ctrl.toScene(center);
    final tx = (center.dx - scenePoint.dx * target)
        .clamp(_viewport.width * (1 - target), 0.0)
        .toDouble();
    final ty = (center.dy - scenePoint.dy * target)
        .clamp(_viewport.height * (1 - target), 0.0)
        .toDouble();
    _ctrl.value = Matrix4.diagonal3Values(target, target, 1)
      ..setTranslationRaw(tx, ty, 0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    if (pages.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0;
      _viewport = Size(w, h);

      final availW = w - 2 * _pad;
      final availH = h - 2 * _pad;
      if (availW <= 0 || availH <= 0) return const SizedBox.shrink();

      // Grid that fits every page on screen at 100%.
      final n = pages.length;
      var cols = 1;
      while (cols * cols < n) {
        cols++;
      }
      final rows = (n + cols - 1) ~/ cols;

      var cellW = (availW - _gap * (cols - 1)) / cols;
      var cellH = cellW / pages.first.aspectRatio;
      final rowH = (availH - _gap * (rows - 1)) / rows;
      if (cellH > rowH) {
        cellH = rowH;
        cellW = cellH * pages.first.aspectRatio;
      }
      if (cellW <= 0 || cellH <= 0) return const SizedBox.shrink();

      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _ctrl,
              minScale: _minScale,
              maxScale: _maxScale,
              child: SizedBox(
                width: w,
                height: h,
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (final page in pages)
                        Container(
                          width: cellW,
                          height: cellH,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border:
                                Border.all(color: const Color(0xFFDADADA)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                offset: Offset(0, 3),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: Image(
                            image: page.image,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Material(
              color: Colors.white,
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _ctrl,
                builder: (_, __, ___) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Zoom out',
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed:
                          _scale <= _minScale + 0.001
                              ? null
                              : () => _zoomTo(_scale / _step),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${(_scale * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      tooltip: 'Zoom in',
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _scale >= _maxScale - 0.001
                          ? null
                          : () => _zoomTo(_scale * _step),
                    ),
                    IconButton(
                      tooltip: 'Fit to screen',
                      icon: const Icon(Icons.fit_screen_outlined, size: 18),
                      onPressed: () => _zoomTo(1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}