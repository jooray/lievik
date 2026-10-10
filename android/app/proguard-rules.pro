# kotlinx.serialization: keep generated serializers for @Serializable classes.
-keepattributes *Annotation*, InnerClasses, Signature, Exceptions
-dontnote kotlinx.serialization.**
-keepclassmembers class today.cypherpunk.lievik.** {
    *** Companion;
}
-keepclasseswithmembers class today.cypherpunk.lievik.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class today.cypherpunk.lievik.**$$serializer { *; }
-keepclassmembers @kotlinx.serialization.Serializable class today.cypherpunk.lievik.** {
    <fields>;
}

# Retrofit: keep the service interface's generic signatures and suspend
# continuations (R8 full mode strips them otherwise).
-keep,allowobfuscation,allowshrinking interface today.cypherpunk.lievik.data.api.LievikApi
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-if interface * { @retrofit2.http.* <methods>; }
-keep,allowobfuscation interface <1>
-dontwarn retrofit2.**
-dontwarn okhttp3.internal.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
