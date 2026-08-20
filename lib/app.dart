import 'package:flutter/material.dart';
import 'services/project_service.dart';
import 'pages/home_page.dart';

class ToolboxApp extends StatelessWidget {
  final ProjectService projectService;

  const ToolboxApp({super.key, required this.projectService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '勘察工具箱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: HomePage(projectService: projectService),
    );
  }
}
