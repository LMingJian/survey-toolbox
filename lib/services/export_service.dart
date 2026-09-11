import 'dart:io';
import 'dart:ui' as ui;
import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/project.dart';
import '../models/photo_record.dart';

class ExportService {
  /// 兜底高宽比（高 / 宽 = 3 / 4，即 4:3 横图）。
  ///
  /// 作为**单一真值来源**：`_getImageSize` 的兜底尺寸与导出时的等比换算回退
  /// 都引用它，避免两处各自写死数字、日后与 `maxW` 脱钩。
  static const double _fallbackHeightRatio = 3 / 4;

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
      }

      // 段内保持 project.photos 的数组顺序 —— 即列表显示顺序，
      // 包含长按拖拽的手动调整结果；不再按拍摄时间重排。
      // section.photos 由 project.photos.where(...) 生成，本身已是数组顺序，
      // 且 sections 构建后不再被修改，故直接引用，无需再复制一份。
      final photos = section.photos;

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
                  fontSize: 16,
                  color: DocxColor('333333'),
                ),
            ],
          ),
        );

        // 图片
        final imageBytes = await _readImage(project.id, photo);
        if (imageBytes != null) {
          final dims = await _getImageSize(imageBytes);
          final maxW = 100.0;
          // 按原始宽高比等比换算。判零必须同时校验 width —— 分母是 width，
          // 只看 height 会在 width == 0 时除零得到 Infinity / NaN。
          // 回退高度由 maxW 推导（不再是与 maxW 脱钩的固定数字）。
          final height = dims.width > 0 && dims.height > 0
              ? maxW * dims.height / dims.width
              : maxW * _fallbackHeightRatio;
          builder = builder.add(
            DocxImage(
              bytes: imageBytes,
              extension: 'png',
              width: maxW,
              height: height,
              align: DocxAlign.center,
              altText: '勘察照片 $timeStr',
            ),
          );
        }
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
      // 100 × (3/4) = 75，与 _fallbackHeightRatio 保持一致
      return const ui.Size(100, 100.0 * _fallbackHeightRatio);
    }
  }
}
