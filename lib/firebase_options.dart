// firebase_options.dart
//
// Hand-authored from google-services.json (project jsc-notifications) so
// Firebase.initializeApp doesn't depend on the Google Services Gradle plugin
// generating values.xml at build time. The plugin appears to be unreliable
// against Flutter 3.24's generated android/ scaffold + firebase_core 3.x —
// passing FirebaseOptions explicitly works regardless.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web target not configured.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions is only configured for Android. '
          'For ${defaultTargetPlatform.name}, run `flutterfire configure`.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDQjPzsZkwYu5VfCFzQ_TjR-trDTMdHn5o',
    appId: '1:918197400502:android:6339d17cbebc50896f4717',
    messagingSenderId: '918197400502',
    projectId: 'jsc-notifications',
    storageBucket: 'jsc-notifications.firebasestorage.app',
  );
}
