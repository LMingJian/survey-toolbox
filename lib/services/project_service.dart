import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import '../models/photo_record.dart';

class ProjectService {
  static const _projectsFileName = 'projects.json';
  final _uuid = const Uuid();

  List<Project> _projects = [];
  String? _basePath;

  List<Project> get projects => _projects;

  Future<String> get basePath async {
    _basePath ??= await _initBasePath();
    return _basePath!;
  }

  Future<String> get _projectsFilePath async {
    final base = await basePath;
    return '$base/$_projectsFileName';
  }

  Future<String> get projectsDir async {
    final base = await basePath;
    return '$base/projects';
  }

  Future<String> _initBasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/toolbox_data';
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return path;
  }

  Future<String> getProjectDir(String projectId) async {
    final dir = await projectsDir;
    return '$dir/$projectId';
  }

  Future<String> getPhotosDir(String projectId) async {
    final base = await getProjectDir(projectId);
    return '$base/photos';
  }

  Future<void> ensureProjectDir(String projectId) async {
    final photosDir = await getPhotosDir(projectId);
    final directory = Directory(photosDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  Future<void> loadProjects() async {
    final filePath = await _projectsFilePath;
    final file = File(filePath);
    if (await file.exists()) {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      _projects = list.map((e) => Project.fromJson(e)).toList();
    } else {
      // Create demo project for first run
      final demoId = _uuid.v4();
      await ensureProjectDir(demoId);
      _projects = [
        Project(
          id: demoId,
          name: '示例项目',
          location: '勘察地点',
          surveyDate: DateTime.now(),
        ),
      ];
      await _saveProjects();
    }
  }

  Future<void> _saveProjects() async {
    final filePath = await _projectsFilePath;
    final file = File(filePath);
    final json = jsonEncode(_projects.map((p) => p.toJson()).toList());
    await file.writeAsString(json);
  }

  Future<Project> createProject({
    String name = '',
    String location = '',
    DateTime? surveyDate,
  }) async {
    final id = _uuid.v4();
    await ensureProjectDir(id);
    final project = Project(
      id: id,
      name: name,
      location: location,
      surveyDate: surveyDate,
    );
    _projects.insert(0, project);
    await _saveProjects();
    return project;
  }

  Future<void> deleteProject(String projectId) async {
    _projects.removeWhere((p) => p.id == projectId);
    await _saveProjects();
    // Delete project directory
    final projectDir = await getProjectDir(projectId);
    final dir = Directory(projectDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> updateProject(Project project) async {
    final index = _projects.indexWhere((p) => p.id == project.id);
    if (index >= 0) {
      _projects[index] = project;
      await _saveProjects();
    }
  }

  Future<Project?> getProject(String projectId) async {
    await loadProjects();
    try {
      return _projects.firstWhere((p) => p.id == projectId);
    } catch (_) {
      return null;
    }
  }

  Future<void> addPhoto(String projectId, PhotoRecord photo) async {
    final project = _projects.firstWhere((p) => p.id == projectId);
    project.photos.add(photo);
    await _saveProjects();
  }

  Future<void> updatePhoto(String projectId, PhotoRecord photo) async {
    final project = _projects.firstWhere((p) => p.id == projectId);
    final index = project.photos.indexWhere((p) => p.id == photo.id);
    if (index >= 0) {
      project.photos[index] = photo;
      await _saveProjects();
    }
  }

  Future<void> deletePhoto(String projectId, String photoId) async {
    final project = _projects.firstWhere((p) => p.id == projectId);
    project.photos.removeWhere((p) => p.id == photoId);
    await _saveProjects();
    // Delete photo files
    final photosDir = await getPhotosDir(projectId);
    final originalFile = File('$photosDir/$photoId.jpg');
    if (await originalFile.exists()) await originalFile.delete();
    final annotatedFile = File('$photosDir/${photoId}_annotated.jpg');
    if (await annotatedFile.exists()) await annotatedFile.delete();
  }

  /// 获取新增的照片目录路径
  Future<String> getNewPhotoPath(String projectId, String photoId) async {
    final photosDir = await getPhotosDir(projectId);
    return '$photosDir/$photoId.jpg';
  }

  /// 获取批注后的照片路径
  Future<String> getAnnotatedPhotoPath(String projectId, String photoId) async {
    final photosDir = await getPhotosDir(projectId);
    return '$photosDir/${photoId}_annotated.jpg';
  }
}
