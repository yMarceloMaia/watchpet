"""Desenho sobre a imagem da câmera: zonas, gatos e data/hora.

As zonas usam as cores dos apps (caixa areia, comida rosa, água azul), com preenchimento
translúcido e contorno com borda escura, para aparecerem em qualquer fundo. A zona onde há
um gato agora fica mais forte. Os textos passam pelo Pillow, que desenha acentos (o
OpenCV não desenha "água").
"""
from functools import lru_cache

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Cores dos apps em BGR (OpenCV) e RGB (Pillow).
KIND_RGB = {"litter": (216, 190, 138), "food": (242, 137, 155), "water": (102, 198, 242)}
KNOWN_RGB = (110, 220, 154)     # gato reconhecido
UNKNOWN_RGB = (244, 193, 82)    # gato na zona, nome incerto
PASSING_RGB = (230, 230, 240)   # gato fora das zonas (não é identificado)
INK = (23, 26, 43)              # texto sobre as etiquetas coloridas


def bgr(rgb):
    return rgb[::-1]


@lru_cache(maxsize=8)
def font(size: int):
    return ImageFont.load_default(size=size)


def draw(frame, zones, active, cats, stamp):
    """Desenha no próprio `frame` (BGR).

    zones: as zonas da câmera; active: nomes das zonas com gato agora;
    cats: [(x1, y1, x2, y2), nome ou None, similaridade, dentro_de_zona];
    stamp: texto de rodapé (câmera e hora).
    """
    h, w = frame.shape[:2]
    s = max(1.0, w / 640)                      # tudo escala com a resolução da câmera
    line = max(2, round(2 * s))
    pts_of = lambda z: np.array([[x * w, y * h] for x, y in z["polygon"]], np.int32)

    # 1. Preenchimento translúcido: fraco em zona vazia, forte em zona com gato.
    for alpha, want_active in ((0.16, False), (0.32, True)):
        layer = frame.copy()
        drew = False
        for z in zones:
            if len(z["polygon"]) >= 3 and (z["name"] in active) == want_active:
                cv2.fillPoly(layer, [pts_of(z)], bgr(KIND_RGB.get(z["kind"], PASSING_RGB)), cv2.LINE_AA)
                drew = True
        if drew:
            cv2.addWeighted(layer, alpha, frame, 1 - alpha, 0, frame)

    # 2. Contornos: borda escura por baixo e a cor por cima, mais grossa se há gato.
    for z in zones:
        if len(z["polygon"]) < 3:
            continue
        t = line + (line if z["name"] in active else 0)
        cv2.polylines(frame, [pts_of(z)], True, bgr(INK), t + max(2, round(2 * s)), cv2.LINE_AA)
        cv2.polylines(frame, [pts_of(z)], True, bgr(KIND_RGB.get(z["kind"], PASSING_RGB)), t, cv2.LINE_AA)

    # 3. Caixas dos gatos.
    for (x1, y1, x2, y2), name, sim, inside in cats:
        color = (KNOWN_RGB if name else UNKNOWN_RGB) if inside else PASSING_RGB
        cv2.rectangle(frame, (x1, y1), (x2, y2), bgr(INK), line + 2, cv2.LINE_AA)
        cv2.rectangle(frame, (x1, y1), (x2, y2), bgr(color), line, cv2.LINE_AA)

    # 4. Textos (Pillow): etiquetas das zonas, nomes dos gatos e rodapé.
    labels = []
    for z in zones:
        if len(z["polygon"]) < 3:
            continue
        p = pts_of(z)
        top = p[np.lexsort((p[:, 0], p[:, 1]))[0]]       # canto de cima (e mais à esquerda)
        labels.append((int(top[0]), int(top[1]), z["name"], KIND_RGB.get(z["kind"], PASSING_RGB), True))
    for (x1, y1, x2, y2), name, sim, inside in cats:
        if inside:
            text = f"{name} {sim:.2f}".replace(".", ",") if name else f"desconhecido {sim:.2f}".replace(".", ",")
            color = KNOWN_RGB if name else UNKNOWN_RGB
        else:
            text, color = "gato", PASSING_RGB
        labels.append((x1, y1, text, color, False))

    img = Image.fromarray(frame[:, :, ::-1])
    d = ImageDraw.Draw(img)
    f = font(round(14 * s))
    pad = round(4 * s)
    for x, y, text, color, above in labels:
        l, t, r, b = d.textbbox((0, 0), text, font=f)
        bw, bh = r - l + 2 * pad, b - t + 2 * pad
        # Etiqueta logo acima do ponto; se não couber, logo abaixo.
        ty = y - bh - line if y - bh - line >= 0 else y + line
        tx = min(max(0, x), w - bw)
        d.rounded_rectangle((tx, ty, tx + bw, ty + bh), radius=round(4 * s), fill=color)
        d.text((tx + pad - l, ty + pad - t), text, font=f, fill=INK)
    if stamp:
        l, t, r, b = d.textbbox((0, 0), stamp, font=f)
        bw, bh = r - l + 2 * pad, b - t + 2 * pad
        d.rounded_rectangle((pad, h - bh - pad, pad + bw, h - pad), radius=round(4 * s), fill=(23, 26, 43))
        d.text((2 * pad - l, h - bh - t), stamp, font=f, fill=(236, 234, 244))
    frame[:] = np.asarray(img)[:, :, ::-1]
