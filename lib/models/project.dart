import 'photo_record.dart';

class Project {
  final String id;
  String name;               // 项目名称（可选）
  String location;           // 勘察地点（可选）
  DateTime? surveyDate;      // 勘察日期（可选）
  final DateTime createdAt;
  List<PhotoRecord> photos;

  Project({
    required this.id,
    this.name = '',
    this.location = '',
    this.surveyDate,
    DateTime? createdAt,
    List<PhotoRecord>? photos,
  }) : photos = photos ?? [],
      createdAt = createdAt ?? DateTime.now();

  int get photoCount => photos.length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'surveyDate': surveyDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'photos': photos.map((p) => p.toJson()).toList(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'] ?? '',
      location: json['location'] ?? '',
      surveyDate: json['surveyDate'] != null
          ? DateTime.parse(json['surveyDate'])
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      photos: (json['photos'] as List)
          .map((p) => PhotoRecord.fromJson(p))
          .toList(),
    );
  }
}
