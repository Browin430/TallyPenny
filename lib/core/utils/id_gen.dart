import 'dart:math';

/// 本地 ID 生成：时间戳 + 随机段，可读且无外部依赖。
/// 后续若引入云同步，可无缝替换为 UUID v4。
class IdGen {
  const IdGen._();

  static final _random = Random.secure();

  static String newId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand =
        List.generate(6, (_) => _random.nextInt(36).toRadixString(36)).join();
    return '$ts$rand';
  }
}
