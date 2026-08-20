import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/annotation_data.dart';
import '../models/photo_record.dart';
import '../services/project_service.dart';
import '../services/photo_service.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/annotation_toolbar.dart';

class PhotoEditorPage extends StatefulWidget {
  final PhotoRecord photoRecord;
  final List<PhotoRecord> allPhotos;
  final String projectId;
  final ProjectService projectService;
  final bool startEditing;

  const PhotoEditorPage({
    super.key,
    required this.photoRecord,
    required this.allPhotos,
    required this.projectId,
    required this.projectService,
    this.startEditing = false,
  });

  @override
  State<PhotoEditorPage> createState() => _PhotoEditorPageState();
}

class _PhotoEditorPageState extends State<PhotoEditorPage> {
  late PhotoRecord _record;
  final _noteController = TextEditingController();
  final _canvasKey = GlobalKey<AnnotationCanvasState>();
  AnnotationType _currentType = AnnotationType.freehand;
  Color _currentColor = Colors.red;
  double _currentWidth = 3.0;
  late bool _readOnly;
  bool _saving = false;
  int _selectedIndex = -1;
  final List<({int index, AnnotationData data})> _deletedStack = [];
  List<AnnotationData> _savedAnnotations = [];
  Size? _editDisplaySize; // 进入编辑时的固定显示尺寸
  ui.Image? _imageInfo;
  Size? _imageSize;
  late int _currentIndex;
  late List<PhotoRecord> _allPhotos;

  @override
  void initState() {
    super.initState();
    _allPhotos = List.from(widget.allPhotos);
    _currentIndex = _allPhotos.indexOf(widget.photoRecord);
    _readOnly = !widget.startEditing;
    _record = widget.photoRecord;
    _noteController.text = _record.note;
    _loadImage();
    if (!_readOnly) {
      _savedAnnotations = List.from(_record.annotations);
      _record.annotations = List.from(_record.annotations);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_canvasKey.currentState != null) {
          _editDisplaySize = _canvasKey.currentState!.displaySize;
        }
      });
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _imageInfo?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final file = File(_record.originalPath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _imageInfo = frame.image;
        _imageSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      });
    }
  }

  void _goTo(int newIndex) {
    if (newIndex < 0 || newIndex >= _allPhotos.length) return;
    setState(() {
      _currentIndex = newIndex;
      _record = _allPhotos[newIndex];
      _noteController.text = _record.note;
    });
  }

  void _onAnnotationAdded(AnnotationData annotation) {
    setState(() {
      _record.annotations.add(annotation);
      _selectedIndex = -1;
    });
  }

  void _onUndo() {
    // 优先恢复已删除的
    if (_deletedStack.isNotEmpty) {
      final restored = _deletedStack.removeLast();
      setState(() {
        _record.annotations.insert(
          restored.index.clamp(0, _record.annotations.length),
          restored.data,
        );
        _selectedIndex = restored.index;
      });
      return;
    }
    if (_record.annotations.isNotEmpty) {
      setState(() {
        _record.annotations.removeLast();
        _selectedIndex = -1;
      });
    }
  }

  void _onDelete() {
    if (_selectedIndex >= 0 && _selectedIndex < _record.annotations.length) {
      final removed = _record.annotations.removeAt(_selectedIndex);
      _deletedStack.add((index: _selectedIndex, data: removed));
      setState(() => _selectedIndex = -1);
    } else {
      // 没选中 → 全部删除
      if (_record.annotations.isEmpty) return;
      setState(() {
        for (int i = _record.annotations.length - 1; i >= 0; i--) {
          _deletedStack.add((index: i, data: _record.annotations[i]));
        }
        _record.annotations.clear();
        _selectedIndex = -1;
      });
    }
  }

  void _onSelect(int index) {
    setState(() => _selectedIndex = _selectedIndex == index ? -1 : index);
  }

  void _onTextRequested(TextEditingController controller, Offset position) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入文字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入标注文字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (controller.text.isNotEmpty) {
                setState(
                  () => _record.annotations.add(
                    AnnotationData(
                      type: AnnotationType.text,
                      text: controller.text,
                      textPosition: position,
                      colorValue: _currentColor.toARGB32(),
                      strokeWidth: _currentWidth,
                    ),
                  ),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      _record.note = _noteController.text;
      // 兜底：如果 editDisplaySize 没捕获到，实时读取
      final displaySize =
          _editDisplaySize ?? _canvasKey.currentState?.displaySize;
      debugPrint(
        '[Save] displaySize fallback: $_editDisplaySize -> $displaySize',
      );
      if (_record.annotations.isNotEmpty &&
          _imageSize != null &&
          displaySize != null) {
        final outputPath = await widget.projectService.getAnnotatedPhotoPath(
          widget.projectId,
          _record.id,
        );
        debugPrint('[Save] merging to: $outputPath');
        await PhotoService.mergeAnnotations(
          _record.originalPath,
          outputPath,
          _record.annotations,
          _imageSize!,
          displaySize,
        );
        _record.annotatedPath = outputPath;
        final mergedExists = await File(outputPath).exists();
        debugPrint('[Save] merged file exists: $mergedExists');
      } else {
        _record.annotatedPath = null;
        debugPrint(
          '[Save] skipping merge - annotations:${_record.annotations.length}, imageSize:$_imageSize, displaySize:$displaySize',
        );
      }
      await widget.projectService.updatePhoto(widget.projectId, _record);
      debugPrint('[Save] updatePhoto done');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功'), duration: Duration(seconds: 1)),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('[Save] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _exportImage() {
    final photo = _allPhotos[_currentIndex];
    final hasAnnotated =
        photo.annotatedPath != null && File(photo.annotatedPath!).existsSync();
    final hasOriginal = File(photo.originalPath).existsSync();

    if (!hasOriginal && !hasAnnotated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可导出的图片')));
      return;
    }

    // 只有一种直接导出
    if (hasAnnotated && !hasOriginal) {
      _copyToDownload(photo.annotatedPath!, '批注图');
      return;
    }
    if (!hasAnnotated && hasOriginal) {
      _copyToDownload(photo.originalPath, '原图');
      return;
    }

    // 两种都有，让用户选
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出图片'),
        content: const Text('请选择要导出的图片类型：'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _copyToDownload(photo.originalPath, '原图');
            },
            child: const Text('原图'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _copyToDownload(photo.annotatedPath!, '批注图');
            },
            child: const Text('批注图'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyToDownload(String sourcePath, String label) async {
    try {
      final dirs = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      final downloadDir =
          (dirs != null &&
              dirs.isNotEmpty &&
              !dirs.first.path.contains('Android/data'))
          ? dirs.first.path
          : '/storage/emulated/0/Pictures';
      final dir = Directory(downloadDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = sourcePath.endsWith('.jpg') ? 'jpg' : 'png';
      final destName =
          '勘察照片${label}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(sourcePath).copy('$downloadDir/$destName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label已导出：$destName'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  void _onAnnotationMoved(int index, Offset delta) {
    if (index < 0 || index >= _record.annotations.length) return;
    setState(() {
      _record.annotations[index] = _record.annotations[index].translated(delta);
    });
  }

  void _deleteCurrentPhoto() {
    final photo = _allPhotos[_currentIndex];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('确定要删除这张照片吗？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.projectService.deletePhoto(widget.projectId, photo.id);
              if (!mounted) return;
              _allPhotos.remove(photo);
              setState(() {
                if (_allPhotos.isEmpty) {
                  Navigator.pop(context, true);
                  return;
                }
                if (_currentIndex >= _allPhotos.length) {
                  _currentIndex = _allPhotos.length - 1;
                }
              });
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _editNote() {
    final ctrl = TextEditingController(text: _noteController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('图片说明'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '输入图片下方说明文字',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _noteController.text = ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          _readOnly
              ? '查看照片 (${_currentIndex + 1}/${_allPhotos.length})'
              : '编辑照片',
        ),
        actions: [
          if (_readOnly) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: '删除照片',
              onPressed: _deleteCurrentPhoto,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: '导出图片',
              onPressed: _exportImage,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: '编辑',
              onPressed: () {
                _savedAnnotations = List.from(_record.annotations);
                _record.annotations = List.from(_record.annotations);
                _deletedStack.clear();
                _selectedIndex = -1;
                setState(() => _readOnly = false);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_canvasKey.currentState != null) {
                    _editDisplaySize = _canvasKey.currentState!.displaySize;
                  }
                });
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消编辑',
              onPressed: () {
                _record.annotations = _savedAnnotations;
                _noteController.text = widget.photoRecord.note;
                _deletedStack.clear();
                _selectedIndex = -1;
                setState(() => _readOnly = true);
              },
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: '保存',
                onPressed: _save,
              ),
          ],
        ],
      ),
      body: _imageInfo == null
          ? const Center(child: CircularProgressIndicator())
          : _readOnly
          ? _buildReadOnly()
          : _buildEdit(),
    );
  }

  Widget _buildReadOnly() {
    final photo = _allPhotos[_currentIndex];
    final imagePath = photo.annotatedPath ?? photo.originalPath;
    final file = File(imagePath);
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < _allPhotos.length - 1;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: AlignmentDirectional.center,
            children: [
              FutureBuilder<Uint8List?>(
                future: file.existsSync()
                    ? file.readAsBytes()
                    : Future.value(null),
                builder: (ctx, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    );
                  }
                  return const SizedBox(
                    height: 200,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              ),
              if (hasPrev)
                Positioned(
                  left: 4,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                      padding: const EdgeInsets.only(
                        left: 10,
                        top: 6,
                        right: 4,
                        bottom: 6,
                      ),
                    ),
                    onPressed: () => _goTo(_currentIndex - 1),
                  ),
                ),
              if (hasNext)
                Positioned(
                  right: 4,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                      padding: const EdgeInsets.all(8),
                    ),
                    onPressed: () => _goTo(_currentIndex + 1),
                  ),
                ),
            ],
          ),
          if (photo.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                photo.note,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEdit() {
    return Column(
      children: [
        Expanded(
          child: AnnotationCanvas(
            key: _canvasKey,
            image: FileImage(File(_record.originalPath)),
            imageSize: _imageSize!,
            annotations: _record.annotations,
            currentType: _currentType,
            currentColor: _currentColor,
            currentWidth: _currentWidth,
            selectedIndex: _selectedIndex,
            onAnnotationAdded: _onAnnotationAdded,
            onTextRequested: _onTextRequested,
            onSelect: _onSelect,
            onAnnotationMoved: _onAnnotationMoved,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: InkWell(
            onTap: _editNote,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notes, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _noteController.text.isEmpty
                          ? '点击添加说明文字...'
                          : _noteController.text,
                      style: TextStyle(
                        color: _noteController.text.isEmpty
                            ? Colors.grey
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.edit, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        AnnotationToolbar(
          currentType: _currentType,
          currentColor: _currentColor,
          currentWidth: _currentWidth,
          onTypeChanged: (type) => setState(() => _currentType = type),
          onColorChanged: (color) => setState(() => _currentColor = color),
          onWidthChanged: (width) => setState(() => _currentWidth = width),
          onUndo: _onUndo,
          onDelete: _onDelete,
        ),
      ],
    );
  }
}
