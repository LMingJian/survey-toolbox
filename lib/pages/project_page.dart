import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import '../models/photo_record.dart';
import '../services/project_service.dart';
import '../services/export_service.dart';

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
  static const double _gridPadding = 8.0;
  static const double _gridSpacing = 8.0;
  static const int _gridColumns = 3;

  // 拖拽边缘自动滚动参数
  static const double _autoScrollZone = 72.0; // 视口边缘触发区（逻辑像素）
  static const double _autoScrollSpeed = 12.0; // 最大滚动速度（px/tick，16ms 一跳 ≈ 750px/s）

  final _gridStackKey = GlobalKey();
  final _scrollController = ScrollController(); // 网格滚动控制器（自动滚动用）
  Timer? _autoScrollTimer; // 边缘自动滚动定时器
  Offset? _lastGlobalPos; // 最近一次手指全局坐标（自动滚动 tick 用）
  double _autoScrollVelocity = 0; // 当前滚动速度（像素/tick，负=向上）
  bool _isDragging = false; // 拖拽进行中（长按触发后锁定滚动）
  int? _dragIndex; // 被拖照片在 _project.photos 中的索引
  int? _hoverIndex; // 目标插入位（移除 _dragIndex 后的顺序）
  int _dragStartPos = 0; // 拖拽开始时拖拽项的显示位置（原位置占位）
  Offset _dragOffset = Offset.zero; // 手指相对网格 Stack 的位置
  double _cellSize = 100; // 网格单元尺寸（LayoutBuilder 中缓存）
  bool _deleteMode = false; // 删除模式开关（初始关闭）

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

  Future<void> _takePhoto() async {
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

    // 拍照后直接进入编辑页
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoEditorPage(
            photoRecord: record,
            allPhotos: _project.photos,
            projectId: _project.id,
            projectService: widget.projectService,
            startEditing: true,
          ),
        ),
      ).then((_) => _refreshProject());
    }
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
    final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
    if (dirs != null && dirs.isNotEmpty && !dirs.first.path.contains('Android/data')) {
      return dirs.first.path;
    }
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _exportWord() async {
    setState(() => _exporting = true);
    try {
      final fileName = '${_project.name.isNotEmpty ? _project.name : '勘察记录'}'
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
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('完成')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('前往文件管理查看')),
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
          SnackBar(content: Text('导出失败: $e'), duration: const Duration(seconds: 6)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------- 长按拖拽排序 ----------

  /// 当前显示顺序：拖拽中把被拖项从原位移到目标插入位，其余项依次让位
  List<int> _computeDisplayOrder() {
    final count = _project.photos.length;
    final order = List<int>.generate(count, (i) => i);
    if (_isDragging && _dragIndex != null && _hoverIndex != null) {
      order.remove(_dragIndex!);
      order.insert(_hoverIndex!, _dragIndex!);
    }
    return order;
  }

  /// 全局坐标 → 网格 Stack 局部坐标
  Offset _gridOffsetOf(Offset globalPos) {
    final box = _gridStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return _dragOffset;
    return box.globalToLocal(globalPos);
  }

  void _onLongPressStart(int index, LongPressStartDetails d) {
    // 防御：拖拽进行中（如多点触控第二根手指长按）忽略新的触发，避免状态被覆盖
    if (_isDragging) return;
    HapticFeedback.mediumImpact(); // 长按进入拖拽的触觉反馈
    setState(() {
      _isDragging = true;
      _dragIndex = index;
      _dragStartPos = index;
      _hoverIndex = index;
      _dragOffset = _gridOffsetOf(d.globalPosition);
    });
    debugPrint(
      '[Drag] START index=$index, photos=${_project.photos.length}, '
      'offset=$_dragOffset, cellSize=$_cellSize',
    );
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    _lastGlobalPos = d.globalPosition;
    final offset = _gridOffsetOf(d.globalPosition);
    final hover = _computeHoverIndex(offset);
    debugPrint(
      '[Drag] MOVE global=${d.globalPosition}, offset=$offset, '
      'hover=$hover, cell=$_cellSize',
    );
    setState(() {
      _dragOffset = offset;
      _hoverIndex = hover;
    });
    _updateAutoScroll();
  }

  void _onLongPressEnd() {
    debugPrint(
      '[Drag] END dragIndex=$_dragIndex, hoverIndex=$_hoverIndex, '
      'photos=${_project.photos.length}',
    );
    _cancelAutoScroll();
    if (_dragIndex == null || _hoverIndex == null) return;
    final photos = _project.photos;
    final item = photos.removeAt(_dragIndex!);
    // clamp 返回 num，需 toInt() 转回 int 作为插入位置
    photos.insert(_hoverIndex!.clamp(0, photos.length).toInt(), item);
    setState(() {
      _isDragging = false;
      _dragIndex = null;
      _hoverIndex = null;
    });
    _persistOrder();
  }

  void _onLongPressCancel() {
    debugPrint('[Drag] CANCEL (drag aborted, state reset)');
    _cancelAutoScroll();
    setState(() {
      _isDragging = false;
      _dragIndex = null;
      _hoverIndex = null;
    });
  }

  /// 手指位置 → 目标插入位（按网格槽位映射，越界钳位到首/末位）
  int _computeHoverIndex(Offset pos) {
    final remaining = _project.photos.length - 1;
    final x = (pos.dx - _gridPadding) / (_cellSize + _gridSpacing);
    final y = (pos.dy - _gridPadding) / (_cellSize + _gridSpacing);
    // clamp 返回 num，需 toInt() 转回 int
    final col = x.floor().clamp(0, _gridColumns - 1).toInt();
    final row = y < 0 ? 0 : y.floor();
    final slot = row * _gridColumns + col;
    return slot.clamp(0, remaining).toInt();
  }

  // ---------- 拖拽边缘自动滚动 ----------

  /// 检测手指是否位于视口上/下边缘区，按进入深度启停自动滚动
  void _updateAutoScroll() {
    final globalPos = _lastGlobalPos;
    if (globalPos == null || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final stackBox = _gridStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    // 视口顶部全局 y = Stack 顶部全局 y + 已滚动偏移（内容上滚时 Stack 上移）
    final viewportTop = stackBox.localToGlobal(Offset.zero).dy + pos.pixels;
    final viewportH = pos.viewportDimension; // 精确视口高度（不含 AppBar/按钮栏）
    final localY = globalPos.dy - viewportTop; // 手指相对视口顶部的 y

    double v = 0;
    if (localY < _autoScrollZone) {
      // 上边缘：向上滚，速度随进入深度线性增加
      v = -((_autoScrollZone - localY) / _autoScrollZone)
              .clamp(0.0, 1.0)
              .toDouble() *
          _autoScrollSpeed;
    } else if (localY > viewportH - _autoScrollZone) {
      // 下边缘：向下滚
      v = ((localY - (viewportH - _autoScrollZone)) / _autoScrollZone)
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
      'hover=$_hoverIndex',
    );
    // 滚动后 Stack 内容位移，用最新手指位置重算（hover 随之更新）
    if (_lastGlobalPos != null && mounted) {
      setState(() {
        _dragOffset = _gridOffsetOf(_lastGlobalPos!);
        _hoverIndex = _computeHoverIndex(_dragOffset);
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

  /// 排序结果持久化（Project.photos 顺序 → projects.json）
  Future<void> _persistOrder() async {
    await widget.projectService.updateProject(_project);
  }

  /// 切换删除模式（同时取消进行中的拖拽，避免手势冲突）
  void _toggleDeleteMode() {
    _cancelAutoScroll();
    setState(() {
      _deleteMode = !_deleteMode;
      _isDragging = false;
      _dragIndex = null;
      _hoverIndex = null;
    });
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
    final hasExportDate = _project.photos.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_project.name.isNotEmpty ? _project.name : '未命名项目'),
        actions: [
          if (hasExportDate) ...[
            IconButton(
              tooltip: _deleteMode ? '退出删除模式' : '删除模式',
              icon: Icon(
                _deleteMode ? Icons.delete : Icons.delete_outline,
                color: _deleteMode ? Colors.red : null,
              ),
              onPressed: _toggleDeleteMode,
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
                    onPressed: _deleteMode ? null : _exportWord,
                    child: const Text('导出'),
                  ),
          ],
        ],
      ),
      body: _project.photos.isEmpty ? _buildEmptyState() : _buildPhotoGrid(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
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
          ),
        ),
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
    return LayoutBuilder(builder: (context, constraints) {
      final cellSize =
          (constraints.maxWidth -
              _gridPadding * 2 -
              _gridSpacing * (_gridColumns - 1)) /
          _gridColumns;
      _cellSize = cellSize;
      final photos = _project.photos;
      final rows = (photos.length + _gridColumns - 1) ~/ _gridColumns;
      final totalHeight =
          _gridPadding * 2 + rows * cellSize + (rows - 1) * _gridSpacing;
      final displayOrder = _computeDisplayOrder();

      return SingleChildScrollView(
        controller: _scrollController,
        // 拖拽中锁定滚动，避免手势冲突（自动滚动由 Timer 驱动 jumpTo）
        physics: _isDragging
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          width: constraints.maxWidth,
          height: totalHeight,
          child: Stack(
            key: _gridStackKey,
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < photos.length; i++)
                _buildPhotoCell(i, displayOrder, cellSize),
              if (_isDragging && _dragIndex != null)
                _buildDragOverlay(cellSize),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildPhotoCell(int index, List<int> displayOrder, double cellSize) {
    final photo = _project.photos[index];
    final isDragging = _isDragging && _dragIndex == index;
    // 被拖项固定显示在原位占位，其余项按让位后的顺序定位
    final layoutPos =
        isDragging ? _dragStartPos : displayOrder.indexOf(index);
    final left =
        _gridPadding + (layoutPos % _gridColumns) * (cellSize + _gridSpacing);
    final top =
        _gridPadding + (layoutPos ~/ _gridColumns) * (cellSize + _gridSpacing);
    final isHoverTarget = _isDragging &&
        !isDragging &&
        _hoverIndex == displayOrder.indexOf(index);

    return AnimatedPositioned(
      // 以 photo.id 为稳定 key，位置变化时触发平滑动画
      key: ValueKey('photo_${photo.id}'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      left: left,
      top: top,
      width: cellSize,
      height: cellSize,
      child: GestureDetector(
        // 删除模式仅支持删除，屏蔽点击打开照片
        onTap: _deleteMode ? null : () => _openPhoto(photo),
        // 删除模式开启时禁用长按拖拽，避免手势冲突
        // 注意：拖拽中必须保持 GestureDetector 不卸载，否则手势识别器被
        // dispose，onLongPressMoveUpdate/onLongPressEnd 将不再回调（拖不动 BUG）
        onLongPressStart:
            _deleteMode ? null : (d) => _onLongPressStart(index, d),
        onLongPressMoveUpdate: _deleteMode ? null : _onLongPressMove,
        onLongPressEnd: _deleteMode ? null : (_) => _onLongPressEnd(),
        onLongPressCancel: _deleteMode ? null : _onLongPressCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            // 拖拽项原位占位：虚线框 + 淡色底；hover 目标：蓝色高亮
            border: isDragging
                ? Border.all(
                    color: Colors.blueGrey.withValues(alpha: 0.6),
                    width: 2,
                  )
                : isHoverTarget
                    ? Border.all(color: Colors.blueAccent, width: 3)
                    : null,
            color: isDragging
                ? Colors.blueGrey.withValues(alpha: 0.12)
                : null,
            boxShadow: isHoverTarget
                ? [
                    BoxShadow(
                      color: Colors.blueAccent.withValues(alpha: 0.35),
                      blurRadius: 12,
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
                if (!isDragging) _PhotoGridItemImage(photo: photo),
                if (isHoverTarget)
                  Container(
                    color: Colors.blueAccent.withValues(alpha: 0.25),
                  ),
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
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
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
