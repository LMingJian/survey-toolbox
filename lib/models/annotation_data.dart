import 'dart:ui';

enum AnnotationType {
  freehand,
  arrow,
  rect,
  text,
  select,
}

class AnnotationData {
  final AnnotationType type;
  final List<Offset> points;       // 自由画笔路径点
  final Offset? start;             // 直线起点
  final Offset? end;               // 直线终点
  final Rect? rect;                // 矩形区域
  final String? text;              // 文字内容
  final Offset? textPosition;      // 文字位置
  final int colorValue;            // Color.value
  final double strokeWidth;

  AnnotationData({
    required this.type,
    this.points = const [],
    this.start,
    this.end,
    this.rect,
    this.text,
    this.textPosition,
    required this.colorValue,
    this.strokeWidth = 3.0,
  });

  Color get color => Color(colorValue);

  AnnotationData translated(Offset delta) {
    return copyWith(
      points: points.map((p) => p + delta).toList(),
      start: start != null ? start! + delta : null,
      end: end != null ? end! + delta : null,
      rect: rect?.translate(delta.dx, delta.dy),
      textPosition: textPosition != null ? textPosition! + delta : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      'start': start != null ? {'dx': start!.dx, 'dy': start!.dy} : null,
      'end': end != null ? {'dx': end!.dx, 'dy': end!.dy} : null,
      'rect': rect != null
          ? {'left': rect!.left, 'top': rect!.top, 'right': rect!.right, 'bottom': rect!.bottom}
          : null,
      'text': text,
      'textPosition': textPosition != null
          ? {'dx': textPosition!.dx, 'dy': textPosition!.dy}
          : null,
      'colorValue': colorValue,
      'strokeWidth': strokeWidth,
    };
  }

  factory AnnotationData.fromJson(Map<String, dynamic> json) {
    return AnnotationData(
      type: AnnotationType.values[json['type']],
      points: (json['points'] as List)
          .map((p) => Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()))
          .toList(),
      start: json['start'] != null
          ? Offset((json['start']['dx'] as num).toDouble(), (json['start']['dy'] as num).toDouble())
          : null,
      end: json['end'] != null
          ? Offset((json['end']['dx'] as num).toDouble(), (json['end']['dy'] as num).toDouble())
          : null,
      rect: json['rect'] != null
          ? Rect.fromLTRB(
              (json['rect']['left'] as num).toDouble(),
              (json['rect']['top'] as num).toDouble(),
              (json['rect']['right'] as num).toDouble(),
              (json['rect']['bottom'] as num).toDouble(),
            )
          : null,
      text: json['text'],
      textPosition: json['textPosition'] != null
          ? Offset(
              (json['textPosition']['dx'] as num).toDouble(),
              (json['textPosition']['dy'] as num).toDouble(),
            )
          : null,
      colorValue: json['colorValue'],
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
    );
  }

  AnnotationData copyWith({
    AnnotationType? type,
    List<Offset>? points,
    Offset? start,
    Offset? end,
    Rect? rect,
    String? text,
    Offset? textPosition,
    int? colorValue,
    double? strokeWidth,
  }) {
    return AnnotationData(
      type: type ?? this.type,
      points: points ?? this.points,
      start: start ?? this.start,
      end: end ?? this.end,
      rect: rect ?? this.rect,
      text: text ?? this.text,
      textPosition: textPosition ?? this.textPosition,
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}
