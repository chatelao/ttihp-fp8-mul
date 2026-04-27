import os
import re
import scripts.generate_puml_urls as puml_encoder

def update_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Regex to find PlantUML proxy URLs
    # Matches: https://www.plantuml.com/plantuml/proxy?[any_params]src=[github_raw_url]/docs/diagrams/FILENAME.PUML
    proxy_regex = r'https://www\.plantuml\.com/plantuml/proxy\?[^)\s]*src=[^)\s]*/docs/diagrams/([^)\s]+\.PUML)'

    def replace_url(match):
        puml_filename = match.group(1)
        puml_path = os.path.join('docs/diagrams', puml_filename)

        if not os.path.exists(puml_path):
            print(f"Warning: {puml_path} not found, skipping replacement for {puml_filename}")
            return match.group(0)

        with open(puml_path, 'r', encoding='utf-8') as pf:
            puml_content = pf.read()
            encoded = puml_encoder.encode_puml(puml_content)
            new_url = f"https://www.plantuml.com/plantuml/png/{encoded}"
            print(f"Updated {puml_filename} in {filepath}")
            return new_url

    new_content = re.sub(proxy_regex, replace_url, content)

    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        return True
    return False

if __name__ == "__main__":
    files_to_update = [
        'README.md',
        'README_SERIAL.md',
        'docs/research/GOOGLE_V7_TPU_TENSORCORE.md',
        'docs/research/BLACKWELL_TENSOR_CORE.md',
        'docs/integration/SERV_INTEGRATION_CONCEPT.md',
        'docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md'
    ]

    for f in files_to_update:
        if os.path.exists(f):
            if update_file(f):
                print(f"Successfully updated {f}")
            else:
                print(f"No changes made to {f}")
        else:
            print(f"File {f} not found")
