import 'dart:convert';

import 'focus_quality.dart';
import 'models.dart';
import 'schema.dart';
import 'timer_engine.dart';

class ActiveSessionCheckpoint {
  const ActiveSessionCheckpoint({
    this.version = 2,
    required this.sessionId,
    required this.template,
    required this.startedAt,
    required this.interruptions,
    required this.timer,
    this.qualityEvidence = emptyFocusQualityEvidence,
    this.pendingInactiveAt,
    this.pendingElapsedSec,
    this.openBackgroundAt,
    this.openBackgroundElapsedSec,
  });

  final int version;
  final String sessionId;
  final TimerTemplate template;
  final int startedAt;
  final int interruptions;
  final TimerSnapshot timer;
  final FocusQualityEvidence qualityEvidence;
  final int? pendingInactiveAt;
  final int? pendingElapsedSec;
  final int? openBackgroundAt;
  final int? openBackgroundElapsedSec;

  Map<String, Object> toJson() => {
    'version': version,
    'sessionId': sessionId,
    'template': template.toJson(),
    'startedAt': startedAt,
    'interruptions': interruptions,
    'timer': timer.toJson(),
    'qualityEvidence': qualityEvidence.toJson(),
    'pendingInactiveAt': ?pendingInactiveAt,
    'pendingElapsedSec': ?pendingElapsedSec,
    'openBackgroundAt': ?openBackgroundAt,
    'openBackgroundElapsedSec': ?openBackgroundElapsedSec,
  };

  String encode() => jsonEncode(toJson());
}

Map<String, Object?> _object(Object? value, String field) {
  if (value is! Map) throw FormatException('$field 结构非法');
  final output = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('$field 结构非法');
    output[entry.key as String] = entry.value;
  }
  return output;
}

double _nonnegativeNumber(Object? value, String field) {
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('活动会话字段非法: $field');
  }
  return value.toDouble();
}

int _nonnegativeInteger(
  Object? value,
  String field, {
  int max = maxDateTimeMilliseconds,
}) {
  final number = _nonnegativeNumber(value, field);
  if (number != number.roundToDouble() || number > max) {
    throw FormatException('活动会话字段非法: $field');
  }
  return number.toInt();
}

int? _optionalInteger(
  Map<String, Object?> object,
  String field, {
  int max = maxDateTimeMilliseconds,
}) => object.containsKey(field)
    ? _nonnegativeInteger(object[field], field, max: max)
    : null;

TimerSnapshot parseTimerSnapshot(Object? value) {
  final object = _object(value, 'timer');
  if (object['version'] != 1) {
    throw const FormatException('invalid timer snapshot version');
  }
  final mode = switch (object['mode']) {
    'countdown' => TimerMode.countdown,
    'countup' => TimerMode.countup,
    _ => throw const FormatException('invalid timer mode'),
  };
  final status = switch (object['status']) {
    'running' => TimerStatus.running,
    'paused' => TimerStatus.paused,
    _ => throw const FormatException('invalid timer status'),
  };
  return TimerSnapshot(
    mode: mode,
    status: status,
    index: _nonnegativeInteger(object['index'], 'index', max: 1 << 31),
    phaseRemainingMs: _nonnegativeNumber(
      object['phaseRemainingMs'],
      'phaseRemainingMs',
    ),
    countUpElapsedMs: _nonnegativeNumber(
      object['countUpElapsedMs'],
      'countUpElapsedMs',
    ),
    savedAt: _nonnegativeInteger(object['savedAt'], 'savedAt'),
  );
}

FocusQualityEvidence _parseEvidence(Object? value) {
  final object = _object(value, 'qualityEvidence');
  if (object['version'] != 1) throw const FormatException('活动会话定力版本不支持');
  return FocusQualityEvidence(
    manualPauseCount: _nonnegativeInteger(
      object['manualPauseCount'],
      'manualPauseCount',
      max: 1 << 31,
    ),
    canceledHoldCount: _nonnegativeInteger(
      object['canceledHoldCount'],
      'canceledHoldCount',
      max: 1 << 31,
    ),
    inAppDiversionCount: _nonnegativeInteger(
      object['inAppDiversionCount'],
      'inAppDiversionCount',
      max: 1 << 31,
    ),
    backgroundExcursionCount: _nonnegativeInteger(
      object['backgroundExcursionCount'],
      'backgroundExcursionCount',
      max: 1 << 31,
    ),
    backgroundFocusSec: _nonnegativeInteger(
      object['backgroundFocusSec'],
      'backgroundFocusSec',
    ),
  );
}

ActiveSessionCheckpoint parseActiveCheckpoint(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const FormatException('活动会话不是合法 JSON');
  }
  final object = _object(decoded, '活动会话');
  final version = object['version'];
  if (version != 1 && version != 2) throw const FormatException('活动会话版本不支持');
  final sessionId = object['sessionId'];
  if (sessionId is! String || sessionId.trim().isEmpty) {
    throw const FormatException('活动会话 id 非法');
  }
  late final TimerTemplate template;
  try {
    template = validateTemplate(object['template']);
  } on SchemaException catch (error) {
    throw FormatException(error.message);
  }
  final timer = parseTimerSnapshot(object['timer']);
  if ((template.kind == TemplateKind.accumulate) !=
      (timer.mode == TimerMode.countup)) {
    throw const FormatException('活动会话模式不匹配');
  }
  return ActiveSessionCheckpoint(
    version: version as int,
    sessionId: sessionId,
    template: template,
    startedAt: _nonnegativeInteger(object['startedAt'], 'startedAt'),
    interruptions: _nonnegativeInteger(
      object['interruptions'],
      'interruptions',
      max: 1 << 31,
    ),
    timer: timer,
    qualityEvidence: version == 2
        ? _parseEvidence(object['qualityEvidence'])
        : emptyFocusQualityEvidence,
    pendingInactiveAt: version == 2
        ? _optionalInteger(object, 'pendingInactiveAt')
        : null,
    pendingElapsedSec: version == 2
        ? _optionalInteger(object, 'pendingElapsedSec')
        : null,
    openBackgroundAt: version == 2
        ? _optionalInteger(object, 'openBackgroundAt')
        : null,
    openBackgroundElapsedSec: version == 2
        ? _optionalInteger(object, 'openBackgroundElapsedSec')
        : null,
  );
}
