"""Réécrit le manifeste d’une APK compilée pour Android 16.

Le programme d’installation d’Android 11 s’arrête quand compileSdk vaut 36.
La caisse déjà installée sur la tablette annonce Android 14 : on aligne
ces champs, sans recompiler.
"""
import struct
import sys
import zipfile

STRING_POOL = 0x0001
START_ELEMENT = 0x0102
INT_DEC = 0x10


def _read_string(data, pos, utf8):
    if utf8:
        char_len = data[pos]
        pos += 1
        if char_len & 0x80:
            char_len = ((char_len & 0x7F) << 8) | data[pos]
            pos += 1
        byte_len = data[pos]
        pos += 1
        if byte_len & 0x80:
            byte_len = ((byte_len & 0x7F) << 8) | data[pos]
            pos += 1
        return data[pos : pos + byte_len].decode("utf-8"), pos, byte_len
    char_len = struct.unpack_from("<H", data, pos)[0]
    pos += 2
    if char_len & 0x8000:
        char_len = ((char_len & 0x7FFF) << 16) | struct.unpack_from("<H", data, pos)[0]
        pos += 2
    byte_len = char_len * 2
    text = data[pos : pos + byte_len].decode("utf-16-le")
    return text, pos, byte_len


def _pool(data, start):
    chunk_type, header_size, size, count, _styles, flags, strings_start, _styles_start = struct.unpack_from(
        "<HHIIIIII", data, start
    )
    if chunk_type != STRING_POOL:
        raise SystemExit("pool de chaînes introuvable")
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from("<" + "I" * count, data, start + header_size)
    base = start + strings_start
    strings = []
    spans = []
    for rel in offsets:
        text, start_at, byte_len = _read_string(data, base + rel, utf8)
        strings.append(text)
        spans.append((start_at, byte_len))
    return strings, spans, start + size


def patch(manifest):
    data = bytearray(manifest)
    strings, spans, offset = _pool(data, 8)
    changed = []
    while offset + 8 <= len(data):
        chunk_type, header_size, size = struct.unpack_from("<HHI", data, offset)
        if size < 8 or offset + size > len(data):
            break
        if chunk_type == START_ELEMENT:
            name = strings[struct.unpack_from("<I", data, offset + 20)[0]]
            attr_start = struct.unpack_from("<H", data, offset + 24)[0]
            attr_size = struct.unpack_from("<H", data, offset + 26)[0]
            attr_count = struct.unpack_from("<H", data, offset + 28)[0]
            for index in range(attr_count):
                at = offset + header_size + attr_start + index * attr_size
                attr_name = strings[struct.unpack_from("<I", data, at + 4)[0]]
                raw_value = struct.unpack_from("<I", data, at + 8)[0]
                value_type = data[at + 15]
                value = struct.unpack_from("<I", data, at + 16)[0]
                if attr_name in ("compileSdkVersion", "platformBuildVersionCode") and value_type == INT_DEC and value == 36:
                    struct.pack_into("<I", data, at + 16, 34)
                    changed.append(attr_name)
                elif attr_name == "platformBuildVersionName" and value_type == INT_DEC and value == 16:
                    struct.pack_into("<I", data, at + 16, 14)
                    changed.append(attr_name)
                elif attr_name == "compileSdkVersionCodename" and raw_value < len(strings) and strings[raw_value] == "16":
                    start, byte_len = spans[raw_value]
                    if byte_len == 2 and data[start : start + 2] == b"16":
                        data[start : start + 2] = b"14"
                    elif byte_len == 4 and data[start : start + 4] == b"1\x006\x00":
                        data[start : start + 4] = b"1\x004\x00"
                        changed.append(attr_name)
            if name == "manifest" and "compileSdkVersion" not in changed:
                raise SystemExit("compileSdkVersion 36 introuvable")
        offset += size
    if "compileSdkVersion" not in changed:
        raise SystemExit("manifeste non modifié")
    return bytes(data), changed


def rewrite(path):
    with zipfile.ZipFile(path, "r") as source:
        manifest = source.read("AndroidManifest.xml")
        patched, changed = patch(manifest)
        items = [(item, source.read(item.filename)) for item in source.infolist()]
    tmp = path + ".patched"
    with zipfile.ZipFile(tmp, "w") as output:
        for item, payload in items:
            info = zipfile.ZipInfo(filename=item.filename, date_time=item.date_time)
            info.compress_type = item.compress_type
            info.external_attr = item.external_attr
            info.create_system = item.create_system
            if item.filename == "AndroidManifest.xml":
                payload = patched
            output.writestr(info, payload)
    import os
    os.replace(tmp, path)
    print(path, ",".join(changed))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: android11_manifest.py fichier.apk ...")
    for apk in sys.argv[1:]:
        rewrite(apk)
