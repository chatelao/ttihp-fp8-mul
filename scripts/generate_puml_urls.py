import zlib
import sys
import os

def encode(text):
    zlib_common = zlib.compressobj(level=-1, method=zlib.DEFLATED, wbits=-15, memLevel=8, strategy=zlib.Z_DEFAULT_STRATEGY)
    compressed_data = zlib_common.compress(text.encode('utf-8'))
    compressed_data += zlib_common.flush()

    return "".join([_plantuml_alphabet[b] for b in _encode_6bit(compressed_data)])

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

if __name__ == "__main__":
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
        if os.path.exists(filepath):
            with open(filepath, 'r') as f:
                print(f"https://www.plantuml.com/plantuml/png/~1{encode(f.read())}")
        else:
            print(f"File not found: {filepath}", file=sys.stderr)
            sys.exit(1)
    else:
        print("Usage: python3 generate_puml_urls.py <puml_file>")
        sys.exit(1)
