import 'package:flutter/material.dart';

import '../theme/zen_theme.dart';
import 'paper_background.dart';

class ZenPage extends StatelessWidget {
  const ZenPage({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = 420,
    this.padding = const EdgeInsets.fromLTRB(32, 6, 32, 48),
  });

  final String title;
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: 60,
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey('close-page'),
                  onPressed: () => Navigator.maybePop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.inkSoft,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: Text(
                    '收 起',
                    style: inkText(context, size: 11, spacing: 5),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Padding(
                        padding: padding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 14),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: inkText(context, size: 15, spacing: 7),
                            ),
                            const SizedBox(height: 30),
                            child,
                            SizedBox(
                              height: MediaQuery.paddingOf(context).bottom,
                            ),
                          ],
                        ),
                      ),
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
}

class ZenSectionTitle extends StatelessWidget {
  const ZenSectionTitle(this.label, {super.key, this.top = 48});

  final String label;
  final double top;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 22),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: inkText(
              context,
              size: 11,
              color: palette.inkSoft,
              spacing: 5,
            ),
          ),
          const SizedBox(height: 10),
          Container(width: 40, height: 1, color: palette.inkFaint),
        ],
      ),
    );
  }
}

/// 朱印：连续天数里程碑的唯一视觉形式，功课簿与隐修履历共用。
class ZenSeal extends StatelessWidget {
  const ZenSeal(this.character, {super.key, required this.earned});

  final String character;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Container(
      width: 54,
      height: 54,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: earned ? palette.work : palette.inkFaint,
          width: 1.4,
        ),
        color: earned ? palette.work.withValues(alpha: 0.08) : null,
      ),
      child: Text(
        character,
        style: inkText(
          context,
          size: 22,
          color: earned ? palette.work : palette.inkFaint,
        ),
      ),
    );
  }
}

class InkChip extends StatelessWidget {
  const InkChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: selected
                ? (filled ? palette.ink : palette.ink.withValues(alpha: 0.08))
                : null,
            border: Border.all(
              color: selected
                  ? palette.ink.withValues(alpha: 0.38)
                  : palette.inkFaint,
            ),
          ),
          child: Text(
            label,
            style: inkText(
              context,
              size: 12,
              color: selected
                  ? (filled ? palette.paper : palette.ink)
                  : palette.inkSoft,
              spacing: 2.5,
            ),
          ),
        ),
      ),
    );
  }
}
