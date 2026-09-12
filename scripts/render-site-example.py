#!/usr/bin/env python3
"""Render a synthetic workflow illustration, never a recording of a user's screen.

Requires Pillow and ffmpeg. These are authoring tools, not app dependencies.
"""
import math
from pathlib import Path
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "site/assets"
WIDTH, HEIGHT, FPS, SECONDS = 1280, 720, 24, 9
INK, MUTED, PAPER, MINT = "#162e34", "#52696e", "#eef4f2", "#1a9e76"
FONT = "/System/Library/Fonts/Helvetica.ttc"


def font(size):
    return ImageFont.truetype(FONT, size)


def frame(t):
    image = Image.new("RGB", (WIDTH, HEIGHT), PAPER)
    draw = ImageDraw.Draw(image)
    draw.text((62, 36), "WORKBENCH  /  ANNOTATE", font=font(18), fill=INK)
    draw.text((62, 68), "Explain the point. Keep your flow.", font=font(36), fill=INK)
    draw.text((62, 120), "Illustrated example · synthetic content", font=font(17), fill=MUTED)

    draw.rounded_rectangle((60, 168, 1220, 584), radius=20, fill="white", outline="#d2e0db", width=2)
    draw.rounded_rectangle((60, 168, 1220, 212), radius=20, fill="#dfe9e5")
    draw.rectangle((60, 191, 1220, 212), fill="#dfe9e5")
    for x, color in [(86, "#d29992"), (110, "#d5c696"), (134, "#94bda6")]:
        draw.ellipse((x, 183, x + 12, 195), fill=color)
    draw.text((530, 179), "A made-up demo", font=font(16), fill=MUTED)
    draw.text((105, 245), "Today’s plan", font=font(30), fill=INK)
    draw.text((105, 289), "One useful conversation. A clear next step.", font=font(20), fill=MUTED)
    cards = [(105, "Listen", "Understand the situation"), (470, "Explain", "Make the idea visible"),
             (835, "Agree next step", "Leave with a useful action")]
    for x, title, subtitle in cards:
        draw.rounded_rectangle((x, 351, x + 325, 510), radius=14, fill="#f3f7f5", outline="#dce6e1")
        draw.text((x + 23, 385), title, font=font(26), fill=INK)
        draw.text((x + 23, 436), subtitle, font=font(17), fill=MUTED)

    if 1.5 < t < 6.4:
        progress = min(1, (t - 1.5) / 1.6)
        points = []
        for i in range(max(2, int(110 * progress))):
            angle = -math.pi / 2 + (i / 109) * math.tau
            points.append((997 + 184 * math.cos(angle), 431 + 109 * math.sin(angle)))
        draw.line(points, fill=MINT, width=7, joint="curve")
        if t > 3.4:
            fraction = min(1, (t - 3.4) / .75)
            end = (int(721 + 130 * fraction), int(548 - 49 * fraction))
            draw.line([(721, 548), end], fill=MINT, width=7)
            if fraction == 1:
                draw.line([(831, 497), end, (837, 515)], fill=MINT, width=7, joint="curve")
        px, py = points[-1]
        draw.polygon([(px + 6, py + 7), (px + 10, py + 34), (px + 17, py + 26), (px + 29, py + 27)], fill=INK)

    step = 0 if t < 1.5 else 1 if t < 6.4 else 2
    captions = ["Start drawing over your demo.", "Bring attention to the next step.", "Clear the ink. Keep presenting."]
    draw.text((62, 622), captions[step], font=font(27), fill=INK)
    labels = ["DRAW", "EXPLAIN", "RETURN"]
    for i, label in enumerate(labels):
        x = 830 + i * 123
        draw.rounded_rectangle((x, 626, x + 111, 663), radius=8, fill=INK if step == i else "#dce7e2")
        draw.text((x + 13, 636), label, font=font(14), fill="white" if step == i else MUTED)
    return image


def main():
    executable = shutil.which("ffmpeg")
    if not executable:
        raise SystemExit("Install ffmpeg to render the optional website illustration.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    frame(4.5).save(OUTPUT / "annotation-example.png")
    command = [executable, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
               "-s", f"{WIDTH}x{HEIGHT}", "-r", str(FPS), "-i", "-", "-an", "-c:v", "libx264",
               "-preset", "medium", "-crf", "24", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
               str(OUTPUT / "annotation-example.mp4")]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    try:
        for index in range(FPS * SECONDS):
            process.stdin.write(frame(index / FPS).tobytes())
        process.stdin.close()
        if process.wait() != 0:
            raise SystemExit("Example video encoding failed.")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()
    print("Rendered nine-second synthetic annotation example and poster.")


if __name__ == "__main__":
    main()
