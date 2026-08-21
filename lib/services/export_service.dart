import 'dart:io';
import 'dart:ui' as ui;
import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/project.dart';
import '../models/photo_record.dart';
import '../utils/date_utils.dart' show ToolDateUtils;

class ExportService {
  Future<Uint8List> exportToBytes(Project project) async {
    debugPrint(
      '[Export] 开始, 项目: ${project.name}, 照片: ${project.photos.length}',
    );

    final groupedPhotos = <String, List<PhotoRecord>>{};
    for (final photo in project.photos) {
      final dateKey = ToolDateUtils.formatDate(photo.captureTime);
      groupedPhotos.putIfAbsent(dateKey, () => []).add(photo);
    }
    final sortedDates = groupedPhotos.keys.toList()
      ..sort((a, b) => a.compareTo(b));

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

    for (final dateKey in sortedDates) {
      final photos = groupedPhotos[dateKey]!;
      photos.sort((a, b) => a.captureTime.compareTo(b.captureTime));

      for (final photo in photos) {
        globalIndex++;
        final timeStr = DateFormat('yyyy-M-d HH:mm').format(photo.captureTime);

        // 段头: 序号 (下方分隔线)
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
            ],
          ),
        );

        // 备注
        if (photo.note.isNotEmpty) {
          builder = builder.p(photo.note);
        }

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
