import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/project_service.dart';
import '../utils/date_utils.dart' show ToolDateUtils;
import 'project_page.dart';
import 'project_settings_page.dart';

class HomePage extends StatefulWidget {
  final ProjectService projectService;

  const HomePage({super.key, required this.projectService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    await widget.projectService.loadProjects();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _createProject() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectSettingsPage(
          projectService: widget.projectService,
          isNew: true,
        ),
      ),
    );
    if (result == true) {
      setState(() {});
    }
  }

  void _openProject(Project project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectPage(
          project: project,
          projectService: widget.projectService,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目'),
        content: Text(
          '确定要删除"${project.name.isNotEmpty ? project.name : '未命名项目'}"吗？\n所有照片将被永久删除。',
        ),
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
    if (confirmed == true) {
      await widget.projectService.deleteProject(project.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('勘察记录'), centerTitle: true),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 30), // ← 调这个值
        child: FloatingActionButton(
          onPressed: _createProject,
          child: const Icon(Icons.add),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : widget.projectService.projects.isEmpty
          ? _buildEmptyState()
          : _buildProjectList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无项目',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text('点击右下角 + 创建项目', style: TextStyle(color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildProjectList() {
    return RefreshIndicator(
      onRefresh: _loadProjects,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.projectService.projects.length,
        itemBuilder: (context, index) {
          final project = widget.projectService.projects[index];
          return _ProjectCard(
            project: project,
            onTap: () => _openProject(project),
            onDelete: () => _deleteProject(project),
          );
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.engineering,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name.isNotEmpty ? project.name : '未命名项目',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${project.photoCount} 张照片 · 创建于 ${ToolDateUtils.formatRelative(project.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                    ),
                    if (project.location.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 14,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              project.location,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.settings),
                            title: const Text('项目信息'),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProjectSettingsPage(
                                    projectService: null,
                                    project: project,
                                    isNew: false,
                                  ),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.delete,
                              color: Colors.red,
                            ),
                            title: const Text(
                              '删除项目',
                              style: TextStyle(color: Colors.red),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              onDelete();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
