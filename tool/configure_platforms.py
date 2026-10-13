#!/usr/bin/env python3
"""Apply the few native settings required after `flutter create`.

Flutter platform folders are generated in CI to avoid committing tool output. This
script is intentionally idempotent and is also the one local developers run.
"""
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    raise SystemExit("Android platform is missing. Run flutter create first.")

text = manifest.read_text(encoding="utf-8")
if '<uses-permission android:name="android.permission.INTERNET"' not in text:
    text = text.replace(
        "<application",
        '    <uses-permission android:name="android.permission.INTERNET" />\n\n    <application',
        1,
    )
text = text.replace('android:label="confluence_kb"', 'android:label="Локальная база знаний"')
if "android:usesCleartextTraffic=" not in text:
    text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
manifest.write_text(text, encoding="utf-8")

# flutter_secure_storage's current Android implementation requires API 23.
# Support both current Kotlin DSL templates and older Groovy Flutter templates.
for gradle_name, old, new in (
    ("android/app/build.gradle.kts", "minSdk = flutter.minSdkVersion", "minSdk = 23"),
    ("android/app/build.gradle", "minSdkVersion flutter.minSdkVersion", "minSdkVersion 23"),
):
    gradle = Path(gradle_name)
    if gradle.exists():
        gradle.write_text(gradle.read_text(encoding="utf-8").replace(old, new), encoding="utf-8")
