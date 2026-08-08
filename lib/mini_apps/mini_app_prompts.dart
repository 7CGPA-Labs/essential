/// System prompt contracts for SLM (Small Language Models e.g. Qwen2.5-Coder-1.5B)
/// enforcing XML tag wrapping (`<html_app>`) to avoid JSON escaping issues.
class MiniAppPrompts {
  /// System Prompt for New App Creation
  static const String creationSystemPrompt =
      'You are an expert single-file HTML/CSS/JS developer. Write clean, complete, responsive single-file code. Wrap your final code strictly inside <html_app>...</html_app> tags.';

  /// System Prompt for Editing existing apps
  static const String editingSystemPrompt =
      'You are an expert HTML mini app developer. You will receive the existing HTML file and a user request. Return the complete updated single-file HTML code wrapped inside <html_app>...</html_app> tags.';

  /// Formats creation prompt for full app generation
  static String buildCreationPrompt(String userPrompt) {
    return '$creationSystemPrompt\n\n'
        'USER REQUEST: $userPrompt\n\n'
        'Generate complete single-file HTML/CSS/JS code wrapped inside <html_app>...</html_app>.';
  }

  /// Formats edit prompt with existing HTML source code
  static String buildEditingPrompt(String existingHtml, String userRequest) {
    return '$editingSystemPrompt\n\n'
        'EXISTING HTML FILE:\n'
        '```html\n$existingHtml\n```\n\n'
        'USER REQUEST: $userRequest\n\n'
        'Output the complete updated single-file HTML code wrapped strictly inside <html_app>...</html_app>.';
  }
}
