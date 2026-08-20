import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/app.dart';
import 'package:toolbox/services/project_service.dart';

void main() {
  testWidgets('App builds and shows title', (WidgetTester tester) async {
    final projectService = ProjectService();
    await tester.pumpWidget(ToolboxApp(projectService: projectService));

    // 验证应用标题渲染
    expect(find.text('勘察记录'), findsOneWidget);
  });
}
