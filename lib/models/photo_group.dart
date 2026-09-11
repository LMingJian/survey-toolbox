/// 照片分组
///
/// 分组只承载「名称 + 顺序」，成员关系挂在 [PhotoRecord.groupId] 上。
/// 分组顺序即 `Project.groups` 的列表顺序，决定列表中各区块的先后。
class PhotoGroup {
  final String id;
  String name;
  final DateTime createdAt;

  PhotoGroup({required this.id, required this.name, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PhotoGroup.fromJson(Map<String, dynamic> json) {
    return PhotoGroup(
      id: json['id'],
      name: json['name'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
    );
  }
}
