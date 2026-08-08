import os
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

MODELS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")
TARGET_PATH = os.path.join(MODELS_DIR, "bge_reranker_base.onnx")
TEMP_PATH = TARGET_PATH + ".tmp"

if os.path.exists(TEMP_PATH) and os.path.getsize(TEMP_PATH) > 200000000:
    if os.path.exists(TARGET_PATH):
        os.remove(TARGET_PATH)
    os.rename(TEMP_PATH, TARGET_PATH)
    print(f"[OK] Replaced 1.11 GB file with INT8 Quantized bge_reranker_base.onnx ({os.path.getsize(TARGET_PATH)/(1024*1024):.2f} MB)")
else:
    print(f"[!] Temp file not found or incomplete.")
