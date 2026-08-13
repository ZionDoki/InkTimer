import 'models.dart';

const defaultHiddenGrowth = HiddenGrowth(
  level: 1,
  totalExp: 0,
  insights: <String>[],
  insightUnlockedAt: <String, int>{},
);

/// 隐修成长数据
class HiddenGrowth {
  const HiddenGrowth({
    required this.level,
    required this.totalExp,
    required this.insights,
    this.insightUnlockedAt = const <String, int>{},
    this.version = 2,
  });

  final int level; // 1-99
  final int totalExp; // 累积经验
  final List<String> insights; // 已解锁的「悟」ID 列表
  final Map<String, int> insightUnlockedAt; // ID -> 首次解锁时间
  final int version;

  Map<String, Object> toJson() => {
    'level': level,
    'totalExp': totalExp,
    'insights': insights,
    'insightUnlockedAt': insightUnlockedAt,
    'version': version,
  };

  HiddenGrowth copyWith({
    int? level,
    int? totalExp,
    List<String>? insights,
    Map<String, int>? insightUnlockedAt,
  }) => HiddenGrowth(
    level: level ?? this.level,
    totalExp: totalExp ?? this.totalExp,
    insights: insights ?? this.insights,
    insightUnlockedAt: insightUnlockedAt ?? this.insightUnlockedAt,
    version: version,
  );
}

/// 解锁的「悟」记录
class Insight {
  const Insight({
    required this.id,
    required this.name,
    required this.description,
    required this.unlockedAt,
  });

  final String id; // 如 'first_100h'
  final String name; // 如 '百时'
  final String description; // 如 '累积专注 100 小时'
  final int unlockedAt; // 解锁时间戳

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'unlockedAt': unlockedAt,
  };
}

/// 「悟」定义
class InsightDefinition {
  const InsightDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.check,
  });

  final String id;
  final String name;
  final String description;
  final bool Function(GrowthContext) check;
}

/// 「印记」：连续天数里程碑的视觉形式。
///
/// 连续天数这条线只用朱印表达，不在隐修履历里再列一遍文字条目，
/// 否则同一个成就会被两套词汇说两次。
class SealMark {
  const SealMark({
    required this.character,
    required this.insightId,
    required this.days,
  });

  final String character;
  final String insightId;
  final int days;
}

/// 成长系统上下文（用于检测「悟」）
class GrowthContext {
  const GrowthContext({
    required this.sessions,
    required this.todos,
    required this.totalSec,
    required this.bestStreakDays,
    required this.zeroInterruptRate,
    required this.unlockedInsights,
  });

  final List<SessionRecord> sessions;
  final List<TodoItem> todos;
  final int totalSec;

  /// 取历史最长连续天数，而不是当下连续天数。
  /// 印记一旦得到就不收回，断了签不会抹掉曾经坐过的二十七天。
  final int bestStreakDays;
  final double zeroInterruptRate;
  final List<String> unlockedInsights;
}
