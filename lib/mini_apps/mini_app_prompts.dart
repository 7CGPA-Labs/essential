/// System prompt contracts for SLM (Small Language Models e.g. Qwen2.5-Coder-1.5B)
/// enforcing XML tag wrapping (`<html_app>` and `<code_diff>`) to avoid JSON escaping issues.
class MiniAppPrompts {
  /// System Prompt for New App Creation
  static const String creationSystemPrompt =
      'You are a single-file HTML/CSS/JS generator. Write clean, responsive single-file code. Wrap your final code strictly inside <html_app>...</html_app> tags. Do not wrap inside JSON.';

  /// System Prompt for Editing existing apps via Search/Replace diffs
  static const String editingSystemPrompt =
      'You are a code editor. You will receive the existing HTML file and a user request. Return ONLY the search/replace diff blocks inside <code_diff>...</code_diff> tags using <<<<<<< SEARCH\n...existing code...\n=======\n...new code...\n>>>>>>> REPLACE format.';

  /// Formats creation prompt for full app generation
  static String buildCreationPrompt(String userPrompt) {
    return '$creationSystemPrompt\n\n'
        'USER REQUEST: $userPrompt\n\n'
        'Generate complete single-file HTML/CSS/JS code wrapped inside <html_app>...</html_app>.';
  }

  /// Formats edit prompt with existing HTML source code and search/replace diff instructions
  static String buildEditingPrompt(String existingHtml, String userRequest) {
    return '$editingSystemPrompt\n\n'
        'EXISTING HTML FILE:\n'
        '```html\n$existingHtml\n```\n\n'
        'USER REQUEST: $userRequest\n\n'
        'Respond with search/replace diff blocks enclosed in <code_diff>...</code_diff>:\n'
        '<code_diff>\n'
        '<<<<<<< SEARCH\n'
        '// Existing lines to replace\n'
        '=======\n'
        '// New lines\n'
        '>>>>>>> REPLACE\n'
        '</code_diff>';
  }
}
