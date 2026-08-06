import 'dart:convert';
import 'dart:developer' as developer;

abstract class SecurityGate {
  SecurityGate? nextGate;

  SecurityGate setNext(SecurityGate gate) {
    nextGate = gate;
    return gate;
  }

  bool handle(String miniAppSpecJson);
}

class SchemaValidator extends SecurityGate {
  @override
  bool handle(String miniAppSpecJson) {
    try {
      final spec = jsonDecode(miniAppSpecJson) as Map<String, dynamic>;
      if (!spec.containsKey('name') || !spec.containsKey('version') || !spec.containsKey('ui')) {
        developer.log("Security Verification Failure: Invalid JSON Schema structure", name: "SecurityGate");
        return false;
      }
      return nextGate?.handle(miniAppSpecJson) ?? true;
    } catch (e) {
      developer.log("Security Verification Failure: Malformed JSON syntax - $e", name: "SecurityGate");
      return false;
    }
  }
}

class PermissionGate extends SecurityGate {
  final List<String> grantedPermissions;

  PermissionGate(this.grantedPermissions);

  @override
  bool handle(String miniAppSpecJson) {
    final spec = jsonDecode(miniAppSpecJson) as Map<String, dynamic>;
    final requested = spec['permissions'] as List?;
    
    if (requested != null) {
      for (final p in requested) {
        if (!grantedPermissions.contains(p)) {
          developer.log("Security Verification Failure: Unauthorized Permission access request ($p)", name: "SecurityGate");
          return false;
        }
      }
    }
    return nextGate?.handle(miniAppSpecJson) ?? true;
  }
}

class DomainAllowlistFilter extends SecurityGate {
  final List<String> allowedDomains;

  DomainAllowlistFilter(this.allowedDomains);

  @override
  bool handle(String miniAppSpecJson) {
    final spec = jsonDecode(miniAppSpecJson) as Map<String, dynamic>;
    final endpoints = spec['network_endpoints'] as List?;

    if (endpoints != null) {
      for (final url in endpoints) {
        final uri = Uri.parse(url as String);
        if (!allowedDomains.contains(uri.host)) {
          developer.log("Security Verification Failure: Blocked domain request - Host ${uri.host} is not in domain allowlist!", name: "SecurityGate");
          return false;
        }
      }
    }
    return nextGate?.handle(miniAppSpecJson) ?? true;
  }
}
