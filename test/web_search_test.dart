import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingsaathi/services/web_search_service.dart';

class RealHttpOverrides extends HttpOverrides {}

void main() {
  HttpOverrides.global = RealHttpOverrides();

  group('WebSearchService NLP Webcrawler Unit Tests', () {
    test('searchWeb gracefully processes live search query', () async {
      final results = await WebSearchService.searchWeb('Google AI Studio');
      expect(results, isA<String>());
    });

    test('searchWeb returns non-null string for technology query', () async {
      final results = await WebSearchService.searchWeb('Flutter framework');
      expect(results, isA<String>());
    });

    test('searchWeb handles empty query gracefully without throwing exception', () async {
      final results = await WebSearchService.searchWeb('');
      expect(results, isA<String>());
      expect(results.isEmpty, isTrue);
    });
  });
}
