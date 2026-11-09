"""Dessine l'icône de l'application préparation (tool/icon.png, 1024 × 1024) sans bibliothèque externe :
fond vert (différent du bleu de la caisse), carton blanc et coche, pour ne pas confondre les deux applications."""
import pathlib
import struct
import zlib

SIZE = 1024
GREEN = (5, 150, 105)
WHITE = (255, 255, 255)
DARK = (4, 120, 87)


def inside_round_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def near_segment(x, y, ax, ay, bx, by, width):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / float(dx * dx + dy * dy)))
    px, py = ax + t * dx, ay + t * dy
    return (x - px) ** 2 + (y - py) ** 2 <= width * width


rows = bytearray()
for y in range(SIZE):
    rows.append(0)
    for x in range(SIZE):
        color = GREEN
        if inside_round_rect(x, y, 230, 330, 794, 820, 48):
            color = WHITE
            if 230 <= x <= 794 and 330 <= y <= 470:
                color = (236, 253, 245)
            if abs(x - 512) <= 34 and 330 <= y <= 470:
                color = (209, 250, 229)
        if inside_round_rect(x, y, 290, 250, 734, 360, 30):
            color = WHITE
        if near_segment(x, y, 380, 640, 470, 730, 34) or near_segment(x, y, 470, 730, 650, 540, 34):
            color = DARK
        rows.extend(color)


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
out = pathlib.Path(__file__).resolve().parent / "icon.png"
out.write_bytes(png)
print("Icône écrite :", out)
