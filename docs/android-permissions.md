# Android Permissions

Add these permissions to `android/app/src/main/AndroidManifest.xml` after generating the Android project:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

For reliable tracking while the screen is off, implement an Android foreground service with a persistent notification. Add `ACCESS_BACKGROUND_LOCATION` only if the app genuinely records location after the user leaves the recording flow, because Android and Play policy review are stricter for that permission.
