# omarchy-sysmon

A system monitor bar widget for [Omarchy](https://omarchy.org): CPU temperature, GPU
temperature and live RAM usage right in the bar. Each one is its own click zone with its
own popup — usage, clocks, memory, storage and every fan the motherboard exposes.

![omarchy-sysmon widget in the bar](screenshot.png)

```
󰻠 54°  󰢮 51°  29%
```

| CPU zone | GPU zone | RAM zone |
| :---: | :---: | :---: |
| ![Processor popup](screenshot-cpu.png) | ![Graphics popup](screenshot-gpu.png) | ![System popup](screenshot-system.png) |

## Features

- **Bar** — three independent zones:
  - **󰻠 CPU temperature** — colored by temperature (normal, accent from 75 °C, urgent
    from 85 °C).
  - **󰢮 GPU temperature** — same coloring; only shown when an NVIDIA GPU is present.
  - **RAM usage %** — updates live (accent from 80 %, urgent from 90 %).
- **Popup per zone** (left click) — clicking a zone shows only what belongs to it:
  - **CPU** — model, thread count, temperature, usage with a meter, current/max
    frequency, load average and the CPU fan.
  - **GPU** — name and driver, temperature, core and memory-controller usage, VRAM with
    a meter, core and memory clocks, power draw, P-state and GPU fan.
  - **RAM (system overview)** — CPU/GPU summary, RAM used / total with a meter, swap,
    NVMe temperature and every motherboard fan with its RPM, plus uptime.
  - Clicking the open zone again closes the popup; clicking another zone switches to it.
- **Right click** on any zone opens `btop`.
- **Hover** shows a one-line tooltip specific to that zone.
- **Vertical bars** are supported: the three zones stack instead of sitting in a row.
- **Degrades gracefully** — without an NVIDIA GPU the GPU zone disappears, and without
  `nvidia-smi` no process is spawned at all.

## Requirements

- Omarchy 4.x with the Quickshell-based shell (uses `BarWidget`, `PopupCard` and the
  `qs.Ui` components).
- `bash` and `awk` (present on any Omarchy install).
- **Optional — CPU/board sensors:** `lm-sensors` and the kernel driver for your
  super-I/O chip. Temperatures work out of the box on AMD (`k10temp`) and Intel
  (`coretemp`); fan RPM requires a driver such as `nct6687`, `nct6775` or `it87`.
- **Optional — NVIDIA GPU:** the proprietary driver with `nvidia-smi` in `PATH`.
  AMD and Intel GPUs are not read yet (see [Limitations](#limitations)).

## Installation

```bash
omarchy plugin add https://github.com/DemianSoriaVicente/omarchy-sysmon.git --enable --yes
omarchy bar move demi.sysmon --after omarchy.workspaces
omarchy restart shell
```

The second command puts the widget between the workspaces and the clock. Pick any other
placement you like, for example:

```bash
omarchy bar move demi.sysmon --after omarchy.menu
omarchy bar move demi.sysmon --section right --index 0
```

To uninstall:

```bash
omarchy plugin remove demi.sysmon --yes
```

## Configuration

There is no settings UI yet; the few knobs live in the source:

| What | Where |
|---|---|
| Refresh interval (default 2 s idle, 1 s with the popup open) | `Sysmon.qml`, `Timer { interval: root.popupOpen ? 1000 : 2000 }` |
| Temperature colors (75 °C accent, 85 °C urgent) | `Sysmon.qml`, `tempColor()` |
| Fan names for boards whose driver exposes no `fan*_label` | `collect.sh`, the `case "$idx"` block |
| Which fans to list | `collect.sh`, the fan loop (zero-RPM fans are skipped) |

After editing an installed plugin run `omarchy-shell shell rescanPlugins` or
`omarchy restart shell`.

## How it works

- `collect.sh` runs on a timer and prints one `key=value` per line: CPU model and
  temperature (from `k10temp`/`coretemp` hwmon), NVMe temperature, fan speeds, average
  CPU frequency, memory, load average and uptime. CPU usage is computed from two
  `/proc/stat` samples, with the previous sample cached in `$XDG_RUNTIME_DIR`.
- GPU data is streamed by a single long-lived `nvidia-smi -lms 1000` process instead of
  spawning a new query every second. It is restarted automatically if it dies.
- Everything is local. No network access, no telemetry, no root.

Measured on a Ryzen 5 5600X + RTX 4060: `collect.sh` takes ~90 ms of wall time every
2 s and `nvidia-smi -lms 1000` sits around 0.3 % of one core.

## Limitations

- GPU support is **NVIDIA only** and depends on `nvidia-smi`. AMD (`amdgpu` hwmon) and
  Intel GPUs would need extra code in `collect.sh`.
- `power.draw` is `[N/A]` on some driver versions (including 615.78.08); the row hides
  itself automatically.
- A GPU fan reading of `0 %` is shown as `0% (semi-passive)` — many cards stop their
  fans below a temperature threshold.
- Motherboard fan names are a heuristic when the driver does not provide labels:
  `fan1` is treated as CPU, `fan2` as pump, the rest as case fans. Adjust the mapping in
  `collect.sh` if your board differs.
- Temperatures are read as whole degrees Celsius.

## License

[MIT](LICENSE)

---

## Español

Widget de monitor de sistema para la barra de Omarchy: temperatura de CPU, temperatura
de GPU y uso de RAM en tiempo real, cada uno como zona de clic con su propio popup (uso,
frecuencias, memoria, NVMe y **todos** los ventiladores).

**Instalación**

```bash
omarchy plugin add https://github.com/DemianSoriaVicente/omarchy-sysmon.git --enable --yes
omarchy bar move demi.sysmon --after omarchy.workspaces
omarchy restart shell
```

**Uso**

- Clic izquierdo en la CPU, la GPU o el % de RAM: abre el panel de esa zona (pulsar de
  nuevo la zona abierta lo cierra).
- Clic derecho: abre `btop`.
- Pasar el ratón: tooltip de la zona.

**Requisitos**: Omarchy 4.x. Para la GPU hace falta el driver de NVIDIA con `nvidia-smi`.
Para los ventiladores, un driver de sensores como `nct6687`/`nct6775`.

**Desinstalar**

```bash
omarchy plugin remove demi.sysmon --yes
```

Licencia MIT.
