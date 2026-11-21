"""Configuração do servidor.

Todos os caminhos do config.yaml são relativos à pasta de dados; o __main__ faz chdir para
ela antes de carregar, então aqui basta abrir "config.yaml".
"""
import copy
import secrets
import threading
from pathlib import Path

import yaml

_lock = threading.Lock()

DEFAULTS = {
    "cameras": [],
    "detection": {
        "model": "yolov8n.pt",
        "confidence": 0.4,
        "fps": 3,
        "identify_threshold": 0.70,
        "device": "auto",            # auto | cpu | cuda
    },
    # Visitas: tempo mínimo que o MESMO gato precisa ficar na zona para contar, e quanto tempo
    # sem vê-lo encerra a visita. Por tipo: usar a caixa demora mais (e o gato some agachado).
    "visits": {"min_litter": 15, "min_food": 8, "min_water": 5,
               "gap_litter": 30, "gap_food": 15, "gap_water": 10},
    "alerts": {
        "enabled": True,
        "camera_offline_minutes": 3,  # avisa quando uma câmera fica fora do ar esse tempo
        "water_by_hour": 18,          # a partir dessa hora, avisa quem ainda não bebeu água hoje
        "food_by_hour": 18,
        "litter_max_hours": 24,       # avisa quem não vai à caixa há tanto tempo
        "litter_spike_factor": 2.0,   # avisa quando as idas à caixa hoje passam N× a média da semana
    },
    "db": "data/catwatch.db",
    "gallery": "data/cats",
    "server": {"host": "0.0.0.0", "port": 8000},
}

# Faixas aceitas pela API de configurações: (mínimo, máximo).
LIMITS = {
    ("detection", "fps"): (1, 15),
    ("detection", "confidence"): (0.1, 0.95),
    ("detection", "identify_threshold"): (0.3, 0.99),
    **{("visits", f"min_{k}"): (1, 600) for k in ("litter", "food", "water")},
    **{("visits", f"gap_{k}"): (2, 600) for k in ("litter", "food", "water")},
    ("alerts", "camera_offline_minutes"): (1, 240),
    ("alerts", "water_by_hour"): (0, 23),
    ("alerts", "food_by_hour"): (0, 23),
    ("alerts", "litter_max_hours"): (4, 96),
    ("alerts", "litter_spike_factor"): (1.2, 10),
    ("server", "port"): (1024, 65535),
}
CHOICES = {("detection", "device"): ("auto", "cpu", "cuda")}
# Mudanças nesses campos só valem depois de reiniciar o servidor.
NEEDS_RESTART = {("server", "port"), ("detection", "device"), ("detection", "model")}


def _merge(base: dict, extra: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in (extra or {}).items():
        out[k] = _merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def token_path(cfg: dict) -> Path:
    return Path(cfg["db"]).parent / "token.txt"


def load(path: str = "config.yaml") -> dict:
    p = Path(path)
    user = yaml.safe_load(p.read_text(encoding="utf-8")) if p.exists() else {}
    cfg = _merge(DEFAULTS, user or {})
    cfg["_path"] = path
    # Regra antiga (um tempo só para tudo, 3 s) contava passadas rápidas; troca pelos valores por tipo.
    legacy = [k for k in ("min_seconds", "gap_seconds") if k in cfg["visits"]]
    for k in legacy:
        cfg["visits"].pop(k)
    if legacy and p.exists():
        save(cfg)
    if not p.exists():
        save(cfg)  # primeira execução numa pasta nova: deixa um config.yaml completo para editar
    # Token gerado na primeira execução e guardado fora do YAML (que pode ir pro git).
    tok = token_path(cfg)
    tok.parent.mkdir(parents=True, exist_ok=True)
    if not tok.exists():
        tok.write_text(secrets.token_urlsafe(16), encoding="utf-8")
    cfg["server"]["token"] = cfg["server"].get("token") or tok.read_text(encoding="utf-8").strip()
    return cfg


def visit_rules(cfg: dict) -> tuple[dict, dict]:
    """(tempo mínimo, tolerância sem ver o gato) por tipo de zona, para o VisitTracker."""
    v = cfg["visits"]
    kinds = ("litter", "food", "water")
    return {k: v[f"min_{k}"] for k in kinds}, {k: v[f"gap_{k}"] for k in kinds}


def regenerate_token(cfg: dict) -> str:
    """Cria um token novo; quem usava o antigo (celulares, outros PCs) perde o acesso."""
    new = secrets.token_urlsafe(16)
    tmp = token_path(cfg).with_suffix(".tmp")
    tmp.write_text(new, encoding="utf-8")
    tmp.replace(token_path(cfg))
    cfg["server"]["token"] = new
    return new


def settings(cfg: dict) -> dict:
    """As configurações editáveis pelos apps (sem câmeras, caminhos ou token)."""
    return {
        "detection": {k: cfg["detection"][k] for k in ("fps", "confidence", "identify_threshold", "device")},
        "visits": dict(cfg["visits"]),
        "alerts": dict(cfg["alerts"]),
        "server": {"port": cfg["server"]["port"]},
    }


def apply_settings(cfg: dict, changes: dict) -> tuple[list[str], bool]:
    """Valida e aplica mudanças parciais. Devolve (erros, precisa_reiniciar)."""
    errors, restart, staged = [], False, []
    for section, values in (changes or {}).items():
        if not isinstance(values, dict):
            errors.append(f"{section}: formato inválido")
            continue
        for key, value in values.items():
            k = (section, key)
            if k in CHOICES:
                if value not in CHOICES[k]:
                    errors.append(f"{section}.{key}: use {', '.join(CHOICES[k])}")
                    continue
            elif k == ("alerts", "enabled"):
                value = bool(value)
            elif k in LIMITS:
                lo, hi = LIMITS[k]
                try:
                    value = float(value)
                except (TypeError, ValueError):
                    errors.append(f"{section}.{key}: precisa ser um número")
                    continue
                if not lo <= value <= hi:
                    errors.append(f"{section}.{key}: entre {lo} e {hi}")
                    continue
                if isinstance(DEFAULTS[section][key], int):
                    value = int(round(value))
            else:
                errors.append(f"{section}.{key}: não pode ser alterado")
                continue
            staged.append((k, value))
    if errors:
        return errors, False
    for (section, key), value in staged:
        if cfg[section].get(key) != value and (section, key) in NEEDS_RESTART:
            restart = True
        cfg[section][key] = value
    save(cfg)
    return [], restart


def save(cfg: dict) -> None:
    """Grava o config.yaml de forma atômica (arquivo temporário + rename)."""
    out = {k: v for k, v in cfg.items() if not k.startswith("_")}
    out["server"] = {k: v for k, v in out["server"].items() if k != "token"}
    with _lock:
        tmp = Path(cfg["_path"] + ".tmp")
        tmp.write_text(yaml.safe_dump(out, allow_unicode=True, sort_keys=False), encoding="utf-8")
        tmp.replace(cfg["_path"])
