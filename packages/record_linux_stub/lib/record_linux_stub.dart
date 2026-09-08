/// No-op [RecordPlatform] for Linux desktop.
///
/// 本项目目标平台为 Android / iOS（录音走移动端）；Linux 桌面仅用于开发,
/// record 5.x 官方 record_linux 包与平台接口版本长期不匹配导致 AOT 编译失败,
/// 用此 stub 顶替：所有方法抛 UnimplementedError（桌面端不提供录音功能）。
library;

import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

class RecordLinuxStub extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordLinuxStub();
  }

  Never _unsupported(String method) =>
      throw UnimplementedError('record is not supported on Linux (stub): $method');

  @override
  Future<void> create(String recorderId) => _unsupported('create');

  @override
  Future<void> start(String recorderId, RecordConfig config,
          {required String path}) =>
      _unsupported('start');

  @override
  Future<Stream<Uint8List>> startStream(
          String recorderId, RecordConfig config) =>
      _unsupported('startStream');

  @override
  Future<String?> stop(String recorderId) => _unsupported('stop');

  @override
  Future<void> pause(String recorderId) => _unsupported('pause');

  @override
  Future<void> resume(String recorderId) => _unsupported('resume');

  @override
  Future<bool> isRecording(String recorderId) => _unsupported('isRecording');

  @override
  Future<bool> isPaused(String recorderId) => _unsupported('isPaused');

  @override
  Future<bool> hasPermission(String recorderId) => _unsupported('hasPermission');

  @override
  Future<void> dispose(String recorderId) => _unsupported('dispose');

  @override
  Future<Amplitude> getAmplitude(String recorderId) => _unsupported('getAmplitude');

  @override
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder) =>
      _unsupported('isEncoderSupported');

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) =>
      _unsupported('listInputDevices');

  @override
  Future<void> cancel(String recorderId) => _unsupported('cancel');
}
