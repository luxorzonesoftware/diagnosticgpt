# 🛠️ diagnosticgpt

`diagnosticgpt` is an advanced Arch Linux toolkit that collects exhaustive system, hardware, graphics, package, and log data across all desktop environments. Designed for crash, performance, and security analysis, producing a compressed `.zip` file that you can upload to ChatGPT for AI-assisted troubleshooting.

---

## ✨ Features

* **Full System Snapshot** — Kernel, OS, locales, hardware, drivers, services, logs, and more.
* **Desktop Environment Aware** — Collects DE-specific configs and settings for GNOME, KDE Plasma, Xfce, Cinnamon, MATE, LXQt, LXDE, Budgie, Pantheon, Deepin, Enlightenment, UKUI, Phosh, COSMIC, Cutefish, GNOME Flashback, Trinity, Lumina, Moksha, CDE, Liri, Maui, theDesk, and more.
* **Security & Integrity Checks** — Rootkit scans, package verification, open ports, SUID/SGID binaries.
* **Performance Data** — CPU, memory, I/O, process lists, and pressure stall info.
* **Portable & Read-Only** — No system changes, only data collection.

> ⚠️ **Sensitive data warning:** the archive includes IPs, MAC addresses, usernames, installed packages, logs, and configs. Share only with trusted parties.

---

## 📥 Installation

```bash
git clone https://github.com/luxorzonesoftware/diagnosticgpt.git
cd diagnosticgpt
chmod +x diagnosticgpt.sh
```

---

## ▶️ Usage

Run as root for maximum results:

```bash
sudo ./diagnosticgpt.sh
```

Optional flags:

* `--fast` — Skip heavy scans
* `--since '7 days ago'` — Limit logs to a time range
* `-o /path/to/output` — Custom output directory
* `--redact` — Redact sensitive info
* `--summary` — Include a human-readable summary in the output
* `--split-mb <N>` — Split the final archive into `<N>` MB parts

---

## 📂 Output

Outputs a **`.zip`** archive to `/tmp`:

```
/tmp/diagnosticgpt-<host>-<timestamp>.zip
```

If `-o` is used, the archive and snapshot folder will be written there instead.

Contents include:

* Categorized system data
* Desktop environment configs and logs
* Security and performance snapshots
* Optional summary file

---

## ⚙️ How It Works

1. Creates a timestamped output directory.
2. Detects your system environment and desktop environment(s).
3. Runs a set of diagnostic commands for each subsystem.
4. Saves the outputs to structured files.
5. Compresses the folder into a `.zip` archive.

---

## 📊 Generating Summary Results

1. Locate your output file:

```bash
ls /tmp/diagnosticgpt-*.zip
```

2. Upload the `.zip` file directly into your ChatGPT conversation.
3. Copy–paste the prompt below to generate a clean HTML report strictly from your data.

**ChatGPT prompt:**

```
You are a careful analyst. I am uploading a diagnosticgpt bundle (a .zip produced by diagnosticgpt). Extract it, analyze ONLY what’s inside, and produce a single, self-contained HTML report (inline CSS, dark theme, responsive) with these sections:

1) Overview: kernel + host (from 00_system/00-uname.txt), OS (01-os-release.txt), kernel cmdline, time (timedatectl), detected desktop (11_desktop/DE-detection.txt), total packages.
2) Key Findings: bullet list of concrete observations with short rationale. Do not speculate; cite exact file paths/line snippets as evidence.
3) Graphics: session summary (03_graphics/00-session.txt); KMS/GPU warnings (03_graphics/01-kms-dmesg.txt) if any; NVIDIA tool output (04-nvidia-smi.txt) if present.
4) Logs & Crashes: dmesg tail, kernel errors (08_logs/01-kernel-errors.txt), OOM scan (01_boot/04-ooms.txt). Include 20–80 lines of context where relevant.
5) Networking: first page of listeners from 05_network/04-sockets.txt and NetworkManager status.
6) Security: CPU vulnerability files (09_security/00-vulns-sysfs.txt); SUID/SGID sample; open listeners summary.
7) Package integrity: pacman -Dk and -Qkk highlights (quote the exact lines if issues exist); coredumps list, if any.
8) Appendix: link each section to the exact files/paths included in the bundle.

Formatting requirements:
- Use semantic HTML, a simple modern font, subtle cards, and code/pre blocks for logs.
- Clearly mark status tags (OK/WARN/ERROR) without guessing.
- If a section has no data, say “None found in bundle.”
- Never invent information or external context. Everything must be traceable to a file in the archive.

When you’re done, output ONLY the final HTML (no markdown fences).
```

---

## 📜 License

GPL-2.0 License — See [LICENSE](LICENSE)
