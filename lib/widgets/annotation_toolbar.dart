import 'package:flutter/material.dart';
import '../models/annotation_data.dart';

class AnnotationToolbar extends StatelessWidget {
  final AnnotationType currentType;
  final Color currentColor;
  final double currentWidth;
  final void Function(AnnotationType type) onTypeChanged;
  final void Function(Color color) onColorChanged;
  final void Function(double width) onWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onDelete;

  static const availableColors = [
    Colors.red,
    //Colors.orange,
    Colors.yellow,
    //Colors.green,
    Colors.blue,
    //Colors.purple,
    Colors.black,
    Colors.white,
  ];

  // static const availableWidths = [3.0, 4.0, 8.0];
  static const availableWidths = [3.0];

  const AnnotationToolbar({
    super.key,
    required this.currentType,
    required this.currentColor,
    required this.currentWidth,
    required this.onTypeChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onUndo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行：5 种工具，平分宽度
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ToolButton(
                  icon: Icons.gesture,
                  label: '画笔',
                  isSelected: currentType == AnnotationType.freehand,
                  onTap: () => onTypeChanged(AnnotationType.freehand),
                ),
                _ToolButton(
                  icon: Icons.arrow_upward,
                  label: '箭头',
                  isSelected: currentType == AnnotationType.arrow,
                  onTap: () => onTypeChanged(AnnotationType.arrow),
                ),
                _ToolButton(
                  icon: Icons.touch_app,
                  label: '选择',
                  isSelected: currentType == AnnotationType.select,
                  onTap: () => onTypeChanged(AnnotationType.select),
                ),
                _ToolButton(
                  icon: Icons.rectangle_outlined,
                  label: '矩形',
                  isSelected: currentType == AnnotationType.rect,
                  onTap: () => onTypeChanged(AnnotationType.rect),
                ),
                _ToolButton(
                  icon: Icons.text_fields,
                  label: '文字',
                  isSelected: currentType == AnnotationType.text,
                  onTap: () => onTypeChanged(AnnotationType.text),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 第二行：颜色 + 粗细 + 操作（横向滚动，绝不溢出）
            SizedBox(
              height: 36,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 颜色
                    ...availableColors.map(
                      (c) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: () => onColorChanged(c),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: currentColor == c
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade400,
                                width: currentColor == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 22,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 8),
                    // 粗细
                    ...availableWidths.map(
                      (w) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: () => onWidthChanged(w),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: currentWidth == w
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade400,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: w * 3,
                                height: w * 3,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 22,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 4),
                    // 撤销
                    IconButton(
                      icon: const Icon(Icons.undo),
                      tooltip: '撤销',
                      onPressed: onUndo,
                      iconSize: 20,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    // 清空
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '删除',
                      onPressed: onDelete,
                      iconSize: 20,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
