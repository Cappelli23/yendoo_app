// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC0lzC8rYyiFACEyRxVOwARBnqQZNo9YM8',
    appId: '1:427307624167:android:6049b34fa57925aecc6442',
    messagingSenderId: '427307624167',
    projectId: 'yendoo-app',
    storageBucket: 'yendoo-app.firebasestorage.app',
  );

  // ANDROID (tu app)

  // WEB (la misma key)
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD2cPjNGLH4DimHAlt8bKRfPXSoSoJSnbc',
    appId: '1:427307624167:web:0000000000000000000000',
    messagingSenderId: '427307624167',
    projectId: 'yendoo-app',
    storageBucket: 'yendoo-app.firebasestorage.app',
  );

  // iOS (lo dejamos apuntando al mismo proyecto)
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD2cPjNGLH4DimHAlt8bKRfPXSoSoJSnbc',
    appId: '1:427307624167:ios:cea33b23e750ce0dcc6442',
    messagingSenderId: '427307624167',
    projectId: 'yendoo-app',
    storageBucket: 'yendoo-app.firebasestorage.app',
  );

  static const FirebaseOptions macos = ios;

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyD2cPjNGLH4DimHAlt8bKRfPXSoSoJSnbc',
    appId: '1:427307624167:windows:000000000000000000',
    messagingSenderId: '427307624167',
    projectId: 'yendoo-app',
    storageBucket: 'yendoo-app.firebasestorage.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyD2cPjNGLH4DimHAlt8bKRfPXSoSoJSnbc',
    appId: '1:427307624167:linux:00000000000000000000',
    messagingSenderId: '427307624167',
    projectId: 'yendoo-app',
    storageBucket: 'yendoo-app.firebasestorage.app',
  );
}
