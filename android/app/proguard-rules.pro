# Kotlinx serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.kabanchiki.app.**$$serializer { *; }
-keepclassmembers class com.kabanchiki.app.** { *** Companion; }
-keepclasseswithmembers class com.kabanchiki.app.** { kotlinx.serialization.KSerializer serializer(...); }

# Ktor / OkHttp
-dontwarn okhttp3.**
-dontwarn org.slf4j.**
