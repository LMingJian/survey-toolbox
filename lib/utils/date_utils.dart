import 'package:intl/intl.dart';

class ToolDateUtils {
  static final _dateFormat = DateFormat('yyyy年M月d日');
  static final _timeFormat = DateFormat('HH:mm:ss');
  static final _fullFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final _shortFormat = DateFormat('yyyy/MM/dd');

  static String formatDate(DateTime date) => _dateFormat.format(date);

  static String formatTime(DateTime time) => _timeFormat.format(time);

  static String formatFull(DateTime dt) => _fullFormat.format(dt);

  static String formatShort(DateTime dt) => _shortFormat.format(dt);

  static String formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return formatDate(dt);
  }

  /// 将 DateTime 格式化为纯日期字符串，用于 Word 标题1
  static String formatDateForWord(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }
}
