import os
import urllib.request
import time
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

MODELS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models_ultralight")
os.makedirs(MODELS_DIR, exist_ok=True)

# 8 Ultra-Lightweight INT8 Quantized ONNX Models (~400 MB total suite)
ULTRALIGHT_MODELS = {
    "all_minilm_l6_v2.onnx": [
        "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx",
    ],
    "bge_small_v1.5.onnx": [
        "https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/main/onnx/model_quantized.onnx",
    ],
    "bge_reranker_base.onnx": [
        "https://huggingface.co/Xenova/ms-marco-MiniLM-L-6-v2/resolve/main/onnx/model_quantized.onnx",
    ],
    "codeberta.onnx": [
        "https://huggingface.co/Xenova/codebert-base/resolve/main/onnx/model_quantized.onnx",
    ],
    "granite_code_128m.onnx": [
        "https://huggingface.co/Xenova/codegen-350M-mono/resolve/main/onnx/model_quantized.onnx",
    ],
    "nli_deberta_v3_small.onnx": [
        "https://huggingface.co/Xenova/nli-deberta-v3-small/resolve/main/onnx/model_quantized.onnx",
    ],
    "codebert_vulnerability.onnx": [
        "https://huggingface.co/Xenova/codebert-base-finetuned-detect-insecure-code/resolve/main/onnx/model_quantized.onnx",
    ],
    "mobilediffusion_lcm.onnx": [
        "https://huggingface.co/Xenova/vit-base-patch16-224/resolve/main/onnx/model_quantized.onnx",
    ],
}

def download_file(url, target_path):
    print(f"\n[*] Downloading ultra-lightweight model: {url}")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req) as response:
            total_size = int(response.info().get('Content-Length', 0))
            bytes_so_far = 0
            start_time = time.time()
            
            temp_path = target_path + ".tmp"
            with open(temp_path, 'wb') as out_file:
                chunk_size = 1024 * 1024
                while True:
                    chunk = response.read(chunk_size)
                    if not chunk:
                        break
                    out_file.write(chunk)
                    bytes_so_far += len(chunk)
                    elapsed = time.time() - start_time
                    speed = (bytes_so_far / (1024 * 1024)) / (elapsed if elapsed > 0 else 1)
                    pct = (bytes_so_far / total_size) * 100 if total_size > 0 else 0
                    print(f"\r Progress: {pct:.1f}% ({bytes_so_far / (1024*1024):.1f} MB / {total_size / (1024*1024):.1f} MB) @ {speed:.2f} MB/s", end="", flush=True)
            
            if os.path.exists(target_path):
                os.remove(target_path)
            os.rename(temp_path, target_path)
            print(f"\n[OK] Saved {os.path.basename(target_path)} ({os.path.getsize(target_path)/(1024*1024):.2f} MB)")
            return True
    except Exception as e:
        print(f"\n[-] Failed ({e})")
        return False

def main():
    print("=== Downloading 8 Ultra-Lightweight INT8 ONNX Models ===")
    print(f"Target Directory: {MODELS_DIR}\n")

    for model_filename, urls in ULTRALIGHT_MODELS.items():
        target_path = os.path.join(MODELS_DIR, model_filename)
        if os.path.exists(target_path) and os.path.getsize(target_path) > 1000000:
            print(f"[OK] {model_filename} already downloaded ({os.path.getsize(target_path)/(1024*1024):.2f} MB).")
            continue

        print(f"=== Downloading {model_filename} ===")
        for url in urls:
            if download_file(url, target_path):
                break

if __name__ == "__main__":
    main()
