import os
import urllib.request
import time

MODELS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")
TARGET_PATH = os.path.join(MODELS_DIR, "bge_reranker_base.onnx")

# Quantized INT8 BGE-Reranker-Base (266 MB instead of 1.11 GB)
URL = "https://huggingface.co/Xenova/bge-reranker-base/resolve/main/onnx/model_quantized.onnx"

print(f"=== Replacing 1.11 GB Reranker with 266 MB INT8 Quantized ONNX ===")
print(f"Target: {TARGET_PATH}\n")

req = urllib.request.Request(URL, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as response:
        total_size = int(response.info().get('Content-Length', 0))
        bytes_so_far = 0
        start_time = time.time()
        
        # Temp file first
        temp_path = TARGET_PATH + ".tmp"
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

        print("\n[+] Download complete! Replacing 1.11 GB file...")
        if os.path.exists(TARGET_PATH):
            os.remove(TARGET_PATH)
        os.rename(temp_path, TARGET_PATH)
        print(f"[✓] Successfully replaced bge_reranker_base.onnx ({os.path.getsize(TARGET_PATH)/(1024*1024):.2f} MB)")
except Exception as e:
    print(f"\n[-] Error: {e}")
