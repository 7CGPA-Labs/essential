# Kingdom AI Server ProGuard Rules
-keep class dev.seven_cgpalabs.codingsaathi.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
# Keep JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}
-dontwarn kotlin.Unit
