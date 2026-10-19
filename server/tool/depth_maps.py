"""Карты глубины для «живого фото» блюд.

Для каждого фото в папке uploads кладёт рядом <фото>.depth.png: серая
картинка, где светлее — ближе к камере. Её читает страница
assets/live_photo/live_photo.html и сдвигает каждую точку фото на свою
глубину — так блюдо выглядит объёмным, а не «вздутым» посередине.

Нейросеть — Depth Anything V2 Small (Apache 2.0), формат ONNX. Работает
без видеокарты, 1–3 секунды на фото.

Запуск:
    python tool/depth_maps.py <model.onnx> <папка uploads> [--force]
"""
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageFilter

PHOTO_EXTS = {'.jpg', '.jpeg', '.png', '.webp'}
SIDE = 518  # модель учили на 518 px; стороны должны делиться на 14
MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def depth_for(session: ort.InferenceSession, photo: Path) -> Image.Image:
    img = Image.open(photo).convert('RGB')
    w, h = img.size
    scale = SIDE / max(w, h)
    nw = max(14, round(w * scale / 14) * 14)
    nh = max(14, round(h * scale / 14) * 14)
    x = np.asarray(img.resize((nw, nh), Image.BICUBIC), dtype=np.float32) / 255.0
    x = ((x - MEAN) / STD).transpose(2, 0, 1)[None]

    name = session.get_inputs()[0].name
    depth = session.run(None, {name: x})[0].reshape(nh, nw)

    # Модель выдаёт «обратную глубину»: больше — ближе. Приводим к 0..1,
    # отбрасывая 1% крайних значений, чтобы одна блестящая точка не сжала
    # весь остальной диапазон
    lo, hi = np.percentile(depth, [1, 99])
    depth = np.clip((depth - lo) / max(hi - lo, 1e-6), 0, 1)
    out = Image.fromarray((depth * 255).astype(np.uint8), 'L')
    # Лёгкое размытие сглаживает ступеньки на краях предметов
    return out.filter(ImageFilter.GaussianBlur(1.2))


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(64)
    model, root = Path(sys.argv[1]), Path(sys.argv[2])
    force = '--force' in sys.argv

    session = ort.InferenceSession(str(model), providers=['CPUExecutionProvider'])
    photos = [p for p in root.rglob('*') if p.suffix.lower() in PHOTO_EXTS
              and not p.name.endswith('.depth.png')]
    done = 0
    for photo in sorted(photos):
        target = photo.with_name(photo.name + '.depth.png')
        if target.exists() and not force:
            continue
        try:
            depth_for(session, photo).save(target)
            done += 1
            print(f'  {photo.name}')
        except Exception as e:  # битое фото не должно останавливать остальные
            print(f'  пропущено {photo.name}: {e}')
    print(f'Готово: {done} карт глубины')


if __name__ == '__main__':
    main()
