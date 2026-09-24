import 'package:flutter/foundation.dart';

@immutable
class RiwayaDescriptor {
  const RiwayaDescriptor({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.sourceDatabase,
    required this.profileId,
    required this.phonemeArtifact,
    required this.dataVersion,
    this.tajweedVerified = false,
  });

  /// Stable key: 'hafs', 'warsh', 'qalun', 'qaloon', … Used in asset URLs and storage paths.
  final String id;

  final String nameAr;
  final String nameEn;

  /// Generator input, e.g. 'hafs.sqlite' or 'warsh.sqlite'.
  final String sourceDatabase;

  /// The `moshaf` profile this riwaya's artifact was generated with.
  final String profileId;

  /// Artifact file name, e.g. 'hafs_phonemes.json' or 'warsh_phonemes.json'.
  final String phonemeArtifact;

  /// Bumped whenever the artifact is regenerated. Independent of the ASR model
  /// version, which is riwaya-agnostic.
  final int dataVersion;

  /// Whether tajweed evaluation has been validated for this riwaya. False means
  /// word-level tracking only — the adapter reads this instead of branching on
  /// the id, so an unproven riwaya can ship and be promoted by flipping a field.
  final bool tajweedVerified;

  factory RiwayaDescriptor.fromJson(Map<String, dynamic> json) {
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw ArgumentError('riwaya descriptor is missing "$key": $json');
      }
      return value;
    }

    return RiwayaDescriptor(
      id: required('id'),
      nameAr: required('nameAr'),
      nameEn: required('nameEn'),
      sourceDatabase: required('sourceDatabase'),
      profileId: required('profileId'),
      phonemeArtifact: required('phonemeArtifact'),
      dataVersion: json['dataVersion'] as int? ?? 1,
      tajweedVerified: json['tajweedVerified'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'RiwayaDescriptor($id, v$dataVersion, '
      'tajweedVerified: $tajweedVerified)';
}
