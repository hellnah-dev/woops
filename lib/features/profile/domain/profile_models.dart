import 'profile_enums.dart';

class ProfilePrompt {
  const ProfilePrompt({required this.prompt, required this.answer, this.id, this.position = 0});

  final String? id;
  final String prompt;
  final String answer;
  final int position;

  factory ProfilePrompt.fromJson(Map<String, dynamic> json) => ProfilePrompt(
        id: json['id'] as String?,
        prompt: json['prompt'] as String,
        answer: json['answer'] as String,
        position: (json['position'] as num?)?.toInt() ?? 0,
      );
}

class Interest {
  const Interest({required this.id, required this.name, this.emoji, this.category = 'general'});

  final int id;
  final String name;
  final String? emoji;
  final String category;

  factory Interest.fromJson(Map<String, dynamic> json) => Interest(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        emoji: json['emoji'] as String?,
        category: json['category'] as String? ?? 'general',
      );

  @override
  bool operator ==(Object other) => other is Interest && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What other people can see about a user. Never contains birthdate,
/// coordinates or account status.
class ProfileCard {
  const ProfileCard({
    required this.id,
    required this.displayName,
    required this.age,
    required this.gender,
    required this.bio,
    required this.intention,
    required this.photos,
    required this.interests,
    required this.prompts,
    this.jobTitle,
    this.city,
    this.distanceKm,
    this.likedAt,
  });

  final String id;
  final String displayName;
  final int age;
  final Gender gender;
  final String bio;
  final Intention intention;
  final String? jobTitle;
  final String? city;
  final List<String> photos;
  final List<String> interests;
  final List<ProfilePrompt> prompts;
  final int? distanceKm;
  final DateTime? likedAt;

  String? get primaryPhoto => photos.isEmpty ? null : photos.first;

  factory ProfileCard.fromJson(Map<String, dynamic> json) => ProfileCard(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        age: (json['age'] as num).toInt(),
        gender: Gender.fromValue(json['gender'] as String),
        bio: json['bio'] as String? ?? '',
        intention: Intention.fromValue(json['intention'] as String? ?? 'figuring_out'),
        jobTitle: json['job_title'] as String?,
        city: json['city'] as String?,
        photos: (json['photos'] as List?)?.cast<String>() ?? const [],
        interests: (json['interests'] as List?)?.cast<String>() ?? const [],
        prompts: ((json['prompts'] as List?) ?? const [])
            .map((p) => ProfilePrompt.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
        distanceKm: (json['distance_km'] as num?)?.toInt(),
        likedAt: json['liked_at'] == null ? null : DateTime.parse(json['liked_at'] as String),
      );
}

class ProfilePhotoRecord {
  const ProfilePhotoRecord({required this.id, required this.storagePath, required this.position});

  final String id;
  final String storagePath;
  final int position;

  factory ProfilePhotoRecord.fromJson(Map<String, dynamic> json) => ProfilePhotoRecord(
        id: json['id'] as String,
        storagePath: json['storage_path'] as String,
        position: (json['position'] as num).toInt(),
      );
}

/// The signed-in user's own, full profile.
class MyProfile {
  const MyProfile({
    required this.id,
    required this.displayName,
    required this.birthdate,
    required this.gender,
    required this.bio,
    required this.intention,
    required this.onboardingCompleted,
    required this.photos,
    required this.interestIds,
    required this.prompts,
    this.jobTitle,
    this.city,
  });

  final String id;
  final String displayName;
  final DateTime birthdate;
  final Gender gender;
  final String bio;
  final Intention intention;
  final String? jobTitle;
  final String? city;
  final bool onboardingCompleted;
  final List<ProfilePhotoRecord> photos;
  final Set<int> interestIds;
  final List<ProfilePrompt> prompts;

  String? get primaryPhoto => photos.isEmpty ? null : photos.first.storagePath;

  /// 0..1, used to nudge people to complete their profile.
  double get completeness {
    var score = 0.0;
    score += (photos.length.clamp(0, 4)) / 4 * 0.4;
    if (bio.trim().isNotEmpty) score += 0.2;
    if (interestIds.length >= 3) score += 0.15;
    if (prompts.isNotEmpty) score += 0.15;
    if ((jobTitle ?? '').isNotEmpty) score += 0.05;
    if ((city ?? '').isNotEmpty) score += 0.05;
    return score.clamp(0, 1);
  }

  factory MyProfile.fromJson(Map<String, dynamic> json) {
    final photos = ((json['profile_photos'] as List?) ?? const [])
        .map((p) => ProfilePhotoRecord.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final prompts = ((json['profile_prompts'] as List?) ?? const [])
        .map((p) => ProfilePrompt.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return MyProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      birthdate: DateTime.parse(json['birthdate'] as String),
      gender: Gender.fromValue(json['gender'] as String),
      bio: json['bio'] as String? ?? '',
      intention: Intention.fromValue(json['intention'] as String),
      jobTitle: json['job_title'] as String?,
      city: json['city'] as String?,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      photos: photos,
      interestIds: ((json['profile_interests'] as List?) ?? const [])
          .map((e) => ((e as Map)['interest_id'] as num).toInt())
          .toSet(),
      prompts: prompts,
    );
  }
}

class DiscoveryPreferences {
  const DiscoveryPreferences({
    this.minAge = 18,
    this.maxAge = 99,
    this.maxDistanceKm = 50,
    this.genders = const {Gender.woman, Gender.man, Gender.nonbinary},
    this.intentions = const {},
    this.interestIds = const {},
  });

  final int minAge;
  final int maxAge;
  final int maxDistanceKm;
  final Set<Gender> genders;
  final Set<Intention> intentions;
  final Set<int> interestIds;

  factory DiscoveryPreferences.fromJson(Map<String, dynamic> json) => DiscoveryPreferences(
        minAge: (json['min_age'] as num).toInt(),
        maxAge: (json['max_age'] as num).toInt(),
        maxDistanceKm: (json['max_distance_km'] as num).toInt(),
        genders: ((json['genders'] as List?) ?? const []).map((g) => Gender.fromValue(g as String)).toSet(),
        intentions:
            ((json['intentions'] as List?) ?? const []).map((i) => Intention.fromValue(i as String)).toSet(),
        interestIds: ((json['interest_ids'] as List?) ?? const []).map((i) => (i as num).toInt()).toSet(),
      );

  Map<String, dynamic> toJson() => {
        'min_age': minAge,
        'max_age': maxAge,
        'max_distance_km': maxDistanceKm,
        'genders': genders.map((g) => g.value).toList(),
        'intentions': intentions.map((i) => i.value).toList(),
        'interest_ids': interestIds.toList(),
      };

  DiscoveryPreferences copyWith({
    int? minAge,
    int? maxAge,
    int? maxDistanceKm,
    Set<Gender>? genders,
    Set<Intention>? intentions,
    Set<int>? interestIds,
  }) =>
      DiscoveryPreferences(
        minAge: minAge ?? this.minAge,
        maxAge: maxAge ?? this.maxAge,
        maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
        genders: genders ?? this.genders,
        intentions: intentions ?? this.intentions,
        interestIds: interestIds ?? this.interestIds,
      );
}

/// Data collected by the onboarding wizard before the profile row exists.
class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    required this.birthdate,
    required this.gender,
    required this.interestedIn,
    required this.intention,
    required this.interestIds,
  });

  final String displayName;
  final DateTime birthdate;
  final Gender gender;
  final Set<Gender> interestedIn;
  final Intention intention;
  final Set<int> interestIds;
}
