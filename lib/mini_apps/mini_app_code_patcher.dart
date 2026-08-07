import 'package:flutter/foundation.dart';

/// MiniAppCodePatcher handles XML Tag Extraction (`<html_app>`),
/// Search/Replace diff editing (`<code_diff>` / SEARCH-REPLACE blocks),
/// and HTML auto-repair to prevent broken WebView execution.
class MiniAppCodePatcher {
  /// Extracts HTML/CSS/JS code from LLM output.
  /// Isolates content strictly inside `<html_app>...</html_app>` tags.
  /// Raw text outside `<html_app>` tags is completely ignored.
  static String extractAppCode(String llmOutput) {
    if (llmOutput.isEmpty) return '';

    // 1. Try isolating content inside <html_app>...</html_app>
    final appTagMatch = RegExp(
      r'<html_app>\s*([\s\S]*?)(?:</html_app>|$)',
      caseSensitive: false,
    ).firstMatch(llmOutput);

    String code;
    if (appTagMatch != null && appTagMatch.group(1) != null) {
      code = appTagMatch.group(1)!.trim();
    } else {
      // Fallback: Check for markdown code blocks or direct HTML string
      final markdownMatch = RegExp(
        r'```(?:html)?\s*([\s\S]*?)```',
        caseSensitive: false,
      ).firstMatch(llmOutput);

      if (markdownMatch != null) {
        code = markdownMatch.group(1)!.trim();
      } else {
        final docTypeStart = llmOutput.indexOf('<!DOCTYPE html');
        final htmlStart = llmOutput.indexOf('<html');
        final startIdx = docTypeStart >= 0
            ? docTypeStart
            : (htmlStart >= 0 ? htmlStart : -1);
        final endIdx = llmOutput.lastIndexOf('</html>');

        if (startIdx >= 0 && endIdx > startIdx) {
          code = llmOutput.substring(startIdx, endIdx + 7).trim();
        } else if (startIdx >= 0) {
          code = llmOutput.substring(startIdx).trim();
        } else {
          code = llmOutput.trim();
        }
      }
    }

    // Clean any inner backtick wrapping if present inside <html_app>
    if (code.startsWith('```html')) {
      code = code.substring(7);
    } else if (code.startsWith('```')) {
      code = code.substring(3);
    }
    if (code.endsWith('```')) {
      code = code.substring(0, code.length - 3);
    }

    return autoRepairHtml(code.trim());
  }

  /// Extracts search/replace diff blocks from LLM output (`<code_diff>` or raw diffs)
  /// and applies them sequentially to [originalHtml].
  static String applyDiffs(String originalHtml, String diffOutput) {
    if (diffOutput.isEmpty) return originalHtml;

    // Isolate code_diff tag if present
    String diffContent = diffOutput;
    final diffTagMatch = RegExp(
      r'<code_diff>\s*([\s\S]*?)(?:</code_diff>|$)',
      caseSensitive: false,
    ).firstMatch(diffOutput);

    if (diffTagMatch != null && diffTagMatch.group(1) != null) {
      diffContent = diffTagMatch.group(1)!;
    }

    // Find all SEARCH / REPLACE diff blocks
    final diffRegex = RegExp(
      r'<<<<<<<\s*SEARCH\r?\n([\s\S]*?)\r?\n=======\r?\n([\s\S]*?)\r?\n>>>>>>>\s*REPLACE',
    );

    final matches = diffRegex.allMatches(diffContent).toList();
    if (matches.isEmpty) {
      debugPrint('[MiniAppCodePatcher] No SEARCH/REPLACE diff blocks found.');
      return originalHtml;
    }

    String currentHtml = originalHtml;

    for (final match in matches) {
      final searchBlock = match.group(1);
      final replaceBlock = match.group(2) ?? '';

      if (searchBlock == null) continue;

      currentHtml = _patchSingleBlock(currentHtml, searchBlock, replaceBlock);
    }

    return autoRepairHtml(currentHtml);
  }

  /// Patches a single search block with replace block in [source]
  static String _patchSingleBlock(
      String source, String searchBlock, String replaceBlock) {
    // 1. Direct exact match
    if (source.contains(searchBlock)) {
      return source.replaceFirst(searchBlock, replaceBlock);
    }

    // 2. Line ending normalization (\r\n -> \n)
    final normalizedSource = source.replaceAll('\r\n', '\n');
    final normalizedSearch = searchBlock.replaceAll('\r\n', '\n');
    final normalizedReplace = replaceBlock.replaceAll('\r\n', '\n');

    if (normalizedSource.contains(normalizedSearch)) {
      return normalizedSource.replaceFirst(
          normalizedSearch, normalizedReplace);
    }

    // 3. Line-by-line whitespace-trimmed match
    final sourceLines = normalizedSource.split('\n');
    final searchLines = normalizedSearch.split('\n');

    if (searchLines.isEmpty) return source;

    int matchIndex = -1;
    for (int i = 0; i <= sourceLines.length - searchLines.length; i++) {
      bool isMatch = true;
      for (int j = 0; j < searchLines.length; j++) {
        if (sourceLines[i + j].trimRight() != searchLines[j].trimRight()) {
          isMatch = false;
          break;
        }
      }
      if (isMatch) {
        matchIndex = i;
        break;
      }
    }

    if (matchIndex != -1) {
      final replaceLines = normalizedReplace.split('\n');
      sourceLines.replaceRange(
        matchIndex,
        matchIndex + searchLines.length,
        replaceLines,
      );
      return sourceLines.join('\n');
    }

    debugPrint('[MiniAppCodePatcher] Could not find match for search block:\n$searchBlock');
    return source;
  }

  /// Fallback auto-repair to close missing `</script>`, `</body>`, or `</html>` tags.
  static String autoRepairHtml(String html) {
    if (html.isEmpty) return html;

    String repaired = html;

    // Check script tags balance
    final scriptOpenCount = RegExp(r'<script\b', caseSensitive: false)
        .allMatches(repaired)
        .length;
    final scriptCloseCount = RegExp(r'</script>', caseSensitive: false)
        .allMatches(repaired)
        .length;

    if (scriptOpenCount > scriptCloseCount) {
      repaired += '\n</script>';
    }

    // Check body tag
    final hasBodyOpen = RegExp(r'<body\b', caseSensitive: false).hasMatch(repaired);
    final hasBodyClose = RegExp(r'</body>', caseSensitive: false).hasMatch(repaired);
    final hasHtmlClose = RegExp(r'</html>', caseSensitive: false).hasMatch(repaired);

    if (hasBodyOpen && !hasBodyClose) {
      if (hasHtmlClose) {
        repaired = repaired.replaceFirst(
          RegExp(r'</html>', caseSensitive: false),
          '</body>\n</html>',
        );
      } else {
        repaired += '\n</body>';
      }
    }

    if (!hasHtmlClose && (hasBodyClose || hasBodyOpen || repaired.toLowerCase().contains('<html'))) {
      repaired += '\n</html>';
    }

    return repaired;
  }
}
