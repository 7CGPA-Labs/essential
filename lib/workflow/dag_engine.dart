import 'dart:convert';

class DagWorkflowEngine {
  // Parses a Directed Acyclic Graph dynamic JSON automation workflow spec:
  // e.g. Node A (Trigger) -> Node B (Condition) -> Node C (Action)
  static Map<String, dynamic> executeWorkflow(String workflowSchemaJson) {
    try {
      final spec = jsonDecode(workflowSchemaJson) as Map<String, dynamic>;
      final nodes = spec['nodes'] as List;
      final edges = spec['edges'] as List;

      // Simple topological dependency sorting validation and traversal
      final visited = <String>{};
      final executionOrder = <Map<String, dynamic>>[];

      // Build dependency graph representation
      final adjacencyList = <String, List<String>>{};
      final inDegree = <String, int>{};
      final nodeMap = <String, Map<String, dynamic>>{};

      for (final node in nodes) {
        final id = node['id'] as String;
        nodeMap[id] = node as Map<String, dynamic>;
        adjacencyList[id] = [];
        inDegree[id] = 0;
      }

      for (final edge in edges) {
        final from = edge['from'] as String;
        final to = edge['to'] as String;
        adjacencyList[from]!.add(to);
        inDegree[to] = (inDegree[to] ?? 0) + 1;
      }

      // Kahn's topological sort implementation
      final queue = <String>[];
      inDegree.forEach((nodeId, deg) {
        if (deg == 0) queue.add(nodeId);
      });

      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        executionOrder.add(nodeMap[current]!);
        visited.add(current);

        for (final neighbor in adjacencyList[current]!) {
          inDegree[neighbor] = inDegree[neighbor]! - 1;
          if (inDegree[neighbor] == 0) {
            queue.add(neighbor);
          }
        }
      }

      if (executionOrder.length != nodes.length) {
        throw Exception("Cyclic dependency error detected in DAG schema nodes!");
      }

      // Execute nodes sequentially
      final executionLog = [];
      for (final node in executionOrder) {
        final type = node['type'] as String;
        final details = node['properties'] as Map<String, dynamic>;
        executionLog.add("Executed ${node['id']} (Type: $type) with properties: $details");
      }

      return {
        'status': 'success',
        'execution_sequence': executionLog,
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': e.toString(),
      };
    }
  }
}
