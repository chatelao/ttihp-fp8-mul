import os
import subprocess
import re
import sys

def main():
    circuit_md_path = 'CIRCUIT.md'
    output_svg_path = 'docs/circuit.svg'
    temp_tex_path = 'circuit_temp.tex'
    temp_dvi_path = 'circuit_temp.dvi'

    if not os.path.exists(circuit_md_path):
        print(f"Error: {circuit_md_path} not found.")
        sys.exit(1)

    with open(circuit_md_path, 'r') as f:
        content = f.read()

    # Extract LaTeX block between $$ and $$
    match = re.search(r'\$\$(.*?)\$\$', content, re.DOTALL)
    if not match:
        print("Error: No LaTeX block found in CIRCUIT.md")
        sys.exit(1)

    latex_code = match.group(1).strip()

    # Wrap in standalone tikz document
    tex_template = r"""\documentclass[tikz]{standalone}
\usepackage{circuitikz}
\begin{document}
\begin{tikzpicture}
%s
\end{tikzpicture}
\end{document}
""" % latex_code

    with open(temp_tex_path, 'w') as f:
        f.write(tex_template)

    try:
        # Run latex to generate DVI
        subprocess.run(['latex', '-interaction=nonstopmode', temp_tex_path], check=True, stdout=subprocess.DEVNULL)

        # Run dvisvgm to generate SVG
        # -n: no fonts (convert to paths)
        # -o: output file
        subprocess.run(['dvisvgm', temp_dvi_path, '-n', '-o', output_svg_path], check=True, stdout=subprocess.DEVNULL)

        print(f"Successfully rendered to {output_svg_path}")

    except subprocess.CalledProcessError as e:
        print(f"Error during rendering: {e}")
        sys.exit(1)
    finally:
        # Cleanup temporary files
        for ext in ['.tex', '.dvi', '.aux', '.log']:
            path = 'circuit_temp' + ext
            if os.path.exists(path):
                os.remove(path)

if __name__ == "__main__":
    main()
