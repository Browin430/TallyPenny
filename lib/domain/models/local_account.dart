class LocalAccount {
  const LocalAccount({
    required this.id,
    required this.username,
    required this.passwordSalt,
    required this.passwordHash,
    required this.databaseName,
    required this.settingsPrefix,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String passwordSalt;
  final String passwordHash;
  final String databaseName;
  final String settingsPrefix;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'passwordSalt': passwordSalt,
        'passwordHash': passwordHash,
        'databaseName': databaseName,
        'settingsPrefix': settingsPrefix,
        'createdAt': createdAt.toIso8601String(),
      };

  static LocalAccount fromJson(Map<String, dynamic> json) => LocalAccount(
        id: json['id'] as String,
        username: json['username'] as String,
        passwordSalt: json['passwordSalt'] as String,
        passwordHash: json['passwordHash'] as String,
        databaseName: json['databaseName'] as String,
        settingsPrefix: (json['settingsPrefix'] as String?) ?? '',
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      );
}
