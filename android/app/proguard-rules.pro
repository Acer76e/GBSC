# Keep ML Kit text recognition internals
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class com.gbsc.cherry.data.** {
    kotlinx.serialization.KSerializer serializer(...);
}
