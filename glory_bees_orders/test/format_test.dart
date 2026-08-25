import 'package:flutter_test/flutter_test.dart';
import 'package:glory_bees_orders/format.dart';
import 'package:glory_bees_orders/services/settings_service.dart';

void main() {
  group('normalizeStoreUrl', () {
    test('adds https and trims trailing slashes', () {
      expect(normalizeStoreUrl('glorybeessewingcenter.com/'),
          'https://glorybeessewingcenter.com');
      expect(normalizeStoreUrl('  https://example.com///  '), 'https://example.com');
    });

    test('strips a pasted REST or admin path', () {
      expect(normalizeStoreUrl('https://example.com/wp-json/wc/v3/orders'),
          'https://example.com');
      expect(
          normalizeStoreUrl(
              'https://example.com/wp-admin/admin.php?page=wc-settings'),
          'https://example.com');
    });

    test('leaves http alone rather than silently upgrading it', () {
      expect(normalizeStoreUrl('http://example.com'), 'http://example.com');
    });

    test('returns empty for empty input', () {
      expect(normalizeStoreUrl('   '), '');
    });
  });

  group('formatAge', () {
    test('minutes, hours, then days', () {
      expect(formatAge(const Duration(seconds: 20)), '1m');
      expect(formatAge(const Duration(minutes: 41)), '41m');
      expect(formatAge(const Duration(hours: 5)), '5h');
      expect(formatAge(const Duration(hours: 24)), '1 day');
      expect(formatAge(const Duration(hours: 73)), '3 days');
    });
  });

  group('formatWhen', () {
    test('labels today and yesterday', () {
      final now = DateTime.now();
      final todayAfternoon = DateTime(now.year, now.month, now.day, 14, 5);
      expect(formatWhen(todayAfternoon), 'Today, 2:05 PM');

      final yesterday = todayAfternoon.subtract(const Duration(days: 1));
      expect(formatWhen(yesterday), startsWith('Yesterday, '));
    });

    test('renders midnight and noon as 12', () {
      final now = DateTime.now();
      expect(formatWhen(DateTime(now.year, now.month, now.day, 0, 7)),
          'Today, 12:07 AM');
      expect(formatWhen(DateTime(now.year, now.month, now.day, 12, 0)),
          'Today, 12:00 PM');
    });

    test('handles a null date', () {
      expect(formatWhen(null), 'Unknown date');
    });
  });

  group('statusLabel', () {
    test('uses friendly names and falls back gracefully', () {
      expect(statusLabel('on-hold'), 'On hold');
      expect(statusLabel('processing'), 'Processing');
      expect(statusLabel('checkout-draft'), 'Checkout draft');
      expect(statusLabel(''), 'Unknown');
    });
  });
}
