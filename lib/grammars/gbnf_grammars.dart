/// Pre-built GBNF (GGML Backus-Naur Form) grammars for structured sampling.
class GbnfGrammars {
  /// Strict JSON Grammar: forces output to be valid JSON.
  static const String json = r'''
root   ::= object | array
object ::= "{" ws ( member ("," ws member)* )? "}" ws
member ::= string ":" ws value
array  ::= "[" ws ( value ("," ws value)* )? "]" ws
value  ::= object | array | string | number | "true" | "false" | "null"

string ::= "\"" ( [^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) )* "\"" ws
number ::= "-"? ([0-9]+) ("." [0-9]+)? ([eE] [+-]? [0-9]+)? ws
ws     ::= ([ \t\n\r])*
''';

  /// MCP Tool Call Grammar: forces output to follow structured Tool Call format.
  /// Format: { "tool": "VisionAdapter.ocr", "arguments": { "path": "/sdcard/frame.jpg" } }
  static const String toolCall = r'''
root       ::= "{" ws "\"tool\"" ":" ws string "," ws "\"arguments\"" ":" ws object "}" ws
object     ::= "{" ws ( member ("," ws member)* )? "}" ws
member     ::= string ":" ws value
array      ::= "[" ws ( value ("," ws value)* )? "]" ws
value      ::= object | array | string | number | "true" | "false" | "null"

string     ::= "\"" ( [^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) )* "\"" ws
number     ::= "-"? ([0-9]+) ("." [0-9]+)? ([eE] [+-]? [0-9]+)? ws
ws         ::= ([ \t\n\r])*
''';
}
