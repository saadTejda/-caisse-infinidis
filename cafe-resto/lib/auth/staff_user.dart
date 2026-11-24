class StaffUser {
  const StaffUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.locale,
    required this.isActive,
    required this.roles,
    required this.permissions,
  });

  final int? id;
  final String name;
  final String email;
  final String phone;
  final String locale;
  final bool isActive;
  final List<String> roles;
  final List<String> permissions;

  bool get isAdmin => roles.contains('admin');

  bool can(String permission) => isAdmin || permissions.contains(permission);

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((item) => '$item').where((item) => item.isNotEmpty).toList();
    }

    final locale = '${json['locale'] ?? 'fr'}';
    return StaffUser(
      id: int.tryParse('${json['id']}'),
      name: '${json['name'] ?? ''}',
      email: '${json['email'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      locale: const ['fr', 'ar', 'en'].contains(locale) ? locale : 'fr',
      isActive: json['is_active'] != false && json['is_active'] != 0 && json['is_active'] != '0',
      roles: strings(json['roles']),
      permissions: strings(json['permissions']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'locale': locale,
        'is_active': isActive,
        'roles': roles,
        'permissions': permissions,
      };

  static const empty = StaffUser(
    id: null,
    name: '',
    email: '',
    phone: '',
    locale: 'fr',
    isActive: true,
    roles: [],
    permissions: [],
  );
}
