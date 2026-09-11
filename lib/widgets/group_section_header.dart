import 'package:flutter/material.dart';

import '../utils/photo_grid_layout.dart';

/// 分组区块的标题行
///
/// 纯展示组件：长按拖拽的手势由外层（照片列表）负责绑定，
/// 这里只负责视觉与「重命名 / 解散」菜单。
class GroupSectionHeader extends StatelessWidget {
  final String title;
  final int photoCount;

  /// 是否可长按拖拽排序（未分组区块不可拖拽）
  final bool draggable;

  /// 正在被拖拽（高亮 + 抬升）
  final bool dragging;

  final VoidCallback? onRename;
  final VoidCallback? onDissolve;

  const GroupSectionHeader({
    super.key,
    required this.title,
    required this.photoCount,
    this.draggable = true,
    this.dragging = false,
    this.onRename,
    this.onDissolve,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasMenu = onRename != null || onDissolve != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      height: PhotoGridLayout.headerHeight,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: dragging ? 0.20 : 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dragging
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0.28),
          width: dragging ? 2 : 1,
        ),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          if (draggable) ...[
            Icon(
              Icons.drag_indicator,
              size: 18,
              color: scheme.primary.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$photoCount 张',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SizedBox(
            width: 40,
            child: hasMenu
                ? PopupMenuButton<String>(
                    tooltip: '分组操作',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: Icon(
                      Icons.more_vert,
                      color: scheme.onSurfaceVariant,
                    ),
                    onSelected: (value) {
                      if (value == 'rename') onRename?.call();
                      if (value == 'dissolve') onDissolve?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'dissolve', child: Text('解散分组')),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
