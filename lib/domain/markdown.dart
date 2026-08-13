String _escapeHtml(String source) => source
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _renderInline(String source) => source
    .replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (match) => '<strong>${match.group(1)}</strong>',
    )
    .replaceAllMapped(
      RegExp(r'\*([^*]+)\*'),
      (match) => '<em>${match.group(1)}</em>',
    )
    .replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (match) => '<code>${match.group(1)}</code>',
    )
    .replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)'),
      (match) =>
          '<a href="${match.group(2)}" target="_blank" rel="noopener">${match.group(1)}</a>',
    )
    .replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\((?:[^()]|\([^()]*\))*\)'),
      (match) => match.group(1)!,
    );

String renderMarkdown(String source) {
  final output = <String>[];
  var paragraph = <String>[];
  var list = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    output.add('<p>${paragraph.map(_renderInline).join('<br>')}</p>');
    paragraph = <String>[];
  }

  void flushList() {
    if (list.isEmpty) return;
    output.add(
      '<ul>${list.map((item) => '<li>${_renderInline(item)}</li>').join()}</ul>',
    );
    list = <String>[];
  }

  for (final line in _escapeHtml(source).split('\n')) {
    final trimmed = line.trim();
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
    final item = RegExp(r'^-\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      flushList();
      final level = heading.group(1)!.length + 2;
      output.add('<h$level>${_renderInline(heading.group(2)!)}</h$level>');
    } else if (item != null) {
      flushParagraph();
      list.add(item.group(1)!);
    } else if (trimmed.isEmpty) {
      flushParagraph();
      flushList();
    } else {
      flushList();
      paragraph.add(trimmed);
    }
  }
  flushParagraph();
  flushList();
  return output.join();
}
