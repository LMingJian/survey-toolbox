import 'package:flutter/material.dart';
import 'app.dart';
import 'services/project_service.dart';

void main() {
  final projectService = ProjectService();
  runApp(ToolboxApp(projectService: projectService));
}
