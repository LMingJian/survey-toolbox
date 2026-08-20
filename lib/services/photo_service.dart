import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PhotoService {
  static Future<String> mergeAnnotations(
    String originalPath,
    String outputPath,
    List<dynamic> annotations,
    Size imageSize,
    Size displaySize,
  ) async {
    final file = File(originalPath);
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());

    // 显示空间 → 图片空间的缩放比
    final scaleX = imageSize.width / displaySize.width;
    final scaleY = imageSize.height / displaySize.height;
    debugPrint('[Merge] imageSize: $imageSize, displaySize: $displaySize, scale: $scaleX x $scaleY');
    debugPrint('[Merge] annotations count: ${annotations.length}');

    _drawAnnotations(canvas, annotations, scaleX);

    final picture = recorder.endRecording();
    final img = await picture.toImage(imageSize.width.toInt(), imageSize.height.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);

    final outFile = File(outputPath);
    await outFile.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    img.dispose();
    return outputPath;
  }

  static void _drawAnnotations(Canvas canvas, List<dynamic> annotations, double scale) {
    for (int idx = 0; idx < annotations.length; idx++) {
      final a = annotations[idx];
      if (idx == 0) {
        debugPrint('[Merge] 首个批注 type: ${a.type}, strokeWidth: ${a.strokeWidth}, scale: $scale, scaledSW: ${a.strokeWidth * scale}');
      }
      final p = Paint()
        ..color = a.color
        ..strokeWidth = a.strokeWidth * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      switch (a.type.index) {
        case 0:
          if (a.points.length > 1) {
            final path = Path();
            path.moveTo(a.points[0].dx * scale, a.points[0].dy * scale);
            for (int i = 1; i < a.points.length; i++) {
              path.lineTo(a.points[i].dx * scale, a.points[i].dy * scale);
            }
            canvas.drawPath(path, p);
          }
          break;
        case 1:
          if (a.start != null && a.end != null) {
            final s = Offset(a.start.dx * scale, a.start.dy * scale);
            final e = Offset(a.end.dx * scale, a.end.dy * scale);
            canvas.drawLine(s, e, p);
            final dx = e.dx - s.dx;
            final dy = e.dy - s.dy;
            final len = math.sqrt(dx * dx + dy * dy).clamp(1.0, double.infinity);
            final ux = dx / len;
            final uy = dy / len;
            final as = a.strokeWidth * scale * 5;
            final px = -uy * as;
            final py = ux * as;
            final push = as * 0.6;
            final tipX = e.dx + ux * push;
            final tipY = e.dy + uy * push;
            final left = Offset(tipX - ux * as * 2.0 + px, tipY - uy * as * 2.0 + py);
            final right = Offset(tipX - ux * as * 2.0 - px, tipY - uy * as * 2.0 - py);
            final ap = Paint()..color = a.color..style = PaintingStyle.fill;
            canvas.drawPath(Path()..moveTo(tipX, tipY)..lineTo(left.dx, left.dy)..lineTo(right.dx, right.dy)..close(), ap);
          }
          break;
        case 2: // rect
          if (a.rect != null) {
            final r = Rect.fromLTRB(
              a.rect.left * scale, a.rect.top * scale,
              a.rect.right * scale, a.rect.bottom * scale,
            );
            canvas.drawRect(r, p);
          }
          break;
        case 3: // text
          if (a.text != null && a.textPosition != null) {
            final tp = TextPainter(
              text: TextSpan(
                text: a.text,
                style: TextStyle(color: a.color, fontSize: a.strokeWidth * 6 * scale),
              ),
              textDirection: TextDirection.ltr,
            );
            tp.layout();
            tp.paint(canvas, Offset(a.textPosition.dx * scale, a.textPosition.dy * scale));
          }
          break;
      }
    }
  }
}
