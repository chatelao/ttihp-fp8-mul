import wavedrom
import json
import os

regs = {
    "docs/metadata_c0_ui.svg": { "reg": [
      {"name": "NBM Offset A", "bits": 3},
      {"name": "LNS Mode", "bits": 2},
      {"name": "Loopback En", "bits": 1},
      {"name": "Debug En", "bits": 1},
      {"name": "Short Protocol", "bits": 1}
    ], "config": {"bits": 8}},

    "docs/metadata_c0_uio.svg": { "reg": [
      {"name": "NBM Offset B / Format A/B", "bits": 3},
      {"name": "Rounding Mode", "bits": 2},
      {"name": "Overflow Mode", "bits": 1},
      {"name": "Packed Mode", "bits": 1},
      {"name": "MX+ Enable", "bits": 1}
    ], "config": {"bits": 8}},

    "docs/scale_a.svg": { "reg": [ {"name": "Scale A", "bits": 8} ], "config": {"bits": 8}},

    "docs/config_a.svg": { "reg": [
      {"name": "Format A", "bits": 3},
      {"name": "BM Index A", "bits": 5}
    ], "config": {"bits": 8}},

    "docs/scale_b.svg": { "reg": [ {"name": "Scale B", "bits": 8} ], "config": {"bits": 8}},

    "docs/config_b.svg": { "reg": [
      {"name": "Format B", "bits": 3},
      {"name": "BM Index B", "bits": 5}
    ], "config": {"bits": 8}}
}

for filepath, data in regs.items():
    svg = wavedrom.render(json.dumps(data))
    svg.saveas(filepath)
    print(f"Rendered {filepath}")
