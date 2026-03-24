# AHB Integrationskonzept: Cortex-M3 zu MAC Unit

Dieses Dokument beschreibt das Konzept zur Integration der Tiny Tapeout MAC-Einheit mit dem ARM Cortex-M3 (EMCU) über den **Advanced High-performance Bus (AHB)** auf dem Gowin GW1NSR-4C FPGA.

## 1. Einleitung

Während die aktuelle Integration über GPIO (Bit-Banging) oder das vorgeschlagene APB-Interface (Memory-Mapped) funktioniert, bietet die **AHB-Integration** eine deutlich höhere Performance. AHB ist der primäre Systembus des Cortex-M3 und erlaubt Burst-Transfers sowie Zero-Wait-State-Zugriffe.

## 2. Integration als AHB_SLAVE (Peripheral Mode)

In diesem Modus fungiert die MAC-Einheit als passives Peripheriegerät am AHB-Bus. Der Cortex-M3 ist der Master und steuert alle Datentransfers.

### Funktionsweise
- Ein **AHB-to-MAC Bridge** Modul übersetzt AHB-Protokollphasen (`HSEL`, `HTRANS`, `HADDR`, `HWRITE`, `HWDATA`) in die Steuersignale der MAC-Einheit.
- **Pipeline-Unterstützung**: AHB nutzt getrennte Adress- und Datenphasen. Die Bridge muss die Adresse für einen Zyklus puffern, um sie mit der Datenphase zu korrelieren.
- **Wait-States**: Die Bridge nutzt das `HREADY`-Signal, um den Bus-Master (M3) zu pausieren, falls die MAC-Einheit gerade das sequentielle Streaming-Protokoll abarbeitet.

### Vorteile
- Nahtlose Einbindung in den System-Adressraum.
- Höhere Taktraten und geringere Latenz im Vergleich zur APB-Bridge.
- Direkte Unterstützung durch Standard-Compiler via Memory-Pointer.

## 3. Integration als AHB_MASTER (DMA/Accelerator Mode)

In diesem Modus agiert ein Hardware-Sequenzer (Teil der MAC-Integration) als Master auf dem AHB-Bus.

### Funktionsweise
- **Autonomer Zugriff**: Die Einheit fordert den Bus an und liest Operanden (z.B. Gewichte aus dem Flash oder SRAM) sowie Eingangsdaten direkt aus dem Speicher.
- **Beschleuniger-Struktur**:
  1. Der M3 konfiguriert Startadresse und Blockgröße via Steuerregister.
  2. Die MAC-Einheit übernimmt die Bus-Kontrolle und streamt Daten autonom.
  3. Ergebnisse werden direkt in den Zielspeicher zurückgeschrieben.
- **Interrupts**: Ein Abschluss-Signal (IRQ) informiert den M3, sobald die Matrix-Operation beendet ist.

### Vorteile
- **Minimale CPU-Last**: Der M3 steht für andere Aufgaben zur Verfügung (z.B. Kommunikationsstack), während die Hardware rechnet.
- **Maximaler Durchsatz**: Optimale Ausnutzung der AHB-Bandbreite durch Bursts.
- Ideal für großflächige Berechnungen, wie sie bei der Inferenz von Sprachmodellen (LLMs) vorkommen.

## 4. Vergleich der Integrationsmethoden

| Feature | GPIO (Status Quo) | APB (Geplant) | AHB_SLAVE | AHB_MASTER (DMA) |
|:---:|:---:|:---:|:---:|:---:|
| **Bus-Typ** | Bit-Banging | Peripheral Bus | System Bus | System Bus |
| **Datendurchsatz** | ~100 KB/s | ~2 MB/s | ~10-20 MB/s | >50 MB/s |
| **CPU-Last** | 100% | Mittel | Gering | Minimal |
| **Design-Aufwand** | Minimal | Mittel | Hoch | Sehr Hoch |

## 5. Zusammenfassung und Ausblick

Die Wahl zwischen AHB-Slave und AHB-Master hängt vom Anwendungsfall ab. Für einfache Beschleunigungsaufgaben ist die **AHB_SLAVE**-Implementierung aufgrund ihrer einfacheren Steuerbarkeit vorzuziehen. Für skalierbare KI-Anwendungen, die große Datenmengen verarbeiten, bietet die **AHB_MASTER**-Variante mit DMA-Funktionalität die notwendige Performance, um das volle Potenzial des Gowin GW1NSR-4C auszuschöpfen.
