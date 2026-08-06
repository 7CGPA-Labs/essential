import 'package:flutter_test/flutter_test.dart';
import 'package:essential/sandbox/security_gate.dart';
import 'package:essential/workflow/dag_engine.dart';

void main() {
  group('Security Verification Chain Tests', () {
    final validator = SchemaValidator();
    final permissions = PermissionGate(['CAMERA', 'LOCATION']);
    final allowlist = DomainAllowlistFilter(['api.github.com', 'localhost']);

    validator.setNext(permissions).setNext(allowlist);

    test('Valid Mini-App Spec Passes Chain', () {
      const spec = '''{
        "name": "Weather Mini-App",
        "version": "1.0.0",
        "ui": "CARD",
        "permissions": ["LOCATION"],
        "network_endpoints": ["https://localhost/api/weather"]
      }''';
      expect(validator.handle(spec), isTrue);
    });

    test('Missing Required Key Fails Chain', () {
      const badSpec = '''{
        "name": "Broken App",
        "version": "1.0.0"
      }''';
      expect(validator.handle(badSpec), isFalse);
    });

    test('Unauthorized Permission Fails Chain', () {
      const badSpec = '''{
        "name": "Spy App",
        "version": "1.0.0",
        "ui": "CARD",
        "permissions": ["CONTACTS"]
      }''';
      expect(validator.handle(badSpec), isFalse);
    });

    test('Blocked Domain Fails Chain', () {
      const badSpec = '''{
        "name": "Phishing App",
        "version": "1.0.0",
        "ui": "CARD",
        "permissions": [],
        "network_endpoints": ["https://malicious-site.com/api"]
      }''';
      expect(validator.handle(badSpec), isFalse);
    });
  });

  group('DAG Workflow Engine Tests', () {
    test('Topological Node Execution Ordering', () {
      const dagSchema = '''{
        "nodes": [
          {"id": "node-1", "type": "TRIGGER", "properties": {"event": "BOOT"}},
          {"id": "node-3", "type": "ACTION", "properties": {"op": "NOTIFY"}},
          {"id": "node-2", "type": "CONDITION", "properties": {"check": "IS_CHARGING"}}
        ],
        "edges": [
          {"from": "node-1", "to": "node-2"},
          {"from": "node-2", "to": "node-3"}
        ]
      }''';

      final result = DagWorkflowEngine.executeWorkflow(dagSchema);
      expect(result['status'], equals('success'));
      final sequence = result['execution_sequence'] as List;
      expect(sequence[0], contains('node-1'));
      expect(sequence[1], contains('node-2'));
      expect(sequence[2], contains('node-3'));
    });

    test('Cyclic Edge Dependency Rejection', () {
      const badDag = '''{
        "nodes": [
          {"id": "A", "type": "TRIGGER", "properties": {}},
          {"id": "B", "type": "ACTION", "properties": {}}
        ],
        "edges": [
          {"from": "A", "to": "B"},
          {"from": "B", "to": "A"}
        ]
      }''';

      final result = DagWorkflowEngine.executeWorkflow(badDag);
      expect(result['status'], equals('error'));
      expect(result['message'], contains('Cyclic dependency'));
    });
  });
}
