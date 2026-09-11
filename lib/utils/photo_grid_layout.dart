import 'dart:ui' show Rect;

import '../models/photo_group.dart';
import '../models/photo_record.dart';

/// 一个区块（分组 或 未分组）在网格中的排布结果
///
/// 区块 = 可选的一行标题 + 若干行图片。标题使行高不再均匀，
/// 因此现有实现从「按公式算槽位」改为「预先算出每个槽位的绝对矩形」。
class PhotoGridSectionLayout {
  /// 分组 id；null 表示未分组区块
  final String? groupId;

  /// 区块标题（无标题时为空串）
  final String title;

  /// 在 `Project.groups` 中的下标；未分组区块为 -1
  final int groupIndex;

  final bool showHeader;
  final Rect? headerRect;

  /// 与 [photos] 一一对应的槽位矩形
  final List<Rect> slotRects;
  final List<PhotoRecord> photos;

  /// 整个区块的纵向范围（标题顶 → 最后一行底）
  final double bandTop;
  final double bandBottom;

  const PhotoGridSectionLayout({
    required this.groupId,
    required this.title,
    required this.groupIndex,
    required this.showHeader,
    required this.headerRect,
    required this.slotRects,
    required this.photos,
    required this.bandTop,
    required this.bandBottom,
  });

  /// 区块纵向中点：长按标题拖拽排序时用于判定目标插入位
  double get bandCenter => (bandTop + bandBottom) / 2;
}

/// 照片网格布局：把「分组区块」展开成一串绝对定位矩形
class PhotoGridLayout {
  static const double padding = 8.0;
  static const double spacing = 8.0;
  static const int columns = 3;

  /// 分组标题行高
  static const double headerHeight = 40.0;

  /// 标题与其下第一行图片的间距
  static const double headerGap = 6.0;

  /// 区块之间的间距
  static const double sectionGap = 14.0;

  final List<PhotoGridSectionLayout> sections;
  final double cellSize;
  final double totalHeight;

  const PhotoGridLayout({
    required this.sections,
    required this.cellSize,
    required this.totalHeight,
  });

  /// 分组区块（不含未分组）
  List<PhotoGridSectionLayout> get groupSections =>
      sections.where((s) => s.groupIndex >= 0).toList();

  /// 某张照片所在的区块；找不到返回 null
  PhotoGridSectionLayout? sectionOf(String photoId) {
    for (final s in sections) {
      if (s.photos.any((p) => p.id == photoId)) return s;
    }
    return null;
  }

  /// 某张照片的槽位矩形
  Rect? rectOf(String photoId) {
    final s = sectionOf(photoId);
    if (s == null) return null;
    final i = s.photos.indexWhere((p) => p.id == photoId);
    if (i < 0 || i >= s.slotRects.length) return null;
    return s.slotRects[i];
  }

  /// 依据「分组顺序 + 各组内顺序」计算布局
  ///
  /// [members] 以 groupId 为键（null = 未分组），值即该区块内的照片顺序。
  static PhotoGridLayout build({
    required double width,
    required List<PhotoGroup> groups,
    required Map<String?, List<PhotoRecord>> members,
  }) {
    final cellSize =
        (width - padding * 2 - spacing * (columns - 1)) / columns;

    // 1. 组装区块顺序：各分组（按 groups 顺序）→ 未分组（置底）
    final drafts = <_Draft>[];
    for (int i = 0; i < groups.length; i++) {
      drafts.add(
        _Draft(
          groupId: groups[i].id,
          title: groups[i].name,
          groupIndex: i,
          showHeader: true,
          photos: members[groups[i].id] ?? const <PhotoRecord>[],
        ),
      );
    }
    final ungrouped = members[null] ?? const <PhotoRecord>[];
    if (groups.isEmpty) {
      // 还没有任何分组时保持原有观感：不加标题、直接平铺
      drafts.add(
        _Draft(
          groupId: null,
          title: '',
          groupIndex: -1,
          showHeader: false,
          photos: ungrouped,
        ),
      );
    } else if (ungrouped.isNotEmpty) {
      drafts.add(
        _Draft(
          groupId: null,
          title: '未分组',
          groupIndex: -1,
          showHeader: true,
          photos: ungrouped,
        ),
      );
    }

    // 2. 逐块排布
    var y = padding;
    final sections = <PhotoGridSectionLayout>[];
    for (int s = 0; s < drafts.length; s++) {
      final draft = drafts[s];
      final bandTop = y;

      Rect? headerRect;
      if (draft.showHeader) {
        headerRect = Rect.fromLTWH(
          padding,
          y,
          width - padding * 2,
          headerHeight,
        );
        y += headerHeight + headerGap;
      }

      final slots = <Rect>[];
      final rows = (draft.photos.length + columns - 1) ~/ columns;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < columns; c++) {
          final i = r * columns + c;
          if (i >= draft.photos.length) break;
          slots.add(
            Rect.fromLTWH(
              padding + c * (cellSize + spacing),
              y,
              cellSize,
              cellSize,
            ),
          );
        }
        y += cellSize + spacing;
      }
      if (draft.photos.isNotEmpty) y -= spacing; // 去掉最后一行的行间距
      final bandBottom = y;
      if (s != drafts.length - 1) y += sectionGap;

      sections.add(
        PhotoGridSectionLayout(
          groupId: draft.groupId,
          title: draft.title,
          groupIndex: draft.groupIndex,
          showHeader: draft.showHeader,
          headerRect: headerRect,
          slotRects: slots,
          photos: List<PhotoRecord>.unmodifiable(draft.photos),
          bandTop: bandTop,
          bandBottom: bandBottom,
        ),
      );
    }

    return PhotoGridLayout(
      sections: sections,
      cellSize: cellSize,
      totalHeight: y + padding,
    );
  }
}

class _Draft {
  final String? groupId;
  final String title;
  final int groupIndex;
  final bool showHeader;
  final List<PhotoRecord> photos;

  const _Draft({
    required this.groupId,
    required this.title,
    required this.groupIndex,
    required this.showHeader,
    required this.photos,
  });
}
