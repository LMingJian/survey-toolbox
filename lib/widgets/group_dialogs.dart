import 'package:flutter/material.dart';

import '../models/photo_group.dart';

/// 分组选择结果：二者只会有一个非空
class GroupAssignment {
  /// 加入已有分组
  final String? groupId;

  /// 新建分组并加入（分组名称）
  final String? newName;

  const GroupAssignment({this.groupId, this.newName});

  bool get isExisting => groupId != null;
}

/// 弹窗：把已选照片加入分组
///
/// 交互：既可以直接输入新分组名称「新建并加入」，也可以点已有分组立即加入。
/// 返回 null 表示取消。
Future<GroupAssignment?> showGroupPickerDialog(
  BuildContext context, {
  required List<PhotoGroup> groups,
  required int photoCount,
}) {
  return showDialog<GroupAssignment>(
    context: context,
    builder: (_) =>
        _GroupPickerDialog(groups: groups, photoCount: photoCount),
  );
}

/// 弹窗：重命名分组。返回新名称，null 表示取消。
Future<String?> showGroupRenameDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _GroupRenameDialog(initialName: initialName),
  );
}

class _GroupPickerDialog extends StatefulWidget {
  final List<PhotoGroup> groups;
  final int photoCount;

  const _GroupPickerDialog({required this.groups, required this.photoCount});

  @override
  State<_GroupPickerDialog> createState() => _GroupPickerDialogState();
}

class _GroupPickerDialogState extends State<_GroupPickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitNew() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, GroupAssignment(newName: name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = widget.groups;

    return AlertDialog(
      title: const Text('照片分组'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已选 ${widget.photoCount} 张照片',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: groups.isEmpty,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '新建分组',
                  hintText: '输入分组名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitNew(),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '或加入已有分组',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                for (final group in groups)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(
                      context,
                      GroupAssignment(groupId: group.id),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submitNew,
          child: const Text('新建并加入'),
        ),
      ],
    );
  }
}

class _GroupRenameDialog extends StatefulWidget {
  final String initialName;

  const _GroupRenameDialog({required this.initialName});

  @override
  State<_GroupRenameDialog> createState() => _GroupRenameDialogState();
}

class _GroupRenameDialogState extends State<_GroupRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名分组'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '分组名称',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
