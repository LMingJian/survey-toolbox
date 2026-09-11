import 'annotation_data.dart';

class PhotoRecord {
  final String id;
  final String originalPath;       // 原图存储路径
  String? annotatedPath;           // 批注合并后的图片路径
  String note;                     // 下方文字说明
  final DateTime captureTime;      // 拍摄时间
  List<AnnotationData> annotations; // 批注数据
  String? groupId;                 // 所属分组 id（null = 未分组）

  PhotoRecord({
    required this.id,
    required this.originalPath,
    this.annotatedPath,
    this.note = '',
    required this.captureTime,
    List<AnnotationData>? annotations,
    this.groupId,
  }) : annotations = annotations ?? [];

  bool get hasAnnotations => annotations.isNotEmpty;
  bool get hasNote => note.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalPath': originalPath,
      'annotatedPath': annotatedPath,
      'note': note,
      'captureTime': captureTime.toIso8601String(),
      'annotations': annotations.map((a) => a.toJson()).toList(),
      'groupId': groupId,
    };
  }

  factory PhotoRecord.fromJson(Map<String, dynamic> json) {
    return PhotoRecord(
      id: json['id'],
      originalPath: json['originalPath'],
      annotatedPath: json['annotatedPath'],
      note: json['note'] ?? '',
      captureTime: DateTime.parse(json['captureTime']),
      annotations: (json['annotations'] as List)
          .map((a) => AnnotationData.fromJson(a))
          .toList(),
      // 旧数据没有该字段，缺省为未分组
      groupId: json['groupId'],
    );
  }
}
