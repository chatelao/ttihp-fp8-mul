#!/usr/bin/env python3
import sys
import os

def bin_to_mi(bin_path, mi_path):
    """
    Converts a raw binary file to a Gowin EDA compatible .mi file.
    The .mi file format starts with a header and then hex data.
    """
    if not os.path.exists(bin_path):
        print(f"Error: {bin_path} not found.")
        return

    with open(bin_path, "rb") as f:
        data = f.read()

    # Gowin .mi Header (official Gowin EDA Hex format)
    # #File_format=Hex
    # #Address_depth=XXXX
    # #Data_width=32

    depth = (len(data) + 3) // 4  # Number of 32-bit words

    with open(mi_path, "w") as f:
        f.write("#File_format=Hex\n")
        f.write(f"#Address_depth={depth}\n")
        f.write("#Data_width=32\n")

        for i in range(0, len(data), 4):
            word_bytes = data[i:i+4]
            # M3 is little-endian, so we read bytes in order but format as a 32-bit hex word
            # If the file isn't a multiple of 4, pad with 0
            if len(word_bytes) < 4:
                word_bytes = word_bytes + b'\x00' * (4 - len(word_bytes))

            # Pack into a 32-bit integer (Little Endian)
            word = int.from_bytes(word_bytes, byteorder='little')
            f.write(f"{word:08X}\n")

    print(f"Successfully converted {bin_path} to {mi_path} ({depth} words).")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: bin2mi.py <input.bin> [output.mi]")
        sys.exit(1)

    bin_file = sys.argv[1]
    mi_file = sys.argv[2] if len(sys.argv) > 2 else bin_file.replace(".bin", ".mi")
    bin_to_mi(bin_file, mi_file)
