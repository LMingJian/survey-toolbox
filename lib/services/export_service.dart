import 'dart:io';
import 'dart:ui' as ui;
import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/project.dart';
import '../models/photo_record.dart';

class ExportService {
  Future<Uint8List> exportToBytes(Project project) async {
    debugPrint(
      '[Export] 开始, 项目: ${project.name}, 照片: ${project.photos.length}, '
      '分组: ${project.groups.length}',
    );

    // 按分组切分：先各分组（按 groups 顺序），再未分组（置底）
    // 无分组时输出与改造前完全一致（只有一段、无小标题）
    final hasGroups = project.groups.isNotEmpty;
    final groupIds = project.groups.map((g) => g.id).toSet();
    bool isUngrouped(PhotoRecord photo) =>
        photo.groupId == null || !groupIds.contains(photo.groupId);

    final sections = <({String? title, List<PhotoRecord> photos})>[];
    for (final group in project.groups) {
      final members = project.photos
          .where((p) => p.groupId == group.id)
          .toList();
      if (members.isEmpty) continue; // 空分组不输出
      sections.add((title: group.name, photos: members));
    }
    final ungrouped = project.photos.where(isUngrouped).toList();
    if (ungrouped.isNotEmpty) {
      sections.add((title: hasGroups ? '未分组' : null, photos: ungrouped));
    }

    var globalIndex = 0;
    var builder = docx();

    // 标题: 勘察现场报表
    builder = builder.add(
      DocxParagraph(
        align: DocxAlign.center,
        children: [
          DocxText(
            '勘察现场报表',
            fontSize: 36,
            fontWeight: DocxFontWeight.bold,
            color: DocxColor('1F4E79'),
          ),
        ],
      ),
    );

    // 副标题
    final exportTime = DateFormat('yyyy年M月d日 HH:mm').format(DateTime.now());
    builder = builder.add(
      DocxParagraph(
        align: DocxAlign.center,
        children: [
          DocxText(
            '导出时间: $exportTime  |  共 ${project.photos.length} 条记录',
            fontSize: 12,
            color: DocxColor('666666'),
          ),
        ],
      ),
    );

    builder = builder.add(DocxParagraph(children: [])); // 空行

    for (final section in sections) {
      // 分组小标题（未分组且项目无分组时不输出）
      final title = section.title;
      if (title != null) {
        builder = builder.add(
          DocxParagraph(
            borderBottomSide: DocxBorderSide(
              style: DocxBorder.single,
              size: 8,
              color: DocxColor('1F4E79'),
            ),
            paddingBottom: 4,
            children: [
              DocxText(
                title,
                fontSize: 20,
                fontWeight: DocxFontWeight.bold,
                color: DocxColor('1F4E79'),
              ),
            ],
          ),
        );
        builder = builder.add(DocxParagraph(children: [])); // 空行
      }

      // 段内按拍摄时间排序（与改造前一致）
      final photos = List<PhotoRecord>.from(section.photos)
        ..sort((a, b) => a.captureTime.compareTo(b.captureTime));

      for (final photo in photos) {
        globalIndex++;
        final timeStr = DateFormat('yyyy-M-d HH:mm').format(photo.captureTime);

        // 段头: 序号 + 备注内容 (下方分隔线)
        builder = builder.add(
          DocxParagraph(
            borderBottomSide: DocxBorderSide(
              style: DocxBorder.single,
              size: 6,
              color: DocxColor('4472C4'),
            ),
            paddingBottom: 4,
            children: [
              DocxText(
                '$globalIndex.',
                fontSize: 16,
                fontWeight: DocxFontWeight.bold,
                color: DocxColor('2E5496'),
              ),
              if (photo.note.isNotEmpty)
                DocxText(
                  ' ${photo.note}',
                  fontSize: 14,
                  color: DocxColor('333333'),
                ),
            ],
          ),
        );

        // 图片
        final imageBytes = await _readImage(project.id, photo);
        if (imageBytes != null) {
          final dims = await _getImageSize(imageBytes);
          final maxW = 300.0;
          builder = builder.add(
            DocxImage(
              bytes: imageBytes,
              extension: 'png',
              width: maxW,
              height: dims.height > 0 ? maxW * dims.height / dims.width : 375.0,
              align: DocxAlign.center,
              altText: '勘察照片 $timeStr',
            ),
          );
        }

        builder = builder.add(DocxParagraph(children: [])); // 间隔
      }
    }

    final doc = builder.build();
    final bytes = await DocxExporter().exportToBytes(doc);
    debugPrint('[Export] 构建完成, 大小: ${bytes.length} bytes');
    return bytes;
  }

  Future<Uint8List?> _readImage(String projectId, PhotoRecord photo) async {
    try {
      final path = photo.annotatedPath ?? photo.originalPath;
      final file = File(path);
      if (await file.exists()) return await file.readAsBytes();
    } catch (e) {
      debugPrint('[Export] 读取图片失败: $e');
    }
    return null;
  }

  Future<ui.Size> _getImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = ui.Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return size;
    } catch (_) {
      return const ui.Size(500, 375);
    }
  }
}
