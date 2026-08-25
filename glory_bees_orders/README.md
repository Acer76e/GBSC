# Glory Bees Orders

An Android app that shows, at a glance, which website orders are waiting to be
shipped — the phone equivalent of watching Order Buzz on the shop PC.

It reads orders straight from the WooCommerce store at
`glorybeessewingcenter.com` over the WooCommerce REST API. There are no push
notifications and nothing pops up: open the app and the number of orders
waiting is the first thing on the screen.

## What it shows

**Home — "Orders to ship"**

- A big count of orders that need a parcel sent.
- One card per order: order number, customer, how long it has been waiting,
  item count, total, shipping method and the date it came in.
- The waiting time is colour-coded — green under a day, amber after a day,
  red after three.
- In-store pickups are tagged and kept out of the ship count, so the number on
  the header is only the parcels.
- A "Note" tag whenever the customer left a message at checkout.
- Pull down to refresh. It also refreshes whenever the app is opened, and
  every five minutes while it is on screen.

**Tap an order**

- Every line item with quantity, SKU and any options (cut length, colour, …).
- The shipping address, with a one-tap copy button for the label.
- Call or email the customer.
- **Mark as shipped**, which sets the order to Completed in WooCommerce
  (needs a Read/Write key — see below).
- Open the order in the store admin in a browser.

**Settings**

- Choose which statuses count as waiting (Processing and On hold by default;
  Pending payment can be added).
- Show or hide in-store pickups; oldest-first or newest-first.
- Test the connection, or disconnect the phone.

## One-time setup on the website

The app needs a WooCommerce API key. This is done once, on a computer:

1. Sign in to `glorybeessewingcenter.com/wp-admin` as an administrator.
2. Go to **WooCommerce → Settings → Advanced → REST API**.
3. Click **Add key**.
4. Description: `Phone — orders`. User: your admin account.
5. Permissions:
   - **Read** — the app can show orders but not change them.
   - **Read/Write** — also lets "Mark as shipped" work from the phone.
6. Click **Generate API key**. Copy the **consumer key** (`ck_…`) and
   **consumer secret** (`cs_…`) — WooCommerce only shows them once.
7. Open the app and paste both in. The store address is already filled in.

The app checks the key against the store before it saves anything, so a typo
is caught immediately rather than showing up later as an empty list.

If the key is ever lost or the phone is, delete that key on the same
WooCommerce screen — it stops working straight away and nothing else is
affected.

## Getting the APK onto the phone

**On the phone, open this link and tap the file:**

https://github.com/Acer76e/GBSC/releases/latest/download/glory-bees-orders.apk

That is a permanent link — it always serves the most recent build, so it is
worth bookmarking. Chrome will download the APK; open the download and tap
Install. Android asks for permission to install from the browser the first
time, which only has to be granted once.

There is also `glory-bees-orders-arm64.apk` on the
[releases page](https://github.com/Acer76e/GBSC/releases/tag/orders-latest) —
same app, smaller download, for phones from the last few years. If unsure, use
the plain one.

Every push to the app's branch rebuilds and replaces both files on that
release.

### The Actions artifact

The same APKs are also attached to each workflow run under **Actions → Build
Orders APK → glory-bees-orders-apk**. That copy needs a signed-in browser and
comes down as a zip, so it is really only useful on a computer — on a phone,
use the release link above.

### Installing updates over the top

By default each CI run signs with a throwaway debug key, and Android refuses
to install an update signed by a different key — you would have to uninstall
first, which also wipes the saved API key.

To fix that permanently, generate one keystore and store it as repository
secrets:

```bash
glory_bees_orders/tools/generate-keystore.sh
```

It prints the four values to add under **Settings → Secrets and variables →
Actions**: `KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`.
Every build after that is signed with the same key and installs straight over
the previous version. Keep the generated `.keystore` file somewhere safe —
losing it means going back to uninstall-and-reinstall.

## Where the credentials live

- The consumer key and secret are stored in Android's encrypted storage
  (`flutter_secure_storage`, backed by the Android Keystore) — not in a plain
  file, and not in this repository.
- They are sent only to `glorybeessewingcenter.com`, as an HTTPS Basic auth
  header. If the web host strips that header, the app retries once with the
  credentials as query parameters, which is WooCommerce's documented fallback.
- Nothing is sent anywhere else. There is no analytics and no server in
  between: the phone talks to the store directly.

## Building locally

Needs Flutter 3.24 and the Android SDK.

```bash
cd glory_bees_orders
flutter create --project-name glory_bees_orders --org com.acer76e --platforms=android --no-pub .
flutter pub get
flutter test
flutter run                  # on a connected phone
flutter build apk --release
```

`android/` is generated rather than committed — CI runs the same
`flutter create` and then patches the manifest (internet permission, app name,
the intent queries that the call/email/browser buttons need) and drops in the
launcher icon from `android_res/`.

## Layout

```
glory_bees_orders/
├── lib/
│   ├── main.dart                    # entry point, providers, first-run routing
│   ├── theme.dart                   # palette, Pill widget
│   ├── format.dart                  # date/age formatting
│   ├── models/wc_order.dart         # WooCommerce order parsing
│   ├── services/
│   │   ├── settings_service.dart    # store URL + key in encrypted storage
│   │   ├── woo_api.dart             # REST client, auth fallback, error text
│   │   └── orders_controller.dart   # the order list the screens read
│   ├── screens/                     # setup, orders, order detail, settings
│   └── widgets/order_card.dart
├── test/                            # parsing, API behaviour, screen tests
├── android_res/                     # adaptive launcher icon
└── tools/generate-keystore.sh
```

## Known limits

- Read-only unless the API key has Read/Write; "Mark as shipped" then reports
  that plainly instead of failing silently.
- Shows the 50 most recent matching orders. A shop with more than 50 unshipped
  orders at once would need paging added.
- No background alerts. The app tells you what is waiting when you open it; it
  will not buzz when an order arrives.
