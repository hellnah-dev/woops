class PrivacySettings {
  const PrivacySettings({
    this.discoverable = true,
    this.showDistance = true,
    this.readReceipts = true,
    this.showZodiac = true,
  });

  final bool discoverable;
  final bool showDistance;
  final bool readReceipts;
  final bool showZodiac;

  factory PrivacySettings.fromJson(Map<String, dynamic> json) => PrivacySettings(
    discoverable: json['discoverable'] as bool? ?? true,
    showDistance: json['show_distance'] as bool? ?? true,
    readReceipts: json['read_receipts'] as bool? ?? true,
    showZodiac: json['show_zodiac'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'discoverable': discoverable,
    'show_distance': showDistance,
    'read_receipts': readReceipts,
    'show_zodiac': showZodiac,
  };

  PrivacySettings copyWith({bool? discoverable, bool? showDistance, bool? readReceipts, bool? showZodiac}) =>
      PrivacySettings(
        discoverable: discoverable ?? this.discoverable,
        showDistance: showDistance ?? this.showDistance,
        readReceipts: readReceipts ?? this.readReceipts,
        showZodiac: showZodiac ?? this.showZodiac,
      );
}

class NotificationPreferences {
  const NotificationPreferences({this.newMatches = true, this.newMessages = true, this.newLikes = true});

  final bool newMatches;
  final bool newMessages;
  final bool newLikes;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) => NotificationPreferences(
    newMatches: json['new_matches'] as bool? ?? true,
    newMessages: json['new_messages'] as bool? ?? true,
    newLikes: json['new_likes'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {'new_matches': newMatches, 'new_messages': newMessages, 'new_likes': newLikes};

  NotificationPreferences copyWith({bool? newMatches, bool? newMessages, bool? newLikes}) => NotificationPreferences(
    newMatches: newMatches ?? this.newMatches,
    newMessages: newMessages ?? this.newMessages,
    newLikes: newLikes ?? this.newLikes,
  );
}

class BlockedUser {
  const BlockedUser({required this.id, required this.displayName, required this.blockedAt});

  final String id;
  final String displayName;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    id: json['id'] as String,
    displayName: json['display_name'] as String,
    blockedAt: DateTime.parse(json['blocked_at'] as String),
  );
}
