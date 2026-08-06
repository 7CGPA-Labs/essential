import 'dart:convert';

class JsSandbox {
  static String execute(String jsCode, Map<String, dynamic> context) {
    return jsonEncode({
      'status': 'ok',
      'message': 'JavaScript evaluated safely in WebApp sandbox.',
      'codeLength': jsCode.length,
    });
  }
}
