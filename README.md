# diagnosticgpt

`diagnosticgpt` is an advanced Arch Linux diagnostic toolkit that collects exhaustive system, hardware, graphics, package, and log data across all desktop environments. It is designed for crash, performance, and security analysis, producing a compressed `.tar.gz` archive that you can upload to ChatGPT for AI-assisted troubleshooting.

---

## Features

* **Full System Snapshot** — Kernel, OS, locales, hardware, drivers, services, logs, and more.
* **Desktop Environment Aware** — Collects DE-specific configs and settings (GNOME, KDE Plasma, XFCE, Cinnamon, MATE, LXQt, LXDE, Budgie, Pantheon, Deepin, Enlightenment, UKUI, Phosh, COSMIC, Cutefish, Trinity, Lumina, Moksha, CDE, Liri, Maui, theDesk).
* **Security & Integrity Checks** — Rootkit scans, package verification, open ports, SUID/SGID binaries.
* **Performance Data** — CPU, memory, I/O, process lists, and pressure stall info.
* **Portable & Read-Only** — No system changes, only data collection.

---

## Installation

```bash
git clone https://github.com/yourusername/diagnosticgpt.git
cd diagnosticgpt
chmod +x diagnosticgpt.sh
```

---

## Usage

Run as root for the most complete results:

```bash
sudo ./diagnosticgpt.sh
```

Optional flags:

* `--fast` — Skip heavy scans
* `--since '7 days ago'` — Limit logs to a time range
* `-o /path/to/output` — Custom output directory
* `--redact` — Light redaction of sensitive info

---

## Output

When the script finishes, it creates:

```
/tmp/diagnosticgpt-<hostname>-<timestamp>.tar.gz
```

This archive contains:

* Categorized system data in subfolders (`00_system`, `01_boot`, `02_hardware`, etc.)
* Desktop environment configs and logs
* Security and performance snapshots

---

## How It Works

When you run `diagnosticgpt.sh`, the script:

1. Creates a timestamped output directory.
2. Detects your system environment and desktop environment(s).
3. Runs a set of diagnostic commands for each subsystem.
4. Saves the outputs to structured files.
5. Compresses the folder into a `.tar.gz` archive.

---

## Getting AI Help

1. Locate your output file:

```bash
ls /tmp/diagnosticgpt-*.tar.gz
```

2. Upload the `.tar.gz` file directly into your ChatGPT conversation.
3. Ask for a full analysis of the results — ChatGPT will parse and explain possible causes for crashes, performance issues, or misconfigurations.

---

## License

MIT License — See [LICENSE](LICENSE) for details.
