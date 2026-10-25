/// Semantic versions and the update policy.
///
/// See `contract/runtime-contract.md` section 5.
library;

/// Which updates an app is willing to take.
///
/// A major release is refused under every policy, including [range]. `LZ-62`
/// defines major as signature-breaking by construction, so its messages no
/// longer take the parameters generated accessors pass. Taking one would not be
/// a stale screen, it would be a wrong one.
sealed class LocalazeUpdatePolicy {
  const LocalazeUpdatePolicy();

  /// Never fetch. The app ships with what it was built with.
  static const LocalazeUpdatePolicy none = _None();

  /// Wording fixes only.
  static const LocalazeUpdatePolicy patchOnly = _PatchOnly();

  /// Wording fixes and added keys. The default, and exactly the set that leaves
  /// every existing call site valid.
  static const LocalazeUpdatePolicy minorAndPatch = _MinorAndPatch();

  /// Same major, and within [from] and [to] inclusive.
  const factory LocalazeUpdatePolicy.range({
    required String from,
    required String to,
  }) = _Range;

  /// Whether this policy would even make a request. Only [none] would not.
  bool get fetches => true;

  String get name;

  /// Whether [candidate] may replace [current].
  ///
  /// [LocalazeVersion.accepts] has already established that the candidate is a
  /// greater version with the same major, so implementations only decide the
  /// narrower question their own name describes.
  bool permits(LocalazeVersion current, LocalazeVersion candidate);
}

class _None extends LocalazeUpdatePolicy {
  const _None();
  @override
  bool get fetches => false;
  @override
  String get name => 'none';
  @override
  bool permits(LocalazeVersion current, LocalazeVersion candidate) => false;
}

class _PatchOnly extends LocalazeUpdatePolicy {
  const _PatchOnly();
  @override
  String get name => 'patchOnly';
  @override
  bool permits(LocalazeVersion current, LocalazeVersion candidate) =>
      current.minor == candidate.minor;
}

class _MinorAndPatch extends LocalazeUpdatePolicy {
  const _MinorAndPatch();
  @override
  String get name => 'minorAndPatch';
  @override
  bool permits(LocalazeVersion current, LocalazeVersion candidate) => true;
}

class _Range extends LocalazeUpdatePolicy {
  const _Range({required this.from, required this.to});

  final String from;
  final String to;

  @override
  String get name => 'range($from..$to)';

  @override
  bool permits(LocalazeVersion current, LocalazeVersion candidate) {
    final lower = LocalazeVersion.parse(from);
    final upper = LocalazeVersion.parse(to);
    if (lower == null || upper == null) return false;
    return candidate.compareTo(lower) >= 0 && candidate.compareTo(upper) <= 0;
  }
}

/// A semantic version, compared numerically field by field.
///
/// String comparison would put `1.10.0` below `1.9.0`, which is the kind of
/// bug that only shows up once a project has shipped ten minor releases.
class LocalazeVersion implements Comparable<LocalazeVersion> {
  const LocalazeVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Returns null for anything that is not `major.minor.patch`.
  ///
  /// A malformed version is refused rather than coerced, because guessing what
  /// `latest` or `2.0` meant is how a major update gets applied by accident.
  static LocalazeVersion? parse(String? raw) {
    if (raw == null) return null;
    final fields = raw.trim().split('.');
    if (fields.length != 3) return null;

    final numbers = <int>[];
    for (final field in fields) {
      final value = int.tryParse(field);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    return LocalazeVersion(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(LocalazeVersion other) {
    if (major != other.major) return major - other.major;
    if (minor != other.minor) return minor - other.minor;
    return patch - other.patch;
  }

  /// Whether [candidate] may replace [current] under [policy].
  ///
  /// Three gates, in order of how cheaply they settle the question: the policy
  /// fetches at all, the candidate is actually newer, and the major matches.
  /// The major gate is outside the policy on purpose — no policy may override
  /// it, so putting it in each policy would invite one to forget.
  static bool accepts(
    String? current,
    String? candidate,
    LocalazeUpdatePolicy policy,
  ) {
    if (!policy.fetches) return false;

    final from = parse(current);
    final to = parse(candidate);
    if (from == null || to == null) return false;

    if (to.compareTo(from) <= 0) return false;
    if (to.major != from.major) return false;

    return policy.permits(from, to);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalazeVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
