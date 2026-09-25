# PerformanceDaddy

A native Mac performance investigator and regression lab.

PerformanceDaddy shows local processes, occupied ports, local coding-agent
families and RAM usage, with reviewed process termination and a separate
incident-diagnosis workspace. It runs locally without dependencies or accounts.

## Daily use

- **Understand a process:** click **Running** to sort duration; it remains visible
  while inspecting a row. **What is this?** gives app-path association, observed
  ancestor-app context, documented role hints for 37 macOS services and an explicit
  unknown fallback. Search also matches roles, categories and app context. Catalog
  matches require an exact executable name in a system location, not authentication.
  **Validate running code** performs an explicit, offline native identity check.
  Apple/developer validation is separate from inferred app association and is not
  proof of safety or necessity. Online revocation/notarization is not checked;
  unavailable evidence does not establish invalid code. Results reset when the
  selected PID/start, UID or executable changes; checks are serialized and cancelled
  when the inspector closes.
  **Inspect startup metadata** checks bounded launch configurations on demand and
  shows exact executable matches, configured policy and coverage. A selected row
  is also observed running in the latest sample, but configuration plus observation
  does not prove the policy launched it, that it is enabled, or why it returned.
  Startup inspection does not validate publisher identity.
  **Review Login Items in Settings** opens the supported macOS control without edits.
- **Stop history:** the clock-arrow toolbar button shows successful reviewed stop
  requests, missing observations, confirmed exits and later matching executables.
  A separate read-only native identity check confirms that an original instance
  is gone; missing samples or denied inspection do not prove exit. Reappearances
  are not proven automatic restarts. History
  is stored locally with a 500-event, 100-watch and 24-hour bound. Events survive
  relaunch; active exit watches do not.
  Existing sibling instances, rejected signals and pre-stop starts do not count.

- **Configuration:** on-demand metadata inventory of known shell/agent paths
  under the user's home folder. Search, sort and select a file for size,
  modification date and Finder reveal. No content
  reads, symlink following, recursive scan, edits or deletion. This does not prove
  a config was loaded, resolve inherited settings or inventory every config.
- **Processes:** search by name, PID, project folder or port; sort by CPU, RAM,
  name or port; select a row for its context and children. Command-click selects
  multiple rows.
- **Ports:** TCP listeners and bound UDP sockets, grouped by owning process.
  Search a port number to find its owner. The inspector shows IPv4/IPv6 bind
  addresses and distinguishes loopback from non-loopback binding. This is local
  socket inventory; it does not probe other machines.
- **Agent sessions:** exact-name recognition for Codex, Claude, Devin, Hermes,
  Aider, Gemini CLI, OpenCode and Cursor CLI, including Claude's versioned native
  installer executables. Same-provider wrappers collapse
  into one workload with descendant CPU, resident RAM and ports; sibling
  launches remain separate. Generic Node/Python wrappers may not be identifiable.
  This is local process evidence, not cloud sessions or conversation activity.
- **Memory:** five minutes of in-memory RAM estimates, macOS memory pressure,
  swap, compressed memory and the largest resident processes. The menu bar
  retains the RAM readout while the window is closed.
- **Process resource history:** the inspector shows resident-memory change and
  peak over up to five minutes for the 512 largest processes (150 samples each).
  A large net increase is a review cue, not a leak diagnosis. Histories reset
  across missing observations, pause and long gaps. Physical footprint and
  cumulative native disk-read/write counters are separate measurements; agent
  inspectors explicitly show the root process, not family totals. These new
  inspector fields are not yet included in snapshot export.
- **Stop:** review selected processes, a process family, or all currently
  matching rows. Normal stop sends SIGTERM; force stop explicitly sends SIGKILL.
  The review freezes exact targets and checks PID/start-time identity again at
  execution. Protected system processes and other users' processes are excluded.
  Stop results distinguish confirmed exits, still-observed processes and unknown
  exit status. A successful signal alone does not establish successful termination.
- **Context actions:** right-click a process to copy its PID, project path or
  endpoints, reveal its executable in Finder, or review stopping its family.
  Agent bulk-family reviews deduplicate overlapping targets.
- **Export:** the share button saves a versioned local JSON snapshot. It omits
  process names, paths, raw PIDs, process start times and bind addresses, retaining
  anonymous parent relationships, agent types, resource measurements, coverage
  and port numbers. It does not claim a cause or a verified improvement.
- **Monitor overhead:** the footer exposes this app's CPU, resident RAM and latest
  collection duration. These are measurements, not a certified overhead budget.

Snapshots refresh about every ten seconds and back off to at most fifteen
seconds when collection takes longer. Socket inventories refresh about every
thirty seconds at the default cadence. Initial and manual refreshes remain
immediate. Pause freezes the display. Collection reads process metadata, not
prompts, transcripts, environment variables or command arguments.

## Run locally

```bash
swift test
swift run PerformanceDaddy
```

For a Finder-launchable development app and working menu bar:

```bash
sh scripts/run-local.sh
```

This builds an unsigned local app under `.build/PerformanceDaddy.app`. Quit a
previous running copy before rebuilding. No release or installation is performed.

Use `swift run PerformanceDaddy --preview-fixture` to inspect the selected UI
with clearly labelled synthetic before/after evidence.

Completed diagnostic captures are stored locally under Application Support and
bounded to the ten most recent runs. Reports are reconstructed with the current
deterministic analysis engine at launch. Corrupt or incompatible history is ignored
without preventing startup.

## Native release

Build and verify both architectures through XcodeBuildMCP before running
`scripts/package-release.py`. The script accepts only fresh Release products,
verifies bundled artwork, creates the stable `com.significanthobbies.performancedaddy`
identity and signs with hardened runtime. It never installs, notarizes or publishes
the candidate; those remain explicit release gates. The current public update is
0.2.3 (build 3), distributed through the signed Sparkle appcast at
`https://performance.daddyrad.com/updates/appcast.xml`.

Tracking spec: [PerformanceDaddy #2](https://github.com/sarthakagrawal927/performancedaddy/issues/2)

## Measurement limits

RAM in use is an estimate that excludes free and inactive pages; the pressure
label comes from macOS separately. Per-process resident memory includes shared
pages and cannot be summed into physical RAM usage. CPU uses 100% per logical
core. Ports may be unavailable due to permissions, process exits or bounded
scan limits; a non-loopback bind alone does not establish network reachability.

Known-good baselines, workflow experiments, retained history, disk/GPU/network
throughput and StorageDaddy handoff remain future work.

Before/after diagnosis rejects insufficient or mismatched evidence and reports
mixed resource changes as inconclusive. Allocated swap alone is not a diagnosis
of active paging; a comparison does not establish what caused a change.
## Memory and thermal evidence

Open **Memory & thermals** in the footer of any live page for native VM categories,
swap-in/out rates, thermal state, Low Power Mode and optional macOS CPU allowances.
Rates reset after pause/resume, failed reads and long gaps. Memory categories
overlap; swap rates describe VM pages, not physical disk throughput. These values
are included explicitly in redacted snapshot exports.

Raw fan RPM and temperature readings appear as unavailable because this release
does not use unsupported private SMC interfaces. The supported signal is Apple's
system thermal state plus public power constraints. PerformanceDaddy does not
install a helper or change fan settings.
CPU allowances may also be unavailable on a particular Mac; unavailable never
means zero or unrestricted.
