"""Detecção de gatos (YOLO) e identificação (embedding + vizinho mais próximo)."""
from pathlib import Path

import cv2
import numpy as np
import torch
import torchvision
from ultralytics import YOLO

CAT_CLASS = 15  # COCO
# O YOLO reduz a imagem para este lado antes de procurar (padrão dele: 640). Numa câmera de
# 1280x720 vista de cima, o gato de ~120 px virava ~60 px e quase nunca era achado (18% dos
# quadros de dia, 1% à noite, medido com fotos dos gatos); na resolução da câmera, até 1280,
# sobe para 82% e 41%, com uns 3x o tempo da detecção.
MAX_INPUT = 1280


def input_size(h: int, w: int) -> int:
    """Lado da imagem para o YOLO: o da câmera (múltiplo de 32), entre 640 e MAX_INPUT."""
    return int(min(MAX_INPUT, max(640, -(-max(h, w) // 32) * 32)))


def resolve_device(choice: str) -> str:
    """'auto' usa a placa de vídeo NVIDIA quando existe; 'cuda' sem placa cai para CPU em vez de travar."""
    if choice in ("auto", "cuda") and torch.cuda.is_available():
        return "cuda"
    return "cpu"


def gpu_name() -> str | None:
    return torch.cuda.get_device_name(0) if torch.cuda.is_available() else None


def gpu_memory_mb() -> float | None:
    return torch.cuda.memory_allocated(0) / 2**20 if torch.cuda.is_available() else None


class CatDetector:
    def __init__(self, model: str, conf: float, device: str = "cpu"):
        self.model, self.conf, self.device = YOLO(model), conf, device

    def __call__(self, frame):
        """Devolve lista de (x1, y1, x2, y2, confiança), caixa em pixels."""
        r = self.model(frame, classes=[CAT_CLASS], conf=self.conf, device=self.device,
                       imgsz=input_size(*frame.shape[:2]), verbose=False)[0]
        return [(*map(int, b), float(c)) for b, c in zip(r.boxes.xyxy.tolist(), r.boxes.conf.tolist())]


UNKNOWN = "desconhecido"
INPUT = 224          # lado da imagem que a ResNet recebe
MIN_CROP = 48        # gato menor que isso (em pixels) está longe demais para dizer quem é
MARGIN = 0.03        # o melhor gato precisa ganhar do segundo por pelo menos isto
MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)


def cat_scores(names: list[str], sims) -> dict[str, float]:
    """Nota de cada gato: a da foto dele mais parecida (não depende de quantas fotos ele tem;
    a média das 3 melhores favorecia quem tinha só 1)."""
    per_cat: dict[str, float] = {}
    for n, s in zip(names, sims):
        per_cat[n] = max(per_cat.get(n, -1.0), float(s))
    return per_cat


def decide(per_cat: dict[str, float], threshold: float, margin: float = MARGIN) -> tuple[str, float]:
    """Nome do gato num quadro só: a nota precisa passar do limite E ganhar do segundo gato por
    uma margem; empate técnico é "desconhecido". Devolve (nome, nota do mais parecido)."""
    if not per_cat:
        return UNKNOWN, 0.0
    ranked = sorted(per_cat.items(), key=lambda kv: kv[1], reverse=True)
    best, top = ranked[0]
    second = ranked[1][1] if len(ranked) > 1 else -1.0
    if top < threshold or top - second < margin:
        return UNKNOWN, top
    return best, top


def pick(names: list[str], sims: np.ndarray, threshold: float, margin: float = MARGIN) -> tuple[str, float]:
    """Decide o gato a partir das similaridades com cada foto da galeria."""
    return decide(cat_scores(names, sims), threshold, margin)


class CatIdentifier:
    def __init__(self, gallery_dir: str, threshold: float, device: str = "cpu"):
        w = torchvision.models.ResNet50_Weights.DEFAULT
        self.device = device
        self.net = torchvision.models.resnet50(weights=w)
        self.net.fc = torch.nn.Identity()
        self.net.eval().to(device)
        self.threshold = threshold
        # (nomes, vetores, arquivos) trocados juntos numa atribuição só: quem lê em outra
        # thread nunca vê nomes de uma galeria com vetores de outra.
        self.gallery: tuple[list[str], np.ndarray, list[str]] = ([], np.zeros((0, 2048), np.float32), [])
        self.load(gallery_dir)

    @property
    def names(self) -> list[str]:
        return self.gallery[0]

    @staticmethod
    def prepare(bgr) -> np.ndarray:
        """Gato inteiro num quadrado: completa as bordas em vez de cortar o centro
        (um gato deitado perdia a cabeça e o rabo no recorte central da ResNet)."""
        h, w = bgr.shape[:2]
        side = max(h, w)
        top, left = (side - h) // 2, (side - w) // 2
        sq = cv2.copyMakeBorder(bgr, top, side - h - top, left, side - w - left, cv2.BORDER_CONSTANT, value=(124, 116, 104))
        sq = cv2.resize(sq, (INPUT, INPUT), interpolation=cv2.INTER_AREA)
        rgb = cv2.cvtColor(sq, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        return ((rgb - MEAN) / STD).transpose(2, 0, 1)

    @torch.no_grad()
    def embed(self, bgr) -> np.ndarray:
        """Vetor do gato, média com a imagem espelhada: virado para o outro lado é o mesmo gato."""
        x = self.prepare(bgr)
        batch = torch.from_numpy(np.stack([x, x[:, :, ::-1].copy()])).to(self.device)
        v = self.net(batch).mean(0).cpu().numpy()
        return v / (np.linalg.norm(v) + 1e-9)

    def load(self, gallery_dir: str):
        names, vecs, paths = [], [], []
        for d in sorted(Path(gallery_dir).iterdir()) if Path(gallery_dir).exists() else []:
            if not d.is_dir():
                continue
            for img in sorted(d.glob("*")):
                im = cv2.imread(str(img))
                if im is not None:
                    names.append(d.name)
                    vecs.append(self.embed(im))
                    paths.append(str(img))
        self.gallery = (names, np.array(vecs, np.float32) if vecs else np.zeros((0, 2048), np.float32), paths)

    def add(self, name: str, bgr, path: str = "") -> None:
        """Inclui uma foto nova sem reanalisar a galeria inteira."""
        names, vecs, paths = self.gallery
        self.gallery = (names + [name], np.vstack([vecs, self.embed(bgr)[None, :]]), paths + [str(path)])

    def _keep(self, keep: list[int]) -> None:
        names, vecs, paths = self.gallery
        self.gallery = ([names[i] for i in keep], vecs[keep] if keep else np.zeros((0, 2048), np.float32),
                        [paths[i] for i in keep])

    def remove(self, name: str) -> None:
        """Tira um gato da galeria sem reanalisar as fotos dos outros."""
        self._keep([i for i, n in enumerate(self.gallery[0]) if n != name])

    def remove_paths(self, gone) -> None:
        """Tira fotos específicas (pelo arquivo) da galeria."""
        gone = {str(p) for p in gone}
        self._keep([i for i, p in enumerate(self.gallery[2]) if p not in gone])

    def scores(self, crop) -> dict[str, float]:
        """Nota de cada gato para este recorte; vazio se não dá para dizer (galeria vazia, ou
        gato pequeno demais na imagem: sem detalhe, o palpite seria quase aleatório)."""
        names, vecs, _ = self.gallery
        if not names or min(crop.shape[:2]) < MIN_CROP:
            return {}
        return cat_scores(names, vecs @ self.embed(crop))

    def __call__(self, crop) -> tuple[str, float]:
        """Devolve (nome, similaridade do gato mais parecido)."""
        return decide(self.scores(crop), self.threshold)
