"""Complète le projet Android généré par `flutter create` : autorisations, nom de l'application, version minimale d'Android,
et signature fixe quand CAISSE_KEYSTORE_FILE est défini (sinon la clé de test de Flutter reste utilisée)."""
import os
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

signing = bool(os.environ.get("CAISSE_KEYSTORE_FILE"))
groovy_signing = """    signingConfigs {
        release {
            storeFile file(System.getenv("CAISSE_KEYSTORE_FILE"))
            storePassword System.getenv("CAISSE_KEYSTORE_PASSWORD")
            keyAlias "caisse"
            keyPassword System.getenv("CAISSE_KEYSTORE_PASSWORD")
        }
    }

"""
kts_signing = """    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("CAISSE_KEYSTORE_FILE"))
            storePassword = System.getenv("CAISSE_KEYSTORE_PASSWORD")
            keyAlias = "caisse"
            keyPassword = System.getenv("CAISSE_KEYSTORE_PASSWORD")
        }
    }

"""

for name in ("build.gradle", "build.gradle.kts"):
    gradle = root / "android" / "app" / name
    if not gradle.exists():
        continue
    g = gradle.read_text(encoding="utf-8")
    g = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23", g)
    if signing and "CAISSE_KEYSTORE_FILE" not in g:
        kts = name.endswith(".kts")
        g = re.sub(r"(\n\s*buildTypes\s*\{)", "\n" + (kts_signing if kts else groovy_signing).rstrip("\n") + r"\1", g, count=1)
        if kts:
            g = g.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
        else:
            g = re.sub(r"signingConfig\s*=?\s*signingConfigs\.debug", "signingConfig = signingConfigs.release", g)
        if "signingConfigs.release" not in g and 'getByName("release")' not in g:
            raise SystemExit("Signature : bloc release introuvable dans " + name)
    gradle.write_text(g, encoding="utf-8")

print("Projet Android complété" + (" (signature fixe)." if signing else " (clé de test)."))
