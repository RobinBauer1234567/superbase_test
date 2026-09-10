class MatchTimeHelper {
  static final RegExp _timezoneSuffixPattern = RegExp(r'(Z|[+-]\d{2}:\d{2})$');

  /// Parses match timestamps from DB/API in a timezone-safe way.
  ///
  /// If no timezone suffix is present, the value is treated as UTC.
  static DateTime? parseToLocal(dynamic rawValue) {
    if (rawValue == null) return null;
    final value = rawValue.toString().trim();
    if (value.isEmpty) return null;

    final hasTimezoneSuffix = _timezoneSuffixPattern.hasMatch(value);
    if (hasTimezoneSuffix) {
      final parsed = DateTime.tryParse(value);
      return parsed?.toLocal();
    }

    final parsedAsUtc = DateTime.tryParse('${value}Z');
    return parsedAsUtc?.toLocal();
  }

  static DateTime? parseToUtc(dynamic rawValue) {
    return parseToLocal(rawValue)?.toUtc();
  }
}
