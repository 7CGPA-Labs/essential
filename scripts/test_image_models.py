import urllib.request

urls = [
    "https://huggingface.co/Xenova/vit-base-patch16-224/resolve/main/onnx/model_quantized.onnx",
    "https://huggingface.co/Xenova/resnet-50/resolve/main/onnx/model_quantized.onnx",
    "https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/main/onnx/model_quantized.onnx",
    "https://huggingface.co/briaai/BRIA-2.2-HD-ONNX/resolve/main/unet/model.onnx",
    "https://huggingface.co/google/mobilenet_v2_1.0_224/resolve/main/model.onnx",
]

for url in urls:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"[+] FOUND: {url} (Length: {resp.info().get('Content-Length')})")
    except Exception as e:
        print(f"[-] FAILED: {url} ({e})")
