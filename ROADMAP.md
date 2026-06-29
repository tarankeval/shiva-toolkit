# Shiva Toolkit Roadmap

This roadmap describes the intended direction after `v1.0.0 Stable`.

The guiding principle is simple: Shiva Toolkit should grow from a diagnostic
tool into an operational assistant for the servers it protects. Each version
has one main idea and a limited scope so development stays focused.

## Current Baseline: v1.0.0 Stable

`v1.0.0` is the reserved stable baseline.

It provides:

- server health summaries;
- host profiles;
- network, VPN, Docker, update, log, backup, SMART, and doctor checks;
- Debian package build support;
- a tested installation path.

Future work should preserve this baseline through the existing `v1.0.0` tag.

## v1.1: Automation

Main idea:

> Shiva Toolkit should not only show a problem. It should help fix it.

### Shiva Watchdog

Add a background service, for example `shiva-watchdog`, that periodically
checks critical server state every 30 to 60 seconds.

Initial checks:

- internet connectivity;
- DNS resolution;
- default gateway;
- OpenVPN state;
- required network interfaces;
- free disk space;
- temperature.

Expected behavior:

```text
Internet lost
  -> check DHCP
  -> restart interface
  -> verify again
  -> notify Telegram if recovery failed
```

The first practical target is the original operational problem: after a
network break, the server should attempt recovery without requiring a manual
reboot.

Acceptance criteria:

- `shiva-watchdog` can run as a systemd service;
- checks and repair actions are configurable per host profile;
- failed recovery attempts are logged;
- repeated alerts are rate-limited;
- destructive or risky repair actions are opt-in.

### Shiva Repair

Add explicit repair commands:

```bash
shiva repair network
shiva repair openvpn
shiva repair dns
```

Each repair target should follow a known sequence rather than improvising.

Examples:

- `network`: inspect interface, DHCP, gateway, DNS, then restart the selected
  interface only when configured to do so;
- `openvpn`: inspect service state, tunnel interface, logs, then restart the
  service when allowed;
- `dns`: inspect resolver configuration, test known resolvers, then restart
  the resolver service when configured.

Acceptance criteria:

- repair commands support dry-run mode;
- every action is printed before it runs;
- commands return meaningful exit codes;
- repair sequences reuse existing health-check helpers where possible.

### Server History

Add:

```bash
shiva history
```

Example output:

```text
24 Jun
  OK reboot
  OK internet restored
  OK tun0 restored
  OK SMART
  OK backup created
```

Acceptance criteria:

- events are stored in a simple local history file;
- watchdog, repair, backup, and health modules can append events;
- history output is readable without extra tools;
- logs remain local by default.

## v1.2: Monitoring

Main idea:

> Shiva Toolkit should make server state visible before a human needs to log in.

### Telegram Notifications

Add Telegram alerts for important state transitions.

Examples:

```text
Internet restored
VPN disconnected
SSD 90%
SMART warning
Backup completed
```

Acceptance criteria:

- Telegram token and chat ID are configured outside the repository;
- notifications are optional per profile;
- alerts are sent on state changes, not on every check loop;
- repeated warnings are rate-limited.

### Health Dashboard

Add:

```bash
shiva dashboard
```

Example output:

```text
CPU  [#######---]
RAM  [#####-----]
SSD  [##########]
VPN  [##########]
```

Acceptance criteria:

- output works in a normal terminal;
- dashboard can run once or refresh periodically;
- it uses the same status model as `shiva-health`;
- it remains useful over SSH.

Initial implementation status:

- `shiva dashboard` renders a compact one-shot terminal overview;
- `shiva dashboard --watch --interval 5` refreshes the dashboard over SSH;
- `shiva dashboard --json` exposes the same summary for future tooling.

### Module Logs

Add targeted log views:

```bash
shiva log internet
shiva log vpn
shiva log watchdog
```

Acceptance criteria:

- logs can be filtered by module;
- output defaults to recent entries;
- commands work without requiring a heavy database.

Initial implementation status:

- `shiva log watchdog`, `shiva log internet`, `shiva log dns`, and
  `shiva log vpn` filter local Shiva history by operational topic;
- `shiva log all --json` exposes recent module logs for dashboard and future
  cluster views;
- the existing `shiva logs` command remains available for system journal
  warnings and errors.

## v1.2.5: Hardening

Main idea:

> Shiva Toolkit should become architecturally stable before adding many more
> infrastructure features.

Priorities:

- one JSON shape for command output;
- one exit-code policy across commands;
- unified configuration and profile conventions;
- clearer `--help` output and README documentation;
- a shared Health Engine used by Health, Dashboard, Advisor, History, Cluster,
  and Notify.

Initial implementation status:

- `lib/shiva/health-engine.sh` provides the first shared health collection
  layer;
- `shiva health --json` exposes health checks, summary counters, overall
  status, hostname, and profile from that shared engine;
- the existing human-readable `shiva health` output remains compatible.

## v1.3: Server Farm

Main idea:

> Shiva Toolkit should understand several machines as one small infrastructure.

Add:

```bash
shiva nodes
```

Example output:

```text
shiva-server  Online
vpn           Online
whisper       Online
llm           Offline
```

Potential node types:

- `shiva-server`: main home server; disk, SMART, temperature, network,
  OpenVPN client, backups, and system services;
- `shiva-vpn`: VPN server in Germany; OpenVPN server, ocserv, Amnezia, ports,
  internet, load, and certificates;
- `ananda`: Ananda AI; Gunicorn, Web API, database, memory, logs, and service
  state;
- `whisper`: speech recognition server; processing queue, CPU, memory,
  service state, and temperature;
- `llm`: future local language model server; CPU/GPU usage, memory, model
  state, and Docker if used.

Acceptance criteria:

- node inventory is configured locally;
- each node has a role and health endpoint or SSH check;
- the command clearly separates local checks from remote checks;
- offline nodes do not block the whole command.

Initial implementation status:

- `shiva nodes` lists configured local inventory without network scanning;
- `shiva nodes --json` exposes the inventory for dashboard and future cluster
  views;
- `shiva dashboard` includes the configured node count.

## v2.0: Infrastructure

Main idea:

> Shiva Toolkit becomes a small infrastructure control center tailored to this
> environment.

Add:

```bash
shiva cluster
```

The cluster view should summarize:

- CPU;
- RAM;
- VPN;
- Docker;
- AI workloads;
- backups;
- network;
- temperature;
- disk;
- overall health.

This is not meant to replace Proxmox. It should be a lighter, purpose-built
view for the exact machines and services Shiva Toolkit manages.

Acceptance criteria:

- cluster state is readable from one terminal command;
- each node contributes a normalized health summary;
- unhealthy areas are visible immediately;
- the system remains scriptable and simple to install.

Initial implementation status:

- `shiva cluster` shows a compact infrastructure overview from local
  dashboard, node inventory, watchdog state, service state, advisor count, and
  notification state;
- `shiva cluster --json` exposes the same overview for future dashboard and
  notification integrations;
- remote node health is intentionally not scanned yet.

## Cross-Version Feature: Shiva Advisor

Main idea:

> Shiva Toolkit should explain what deserves attention next.

Add an advisor layer that turns health and history into recommendations.

Example:

```text
Health 93%

Recommendations
- Enable SMART tests
- Backup older than 5 days
- RAM usage growing
- Consider reboot in 12 days
- VPN latency increased
```

The advisor can start as deterministic rules. It does not need an AI model in
the first implementation.

Acceptance criteria:

- recommendations explain the reason behind each warning;
- advice is ranked by operational importance;
- the command never hides raw diagnostic data;
- recommendations can be disabled per profile.

## Development Rules

- Keep `v1.0.0` as the stable reference point.
- Develop each version on a dedicated branch, for example
  `v1.1-automation`, `v1.2-monitoring`, and `v1.3-nodes`.
- Prefer small, testable modules over one large script.
- Keep every command useful over SSH.
- Make risky actions explicit, configurable, and visible before execution.
- Add tests for every repair sequence and status parser.
- Preserve local configuration during package upgrades.
