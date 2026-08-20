import 'dart:io';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _project = widget.project;
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

  void _deletePhoto(PhotoRecord photo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('确定要删除这张照片吗？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.projectService.deletePhoto(_project.id, photo.id);
              _refreshProject();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExportDate = _project.photos.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_project.name.isNotEmpty ? _project.name : '未命名项目'),
        actions: [
          if (hasExportDate)
            _exporting
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(onPressed: _exportWord, child: const Text('导出')),
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
                  onPressed: _pickFromGallery,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Icon(Icons.photo_library, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _takePhoto,
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
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _project.photos.length,
      itemBuilder: (context, index) {
        final photo = _project.photos[index];
        return _PhotoGridItem(
          photo: photo,
          onTap: () => _openPhoto(photo),
          onLongPress: () => _deletePhoto(photo),
        );
      },
    );
  }
}

class _PhotoGridItem extends StatelessWidget {
  final PhotoRecord photo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PhotoGridItem({required this.photo, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final imagePath = photo.annotatedPath ?? photo.originalPath;
    final file = File(imagePath);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
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
        ),
      ),
    );
  }
}
