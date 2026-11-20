"""Detecção de gatos (YOLO) e identificação (embedding + vizinho mais próximo)."""
from pathlib import Path

import cv2
import numpy as np
import torch
import torchvision
from ultralytics import YOLO

CAT_CLASS = 15  # COCO


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
        r = self.model(frame, classes=[CAT_CLASS], conf=self.conf, device=self.device, verbose=False)[0]
        return [(*map(int, b), float(c)) for b, c in zip(r.boxes.xyxy.tolist(), r.boxes.conf.tolist())]


class CatIdentifier:
    def __init__(self, gallery_dir: str, threshold: float, device: str = "cpu"):
        w = torchvision.models.ResNet50_Weights.DEFAULT
        self.device = device
        self.net = torchvision.models.resnet50(weights=w)
        self.net.fc = torch.nn.Identity()
        self.net.eval().to(device)
        self.tf = w.transforms()
        self.threshold = threshold
        self.names: list[str] = []
        self.vecs = np.zeros((0, 2048), dtype=np.float32)
        self.load(gallery_dir)

    @torch.no_grad()
    def embed(self, bgr) -> np.ndarray:
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        t = torch.from_numpy(rgb).permute(2, 0, 1)
        v = self.net(self.tf(t).unsqueeze(0).to(self.device))[0].cpu().numpy()
        return v / (np.linalg.norm(v) + 1e-9)

    def load(self, gallery_dir: str):
        names, vecs = [], []
        for d in sorted(Path(gallery_dir).iterdir()) if Path(gallery_dir).exists() else []:
            if not d.is_dir():
                continue
            for img in d.glob("*"):
                im = cv2.imread(str(img))
                if im is not None:
                    names.append(d.name)
                    vecs.append(self.embed(im))
        self.names = names
        self.vecs = np.array(vecs, dtype=np.float32) if vecs else np.zeros((0, 2048), np.float32)

    def add(self, name: str, bgr) -> None:
        """Inclui uma foto nova sem reanalisar a galeria inteira."""
        vecs = np.vstack([self.vecs, self.embed(bgr)[None, :]])
        # vecs primeiro: quem estiver lendo em outra thread nunca vê mais nomes do que vetores.
        self.vecs, self.names = vecs, self.names + [name]

    def __call__(self, crop) -> tuple[str, float]:
        """Devolve (nome, similaridade). A similaridade é a do gato mais parecido, mesmo se
        abaixo do limite, para dar pra ver o quão perto de acertar o sistema ficou."""
        if not len(self.names):
            return "desconhecido", 0.0
        names, vecs = self.names, self.vecs
        sims = vecs[: len(names)] @ self.embed(crop)
        # média das 3 melhores similaridades por gato, mais estável que o máximo
        best, best_s, top = "desconhecido", self.threshold, 0.0
        for n in set(names):
            s = float(np.sort(sims[[i for i, x in enumerate(names) if x == n]])[-3:].mean())
            top = max(top, s)
            if s > best_s:
                best, best_s = n, s
        return best, top
