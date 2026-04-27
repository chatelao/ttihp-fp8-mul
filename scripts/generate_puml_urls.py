import zlib
import sys
import os

def encode_6bit(b):
    if b < 10:
        return chr(48 + b)
    b -= 10
    if b < 26:
        return chr(65 + b)
    b -= 26
    if b < 26:
        return chr(97 + b)
    b -= 26
    if b == 0:
        return '-'
    if b == 1:
        return '_'
    return '?'

def encode_3bytes(b1, b2, b3):
    c1 = b1 >> 2
    c2 = ((b1 & 0x3) << 4) | (b2 >> 4)
    c3 = ((b2 & 0xF) << 2) | (b3 >> 6)
    c4 = b3 & 0x3F
    res = ""
    for c in [c1, c2, c3, c4]:
        res += encode_6bit(c & 0x3F)
    return res

def encode_puml(puml):
    zlibbed_str = zlib.compress(puml.encode('utf-8'))
    compressed_string = zlibbed_str[2:-4]
    res = ""
    for i in range(0, len(compressed_string), 3):
        if i + 2 == len(compressed_string):
            res += encode_3bytes(compressed_string[i], compressed_string[i + 1], 0)
        elif i + 1 == len(compressed_string):
            res += encode_3bytes(compressed_string[i], 0, 0)
        else:
            res += encode_3bytes(compressed_string[i], compressed_string[i + 1], compressed_string[i + 2])
    return res

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate_puml_urls.py <puml_file1> <puml_file2> ...")
        sys.exit(1)

    for filepath in sys.argv[1:]:
        if not os.path.exists(filepath):
            print(f"Error: {filepath} not found.")
            continue
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            encoded = encode_puml(content)
            print(f"File: {filepath}")
            print(f"URL: https://www.plantuml.com/plantuml/png/{encoded}")
            print("-" * 40)
