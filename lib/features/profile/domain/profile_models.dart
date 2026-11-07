import '../../../core/astro/zodiac.dart';
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
    this.countryCode,
    this.isVerified = false,
    this.username,
    this.zodiac,
    this.isRandom = false,
    this.isRepeat = false,
  });

  final String id;
  final String displayName;
  final String? username;

  /// Null when the person hides their sign.
  final ZodiacSign? zodiac;
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
  final String? countryCode;
  final bool isVerified;

  /// Shown because too few people matched your filters (outside them).
  final bool isRandom;

  /// Someone you already liked or passed, shown again because no one new is left.
  final bool isRepeat;

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
    countryCode: json['country_code'] as String?,
    isVerified: json['is_verified'] as bool? ?? false,
    username: json['username'] as String?,
    zodiac: ZodiacSign.fromValue(json['zodiac'] as String?),
    isRandom: json['is_random'] as bool? ?? false,
    isRepeat: json['is_repeat'] as bool? ?? false,
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

/// Status of the ID-document age check.
enum AgeCheck { none, pending, approved, rejected }

/// One thing a profile still needs before its owner can start matching.
enum ProfileStep {
  photos('Add at least 2 photos', 'People want to see who they are talking to.'),
  bio('Write a short bio', 'A few lines about you start better conversations.'),
  interests('Pick 3 or more interests', 'We use them to suggest people you will click with.');

  const ProfileStep(this.title, this.why);
  final String title;
  final String why;
}

/// One line of the "complete your profile" checklist.
class CompletionItem {
  const CompletionItem(this.label, this.weight, this.progress);
  final String label;

  /// Share of the 100% (0..1).
  final double weight;

  /// How much of this item is done (0..1).
  final double progress;

  bool get done => progress >= 1;

  /// Percentage points still to gain from this item.
  int get remainingPercent => ((1 - progress) * weight * 100).round();
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
    this.countryCode,
    this.isVerified = false,
    this.username,
    this.ageCheck = AgeCheck.none,
    this.ageRejectReason,
    this.selfieStatus,
    this.selfieRejectReason,
  });

  /// Latest selfie verification: null, 'pending', 'approved' or 'rejected'.
  final String? selfieStatus;
  final String? selfieRejectReason;

  final String id;
  final String displayName;
  final String? username;
  final AgeCheck ageCheck;
  final String? ageRejectReason;
  final DateTime birthdate;
  final Gender gender;
  final String bio;
  final Intention intention;
  final String? jobTitle;
  final String? city;
  final String? countryCode;
  final bool isVerified;
  final bool onboardingCompleted;
  final List<ProfilePhotoRecord> photos;
  final Set<int> interestIds;
  final List<ProfilePrompt> prompts;

  String? get primaryPhoto => photos.isEmpty ? null : photos.first.storagePath;

  ZodiacSign get zodiac => ZodiacSign.fromBirthdate(birthdate);

  /// What is still missing before liking and passing are allowed. The same
  /// rules are enforced on the server (`private.profile_ready`).
  List<ProfileStep> get missingSteps => [
    if (photos.length < 2) ProfileStep.photos,
    if (bio.trim().isEmpty) ProfileStep.bio,
    if (interestIds.length < 3) ProfileStep.interests,
  ];

  bool get isReadyToDate => missingSteps.isEmpty;

  /// Everything that counts towards 100%, with its share of the score.
  List<CompletionItem> get completionItems => [
    CompletionItem('Add 4 photos (${photos.length}/4)', 0.4, (photos.length.clamp(0, 4)) / 4),
    CompletionItem('Write a bio', 0.2, bio.trim().isNotEmpty ? 1 : 0),
    CompletionItem('Pick 3+ interests', 0.15, interestIds.length >= 3 ? 1 : 0),
    CompletionItem('Verify with a selfie', 0.05, isVerified ? 1 : 0),
    CompletionItem('Answer a prompt', 0.1, prompts.isNotEmpty ? 1 : 0),
    CompletionItem('Add your job', 0.05, (jobTitle ?? '').isNotEmpty ? 1 : 0),
    CompletionItem('Add your city', 0.05, (city ?? '').isNotEmpty ? 1 : 0),
  ];

  /// 0..1, used to nudge people to complete their profile.
  double get completeness => completionItems.fold(0.0, (sum, i) => sum + i.weight * i.progress).clamp(0, 1).toDouble();

  int get completenessPercent => (completeness * 100).round();

  factory MyProfile.fromJson(Map<String, dynamic> json) {
    final photos =
        ((json['profile_photos'] as List?) ?? const [])
            .map((p) => ProfilePhotoRecord.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final prompts =
        ((json['profile_prompts'] as List?) ?? const [])
            .map((p) => ProfilePrompt.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final checks =
        ((json['age_verifications'] as List?) ?? const []).map((v) => Map<String, dynamic>.from(v as Map)).toList()
          ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    final latest = checks.firstOrNull;
    final ageCheck = (json['age_verified'] as bool? ?? false)
        ? AgeCheck.approved
        : switch (latest?['status']) {
            'pending' => AgeCheck.pending,
            'rejected' => AgeCheck.rejected,
            _ => AgeCheck.none,
          };
    final selfies =
        ((json['verification_requests'] as List?) ?? const []).map((v) => Map<String, dynamic>.from(v as Map)).toList()
          ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    return MyProfile(
      selfieStatus: selfies.firstOrNull?['status'] as String?,
      selfieRejectReason: selfies.firstOrNull?['reject_reason'] as String?,
      ageCheck: ageCheck,
      ageRejectReason: ageCheck == AgeCheck.rejected ? (latest?['reject_reason'] as String?) : null,
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      birthdate: DateTime.parse(json['birthdate'] as String),
      gender: Gender.fromValue(json['gender'] as String),
      bio: json['bio'] as String? ?? '',
      intention: Intention.fromValue(json['intention'] as String),
      jobTitle: json['job_title'] as String?,
      city: json['city'] as String?,
      countryCode: json['country_code'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      username: json['username'] as String?,
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
    this.countryCodes = const {},
  });

  final int minAge;
  final int maxAge;
  final int maxDistanceKm;
  final Set<Gender> genders;
  final Set<Intention> intentions;
  final Set<int> interestIds;

  /// Empty = any country.
  final Set<String> countryCodes;

  factory DiscoveryPreferences.fromJson(Map<String, dynamic> json) => DiscoveryPreferences(
    minAge: (json['min_age'] as num).toInt(),
    maxAge: (json['max_age'] as num).toInt(),
    maxDistanceKm: (json['max_distance_km'] as num).toInt(),
    genders: ((json['genders'] as List?) ?? const []).map((g) => Gender.fromValue(g as String)).toSet(),
    intentions: ((json['intentions'] as List?) ?? const []).map((i) => Intention.fromValue(i as String)).toSet(),
    interestIds: ((json['interest_ids'] as List?) ?? const []).map((i) => (i as num).toInt()).toSet(),
    countryCodes: ((json['country_codes'] as List?) ?? const []).map((c) => c as String).toSet(),
  );

  Map<String, dynamic> toJson() => {
    'min_age': minAge,
    'max_age': maxAge,
    'max_distance_km': maxDistanceKm,
    'genders': genders.map((g) => g.value).toList(),
    'intentions': intentions.map((i) => i.value).toList(),
    'interest_ids': interestIds.toList(),
    'country_codes': countryCodes.toList(),
  };

  DiscoveryPreferences copyWith({
    int? minAge,
    int? maxAge,
    int? maxDistanceKm,
    Set<Gender>? genders,
    Set<Intention>? intentions,
    Set<int>? interestIds,
    Set<String>? countryCodes,
  }) => DiscoveryPreferences(
    minAge: minAge ?? this.minAge,
    maxAge: maxAge ?? this.maxAge,
    maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
    genders: genders ?? this.genders,
    intentions: intentions ?? this.intentions,
    interestIds: interestIds ?? this.interestIds,
    countryCodes: countryCodes ?? this.countryCodes,
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
    required this.countryCode,
    required this.username,
    this.city,
  });

  final String displayName;
  final DateTime birthdate;
  final Gender gender;
  final Set<Gender> interestedIn;
  final Intention intention;
  final Set<int> interestIds;
  final String countryCode;
  final String username;
  final String? city;
}
