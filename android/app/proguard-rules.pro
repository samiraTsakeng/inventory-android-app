
# ✅ Fix for R8 build error: "Missing class com.google.mlkit.vision.text...."
# google_mlkit_text_recognition references the Chinese/Japanese/Korean/
# Devanagari script recognizers internally, even though we only use
# TextRecognitionScript.latin. Those optional modules aren't bundled since
# we don't declare them as dependencies, so R8 needs to be told it's safe
# to ignore the missing references (they're simply never called at runtime).

#-dontwarn com.google.mlkit.vision.text.chinese.**
#-dontwarn com.google.mlkit.vision.text.devanagari.**
#-dontwarn com.google.mlkit.vision.text.japanese.**
#-dontwarn com.google.mlkit.vision.text.korean.**
