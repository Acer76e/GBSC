import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glory_bees_orders/main.dart';
import 'package:glory_bees_orders/services/orders_controller.dart';
import 'package:glory_bees_orders/services/settings_service.dart';
import 'package:glory_bees_orders/services/woo_api.dart';

// Note: this file is also here to claim the name — `flutter create` in CI
// writes its counter-app template to test/widget_test.dart when the file is
// missing, and that template does not compile against this app.

void main() {
  testWidgets('a phone with no key saved opens on the setup screen',
      (tester) async {
    // Not loaded from storage, so nothing is configured — the first-run path.
    final settings = AppSettings();
    final api = WooApi(settings);

    await tester.pumpWidget(GloryBeesOrdersApp(
      settings: settings,
      api: api,
      orders: OrdersController(settings: settings, api: api),
    ));
    await tester.pump();

    expect(find.text('Glory Bees Orders'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Consumer key'), findsOneWidget);
    // The shop's address is filled in already; only the key has to be typed.
    // (It appears twice — as the field's value and as its hint.)
    expect(find.text(kDefaultStoreUrl), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      kDefaultStoreUrl,
    );
    // Nothing should be asking for orders yet.
    expect(find.text('Orders to ship'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
