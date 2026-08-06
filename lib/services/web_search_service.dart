import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// On-device Web Search service providing live internet information retrieval.
class WebSearchService {
  static Future<String> searchWeb(String query) async {
    try {
      final uri = Uri.parse('https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}');
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = response.body;
        final List<String> snippets = [];

        final regex = RegExp(r'<a class="result__snippet[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true);
        final matches = regex.allMatches(body);

        for (final match in matches.take(4)) {
          final snippetText = match.group(1)
              ?.replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll('&quot;', '"')
              .replaceAll('&#27;', "'")
              .replaceAll('&amp;', '&')
              .replaceAll('\n', ' ')
              .trim();
          if (snippetText != null && snippetText.isNotEmpty) {
            snippets.add(snippetText);
          }
        }

        if (snippets.isNotEmpty) {
          return snippets.join('\n\n');
        }
      }
    } catch (e) {
      debugPrint('DuckDuckGo Web Search Error: $e');
    }

    // Fallback Wikipedia search API
    try {
      final wikiUri = Uri.parse('https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&format=json');
      final response = await http.get(wikiUri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final searchResults = data['query']?['search'] as List?;
        if (searchResults != null && searchResults.isNotEmpty) {
          final List<String> wikiSnippets = [];
          for (final item in searchResults.take(3)) {
            final snippet = item['snippet']
                ?.toString()
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll('&quot;', '"')
                .replaceAll('&amp;', '&')
                .trim();
            if (snippet != null && snippet.isNotEmpty) {
              wikiSnippets.add('[Wikipedia] $snippet');
            }
          }
          if (wikiSnippets.isNotEmpty) {
            return wikiSnippets.join('\n\n');
          }
        }
      }
    } catch (e) {
      debugPrint('Wikipedia Web Search Error: $e');
    }

    return '';
  }
}
