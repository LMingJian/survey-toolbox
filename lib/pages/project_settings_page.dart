import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/project_service.dart';

class ProjectSettingsPage extends StatefulWidget {
  final ProjectService? projectService;
  final Project? project;
  final bool isNew;

  const ProjectSettingsPage({
    super.key,
    required this.projectService,
    this.project,
    this.isNew = false,
  });

  @override
  State<ProjectSettingsPage> createState() => _ProjectSettingsPageState();
}

class _ProjectSettingsPageState extends State<ProjectSettingsPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  DateTime? _surveyDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project?.name ?? '');
    _locationController = TextEditingController(
      text: widget.project?.location ?? '',
    );
    _surveyDate = widget.isNew ? DateTime.now() : widget.project?.surveyDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _surveyDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _surveyDate = date);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      if (widget.isNew) {
        await widget.projectService!.createProject(
          name: _nameController.text.trim(),
          location: _locationController.text.trim(),
          surveyDate: _surveyDate,
        );
      } else {
        widget.project!.name = _nameController.text.trim();
        widget.project!.location = _locationController.text.trim();
        widget.project!.surveyDate = _surveyDate;
        await widget.projectService!.updateProject(widget.project!);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isNew ? '新建项目' : '项目信息')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '项目名称（可选）',
                      hintText: '例如：XXX 项目一期勘察',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: '勘察地点（可选）',
                      hintText: '例如：广州市黄埔区',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '勘察日期（可选）',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        _surveyDate != null
                            ? '${_surveyDate!.year}年${_surveyDate!.month}月${_surveyDate!.day}日'
                            : '点击选择日期',
                        style: TextStyle(
                          color: _surveyDate != null ? null : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '以上信息均为可选，仅用于项目识别和导出文件命名',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? '保存中...' : '确认'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
