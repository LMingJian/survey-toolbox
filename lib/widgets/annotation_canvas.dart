import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/annotation_data.dart';

class AnnotationCanvas extends StatefulWidget {
  final ImageProvider image;
  final Size imageSize;
  final List<AnnotationData> annotations;
  final AnnotationType currentType;
  final Color currentColor;
  final double currentWidth;
  final int selectedIndex;
  final void Function(AnnotationData annotation) onAnnotationAdded;
  final void Function(TextEditingController controller, Offset position) onTextRequested;
  final void Function(int index) onSelect;
  final void Function(int index, Offset delta) onAnnotationMoved;

  const AnnotationCanvas({
    super.key,
    required this.image,
    required this.imageSize,
    required this.annotations,
    required this.currentType,
    required this.currentColor,
    required this.currentWidth,
    required this.selectedIndex,
    required this.onAnnotationAdded,
    required this.onTextRequested,
    required this.onSelect,
    required this.onAnnotationMoved,
  });

  @override
  State<AnnotationCanvas> createState() => AnnotationCanvasState();
}

class AnnotationCanvasState extends State<AnnotationCanvas> {
  List<Offset> _points = [];
  Offset? _dragStart, _dragEnd;
  bool _drawing = false;
  bool _moving = false;
  Offset? _moveLast;
  Size _displaySize = Size.zero;

  Size get displaySize => _displaySize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (_displaySize == Size.zero) _displaySize = _calcDisplay(c);
      final off = _calcOffset(c, _displaySize);
      return GestureDetector(
        onPanStart: (d) => _onStart(d, off),
        onPanUpdate: (d) => _onUpdate(d, off),
        onPanEnd: (_) => _onEnd(),
        child: Stack(fit: StackFit.expand, children: [
          Center(child: SizedBox(width: _displaySize.width, height: _displaySize.height,
              child: Image(image: widget.image, fit: BoxFit.contain))),
          Positioned(left: off.dx, top: off.dy, width: _displaySize.width, height: _displaySize.height,
              child: ClipRect(child: CustomPaint(painter: _Painter(
                annotations: widget.annotations, selectedIndex: widget.selectedIndex,
                points: _points, start: _dragStart, end: _dragEnd, drawing: _drawing,
                type: widget.currentType, color: widget.currentColor, width: widget.currentWidth,
              )))),
        ]));
    });
  }

  Size _calcDisplay(BoxConstraints c) {
    final ia = widget.imageSize.width / widget.imageSize.height;
    final ca = c.maxWidth / c.maxHeight;
    if (ia > ca) return Size(c.maxWidth, c.maxWidth / ia);
    return Size(c.maxHeight * ia, c.maxHeight);
  }
  Offset _calcOffset(BoxConstraints c, Size d) => Offset((c.maxWidth - d.width) / 2, (c.maxHeight - d.height) / 2);
  Offset _local(Offset p, Offset o) => Offset((p.dx - o.dx).clamp(0, _displaySize.width), (p.dy - o.dy).clamp(0, _displaySize.height));

  void _onStart(DragStartDetails d, Offset o) {
    final lp = _local(d.localPosition, o);
    if (widget.currentType == AnnotationType.select) {
      final idx = _hitTest(lp);
      if (idx >= 0 && idx == widget.selectedIndex) {
        // 已经开始拖拽选中的标注
        setState(() { _moving = true; _moveLast = lp; });
        return;
      }
      widget.onSelect(idx);
      return;
    }
    if (widget.currentType == AnnotationType.text) {
      widget.onTextRequested(TextEditingController(), lp);
      return;
    }
    setState(() { _drawing = true; _dragStart = lp; _dragEnd = lp; _points = widget.currentType == AnnotationType.freehand ? [lp] : []; });
  }

  void _onUpdate(DragUpdateDetails d, Offset o) {
    final lp = _local(d.localPosition, o);
    if (_moving && _moveLast != null && widget.selectedIndex >= 0) {
      final delta = lp - _moveLast!;
      widget.onAnnotationMoved(widget.selectedIndex, delta);
      setState(() => _moveLast = lp);
      return;
    }
    if (widget.currentType == AnnotationType.select) return;
    setState(() { _dragEnd = lp; if (widget.currentType == AnnotationType.freehand) _points.add(lp); });
  }

  void _onEnd() {
    if (_moving) {
      _moving = false;
      _moveLast = null;
      return;
    }
    if (!_drawing) return;
    final a = _make();
    if (a != null) widget.onAnnotationAdded(a);
    setState(() { _drawing = false; _points = []; _dragStart = null; _dragEnd = null; });
  }

  AnnotationData? _make() {
    final c = widget.currentColor.toARGB32(); final w = widget.currentWidth;
    switch (widget.currentType) {
      case AnnotationType.freehand: return _points.length < 2 ? null : AnnotationData(type: AnnotationType.freehand, points: List.from(_points), colorValue: c, strokeWidth: w);
      case AnnotationType.arrow: return _dragStart == null || _dragEnd == null ? null : AnnotationData(type: AnnotationType.arrow, start: _dragStart, end: _dragEnd, colorValue: c, strokeWidth: w);
      case AnnotationType.rect: return _dragStart == null || _dragEnd == null ? null : AnnotationData(type: AnnotationType.rect, rect: Rect.fromPoints(_dragStart!, _dragEnd!), colorValue: c, strokeWidth: w);
      default: return null;
    }
  }

  int _hitTest(Offset tap) {
    for (int i = widget.annotations.length - 1; i >= 0; i--) {
      final a = widget.annotations[i];
      final margin = a.strokeWidth * 4 + 8.0;
      switch (a.type) {
        case AnnotationType.freehand:
          for (final p in a.points) { if ((p - tap).distance < margin) return i; }
          break;
        case AnnotationType.arrow:
          if (a.start != null && a.end != null) {
            if (_distToSegment(tap, a.start!, a.end!) < margin) return i;
          }
          break;
        case AnnotationType.rect:
          if (a.rect != null) {
            final r = a.rect!.inflate(margin);
            if (r.contains(tap)) return i;
          }
          break;
        case AnnotationType.text:
          if (a.textPosition != null && (a.textPosition! - tap).distance < margin * 2) return i;
          break;
        default:
      }
    }
    return -1;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a; final ap = p - a;
    final t = (ap.dx * ab.dx + ap.dy * ab.dy) / (ab.dx * ab.dx + ab.dy * ab.dy).clamp(0.001, double.infinity);
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (proj - p).distance;
  }
}

class _Painter extends CustomPainter {
  final List<AnnotationData> annotations;
  final int selectedIndex;
  final List<Offset> points;
  final Offset? start, end;
  final bool drawing;
  final AnnotationType type;
  final Color color;
  final double width;

  _Painter({
    required this.annotations, required this.selectedIndex, required this.points,
    required this.start, required this.end, required this.drawing, required this.type,
    required this.color, required this.width,
  });

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke;

    for (int i = 0; i < annotations.length; i++) {
      final a = annotations[i];
      final isSel = i == selectedIndex;
      p..color = a.color..strokeWidth = a.strokeWidth + (isSel ? 2 : 0);
      _draw(c, p, a.type, a.points, a.start, a.end, a.rect, a.text, a.textPosition, a.strokeWidth, a.color);
      if (isSel) {
        final hp = Paint()..color = Colors.blueAccent..strokeWidth = 2..style = PaintingStyle.stroke..blendMode = BlendMode.srcOver;
        _drawSelectionHighlight(c, hp, a);
      }
    }

    if (drawing && type != AnnotationType.select) {
      p..color = color..strokeWidth = width;
      _draw(c, p, type, points, start, end, null, null, null, width, color);
    }
  }

  void _drawSelectionHighlight(Canvas c, Paint hp, AnnotationData a) {
    switch (a.type) {
      case AnnotationType.rect:
        if (a.rect != null) c.drawRect(a.rect!.inflate(6), hp);
        break;
      case AnnotationType.arrow:
        if (a.start != null && a.end != null) {
          final r = Rect.fromPoints(a.start!, a.end!).inflate(12);
          c.drawRect(r, hp);
        }
        break;
      case AnnotationType.freehand:
        if (a.points.isNotEmpty) {
          double l = a.points[0].dx, t = a.points[0].dy, r = l, b = t;
          for (final p in a.points) {
            if (p.dx < l) l = p.dx;
            if (p.dx > r) r = p.dx;
            if (p.dy < t) t = p.dy;
            if (p.dy > b) b = p.dy;
          }
          c.drawRect(Rect.fromLTRB(l, t, r, b).inflate(12), hp);
        }
        break;
      case AnnotationType.text:
        if (a.text != null && a.textPosition != null) {
          final tp = TextPainter(
            text: TextSpan(text: a.text, style: TextStyle(fontSize: a.strokeWidth * 6)),
            textDirection: TextDirection.ltr,
          );
          tp.layout();
          c.drawRect(Rect.fromLTWH(
            a.textPosition!.dx - 4, a.textPosition!.dy - 4,
            tp.width + 8, tp.height + 8,
          ), hp);
        }
        break;
      default:
    }
  }

  void _draw(Canvas c, Paint p, AnnotationType t, List<Offset> pts, Offset? s, Offset? e, Rect? r, String? txt, Offset? tp, double sw, Color clr) {
    switch (t) {
      case AnnotationType.freehand:
        if (pts.length < 2) return;
        final path = Path()..moveTo(pts[0].dx, pts[0].dy);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        c.drawPath(path, p); break;
      case AnnotationType.arrow:
        if (s != null && e != null) {
          c.drawLine(s, e, p);
          final dx = e.dx - s.dx; final dy = e.dy - s.dy;
          final len = math.sqrt(dx * dx + dy * dy).clamp(1.0, double.infinity);
          final ux = dx / len; final uy = dy / len;
          final as = sw * 5; final px = -uy * as; final py = ux * as;
          final push = as * 0.6;
          final tipX = e.dx + ux * push;
          final tipY = e.dy + uy * push;
          final l = Offset(tipX - ux * as * 2.0 + px, tipY - uy * as * 2.0 + py);
          final rp = Offset(tipX - ux * as * 2.0 - px, tipY - uy * as * 2.0 - py);
          c.drawPath(Path()..moveTo(tipX, tipY)..lineTo(l.dx, l.dy)..lineTo(rp.dx, rp.dy)..close(), Paint()..color = clr..style = PaintingStyle.fill);
        } break;
      case AnnotationType.rect:
        final cr = r ?? (s != null && e != null ? Rect.fromPoints(s, e) : null);
        if (cr != null) c.drawRect(cr, p); break;
      case AnnotationType.text:
        if (txt != null && tp != null) {
          final tp2 = TextPainter(text: TextSpan(text: txt, style: TextStyle(color: clr, fontSize: sw * 6)), textDirection: TextDirection.ltr);
          tp2.layout(); tp2.paint(c, tp);
        } break;
      default:
    }
  }

  @override
  bool shouldRepaint(covariant _Painter d) => true;
}
