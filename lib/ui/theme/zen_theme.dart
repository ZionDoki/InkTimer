import 'package:flutter/material.dart';

@immutable
class ZenPalette extends ThemeExtension<ZenPalette> {
  const ZenPalette({
    required this.paper,
    required this.paperDeep,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.work,
    required this.workSoft,
    required this.workGlow,
    required this.rest,
    required this.restSoft,
    required this.restGlow,
    required this.gold,
    required this.isInk,
  });

  static const paperTheme = ZenPalette(
    paper: Color(0xfff0ebdf),
    paperDeep: Color(0xffe6dfd0),
    ink: Color(0xff231f19),
    inkSoft: Color(0xb3231f19),
    inkFaint: Color(0x40231f19),
    work: Color(0xffa03d1f),
    workSoft: Color(0x4da03d1f),
    workGlow: Color(0x29a03d1f),
    rest: Color(0xff476b58),
    restSoft: Color(0x47476b58),
    restGlow: Color(0x26476b58),
    gold: Color(0xffa8873f),
    isInk: false,
  );

  static const inkTheme = ZenPalette(
    paper: Color(0xff17140f),
    paperDeep: Color(0xff221e17),
    ink: Color(0xffe8e2d4),
    inkSoft: Color(0xb3e8e2d4),
    inkFaint: Color(0x52e8e2d4),
    work: Color(0xffbc6245),
    workSoft: Color(0x5abc6245),
    workGlow: Color(0x33bc6245),
    rest: Color(0xff719780),
    restSoft: Color(0x52719780),
    restGlow: Color(0x33719780),
    gold: Color(0xffc4a45a),
    isInk: true,
  );

  final Color paper;
  final Color paperDeep;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color work;
  final Color workSoft;
  final Color workGlow;
  final Color rest;
  final Color restSoft;
  final Color restGlow;
  final Color gold;
  final bool isInk;

  static ZenPalette of(BuildContext context) =>
      Theme.of(context).extension<ZenPalette>() ?? paperTheme;

  @override
  ZenPalette copyWith({
    Color? paper,
    Color? paperDeep,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? work,
    Color? workSoft,
    Color? workGlow,
    Color? rest,
    Color? restSoft,
    Color? restGlow,
    Color? gold,
    bool? isInk,
  }) => ZenPalette(
    paper: paper ?? this.paper,
    paperDeep: paperDeep ?? this.paperDeep,
    ink: ink ?? this.ink,
    inkSoft: inkSoft ?? this.inkSoft,
    inkFaint: inkFaint ?? this.inkFaint,
    work: work ?? this.work,
    workSoft: workSoft ?? this.workSoft,
    workGlow: workGlow ?? this.workGlow,
    rest: rest ?? this.rest,
    restSoft: restSoft ?? this.restSoft,
    restGlow: restGlow ?? this.restGlow,
    gold: gold ?? this.gold,
    isInk: isInk ?? this.isInk,
  );

  @override
  ZenPalette lerp(covariant ZenPalette? other, double t) {
    if (other == null) return this;
    return ZenPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      paperDeep: Color.lerp(paperDeep, other.paperDeep, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      work: Color.lerp(work, other.work, t)!,
      workSoft: Color.lerp(workSoft, other.workSoft, t)!,
      workGlow: Color.lerp(workGlow, other.workGlow, t)!,
      rest: Color.lerp(rest, other.rest, t)!,
      restSoft: Color.lerp(restSoft, other.restSoft, t)!,
      restGlow: Color.lerp(restGlow, other.restGlow, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      isInk: t < 0.5 ? isInk : other.isInk,
    );
  }

  /// 根据隐修等级返回渐变加深的调色板。
  /// level 1 返回原样，level 99 达到最深状态。
  ZenPalette deepenedForLevel(int level) {
    if (level < 1 || level > 99) return this;
    // 归一化到 0.0-1.0，等级 1 → 0.0，等级 99 → 1.0
    final t = (level - 1) / 98.0;

    if (isInk) {
      // 墨本：背景逐渐接近纯黑，文字逐渐变亮，色彩饱和度提升
      return ZenPalette(
        paper: Color.lerp(paper, const Color(0xff0a0805), t)!,
        paperDeep: Color.lerp(paperDeep, const Color(0xff121008), t)!,
        ink: Color.lerp(ink, const Color(0xfff5f0e8), t)!,
        inkSoft: Color.lerp(inkSoft, const Color(0x95f5f0e8), t)!,
        inkFaint: Color.lerp(inkFaint, const Color(0x33f5f0e8), t)!,
        work: Color.lerp(work, const Color(0xffd67a5a), t)!,
        workSoft: Color.lerp(workSoft, const Color(0x70d67a5a), t)!,
        workGlow: Color.lerp(workGlow, const Color(0x40d67a5a), t)!,
        rest: Color.lerp(rest, const Color(0xff8db89d), t)!,
        restSoft: Color.lerp(restSoft, const Color(0x688db89d), t)!,
        restGlow: Color.lerp(restGlow, const Color(0x408db89d), t)!,
        gold: Color.lerp(gold, const Color(0xffe0c070), t)!,
        isInk: true,
      );
    } else {
      // 纸本：背景逐渐偏向古旧米黄，墨色加深，色彩略微浓郁
      return ZenPalette(
        paper: Color.lerp(paper, const Color(0xffe8dfc8), t)!,
        paperDeep: Color.lerp(paperDeep, const Color(0xffdacfb0), t)!,
        ink: Color.lerp(ink, const Color(0xff1a1510), t)!,
        inkSoft: Color.lerp(inkSoft, const Color(0x9a1a1510), t)!,
        inkFaint: Color.lerp(inkFaint, const Color(0x2a1a1510), t)!,
        work: Color.lerp(work, const Color(0xff8f3518), t)!,
        workSoft: Color.lerp(workSoft, const Color(0x558f3518), t)!,
        workGlow: Color.lerp(workGlow, const Color(0x2f8f3518), t)!,
        rest: Color.lerp(rest, const Color(0xff3d5f4d), t)!,
        restSoft: Color.lerp(restSoft, const Color(0x503d5f4d), t)!,
        restGlow: Color.lerp(restGlow, const Color(0x2a3d5f4d), t)!,
        gold: Color.lerp(gold, const Color(0xff987630), t)!,
        isInk: false,
      );
    }
  }
}

ThemeData buildZenTheme({required bool ink}) {
  final palette = ink ? ZenPalette.inkTheme : ZenPalette.paperTheme;
  final brightness = ink ? Brightness.dark : Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.work,
        brightness: brightness,
        surface: palette.paper,
      ).copyWith(
        primary: palette.work,
        secondary: palette.rest,
        onSurface: palette.ink,
        surface: palette.paper,
        outline: palette.inkFaint,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.paper,
    fontFamily: 'Cormorant',
    fontFamilyFallback: const ['NotoSerifSC', 'serif'],
    extensions: [palette],
    textTheme: TextTheme(
      bodyLarge: zenTextStyle(size: 18, color: palette.ink),
      bodyMedium: zenTextStyle(size: 16, color: palette.ink),
      bodySmall: zenTextStyle(size: 13, color: palette.inkSoft),
      titleLarge: zenTextStyle(
        family: zenSerifSc,
        size: 18,
        color: palette.ink,
      ),
      titleMedium: zenTextStyle(
        family: zenSerifSc,
        size: 15,
        color: palette.ink,
      ),
      labelLarge: zenTextStyle(
        family: zenSerifSc,
        size: 14,
        color: palette.ink,
      ),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: palette.inkFaint.withValues(alpha: 0.08),
    dividerColor: palette.inkFaint,
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.inkFaint),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.work.withValues(alpha: 0.65)),
      ),
      hintStyle: TextStyle(color: palette.inkSoft),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.ink,
      inactiveTrackColor: palette.inkFaint,
      thumbColor: palette.work,
      overlayColor: palette.workGlow,
      trackHeight: 1,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
    ),
  );
}

TextStyle inkText(
  BuildContext context, {
  double size = 14,
  Color? color,
  double spacing = 2,
  FontWeight weight = FontWeight.w400,
}) {
  final palette = ZenPalette.of(context);
  return zenTextStyle(
    family: zenSerifSc,
    size: size,
    weight: weight,
    color: color ?? palette.ink,
    letterSpacing: spacing,
    height: 1.45,
  );
}

/// 正文西文与数字使用的可变衬线体，wght 轴区间 300–700。
const String zenCormorant = 'Cormorant';

/// 中文正文使用的可变衬线体，wght 轴区间 200–900。
const String zenSerifSc = 'NotoSerifSC';

const double _cormorantMinWeight = 300;
const double _cormorantMaxWeight = 700;
const double _serifScMinWeight = 200;
const double _serifScMaxWeight = 900;

/// Cormorant 与 Noto Serif SC 都是可变字体（含 fvar 表）。仅设置 [FontWeight]
/// 不会移动 wght 轴，字形会始终停在轴默认值（Cormorant 300、Noto Serif SC 200），
/// 因此正文会比预期细很多。真正生效必须同时给出 [FontVariation]。
///
/// 超出轴区间的请求会被收敛到端点，避免落回默认实例或触发合成加粗。
List<FontVariation> zenFontVariations(String? family, FontWeight? weight) {
  final requested = (weight ?? FontWeight.w400).value.toDouble();
  final clamped = family == zenSerifSc
      ? requested.clamp(_serifScMinWeight, _serifScMaxWeight)
      : requested.clamp(_cormorantMinWeight, _cormorantMaxWeight);
  return <FontVariation>[FontVariation('wght', clamped.toDouble())];
}

/// 构造已驱动 wght 轴的文本样式。字体族默认取西文衬线体。
TextStyle zenTextStyle({
  String family = zenCormorant,
  double? size,
  Color? color,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
  double? height,
  List<FontFeature>? fontFeatures,
  TextDecoration? decoration,
}) => TextStyle(
  fontFamily: family,
  fontFamilyFallback: family == zenSerifSc
      ? const <String>['serif']
      : const <String>[zenSerifSc, 'serif'],
  fontSize: size,
  color: color,
  fontWeight: weight,
  fontVariations: zenFontVariations(family, weight),
  letterSpacing: letterSpacing,
  height: height,
  fontFeatures: fontFeatures,
  decoration: decoration,
);

extension ZenVariableWeight on TextStyle {
  /// 让已有样式的 [FontWeight] 真正作用到可变字体的 wght 轴上。
  TextStyle get variableWeight =>
      copyWith(fontVariations: zenFontVariations(fontFamily, fontWeight));
}
