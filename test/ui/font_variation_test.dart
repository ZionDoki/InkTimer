import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/ui/theme/zen_theme.dart';

double _wght(TextStyle style) {
  final variations = style.fontVariations;
  expect(variations, isNotNull, reason: '可变字体必须显式提供 fontVariations，否则字重停在轴默认值');
  final axis = variations!.firstWhere((v) => v.axis == 'wght');
  return axis.value;
}

void main() {
  group('可变字体 wght 轴', () {
    test('请求的字重会真正落到轴上，而不是停在默认值', () {
      expect(_wght(zenTextStyle(weight: FontWeight.w400)), 400);
      expect(
        _wght(zenTextStyle(family: zenSerifSc, weight: FontWeight.w600)),
        600,
      );
    });

    test('Cormorant 轴区间 300–700，超出请求收敛到端点', () {
      expect(_wght(zenTextStyle(weight: FontWeight.w100)), 300);
      expect(_wght(zenTextStyle(weight: FontWeight.w200)), 300);
      expect(_wght(zenTextStyle(weight: FontWeight.w900)), 700);
      expect(_wght(zenTextStyle(weight: FontWeight.w700)), 700);
    });

    test('Noto Serif SC 轴区间 200–900，超出请求收敛到端点', () {
      expect(
        _wght(zenTextStyle(family: zenSerifSc, weight: FontWeight.w100)),
        200,
      );
      expect(
        _wght(zenTextStyle(family: zenSerifSc, weight: FontWeight.w900)),
        900,
      );
    });

    test('未指定字体族时按西文衬线体的轴区间处理', () {
      expect(zenFontVariations(null, FontWeight.w100).single.value, 300);
    });

    test('extension 让已有样式的 fontWeight 生效', () {
      const raw = TextStyle(
        fontFamily: zenSerifSc,
        fontWeight: FontWeight.w600,
      );
      expect(raw.fontVariations, isNull);
      expect(_wght(raw.variableWeight), 600);
    });

    test('主题正文与标题都已驱动轴，正文不再停在 200', () {
      final theme = buildZenTheme(ink: false);
      expect(_wght(theme.textTheme.bodyMedium!), 400);
      expect(_wght(theme.textTheme.bodyLarge!), 400);
      expect(_wght(theme.textTheme.bodySmall!), 400);
      expect(_wght(theme.textTheme.titleLarge!), 400);
      expect(_wght(theme.textTheme.titleMedium!), 400);
      expect(_wght(theme.textTheme.labelLarge!), 400);
    });

    test('中文正文样式回退不再绕回自身', () {
      final style = zenTextStyle(family: zenSerifSc);
      expect(style.fontFamily, zenSerifSc);
      expect(style.fontFamilyFallback, isNot(contains(zenSerifSc)));
    });

    testWidgets('inkText 在真实上下文中驱动轴', (tester) async {
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildZenTheme(ink: false),
          home: Builder(
            builder: (context) {
              style = inkText(context, weight: FontWeight.w500);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(_wght(style), 500);
    });
  });
}
