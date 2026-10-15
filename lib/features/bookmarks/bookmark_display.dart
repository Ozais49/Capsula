import 'package:flutter/material.dart';

import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';

IconData sourceIcon(BookmarkSource source) => switch (source) {
  BookmarkSource.reddit => Icons.forum_outlined,
  BookmarkSource.youtube => Icons.smart_display_outlined,
  BookmarkSource.instagram => Icons.photo_camera_outlined,
  BookmarkSource.facebook => Icons.facebook,
  BookmarkSource.x => Icons.tag,
  BookmarkSource.tiktok => Icons.music_note_outlined,
  BookmarkSource.telegram => Icons.send_outlined,
  BookmarkSource.github => Icons.code,
  BookmarkSource.amazon => Icons.shopping_bag_outlined,
  BookmarkSource.website => Icons.public,
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Today", "Yesterday", "Mar 5", or "Mar 5, 2024" for other years.
String formatSavedDate(DateTime date, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(date.toLocal());
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final monthDay = '${_months[day.month - 1]} ${day.day}';
  return day.year == today.year ? monthDay : '$monthDay, ${day.year}';
}
