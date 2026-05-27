enum AccessRuleMode { block, challenge, whitelist, jsChallenge, managedChallenge }

extension AccessRuleModeX on AccessRuleMode {
  String get apiValue {
    switch (this) {
      case AccessRuleMode.block:
        return 'block';
      case AccessRuleMode.challenge:
        return 'challenge';
      case AccessRuleMode.whitelist:
        return 'whitelist';
      case AccessRuleMode.jsChallenge:
        return 'js_challenge';
      case AccessRuleMode.managedChallenge:
        return 'managed_challenge';
    }
  }

  String get label {
    switch (this) {
      case AccessRuleMode.block:
        return 'Block';
      case AccessRuleMode.challenge:
        return 'Challenge';
      case AccessRuleMode.whitelist:
        return 'Allow';
      case AccessRuleMode.jsChallenge:
        return 'JS Challenge';
      case AccessRuleMode.managedChallenge:
        return 'Managed Challenge';
    }
  }

  static AccessRuleMode fromApi(String value) {
    switch (value) {
      case 'block':
        return AccessRuleMode.block;
      case 'challenge':
        return AccessRuleMode.challenge;
      case 'whitelist':
        return AccessRuleMode.whitelist;
      case 'js_challenge':
        return AccessRuleMode.jsChallenge;
      case 'managed_challenge':
        return AccessRuleMode.managedChallenge;
    }
    return AccessRuleMode.block;
  }
}

enum AccessRuleTargetType { ip, ipRange, country, asn }

extension AccessRuleTargetTypeX on AccessRuleTargetType {
  String get apiValue {
    switch (this) {
      case AccessRuleTargetType.ip:
        return 'ip';
      case AccessRuleTargetType.ipRange:
        return 'ip_range';
      case AccessRuleTargetType.country:
        return 'country';
      case AccessRuleTargetType.asn:
        return 'asn';
    }
  }

  String get label {
    switch (this) {
      case AccessRuleTargetType.ip:
        return 'IP';
      case AccessRuleTargetType.ipRange:
        return 'IP Range';
      case AccessRuleTargetType.country:
        return 'Country';
      case AccessRuleTargetType.asn:
        return 'ASN';
    }
  }

  String get hint {
    switch (this) {
      case AccessRuleTargetType.ip:
        return 'e.g. 8.8.8.8';
      case AccessRuleTargetType.ipRange:
        return 'e.g. 192.0.2.0/24';
      case AccessRuleTargetType.country:
        return 'e.g. CN (ISO country code)';
      case AccessRuleTargetType.asn:
        return 'e.g. AS13335';
    }
  }
}

class IpAccessRule {
  final String id;
  final AccessRuleMode mode;
  final AccessRuleTargetType targetType;
  final String targetValue;
  final String? notes;

  IpAccessRule({
    required this.id,
    required this.mode,
    required this.targetType,
    required this.targetValue,
    this.notes,
  });

  factory IpAccessRule.fromJson(Map<String, dynamic> json) {
    final config = (json['configuration'] as Map<String, dynamic>?) ?? const {};
    final target = (config['target'] as String?) ?? 'ip';
    AccessRuleTargetType type;
    switch (target) {
      case 'ip_range':
        type = AccessRuleTargetType.ipRange;
        break;
      case 'country':
        type = AccessRuleTargetType.country;
        break;
      case 'asn':
        type = AccessRuleTargetType.asn;
        break;
      default:
        type = AccessRuleTargetType.ip;
    }
    return IpAccessRule(
      id: json['id'] as String,
      mode: AccessRuleModeX.fromApi((json['mode'] as String?) ?? 'block'),
      targetType: type,
      targetValue: (config['value'] as String?) ?? '',
      notes: json['notes'] as String?,
    );
  }
}
