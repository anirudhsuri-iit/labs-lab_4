import base64
import os
import json
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

KEY = b"hardcodedkey1234".ljust(32, b' ')
IV = bytes([0] * 16)

exfil_dir = "exfiltrated_data"
bin_files = [f for f in os.listdir(exfil_dir) if f.endswith(".bin")]
latest_file = max(bin_files, key=lambda f: os.path.getctime(os.path.join(exfil_dir, f)))
file_path = os.path.join(exfil_dir, latest_file)

with open(file_path, "r") as f:
    data = json.load(f)
    base64_payload = data["payload"]

encrypted_data = base64.b64decode(base64_payload)
cipher = AES.new(KEY, AES.MODE_CBC, IV)

try:
    decrypted = unpad(cipher.decrypt(encrypted_data), AES.block_size)
    print("[+] Decrypted Payload (Raw Bytes):\n", decrypted)

    decoded = decrypted.decode(errors="replace")
    print("\n[+] Clean Decrypted Device Info:\n")
    lines = decoded.splitlines()
    for line in lines:
        if any(keyword in line for keyword in ["Model", "ID", "Android", "built"]):
            print(line)

    clean_start = decrypted.find(b'Model:')
    if clean_start == -1:
        clean_start = decrypted.find(b'DK built')

    if clean_start != -1:
        print("\n[+] Clean Output:\n")
        print(decrypted[clean_start:].decode(errors="replace"))
    else:
        print("\n[!] Could not find clean section. Full dump:\n")
        print(decoded)

except Exception as e:
    print("[!] Decryption failed:", e)

