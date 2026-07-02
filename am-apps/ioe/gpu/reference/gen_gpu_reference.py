#!/usr/bin/env python3

from pathlib import Path
import struct
import zlib

W, H = 640, 480
OUT = Path(__file__).resolve().parent


def rgb(r, g, b):
    return (r & 0xff, g & 0xff, b & 0xff)


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)


def save_png(pixels, name):
    raw = bytearray()
    for y in range(H):
        raw.append(0)
        for x in range(W):
            raw.extend(pixels[y][x])

    data = b"".join([
        b"\x89PNG\r\n\x1a\n",
        chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)),
        chunk(b"IDAT", zlib.compress(bytes(raw), 9)),
        chunk(b"IEND", b""),
    ])
    (OUT / f"{name}.png").write_bytes(data)


def new_image():
    return [[rgb(0, 0, 0) for _ in range(W)] for _ in range(H)]


def fill_rect(pixels, x0, y0, w, h, color):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            pixels[y][x] = color


def draw_background(pixels):
    fill_rect(pixels, 0, 0, W, H, rgb(20, 20, 20))


def draw_border(pixels):
    fill_rect(pixels, 0, 0, W, 8, rgb(255, 255, 255))
    fill_rect(pixels, 0, H - 8, W, 8, rgb(255, 255, 255))
    fill_rect(pixels, 0, 0, 8, H, rgb(255, 255, 255))
    fill_rect(pixels, W - 8, 0, 8, H, rgb(255, 255, 255))


def draw_gradient_band(pixels):
    for y in range(8, 48):
        for x in range(8, W - 8):
            grad = (x * 255) // (W - 1)
            pixels[y][x] = rgb(grad, 255 - grad, 80)


def draw_checkerboard(pixels):
    for y in range(56, H - 8):
        for x in range(8, W - 8):
            checker = ((x // 32) ^ (y // 32)) & 1
            pixels[y][x] = rgb(0, 160, 255) if checker else rgb(20, 20, 20)


def draw_cross(pixels):
    fill_rect(pixels, W // 2 - 3, 8, 7, H - 16, rgb(255, 0, 0))
    fill_rect(pixels, 8, H // 2 - 3, W - 16, 7, rgb(255, 0, 0))


def draw_corner_blocks(pixels):
    bw, bh = max(W // 8, 16), max(H // 8, 16)
    fill_rect(pixels, 16, 16, bw, bh, rgb(255, 0, 0))
    fill_rect(pixels, W - 16 - bw, 16, bw, bh, rgb(0, 255, 0))
    fill_rect(pixels, 16, H - 16 - bh, bw, bh, rgb(0, 0, 255))
    fill_rect(pixels, W - 16 - bw, H - 16 - bh, bw, bh, rgb(255, 255, 0))


def main():
    pixels = new_image()

    draw_background(pixels)
    save_png(pixels, "01-background")

    draw_border(pixels)
    save_png(pixels, "02-border")

    draw_gradient_band(pixels)
    save_png(pixels, "03-gradient")

    draw_checkerboard(pixels)
    save_png(pixels, "04-checker")

    draw_cross(pixels)
    save_png(pixels, "05-cross")

    draw_corner_blocks(pixels)
    save_png(pixels, "06-final")


if __name__ == "__main__":
    main()
