"""Baixa os modelos para server/models/, de onde o PyInstaller os embute no executável."""
import os
from pathlib import Path

models = Path(__file__).resolve().parents[2] / "models"
(models / "torch").mkdir(parents=True, exist_ok=True)
os.environ["TORCH_HOME"] = str(models / "torch")
os.chdir(models)

import torchvision  # noqa: E402
from ultralytics import YOLO  # noqa: E402

YOLO("yolov8n.pt")                                          # detecção (baixa para a pasta atual)
torchvision.models.resnet50(weights="DEFAULT")              # identificação (vai para TORCH_HOME)
print("modelos em", models, [p.name for p in models.rglob("*") if p.is_file()])
