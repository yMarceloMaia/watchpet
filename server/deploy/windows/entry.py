"""Ponto de entrada do executável (PyInstaller): o mesmo que `python -m catwatch`."""
import multiprocessing

if __name__ == "__main__":
    multiprocessing.freeze_support()  # bibliotecas que abrem subprocessos precisam disto no Windows
    import catwatch.__main__  # noqa: F401  (roda o servidor)
