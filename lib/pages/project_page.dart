import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/photo_group.dart';
import '../models/project.dart';
import '../models/photo_record.dart';
import '../services/project_service.dart';
import '../services/export_service.dart';
import '../utils/photo_grid_layout.dart';
import '../widgets/group_dialogs.dart';
import '../widgets/group_section_header.dart';

import 'camera_page.dart';
import 'photo_editor_page.dart';

class ProjectPage extends StatefulWidget {
  final Project project;
  final ProjectService projectService;

  const ProjectPage({
    super.key,
    required this.project,
    required this.projectService,
  });

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  final _imagePicker = ImagePicker();
  late Project _project;
  bool _exporting = false;

  // ---------- 长按拖拽排序状态 ----------
  // 网格常量统一由 PhotoGridLayout 提供：带分组标题后行高不再均匀，
  // 槽位改由 PhotoGridLayout.build 预先算出绝对矩形。

  // 拖拽边缘自动滚动参数
  static const double _autoScrollZone = 72.0; // 视口边缘触发区（逻辑像素）
  static const double _autoScrollSpeed =
      12.0; // 最大滚动速度（px/tick，16ms 一跳 ≈ 750px/s）

  final _gridStackKey = GlobalKey();
  final _scrollController = ScrollController(); // 网格滚动控制器（自动滚动用）
  Timer? _autoScrollTimer; // 边缘自动滚动定时器
  Offset? _lastGlobalPos; // 最近一次手指全局坐标（自动滚动 tick 用）
  double _autoScrollVelocity = 0; // 当前滚动速度（像素/tick，负=向上）

  // 照片拖拽：仅允许在同一分组内重排
  bool _isDragging = false; // 拖拽进行中（长按触发后锁定滚动）
  int? _dragIndex; // 被拖照片在 _project.photos 中的索引
  int? _hoverLocalIndex; // 目标插入位（所属分组内、移除拖拽项后的下标）
  Rect? _dragStartRect; // 拖拽开始时该照片占用的槽位（原位占位）
  List<Rect> _dragSectionSlots = const []; // 所属分组槽位（拖拽中冻结，避免抖动）
  Offset _dragOffset = Offset.zero; // 手指相对网格 Stack 的位置

  // 分组标题拖拽排序
  bool _isGroupDragging = false;
  int? _dragGroupIndex; // 被拖分组在 _project.groups 中的下标
  int? _hoverGroupIndex; // 目标插入位（移除被拖分组后的下标）
  List<PhotoGridSectionLayout> _frozenGroupBands = const []; // 拖拽开始时的区块带

  PhotoGridLayout? _lastLayout; // 最近一次布局结果（拖拽起点计算用）

  bool _deleteMode = false; // 删除模式开关（初始关闭）
  bool _groupMode = false; // 分组模式开关（多选）
  final Set<String> _selectedPhotoIds = {}; // 分组模式下已勾选的照片

  @override
  void initState() {
    super.initState();
    _project = widget.project;
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshProject() async {
    debugPrint('[Refresh] reloading project: ${_project.id}');
    final project = await widget.projectService.getProject(_project.id);
    if (project != null && mounted) {
      final annotCount = project.photos
          .where((p) => p.annotatedPath != null)
          .length;
      debugPrint(
        '[Refresh] loaded, photos: ${project.photos.length}, with annotations: $annotCount',
      );
      setState(() => _project = project);
    }
  }

  /// 相机实现开关
  ///
  /// - `true`（默认）：使用应用内自研相机 [CameraPage]，点快门即成像落盘，
  ///   全程无任何确认步骤；
  /// - `false`：回退到系统相机（image_picker）。系统相机 App 自带的
  ///   「确认 / 重拍」页由相机 App 提供，本应用无法关闭，仅作为自研相机
  ///   出现异常时的备用通路。
  static const bool _useBuiltInCamera = true;

  Future<void> _takePhoto() async {
    if (_useBuiltInCamera) {
      await _openBuiltInCamera();
    } else {
      await _takePhotoWithSystemCamera();
    }
  }

  /// 应用内自研相机：拍完停留相机页可连拍，返回后刷新列表
  Future<void> _openBuiltInCamera() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(
          projectId: _project.id,
          projectService: widget.projectService,
        ),
      ),
    );
    await _refreshProject();
  }

  /// 【备用通路 · 默认停用】系统相机（image_picker）
  ///
  /// 保留原因：自研相机若在个别机型上异常，把 [_useBuiltInCamera] 改为 false
  /// 即可立即回退到原实现。注意此路径存在系统相机自带的确认页。
  Future<void> _takePhotoWithSystemCamera() async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (xFile != null) {
        await _addPhotoFromFile(File(xFile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final xFiles = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
      );
      for (final xFile in xFiles) {
        await _addPhotoFromFile(File(xFile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    }
  }

  Future<void> _addPhotoFromFile(File sourceFile) async {
    final recordId = const Uuid().v4();
    final destPath = await widget.projectService.getNewPhotoPath(
      _project.id,
      recordId,
    );

    // 复制文件到项目目录
    await sourceFile.copy(destPath);

    final record = PhotoRecord(
      id: recordId,
      originalPath: destPath,
      captureTime: DateTime.now(),
    );

    await widget.projectService.addPhoto(_project.id, record);
    await _refreshProject();

    // 说明：此处不再自动跳转批注编辑页。
    // 原行为是拍照后立刻进入批注页并要求点右上角 ✓ 保存，与系统相机自带的
    // 重拍确认叠加成「两次确认」，用户反馈过于繁琐。现改为拍完即入列表；
    // 需要批注时在列表中点开该照片，在查看页点右上角铅笔图标进入编辑。
  }

  void _openPhoto(PhotoRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoEditorPage(
          photoRecord: record,
          allPhotos: _project.photos,
          projectId: _project.id,
          projectService: widget.projectService,
        ),
      ),
    ).then((_) => _refreshProject());
  }

  Future<String> _getDownloadDir() async {
    // 用 path_provider 拿到公共 Download 目录
    final dirs = await getExternalStorageDirectories(
      type: StorageDirectory.downloads,
    );
    if (dirs != null &&
        dirs.isNotEmpty &&
        !dirs.first.path.contains('Android/data')) {
      return dirs.first.path;
    }
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _exportWord() async {
    setState(() => _exporting = true);
    try {
      final fileName =
          '${_project.name.isNotEmpty ? _project.name : '勘察记录'}'
          '_${DateTime.now().millisecondsSinceEpoch}.docx';

      debugPrint('[Export] 生成文档...');
      final exportService = ExportService();
      final bytes = await exportService.exportToBytes(_project);
      debugPrint('[Export] 生成完成, ${bytes.length} bytes');

      // 直接写到 Download 目录，不用 SAF
      final outputDir = await _getDownloadDir();
      final file = File('$outputDir/$fileName');
      await file.writeAsBytes(bytes);
      debugPrint('[Export] 已保存: ${file.path}');
      if (mounted) {
        final goToFile = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导出成功'),
            content: Text('文件已保存：\n$fileName'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('完成'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('前往文件管理查看'),
              ),
            ],
          ),
        );
        if (goToFile == true) {
          OpenFilex.open(file.path);
        }
      }
    } catch (e, st) {
      debugPrint('[Export] 失败: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败: $e'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------- 分组数据辅助 ----------

  /// 照片的实际归属分组：指向已不存在的分组时视为未分组
  String? _effectiveGroupId(PhotoRecord photo) {
    final groupId = photo.groupId;
    if (groupId == null) return null;
    return _project.groups.any((g) => g.id == groupId) ? groupId : null;
  }

  /// 按分组归集照片（保持各自在数组中的相对顺序）；键 null 表示未分组
  Map<String?, List<PhotoRecord>> _sectionMembers() {
    final members = <String?, List<PhotoRecord>>{};
    for (final photo in _project.photos) {
      members.putIfAbsent(_effectiveGroupId(photo), () => []).add(photo);
    }
    return members;
  }

  /// 按「各分组顺序 → 未分组置底」把归集结果压回扁平数组
  ///
  /// 维护该不变式后：数组顺序 == 列表显示顺序（不含标题行），
  /// 后续所有顺序计算都只需依赖数组顺序。
  List<PhotoRecord> _flattenMembers(Map<String?, List<PhotoRecord>> members) {
    final result = <PhotoRecord>[];
    for (final group in _project.groups) {
      result.addAll(members[group.id] ?? const <PhotoRecord>[]);
    }
    result.addAll(members[null] ?? const <PhotoRecord>[]);
    return result;
  }

  /// 拖拽过程中的分组顺序（把被拖分组移到目标插入位）
  List<PhotoGroup> _tentativeGroups() {
    if (!_isGroupDragging ||
        _dragGroupIndex == null ||
        _hoverGroupIndex == null) {
      return _project.groups;
    }
    final list = List<PhotoGroup>.from(_project.groups);
    final item = list.removeAt(_dragGroupIndex!);
    list.insert(_hoverGroupIndex!.clamp(0, list.length), item);
    return list;
  }

  /// 拖拽过程中的区块成员（把被拖照片移到所属分组内的目标位置）
  Map<String?, List<PhotoRecord>> _tentativeMembers() {
    final members = _sectionMembers();
    if (!_isDragging || _dragIndex == null || _hoverLocalIndex == null) {
      return members;
    }
    if (_dragIndex! >= _project.photos.length) return members;
    final dragged = _project.photos[_dragIndex!];
    final groupId = _effectiveGroupId(dragged);
    final list = members.putIfAbsent(groupId, () => <PhotoRecord>[]);
    list.removeWhere((p) => p.id == dragged.id);
    list.insert(_hoverLocalIndex!.clamp(0, list.length), dragged);
    return members;
  }

  // ---------- 长按拖拽排序（照片：仅限同一分组内重排）----------

  /// 全局坐标 → 网格 Stack 局部坐标
  Offset _gridOffsetOf(Offset globalPos) {
    final box = _gridStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return _dragOffset;
    return box.globalToLocal(globalPos);
  }

  void _onLongPressStart(int index, LongPressStartDetails d) {
    // 防御：拖拽进行中（如多点触控第二根手指长按）忽略新的触发，避免状态被覆盖
    if (_isDragging) return;
    final layout = _lastLayout;
    if (layout == null || index < 0 || index >= _project.photos.length) return;
    final photo = _project.photos[index];
    final section = layout.sectionOf(photo.id);
    if (section == null) return;

    HapticFeedback.mediumImpact(); // 长按进入拖拽的触觉反馈
    setState(() {
      _isDragging = true;
      _dragIndex = index;
      // 槽位与起始矩形一次性冻结：组内重排不改变分组几何，因此拖拽中不会漂移
      _dragSectionSlots = section.slotRects;
      _dragStartRect = layout.rectOf(photo.id);
      _hoverLocalIndex = section.photos.indexWhere((p) => p.id == photo.id);
      _dragOffset = _gridOffsetOf(d.globalPosition);
    });
    debugPrint(
      '[Drag] START index=$index, group=${section.groupId}, '
      'slots=${section.slotRects.length}, rect=$_dragStartRect',
    );
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    _lastGlobalPos = d.globalPosition;
    final offset = _gridOffsetOf(d.globalPosition);
    setState(() {
      _dragOffset = offset;
      _hoverLocalIndex = _computeHoverLocalIndex(offset);
    });
    _updateAutoScroll();
  }

  void _onLongPressEnd() {
    final dragIndex = _dragIndex;
    final localIndex = _hoverLocalIndex;
    debugPrint(
      '[Drag] END dragIndex=$dragIndex, hoverLocal=$localIndex, '
      'photos=${_project.photos.length}',
    );
    _cancelAutoScroll();
    if (dragIndex == null || localIndex == null) {
      _resetPhotoDrag();
      return;
    }

    final dragged = _project.photos[dragIndex];
    final groupId = _effectiveGroupId(dragged);
    final members = _sectionMembers();
    final list = members.putIfAbsent(groupId, () => <PhotoRecord>[]);
    list.removeWhere((p) => p.id == dragged.id);
    list.insert(localIndex.clamp(0, list.length), dragged);
    members[groupId] = list;

    setState(() {
      _project.photos = _flattenMembers(members);
      _isDragging = false;
      _dragIndex = null;
      _hoverLocalIndex = null;
      _dragStartRect = null;
      _dragSectionSlots = const [];
    });
    _persistProject();
  }

  void _onLongPressCancel() {
    debugPrint('[Drag] CANCEL (drag aborted, state reset)');
    _cancelAutoScroll();
    _resetPhotoDrag();
  }

  void _resetPhotoDrag() {
    setState(() {
      _isDragging = false;
      _dragIndex = null;
      _hoverLocalIndex = null;
      _dragStartRect = null;
      _dragSectionSlots = const [];
    });
  }

  /// 手指位置 → 所属分组内的目标插入位
  ///
  /// 槽位按「阅读顺序」比较：先比行（y），同行再比列（x）。
  /// 行距远大于列宽，用 `y * 100000 + x` 压成一维键即可保证顺序正确。
  int _computeHoverLocalIndex(Offset pos) {
    final slots = _dragSectionSlots;
    if (slots.isEmpty) return 0;
    final fingerKey = pos.dy * 100000 + pos.dx;
    for (int i = 0; i < slots.length; i++) {
      final center = slots[i].center;
      if (fingerKey < center.dy * 100000 + center.dx) return i;
    }
    // 落在最后一个槽位之后：最大插入位 = 移除拖拽项后的末尾
    return slots.length - 1;
  }

  // ---------- 长按组标题拖拽排序（调整分组顺序）----------

  void _onGroupLongPressStart(int groupIndex, LongPressStartDetails d) {
    if (_isGroupDragging || _isDragging) return;
    final layout = _lastLayout;
    if (layout == null ||
        groupIndex < 0 ||
        groupIndex >= _project.groups.length) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _isGroupDragging = true;
      _dragGroupIndex = groupIndex;
      _hoverGroupIndex = groupIndex;
      // 冻结拖拽开始时的区块带：实时布局会随目标位重排，用实时值会来回抖动
      _frozenGroupBands = layout.groupSections;
    });
    debugPrint(
      '[GroupDrag] START index=$groupIndex, bands=${_frozenGroupBands.length}',
    );
  }

  void _onGroupLongPressMove(LongPressMoveUpdateDetails d) {
    if (_frozenGroupBands.isEmpty) return;
    _lastGlobalPos = d.globalPosition;
    final target = _groupHoverTargetFor(d.globalPosition);
    if (target != _hoverGroupIndex) {
      debugPrint('[GroupDrag] MOVE hover=$target');
      setState(() => _hoverGroupIndex = target);
    }
    _updateAutoScroll();
  }

  /// 手指全局坐标 → 分组拖拽的目标插入位
  ///
  /// 判定基准是拖拽开始时冻结的区块带：手指越过某区块的纵向中点即插到其之前，
  /// 全部越过则落到最后一组。用冻结值而非实时布局，避免重排引发来回抖动。
  int _groupHoverTargetFor(Offset globalPos) {
    final bands = _frozenGroupBands;
    if (bands.isEmpty) return _hoverGroupIndex ?? 0;
    final localY = _gridOffsetOf(globalPos).dy;
    for (int i = 0; i < bands.length; i++) {
      if (localY < bands[i].bandCenter) return i;
    }
    return bands.length - 1;
  }

  void _onGroupLongPressEnd() {
    _cancelAutoScroll();
    final from = _dragGroupIndex;
    final to = _hoverGroupIndex;
    if (from == null || to == null || from >= _project.groups.length) {
      _resetGroupDrag();
      return;
    }
    final groups = List<PhotoGroup>.from(_project.groups);
    final item = groups.removeAt(from);
    groups.insert(to.clamp(0, groups.length), item);
    debugPrint('[GroupDrag] END from=$from to=$to');
    setState(() {
      _project.groups = groups;
      _isGroupDragging = false;
      _dragGroupIndex = null;
      _hoverGroupIndex = null;
      _frozenGroupBands = const [];
    });
    _persistProject();
  }

  void _onGroupLongPressCancel() {
    debugPrint('[GroupDrag] CANCEL');
    _cancelAutoScroll();
    _resetGroupDrag();
  }

  void _resetGroupDrag() {
    setState(() {
      _isGroupDragging = false;
      _dragGroupIndex = null;
      _hoverGroupIndex = null;
      _frozenGroupBands = const [];
    });
  }

  // ---------- 拖拽边缘自动滚动 ----------

  /// 检测手指是否位于视口上/下边缘区，按进入深度启停自动滚动
  void _updateAutoScroll() {
    final globalPos = _lastGlobalPos;
    if (globalPos == null || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final stackBox =
        _gridStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    // 视口顶部全局 y = Stack 顶部全局 y + 已滚动偏移（内容上滚时 Stack 上移）
    final viewportTop = stackBox.localToGlobal(Offset.zero).dy + pos.pixels;
    final viewportH = pos.viewportDimension; // 精确视口高度（不含 AppBar/按钮栏）
    final localY = globalPos.dy - viewportTop; // 手指相对视口顶部的 y

    double v = 0;
    if (localY < _autoScrollZone) {
      // 上边缘：向上滚，速度随进入深度线性增加
      v =
          -((_autoScrollZone - localY) / _autoScrollZone)
              .clamp(0.0, 1.0)
              .toDouble() *
          _autoScrollSpeed;
    } else if (localY > viewportH - _autoScrollZone) {
      // 下边缘：向下滚
      v =
          ((localY - (viewportH - _autoScrollZone)) / _autoScrollZone)
              .clamp(0.0, 1.0)
              .toDouble() *
          _autoScrollSpeed;
    }

    if (v != 0) {
      debugPrint(
        '[AutoScroll] localY=$localY, viewportH=$viewportH, '
        'pixels=${pos.pixels}, v=$v',
      );
    }
    _autoScrollVelocity = v;
    if (v != 0 && pos.maxScrollExtent > 0) {
      _autoScrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _tickAutoScroll(),
      );
    } else {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
    }
  }

  /// 自动滚动 tick：按当前速度滚动一帧，并重算拖拽坐标与目标位
  void _tickAutoScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final current = pos.pixels;
    // _autoScrollVelocity 单位 = px/tick（16ms），直接累加，勿再乘时间
    final target = (current + _autoScrollVelocity)
        .clamp(0.0, pos.maxScrollExtent)
        .toDouble();
    if ((target - current).abs() < 0.5) {
      // 已到边界，停止滚动
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }
    pos.jumpTo(target);
    debugPrint(
      '[AutoScroll] tick pixels=${pos.pixels.toStringAsFixed(1)}, '
      'photoHover=$_hoverLocalIndex, groupHover=$_hoverGroupIndex',
    );
    // 滚动后 Stack 内容位移，用最新手指位置重算目标位
    if (_lastGlobalPos != null && mounted) {
      setState(() {
        if (_isGroupDragging) {
          _hoverGroupIndex = _groupHoverTargetFor(_lastGlobalPos!);
        } else {
          _dragOffset = _gridOffsetOf(_lastGlobalPos!);
          _hoverLocalIndex = _computeHoverLocalIndex(_dragOffset);
        }
      });
    }
  }

  /// 停止自动滚动并清理状态
  void _cancelAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollVelocity = 0;
    _lastGlobalPos = null;
  }

  /// 顺序/分组结果持久化 → projects.json
  Future<void> _persistProject() async {
    await widget.projectService.updateProject(_project);
  }

  /// 切换删除模式（与分组模式互斥，同时取消进行中的拖拽）
  void _toggleDeleteMode() {
    _cancelAutoScroll();
    setState(() {
      _deleteMode = !_deleteMode;
      if (_deleteMode) {
        _groupMode = false;
        _selectedPhotoIds.clear();
      }
      _isDragging = false;
      _dragIndex = null;
      _hoverLocalIndex = null;
      _dragStartRect = null;
      _dragSectionSlots = const [];
    });
  }

  // ---------- 分组模式 ----------

  /// 切换分组模式（与删除模式互斥）
  void _toggleGroupMode() {
    _cancelAutoScroll();
    setState(() {
      _groupMode = !_groupMode;
      if (_groupMode) _deleteMode = false;
      _selectedPhotoIds.clear();
      _isDragging = false;
      _dragIndex = null;
      _hoverLocalIndex = null;
      _dragStartRect = null;
      _dragSectionSlots = const [];
    });
  }

  void _togglePhotoSelection(String photoId) {
    setState(() {
      if (!_selectedPhotoIds.remove(photoId)) {
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  /// 确认分组：弹窗新建分组或加入已有分组
  Future<void> _confirmGrouping() async {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先点选要分组的照片')));
      return;
    }

    final result = await showGroupPickerDialog(
      context,
      groups: List<PhotoGroup>.from(_project.groups),
      photoCount: _selectedPhotoIds.length,
    );
    if (result == null || !mounted) return;

    PhotoGroup target;
    if (result.isExisting) {
      final index = _project.groups.indexWhere((g) => g.id == result.groupId);
      if (index < 0) return; // 分组已不存在
      target = _project.groups[index];
    } else {
      target = PhotoGroup(id: const Uuid().v4(), name: result.newName!);
    }

    final targetId = target.id;
    final movedCount = _selectedPhotoIds.length;

    // 新分组必须先入列：_flattenMembers 是按 _project.groups 的顺序拼装的
    final isNewGroup = !_project.groups.any((g) => g.id == targetId);
    if (isNewGroup) _project.groups.add(target);

    final members = <String?, List<PhotoRecord>>{};
    final newlyJoined = <PhotoRecord>[];

    for (final photo in _project.photos) {
      final oldGroupId = _effectiveGroupId(photo);
      if (_selectedPhotoIds.contains(photo.id)) {
        photo.groupId = targetId;
        // 新加入该组的排到该组末尾；原本就在该组的保持原相对位置
        if (oldGroupId != targetId) {
          newlyJoined.add(photo);
          continue;
        }
      }
      members.putIfAbsent(oldGroupId, () => []).add(photo);
    }
    members.putIfAbsent(targetId, () => []).addAll(newlyJoined);

    setState(() {
      _project.photos = _flattenMembers(members);
      _groupMode = false;
      _selectedPhotoIds.clear();
    });
    await widget.projectService.updateProject(_project);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isNewGroup
              ? '已新建分组「${target.name}」并加入 $movedCount 张照片'
              : '已将 $movedCount 张照片加入「${target.name}」',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 重命名分组
  Future<void> _renameGroup(int groupIndex) async {
    if (groupIndex < 0 || groupIndex >= _project.groups.length) return;
    final group = _project.groups[groupIndex];
    final newName = await showGroupRenameDialog(
      context,
      initialName: group.name,
    );
    if (newName == null || !mounted) return;
    setState(() => group.name = newName);
    await widget.projectService.updateProject(_project);
  }

  /// 解散分组：组内照片回到未分组，照片本身不删除
  Future<void> _dissolveGroup(int groupIndex) async {
    if (groupIndex < 0 || groupIndex >= _project.groups.length) return;
    final group = _project.groups[groupIndex];
    final count = _project.photos
        .where((p) => _effectiveGroupId(p) == group.id)
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散分组'),
        content: Text(
          '确定解散分组「${group.name}」吗？\n'
          '组内 $count 张照片将回到未分组，照片本身不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解散'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    for (final photo in _project.photos) {
      if (photo.groupId == group.id) photo.groupId = null;
    }
    setState(() {
      _project.groups.removeAt(groupIndex);
      _project.photos = _flattenMembers(_sectionMembers());
    });
    await widget.projectService.updateProject(_project);
  }

  /// 删除照片（二次确认防误触），确认后移除数据源并刷新界面
  Future<void> _confirmDeletePhoto(PhotoRecord photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('确定要删除这张照片吗？\n删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.projectService.deletePhoto(_project.id, photo.id);
    if (!mounted) return;
    setState(() {
      _project.photos.removeWhere((p) => p.id == photo.id);
      if (_project.photos.isEmpty) _deleteMode = false; // 全部删完自动退出删除模式
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPhotos = _project.photos.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    // 删除/分组模式属于页面内的临时状态：返回键优先退出模式而非离开项目
    return PopScope(
      canPop: !_deleteMode && !_groupMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_groupMode) {
          _toggleGroupMode();
        } else if (_deleteMode) {
          _toggleDeleteMode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 0,
          title: Text(_project.name.isNotEmpty ? _project.name : '未命名项目'),
          actions: [
            if (hasPhotos) ...[
              IconButton(
                tooltip: _deleteMode ? '退出删除模式' : '删除模式',
                icon: Icon(
                  _deleteMode ? Icons.delete : Icons.delete_outline,
                  color: _deleteMode ? Colors.red : null,
                ),
                onPressed: _groupMode ? null : _toggleDeleteMode,
              ),
              IconButton(
                tooltip: _groupMode ? '退出分组模式' : '分组',
                icon: Icon(
                  _groupMode ? Icons.folder : Icons.folder_outlined,
                  color: _groupMode ? scheme.primary : null,
                ),
                onPressed: _deleteMode ? null : _toggleGroupMode,
              ),
              _exporting
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 48),
                        maximumSize: const Size(48, 48),
                      ),
                      onPressed: (_deleteMode || _groupMode)
                          ? null
                          : _exportWord,
                      child: const Text('导出'),
                    ),
            ],
          ],
        ),
        body: hasPhotos ? _buildPhotoGrid() : _buildEmptyState(),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: _groupMode ? _buildGroupConfirmBar() : _buildCaptureBar(),
          ),
        ),
      ),
    );
  }

  /// 常规工具栏：相册 + 拍照
  Widget _buildCaptureBar() {
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: OutlinedButton(
            onPressed: _deleteMode ? null : _pickFromGallery,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.photo_library, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _deleteMode ? null : _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('拍照'),
            ),
          ),
        ),
      ],
    );
  }

  /// 分组模式工具栏：整体替换为单一的确认按钮
  Widget _buildGroupConfirmBar() {
    final count = _selectedPhotoIds.length;
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _confirmGrouping,
        icon: const Icon(Icons.folder_special_outlined),
        label: Text(count == 0 ? '确认分组' : '确认分组（已选 $count 张）'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_a_photo, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无照片',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text('点击下方拍照按钮开始记录', style: TextStyle(color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 分组标题使行高不再均匀，槽位全部由布局算法预先算出
        final layout = PhotoGridLayout.build(
          width: constraints.maxWidth,
          groups: _tentativeGroups(),
          members: _tentativeMembers(),
        );
        _lastLayout = layout; // 手势回调依赖：拖拽起点与目标位判定

        // 被拖照片所属分组：只有该区块需要画落位提示
        String? draggedGroupId;
        if (_isDragging &&
            _dragIndex != null &&
            _dragIndex! < _project.photos.length) {
          draggedGroupId = _effectiveGroupId(_project.photos[_dragIndex!]);
        }

        final children = <Widget>[];
        for (final section in layout.sections) {
          if (section.showHeader && section.headerRect != null) {
            children.add(_buildSectionHeader(section));
          }
          if (_isDragging &&
              _hoverLocalIndex != null &&
              section.groupId == draggedGroupId) {
            children.add(_buildDropTarget(section));
          }
          for (int i = 0; i < section.photos.length; i++) {
            children.add(_buildPhotoCell(section, i));
          }
        }
        if (_isDragging && _dragIndex != null) {
          children.add(_buildDragOverlay(layout.cellSize));
        }

        return SingleChildScrollView(
          controller: _scrollController,
          // 拖拽中锁定滚动，避免手势冲突（自动滚动由 Timer 驱动 jumpTo）
          physics: (_isDragging || _isGroupDragging)
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            width: constraints.maxWidth,
            height: layout.totalHeight,
            child: Stack(
              key: _gridStackKey,
              clipBehavior: Clip.none,
              children: children,
            ),
          ),
        );
      },
    );
  }

  /// 分组标题行（长按可拖拽调整分组顺序，右侧菜单可重命名/解散）
  Widget _buildSectionHeader(PhotoGridSectionLayout section) {
    final rect = section.headerRect!;
    final isGroup = section.groupIndex >= 0;
    final isDraggingThis =
        _isGroupDragging && _dragGroupIndex == section.groupIndex;

    Widget header = GroupSectionHeader(
      title: section.title,
      photoCount: section.photos.length,
      draggable: isGroup,
      dragging: isDraggingThis,
      onRename: isGroup ? () => _renameGroup(section.groupIndex) : null,
      onDissolve: isGroup ? () => _dissolveGroup(section.groupIndex) : null,
    );

    // 删除/分组模式下不响应长按拖拽，避免与选择手势冲突
    if (isGroup && !_deleteMode && !_groupMode) {
      header = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _onGroupLongPressStart(section.groupIndex, d),
        onLongPressMoveUpdate: _onGroupLongPressMove,
        onLongPressEnd: (_) => _onGroupLongPressEnd(),
        onLongPressCancel: _onGroupLongPressCancel,
        child: header,
      );
    }

    return AnimatedPositioned(
      key: ValueKey('header_${section.groupId ?? 'ungrouped'}'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: header,
    );
  }

  /// 拖拽落位提示：被拖照片即将落入的槽位
  Widget _buildDropTarget(PhotoGridSectionLayout section) {
    final index = _hoverLocalIndex!;
    if (index < 0 || index >= section.slotRects.length) {
      return const SizedBox.shrink();
    }
    final rect = section.slotRects[index];
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blueAccent, width: 3),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCell(PhotoGridSectionLayout section, int index) {
    final photo = section.photos[index];
    final isDragSource =
        _isDragging &&
        _dragIndex != null &&
        _dragIndex! < _project.photos.length &&
        _project.photos[_dragIndex!].id == photo.id;
    // 被拖项固定在拖拽起始槽位占位，其余项落到重排后的槽位
    final rect = isDragSource
        ? (_dragStartRect ?? section.slotRects[index])
        : section.slotRects[index];
    final isSelected = _selectedPhotoIds.contains(photo.id);

    return AnimatedPositioned(
      // 以 photo.id 为稳定 key，位置变化时触发平滑动画
      key: ValueKey('photo_${photo.id}'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        // 分组模式：点选/取消；删除模式：屏蔽点击；常规：打开照片
        onTap: _groupMode
            ? () => _togglePhotoSelection(photo.id)
            : (_deleteMode ? null : () => _openPhoto(photo)),
        // 删除/分组模式开启时禁用长按拖拽，避免手势冲突
        // 注意：拖拽中必须保持 GestureDetector 不卸载，否则手势识别器被
        // dispose，onLongPressMoveUpdate/onLongPressEnd 将不再回调（拖不动 BUG）
        onLongPressStart: (_deleteMode || _groupMode)
            ? null
            : (d) => _onLongPressStart(
                _project.photos.indexWhere((p) => p.id == photo.id),
                d,
              ),
        onLongPressMoveUpdate: (_deleteMode || _groupMode)
            ? null
            : _onLongPressMove,
        onLongPressEnd: (_deleteMode || _groupMode)
            ? null
            : (_) => _onLongPressEnd(),
        onLongPressCancel: (_deleteMode || _groupMode)
            ? null
            : _onLongPressCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            // 拖拽项原位占位：淡色底 + 描边；分组选中：主题色描边 + 外发光
            border: isDragSource
                ? Border.all(
                    color: Colors.blueGrey.withValues(alpha: 0.6),
                    width: 2,
                  )
                : isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  )
                : null,
            color: isDragSource
                ? Colors.blueGrey.withValues(alpha: 0.12)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 拖拽中图片已浮起跟手，原位不重复显示图片（留占位底）
                if (!isDragSource) _PhotoGridItemImage(photo: photo),
                // 分组模式：选中遮罩 + 勾选标记
                if (_groupMode) ...[
                  if (isSelected)
                    ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.28),
                    ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _buildSelectBadge(isSelected),
                  ),
                ],
                // 删除模式：右上角红色 × 按钮（醒目、易点击）
                if (_deleteMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _confirmDeletePhoto(photo),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 多选勾选标记
  Widget _buildSelectBadge(bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.black.withValues(alpha: 0.3),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }

  /// 跟手拖拽浮层：放大 + 阴影
  Widget _buildDragOverlay(double cellSize) {
    final photo = _project.photos[_dragIndex!];
    final size = cellSize * 1.1;
    return Positioned(
      left: _dragOffset.dx - size / 2,
      top: _dragOffset.dy - size / 2,
      width: size,
      height: size,
      child: Material(
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _PhotoGridItemImage(photo: photo),
        ),
      ),
    );
  }
}

class _PhotoGridItemImage extends StatelessWidget {
  final PhotoRecord photo;

  const _PhotoGridItemImage({required this.photo});

  @override
  Widget build(BuildContext context) {
    final imagePath = photo.annotatedPath ?? photo.originalPath;
    final file = File(imagePath);

    return Stack(
      fit: StackFit.expand,
      children: [
        file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : const Icon(Icons.broken_image, color: Colors.grey),
        // 批注标记
        if (photo.hasAnnotations)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.edit, size: 12, color: Colors.white),
            ),
          ),
        // 备注标记
        if (photo.hasNote)
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.notes, size: 12, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
