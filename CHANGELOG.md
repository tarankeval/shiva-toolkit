# Changelog

## Shiva Toolkit v1.1.0 Automation Stable

Release focus:

- add safe automation around health checks, watchdog supervision, repair plans,
  local history, notifications, dashboard, advisor, service management, nodes,
  and cluster overview;
- keep all mutating repair and service actions explicit through `--apply`;
- run `shiva-watchdog` in explicit modes: `--once` for one cycle and `--watch`
  for continuous service mode;
- introduce the shared Health Engine as the canonical local state source for
  Health, Dashboard, Advisor, and Cluster;
- add Dashboard 2.0 metrics, compact display, reusable dashboard snapshot,
  history JSON/date/service filters, notification test command, and watchdog
  metadata for last success and consecutive failures;
- add canonical health snapshot, health timeline, event log, and notification
  queue files as the foundation for Monitoring Phase 2;
- add schema-versioned JSON output for automation consumers;
- preserve local configuration and profile overrides during installation and
  package upgrades.

Verification target before tagging:

- `make test`
- `make deb`
- `shiva doctor release`
- staged `install.sh` verification
- staged DEB installation verification
- real-server smoke checks on `shiva-server`

## Shiva Toolkit v1.0.0 Stable

- first stable baseline;
- profile-driven health checks;
- SMART, VPN, network, Docker, update, log, backup, and Doctor modules;
- installer and Debian package support;
- tests for profiles, VPN filtering, SMART states, health output, and staged
  installation.
