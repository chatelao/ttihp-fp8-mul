import re
import os
import sys
import zlib

_plantuml_alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

def _encode_6bit(data):
    res = []
    for i in range(0, len(data), 3):
        chunk = data[i:i+3]
        if len(chunk) == 3:
            res.append(chunk[0] >> 2)
            res.append(((chunk[0] & 0x03) << 4) | (chunk[1] >> 4))
            res.append(((chunk[1] & 0x0F) << 2) | (chunk[2] >> 6))
            res.append(chunk[2] & 0x3F)
        elif len(chunk) == 2:
            res.append(chunk[0] >> 2)
            res.append(((chunk[0] & 0x03) << 4) | (chunk[1] >> 4))
            res.append((chunk[1] & 0x0F) << 2)
            res.append(0)
        elif len(chunk) == 1:
            res.append(chunk[0] >> 2)
            res.append((chunk[0] & 0x03) << 4)
            res.append(0)
            res.append(0)
    return res

def encode(text):
    zlib_common = zlib.compressobj(level=-1, method=zlib.DEFLATED, wbits=-15, memLevel=8, strategy=zlib.Z_DEFAULT_STRATEGY)
    compressed_data = zlib_common.compress(text.encode('utf-8'))
    compressed_data += zlib_common.flush()
    return "".join([_plantuml_alphabet[b] for b in _encode_6bit(compressed_data)])

def update_file(filepath):
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return

    with open(filepath, 'r') as f:
        content = f.read()

    # Pattern for proxy URLs
    proxy_pattern = r'https://www.plantuml.com/plantuml/proxy\?.*?src=https://raw\.githubusercontent\.com/.*?/(docs/diagrams/.*?\.PUML)'

    def replace_proxy(match):
        puml_rel_path = match.group(1)
        if os.path.exists(puml_rel_path):
            with open(puml_rel_path, 'r') as f:
                puml_content = f.read()
            encoded = encode(puml_content)
            return f"https://www.plantuml.com/plantuml/png/~1{encoded}"
        else:
            print(f"Warning: Local PUML file not found: {puml_rel_path}")
            return match.group(0)

    new_content = re.sub(proxy_pattern, replace_proxy, content)

    if new_content != content:
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"Updated {filepath}")
    else:
        print(f"No changes needed for {filepath}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 update_puml_urls.py <md_file1> <md_file2> ...")
        sys.exit(1)

    for arg in sys.argv[1:]:
        update_file(arg)
