import os
import urllib.request
import zipfile
import shutil

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JNI_DIR = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "jniLibs", "arm64-v8a")
HEADERS_DIR = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "cpp", "onnxruntime_include")

os.makedirs(JNI_DIR, exist_ok=True)
os.makedirs(HEADERS_DIR, exist_ok=True)

AAR_URL = "https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.20.0/onnxruntime-android-1.20.0.aar"
TEMP_AAR = os.path.join(PROJECT_ROOT, "onnxruntime-android-1.20.0.aar")

def main():
    print(f"[*] Downloading ONNX Runtime Android AAR: {AAR_URL}")
    req = urllib.request.Request(AAR_URL, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp, open(TEMP_AAR, 'wb') as f:
        f.write(resp.read())
    print(f"[OK] Downloaded {TEMP_AAR} ({os.path.getsize(TEMP_AAR)/(1024*1024):.2f} MB)")

    print("[*] Extracting native libonnxruntime.so and C++ headers...")
    with zipfile.ZipFile(TEMP_AAR, 'r') as zip_ref:
        for member in zip_ref.namelist():
            # Extract arm64-v8a libonnxruntime.so
            if member == "jni/arm64-v8a/libonnxruntime.so":
                target_so = os.path.join(JNI_DIR, "libonnxruntime.so")
                with zip_ref.open(member) as source, open(target_so, 'wb') as target:
                    shutil.copyfileobj(source, target)
                print(f"[OK] Extracted {target_so} ({os.path.getsize(target_so)/(1024*1024):.2f} MB)")
            
            # Extract header files
            if member.startswith("headers/") and member.endswith(".h"):
                header_filename = os.path.basename(member)
                target_header = os.path.join(HEADERS_DIR, header_filename)
                with zip_ref.open(member) as source, open(target_header, 'wb') as target:
                    shutil.copyfileobj(source, target)
                print(f"[OK] Extracted header: {header_filename}")

    if os.path.exists(TEMP_AAR):
        os.remove(TEMP_AAR)
    print("\n[SUCCESS] ONNX Runtime native library and C++ headers configured cleanly!")

if __name__ == "__main__":
    main()
