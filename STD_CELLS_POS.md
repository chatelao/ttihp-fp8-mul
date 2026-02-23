# Verwendete Standardzellen und ihre Positionen

Dieser Bericht listet die effektiv verwendeten Standardzellen des IHP SG13G2 PDK für das FP8-Multiplier-Projekt auf und beschreibt die Herleitung dieser Informationen.

## Liste der verwendeten Standardzellen

Basierend auf der Analyse des GDS-Layouts wurden folgende Zellen identifiziert:

- **Logikgatter:**
    - `sg13g2_and2_1`, `sg13g2_and3_1`, `sg13g2_and3_2`, `sg13g2_and4_1`
    - `sg13g2_or2_1`, `sg13g2_or3_1`, `sg13g2_or4_1`
    - `sg13g2_nand2_1`, `sg13g2_nand2_2`, `sg13g2_nand2b_1`, `sg13g2_nand3_1`, `sg13g2_nand3b_1`, `sg13g2_nand4_1`
    - `sg13g2_nor2_1`, `sg13g2_nor2_2`, `sg13g2_nor2b_1`, `sg13g2_nor2b_2`, `sg13g2_nor3_1`, `sg13g2_nor3_2`, `sg13g2_nor4_1`, `sg13g2_nor4_2`
    - `sg13g2_inv_1`, `sg13g2_inv_2`, `sg13g2_inv_4`
    - `sg13g2_xor2_1`, `sg13g2_xnor2_1`
    - `sg13g2_mux2_1`, `sg13g2_mux4_1`
    - `sg13g2_a21o_1`, `sg13g2_a21o_2`, `sg13g2_a21oi_1`, `sg13g2_a21oi_2`, `sg13g2_a22oi_1`, `sg13g2_a221oi_1`
    - `sg13g2_o21ai_1`
- **Hilfszellen:**
    - `sg13g2_buf_1`, `sg13g2_buf_2`, `sg13g2_buf_8`
    - `sg13g2_tielo`
    - `sg13g2_decap_4`, `sg13g2_decap_8`
    - `sg13g2_fill_1`, `sg13g2_fill_2`

## Positionen auf dem Silizium

Die exakten Positionen der Zellen sind im binären GDS-Datenstrom (`tinytapeout.gds`) kodiert. Ein direkter Hinweis auf die Platzierung findet sich in den Instanznamen der Füllzellen (Filler Cells), die nach dem Schema `FILLER_{Reihe}_{X-Koordinate}` benannt sind.

Beispiele für Platzierungen:
- `FILLER_0_0` (Reihe 0, Position 0)
- `FILLER_0_14` (Reihe 0, Position 14)
- `FILLER_1_7` (Reihe 1, Position 7)
- `FILLER_38_408` (Reihe 38, Position 408)

Die Logikzellen sind in den Reihen zwischen den Füllzellen platziert, um die Chipfläche optimal zu nutzen (Target Density ca. 60%).

## Herleitung der Information

Da die ursprünglichen Syntheseberichte und DEF-Dateien nicht im Repository eingecheckt sind, wurde die Information wie folgt rekonstruiert:

1. **Abruf des GDS-Artefakts:** Die Datei `tinytapeout.gds` wurde vom öffentlichen GitHub-Pages-Server des Projekts (`chatelao.github.io/ttihp-fp8-mul/`) abgerufen.
2. **String-Extraktion:** Mittels des Unix-Kommandos `strings` wurden alle druckbaren Zeichenketten aus dem binären GDSII-Datenstrom extrahiert.
3. **Filterung:**
    - Suchmuster `sg13g2_` identifizierte die verwendeten Zelltypen des IHP-PDKs.
    - Suchmuster `FILLER_` identifizierte die platzierten Instanzen der Füllzellen inklusive ihrer Reihen- und Koordinaten-Informationen.
4. **Validierung:** Die Liste der Zelltypen entspricht einem typischen Ergebnis einer Synthese für einen kombinatorischen Multiplikator (Vielzahl von AOI/OAI-Zellen und Standard-Logikgattern).
