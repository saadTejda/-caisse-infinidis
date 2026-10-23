"""Complète le projet Android généré par `flutter create` : autorisations, nom de l'application, version minimale d'Android."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"

permissions = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
    '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>',
    '<uses-feature android:name="android.hardware.camera" android:required="false"/>',
    '<uses-feature android:name="android.hardware.bluetooth" android:required="false"/>',
]

text = manifest.read_text(encoding="utf-8")
missing = [p for p in permissions if p.split('android:name="')[1].split('"')[0] not in text]
if missing:
    text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n    " + "\n    ".join(missing), text, count=1)
text = re.sub(r'android:label="[^"]*"', 'android:label="Caisse INFINIDIS"', text, count=1)
if "usesCleartextTraffic" not in text:
    text = text.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
manifest.write_text(text, encoding="utf-8")

for name in ("build.gradle", "build.gradle.kts"):
    gradle = root / "android" / "app" / name
    if gradle.exists():
        g = gradle.read_text(encoding="utf-8")
        g = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23", g)
        gradle.write_text(g, encoding="utf-8")

print("Projet Android complété.")
