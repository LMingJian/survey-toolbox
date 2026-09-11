import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/photo_record.dart';
import '../services/project_service.dart';

/// 应用内自研相机页（拍照零确认）
///
/// 交互约定（针对「拍照要确认两次太麻烦」的反馈）：
/// 1. 进入本页即为实时预览，**不经过任何系统相机 App**，因此没有系统相机自带的
///    「确认 / 重拍」页；
/// 2. 点快门即成像并落盘到项目照片目录，**不弹确认、不弹批注页**；
/// 3. 拍完停留本页，可连续拍摄多张，点左上角 ✕ 返回项目照片列表。
///
/// 与系统相机方案的区别：这里用的是 [CameraController] + [CameraPreview]，
/// 属于应用内相机；[ResolutionPreset] 已做降级处理，兼容性优先。
class CameraPage extends StatefulWidget {
  final String projectId;
  final ProjectService projectService;

  const CameraPage({
    super.key,
    required this.projectId,
    required this.projectService,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  /// 初始化时依次尝试的分辨率，逐个降级以兼容老设备
  static const List<ResolutionPreset> _presetFallback = [
    ResolutionPreset.veryHigh,
    ResolutionPreset.high,
    ResolutionPreset.medium,
  ];

  static const String _permissionHint = '相机权限未授予，请在系统设置中允许本应用使用相机';

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  /// 用户选择的闪光灯模式（全局偏好，切到前置时仅临时关闭、不覆盖该偏好）
  FlashMode _flashMode = FlashMode.off;

  bool _initializing = true;
  bool _capturing = false;
  bool _flashOverlay = false;
  String? _error;

  /// 本次进入相机后，成功拍摄并落盘的照片张数
  int _shotCount = 0;

  /// 最近一张照片，用于给出缩略图反馈
  File? _lastShot;

  /// 初始化代次令牌：用于作废「在途但已过期」的初始化结果，避免快速切换摄像头时串台
  int _initToken = 0;

  /// 是否因退到后台而释放了相机、需要在回到前台时重建
  ///
  /// 用独立标记而不是复用 [_initializing]：初始化途中若弹出系统相机权限对话框，
  /// 应用同样会走 inactive/resumed，此时不应重复发起初始化。
  bool _needsReinitOnResume = false;

  bool get _isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  bool get _canCapture =>
      !_initializing && !_capturing && _error == null && _controller != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 字段默认值即为「初始化中」，此处无需 setState（initState 中不可 setState）
    _initCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initToken++; // 作废在途初始化，避免其在 dispose 后回写状态
    final controller = _controller;
    _controller = null;
    _safeDispose(controller);
    super.dispose();
  }

  // ---------------------------------------------------------------- 生命周期

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_needsReinitOnResume && _cameras.isNotEmpty) {
        _needsReinitOnResume = false;
        _startController(_cameras[_cameraIndex]);
      }
      return;
    }
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }

    final controller = _controller;
    if (controller == null) return;

    // 释放相机，避免退到后台被其它应用占用、回来时黑屏
    _controller = null;
    _initToken++;
    _needsReinitOnResume = true;
    _safeDispose(controller);
    if (mounted) {
      setState(() => _initializing = true);
    }
  }

  /// 释放控制器并吞掉异常：dispose 有时会与在途的 takePicture 冲突
  void _safeDispose(CameraController? controller) {
    if (controller == null) return;
    try {
      controller.dispose().catchError((Object _) {});
    } catch (_) {
      // 忽略释放异常
    }
  }

  // -------------------------------------------------------------- 相机初始化

  Future<void> _initCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = '未检测到可用摄像头';
        });
        return;
      }
      _cameras = cameras;
      final backIndex = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = backIndex >= 0 ? backIndex : 0;
      await _startController(_cameras[_cameraIndex]);
    } catch (e) {
      if (!mounted) return;
      final failure = e is CameraException
          ? e
          : CameraException('CameraInitFailed', e.toString());
      setState(() {
        _initializing = false;
        _error = _isPermissionError(failure)
            ? _permissionHint
            : '相机初始化失败：${_describe(failure)}';
      });
    }
  }

  /// 「重试」按钮：先复位状态再重新初始化
  void _retryInit() {
    setState(() {
      _error = null;
      _initializing = true;
    });
    _initCameras();
  }

  Future<void> _startController(CameraDescription description) async {
    final token = ++_initToken;

    // 释放旧控制器
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      try {
        await previous.dispose();
      } catch (_) {
        // 忽略释放异常
      }
    }
    if (!mounted || token != _initToken) return;

    setState(() {
      _initializing = true;
      _error = null;
    });

    CameraController? started;
    CameraException? failure;

    // 分辨率逐级降级，提升老设备兼容性
    for (final preset in _presetFallback) {
      final candidate = CameraController(
        description,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await candidate.initialize();
        started = candidate;
        break;
      } catch (e) {
        failure = e is CameraException
            ? e
            : CameraException('CameraStartFailed', e.toString());
        try {
          await candidate.dispose();
        } catch (_) {
          // 忽略释放异常
        }
        // 权限类错误继续降级没有意义，直接终止
        if (_isPermissionError(failure)) break;
      }
    }

    if (!mounted || token != _initToken) {
      try {
        await started?.dispose();
      } catch (_) {
        // 忽略释放异常
      }
      return;
    }

    if (started == null) {
      setState(() {
        _initializing = false;
        _error = _isPermissionError(failure)
            ? _permissionHint
            : '相机启动失败：${_describe(failure)}';
      });
      return;
    }

    // 用非空别名，避免后续 await 影响类型提升
    final ready = started;

    // 前置摄像头无闪光灯，仅临时关闭；后置沿用用户偏好
    try {
      await ready.setFlashMode(
        description.lensDirection == CameraLensDirection.front
            ? FlashMode.off
            : _flashMode,
      );
    } catch (_) {
      // 该设备不支持当前闪光灯模式，降级为关闭
      _flashMode = FlashMode.off;
      try {
        await ready.setFlashMode(FlashMode.off);
      } catch (_) {
        // 完全无法设置闪光灯，忽略
      }
    }

    if (!mounted || token != _initToken) {
      _safeDispose(ready);
      return;
    }

    setState(() {
      _controller = ready;
      _initializing = false;
    });
  }

  // ------------------------------------------------------------------ 交互

  /// 拍照：直接落盘 + 写入项目，无任何确认弹窗
  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !_canCapture) return;

    setState(() => _capturing = true);
    // 无确认步骤，靠触觉 + 白闪 + 缩略图给出「已拍下」的确定性反馈
    HapticFeedback.mediumImpact();
    _playShutterFlash();

    try {
      final XFile shot = await controller.takePicture();

      final recordId = const Uuid().v4();
      final destPath = await widget.projectService.getNewPhotoPath(
        widget.projectId,
        recordId,
      );
      // 直接复制到项目照片目录（应用私有目录，不写入系统相册，与原流程一致）
      await File(shot.path).copy(destPath);

      await widget.projectService.addPhoto(
        widget.projectId,
        PhotoRecord(
          id: recordId,
          originalPath: destPath,
          captureTime: DateTime.now(),
        ),
      );

      if (!mounted) return;
      setState(() {
        _shotCount++;
        _lastShot = File(destPath);
      });
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍摄失败：${_describe(e)}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _playShutterFlash() async {
    if (!mounted) return;
    setState(() => _flashOverlay = true);
    await Future.delayed(const Duration(milliseconds: 90));
    if (mounted) setState(() => _flashOverlay = false);
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || _initializing) return;

    if (_isFrontCamera) {
      _toast('前置摄像头不支持闪光灯');
      return;
    }

    const order = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final next = order[(order.indexOf(_flashMode) + 1) % order.length];
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {
      _toast('该设备不支持此闪光灯模式');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    final current = _cameras[_cameraIndex];
    // 优先切到方向相反的镜头
    int next = _cameraIndex;
    for (int i = 1; i <= _cameras.length; i++) {
      final idx = (_cameraIndex + i) % _cameras.length;
      if (_cameras[idx].lensDirection != current.lensDirection) {
        next = idx;
        break;
      }
    }
    if (next == _cameraIndex) next = (_cameraIndex + 1) % _cameras.length;
    _cameraIndex = next;
    await _startController(_cameras[next]);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),
          // 快门白闪反馈
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _flashOverlay ? 1 : 0,
                duration: const Duration(milliseconds: 90),
                child: Container(color: Colors.white),
              ),
            ),
          ),
          _buildTopBar(),
          _buildBottomBar(),
          if (_error != null) Positioned.fill(child: _buildErrorOverlay()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }

    // 预览尺寸以传感器方向（横屏）为基准，竖屏下需取倒数，否则画面会被拉伸
    var aspect = controller.value.aspectRatio;
    final previewSize = controller.value.previewSize;
    if (previewSize != null &&
        previewSize.width > 0 &&
        MediaQuery.of(context).orientation == Orientation.portrait) {
      aspect = previewSize.height / previewSize.width;
    }

    // 用 contain 方式居中显示：不裁切、不拉伸，做到所见即所得
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _circleButton(
                icon: Icons.close,
                tooltip: '退出相机',
                onPressed: () => Navigator.of(context).pop(_shotCount),
              ),
              const Spacer(),
              _circleButton(
                icon: _flashIcon,
                tooltip: '闪光灯：$_flashLabel',
                dimmed: _isFrontCamera,
                onPressed: _cycleFlash,
              ),
              const SizedBox(width: 12),
              if (_cameras.length > 1)
                _circleButton(
                  icon: Icons.cameraswitch,
                  tooltip: '切换前后摄像头',
                  onPressed: _switchCamera,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
          child: Row(
            children: [
              SizedBox(width: 56, height: 56, child: _buildLastShotThumb()),
              const Spacer(),
              _buildShutterButton(),
              const Spacer(),
              SizedBox(
                width: 56,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _shotCount > 0 ? '已拍\n$_shotCount 张' : '',
                      key: ValueKey<int>(_shotCount),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastShotThumb() {
    final shot = _lastShot;
    if (shot == null) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            shot,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(color: Colors.white24),
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_shotCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShutterButton() {
    final enabled = _canCapture;
    return Semantics(
      button: true,
      label: '拍照',
      child: GestureDetector(
        onTap: enabled ? _capture : null,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled ? Colors.white : Colors.white38,
              width: 4,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? Colors.white : Colors.white38,
              ),
              child: _capturing
                  ? const Padding(
                      padding: EdgeInsets.all(15),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF1A7F7F),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 48,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_shotCount),
                    child: const Text(
                      '返回',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _retryInit, child: const Text('重试')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool dimmed = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, color: dimmed ? Colors.white38 : Colors.white),
          onPressed: onPressed,
        ),
      ),
    );
  }

  IconData get _flashIcon {
    if (_isFrontCamera) return Icons.flash_off;
    if (_flashMode == FlashMode.auto) return Icons.flash_auto;
    if (_flashMode == FlashMode.off) return Icons.flash_off;
    return Icons.flash_on; // always / torch
  }

  String get _flashLabel {
    if (_isFrontCamera) return '不支持';
    if (_flashMode == FlashMode.auto) return '自动';
    if (_flashMode == FlashMode.off) return '关闭';
    return '开启'; // always / torch
  }

  // ------------------------------------------------------------------ 工具

  bool _isPermissionError(CameraException? e) {
    final code = e?.code ?? '';
    return code.contains('AccessDenied') ||
        code.contains('AccessRestricted') ||
        code.contains('Permission');
  }

  String _describe(CameraException? e) {
    if (e == null) return '未知错误';
    final description = e.description;
    if (description != null && description.isNotEmpty) return description;
    return e.code;
  }
}
