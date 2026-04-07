/// Git author and committer information
library;

class GitAuthor {
  final String name;
  final String email;
  final DateTime timestamp;
  final String timezone;

  GitAuthor({
    required this.name,
    required this.email,
    DateTime? timestamp,
    String? timezone,
  })  : timestamp = timestamp ?? DateTime.now(),
        timezone = timezone ?? _getLocalTimezone();

  /// Parse author line from commit object
  /// Format: Name <email> timestamp timezone
  factory GitAuthor.parse(String line) {
    final match = RegExp(r'^(.+?) <(.+?)> (\d+) ([+-]\d{4})$').firstMatch(line);
    if (match == null) {
      throw FormatException('Invalid author format: $line');
    }

    final name = match.group(1)!;
    final email = match.group(2)!;
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch(int.parse(match.group(3)!) * 1000);
    final timezone = match.group(4)!;

    return GitAuthor(
      name: name,
      email: email,
      timestamp: timestamp,
      timezone: timezone,
    );
  }

  /// Format as author line for commit object
  String format() {
    final seconds = timestamp.millisecondsSinceEpoch ~/ 1000;
    return '$name <$email> $seconds $timezone';
  }

  /// Get local timezone offset as string (e.g., +0530, -0800)
  static String _getLocalTimezone() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final hours = offset.inHours.abs();
    final minutes = offset.inMinutes.abs() % 60;
    final sign = offset.isNegative ? '-' : '+';
    return '$sign${hours.toString().padLeft(2, '0')}${minutes.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => format();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitAuthor &&
        other.name == name &&
        other.email == email &&
        other.timestamp == timestamp &&
        other.timezone == timezone;
  }

  @override
  int get hashCode => Object.hash(name, email, timestamp, timezone);
}
