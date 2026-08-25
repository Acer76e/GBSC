/// Small date helpers. Hand-rolled rather than pulling in `intl` — the app
/// only ever formats US-style dates for one shop.
library;

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _clock(DateTime dt) {
  final hour24 = dt.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
}

/// "Today, 2:14 PM" / "Yesterday, 4:02 PM" / "Aug 18, 4:02 PM".
String formatWhen(DateTime? dt) {
  if (dt == null) return 'Unknown date';
  final now = DateTime.now();
  final justDate = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final dayGap = today.difference(justDate).inDays;
  if (dayGap == 0) return 'Today, ${_clock(dt)}';
  if (dayGap == 1) return 'Yesterday, ${_clock(dt)}';
  final year = dt.year == now.year ? '' : ', ${dt.year}';
  return '${_months[dt.month - 1]} ${dt.day}$year, ${_clock(dt)}';
}

/// Compact waiting time for the age chip: "20m", "5h", "3 days".
String formatAge(Duration age) {
  if (age.inMinutes < 60) return '${age.inMinutes < 1 ? 1 : age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  final days = age.inHours ~/ 24;
  return '$days ${days == 1 ? 'day' : 'days'}';
}

/// "just now" / "4 min ago" — used under the header for the last refresh.
String formatSince(DateTime? dt) {
  if (dt == null) return 'never';
  final gap = DateTime.now().difference(dt);
  if (gap.inSeconds < 45) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  return formatWhen(dt);
}
