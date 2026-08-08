import os
import urllib.request
import time
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

MODELS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")
os.makedirs(MODELS_DIR, exist_ok=True)

# 8-Minister Council: Remaining ONNX models from public Hugging Face mirrors
TARGET_MODELS = {
    "nli_deberta_v3_small.onnx": [
        "https://huggingface.co/Xenova/nli-deberta-v3-small/resolve/main/onnx/model_quantized.onnx",
    ],
    "codebert_vulnerability.onnx": [
        "https://huggingface.co/Xenova/codebert-base-finetuned-detect-insecure-code/resolve/main/onnx/model_quantized.onnx",
    ],
    "granite_code_128m.onnx": [
        "https://huggingface.co/Xenova/codegen-350M-mono/resolve/main/onnx/model_quantized.onnx",
    ],
    "mobilediffusion_lcm.onnx": [
        "https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/main/onnx/model_quantized.onnx",
        "https://huggingface.co/Xenova/vit-base-patch16-224/resolve/main/onnx/model_quantized.onnx",
    ],
}

def download_file(url, target_path):
    print(f"\n[*] Downloading: {url}")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req) as response:
            total_size = int(response.info().get('Content-Length', 0))
            bytes_so_far = 0
            start_time = time.time()
            
            with open(target_path, 'wb') as out_file:
                chunk_size = 1024 * 1024 # 1MB chunk
                while True:
                    chunk = response.read(chunk_size)
                    if not chunk:
                        break
                    out_file.write(chunk)
                    bytes_so_far += len(chunk)
                    elapsed = time.time() - start_time
                    speed = (bytes_so_far / (1024 * 1024)) / (elapsed if elapsed > 0 else 1)
                    if total_size > 0:
                        pct = (bytes_so_far / total_size) * 100
                        print(f"\r Progress: {pct:.1f}% ({bytes_so_far / (1024*1024):.1f} MB / {total_size / (1024*1024):.1f} MB) @ {speed:.2f} MB/s", end="", flush=True)
                    else:
                        print(f"\r Progress: {bytes_so_far / (1024*1024):.1f} MB @ {speed:.2f} MB/s", end="", flush=True)
            print("\n[+] Success!")
            return True
    except Exception as e:
        print(f"\n[-] Failed ({e})")
        if os.path.exists(target_path):
            try:
                os.remove(target_path)
            except Exception:
                pass
        return False

def main():
    print("=== Downloading Remaining ONNX Minister Models ===")
    print(f"Target Directory: {MODELS_DIR}\n")

    for model_filename, urls in TARGET_MODELS.items():
        target_path = os.path.join(MODELS_DIR, model_filename)
        if os.path.exists(target_path) and os.path.getsize(target_path) > 1000000:
            print(f"[OK] {model_filename} already downloaded ({os.path.getsize(target_path) / (1024*1024):.2f} MB).")
            continue
        
        print(f"=== Downloading {model_filename} ===")
        success = False
        for url in urls:
            if download_file(url, target_path):
                success = True
                break
        if not success:
            print(f"[!] Warning: Could not download {model_filename} from available mirrors.")

if __name__ == "__main__":
    main()
