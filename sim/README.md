# CNA simulation: perimeter-VPN baseline

Simulated corporate network architecture (CNA) of a Swiss public hospital, used as the baseline for the semester project on secure mobile access to an on-premise Meditron LLM (LiGHT lab, EPFL). It models how a hospital lets an authorised remote device reach an internal service: a VPN gateway in a DMZ, named accounts in a directory, internal firewalls, and a restricted clinical segment that holds only the LLM endpoint.

It is **not a replica of CHUV's network**. It reproduces the pattern of a hospital remote-access setup, based on published hospital requirements and reference designs (HIL H.TEC:2015 v3.0, NIST SP 1800-1 and 800-46, NHS England segmentation guidance). The baseline has **no MFA and no device posture check**, as a deliberate worst case. TOTP is a switchable variant.

```
external zone       DMZ              corporate zone              clinical zone
clinician --VPN--> vpn-gateway --> dmz-fw --> corp-ws, directory
                                                 |
                                              corp-fw --port 8000 only--> meditron-llm
```

| Container | Role |
|---|---|
| `clinician` | Mobile clinician device, external zone. OpenVPN client with a certificate, user name and password (plus a TOTP code in the variant). |
| `vpn-gateway` | OpenVPN server in the DMZ. Checks the client certificate, then the account against the directory. Does not NAT, so client addresses survive for logging. |
| `dmz-fw` | Firewall between DMZ and corporate segment. The gateway itself may only reach the directory on 636, and the tunnel address pool is let through. |
| `directory` | OpenLDAP standing in for Active Directory. Named accounts, lockout policy, LDAPS only. |
| `corp-ws` | Corporate workstation. |
| `corp-fw` | Internal firewall. Corporate to LLM on port 8000 only, everything else dropped and logged. No NAT. |
| `meditron-llm` | LLM endpoint: a stub (profile `stub`) or a forwarder to EPFL RCP (profile `rcp`). HTTPS on 8000, plain-HTTP decoy on 8001. |
| `pki-init` | One-shot: creates the CA and all certificates, then discards the CA key. |

## Run

Requires Docker with Compose v2.

```
cd sim
docker compose --profile stub up -d --build     # first start creates the PKI, wait about 20 s
./tests/verify.sh                               # authentication, reachability and logging matrix
./tests/scenarios.sh                            # S1 stolen credentials, S2 lateral movement, S3 attribution
./tests/s4-gateway.sh                           # S4 compromised gateway
./tests/t5-capture.sh                           # T5 are prompts readable on the wire
docker compose --profile stub --profile rcp down -v
```

Use `down -v` with both profiles whenever you switch variant or profile. It removes the containers (they share the name `meditron-llm`) and the volumes, which regenerates the PKI and the directory data.

### Variants

| Variant | Command (after a `down -v`) | What changes |
|---|---|---|
| TOTP second factor | `MFA=totp docker compose --profile stub up -d --build` | The password field carries a 6-digit code. `verify.sh` runs one extra check. |
| Plain HTTP on the LLM leg | `LLM_TLS=off docker compose --profile stub up -d --build` | T5 and S4 then show prompts readable after the tunnel. |
| Capacity-limited stub | `STUB_DELAY=2 STUB_CONCURRENCY=4 docker compose --profile stub up -d --build`, then `./tests/t6-flood.sh` | 100 parallel requests from `corp-ws` against a stub that serves 4 at a time. |
| WAN-like latency and loss | `./tests/netem.sh on 60ms 20ms 0.5%` and `./tests/netem.sh off` | Adds delay, jitter and loss on the clinician's uplink. The defaults are placeholders: replace them with measured values. |
| Real Meditron on RCP | see below | The LLM forwards to the EPFL RCP cluster. |

### Real Meditron through RCP

Needs the EPFL network or VPN.

```
cp .env.example .env              # fill in RCP_API_KEY
./tests/list-rcp-models.sh        # prints the model ids, put one in RCP_MODEL
docker compose --profile rcp up -d --build
./tests/verify.sh
```

The LLM host is attached to two networks (`clinical-net` and `llm-egress`) and has `ip_forward=0`, so it does not route between them. The test prompts are fixed marker strings. Do not send real patient data.

## Test accounts

| Account | Password | Use |
|---|---|---|
| `dr.martin` | `Clinician-Pass-1` | The clinician. |
| `dr.lockout` | `Lockout-Pass-1` | Lockout test. `verify.sh` recreates it at the start of each run. |

These are simulation values only. The TOTP seed for both is fixed (`JBSWY3DPEHPK3PXP`) so runs are reproducible.

## How each assumption is enforced

| Assumption | Enforcement | Checked by |
|---|---|---|
| Four zones: external, DMZ, corporate, restricted clinical | Docker networks `external-net`, `dmz-net`, `corp-net`, `clinical-net` | `verify.sh`, zones |
| Remote access through a VPN gateway in the DMZ, with only the VPN port exposed | `vpn-gateway`: INPUT policy DROP except UDP 1194 from the external side | tcp/22 closed |
| Named account against a central directory | OpenLDAP, LDAPS login check in `roles/auth-ldap.sh` | wrong password, unknown user |
| The remote machine is identifiable | OpenVPN requires a client certificate from the hospital CA | no certificate, foreign-CA certificate |
| LLM reachable only on its inference port, with no routing between its interfaces | `corp-fw` FORWARD DROP plus one ACCEPT to `10.30.0.10:8000`, and `ip_forward=0` on the LLM | decoy :8001 blocked, sysctl check |
| Traffic encrypted, including inside the network | TLS 1.2+ on the LLM port with a certificate from the hospital CA | plain HTTP refused, T5 |
| Access attempts logged with user and result | `vpn-auth.log` and `vpn-sessions.log` on the gateway, source address in the LLM log, no NAT | logging checks, S3 |
| Lockout after 5 failures in 60 s, unlock after 20 min | OpenLDAP password policy (`roles/seed.ldif`) | lockout test |
| Password baseline, TOTP variant | `MFA=totp` adds a code, checked before the directory | variant run |
| Clinical segment has no way out | The stub LLM has no default route (`roles/llm.sh`), and in the `rcp` profile only the `llm-egress` route exists | no-way-out check (stub) |

## Tests and what they show

| Script | Scenario | Reads as |
|---|---|---|
| `verify.sh` | Authentication, reachability and logging matrix. 29 checks in the baseline (28 with the `rcp` profile), 30 with TOTP. | Does the simulation behave as the assumptions say? |
| `scenarios.sh` S1 | A second host with the stolen certificate and key: without password, with password, with password and TOTP seed. | One stolen laptop is enough in the baseline. TOTP needs the phone as well. |
| `scenarios.sh` S2 | Compromised corporate workstation probes the LLM and the directory. | Only port 8000 is open, but any corporate host can use it. |
| `scenarios.sh` S3 | Attribution: LLM log versus gateway session log. | The LLM sees only the tunnel address. Two logs must be joined. |
| `s4-gateway.sh` | Attacker with a shell on the gateway. | Blocked from its own address, but a tunnel address as source reaches the LLM. |
| `t5-capture.sh` | Prompt marker on the outer VPN leg and after the tunnel. | TLS on the LLM protects prompts inside the network. |
| `t6-flood.sh` | Flood from a corporate host against a limited stub. | No per-source limit, so one host delays the clinician. |

## Design notes

- **Docker `internal: true` is not used** on `dmz-net` and `clinical-net`. Docker drops routed traffic on an internal network whose destination lies outside the subnet, even when it passes through a router container, which breaks the firewall chain once NAT is removed. "No way out" for the clinical segment is enforced by the LLM host's routing instead.
- **No NAT** at the gateway or the firewalls, so the LLM sees the tunnel address and the gateway log can map it to a user.
- **OpenVPN does not pass container environment variables to its login script.** The gateway writes `setenv MFA ...` into the server config for that reason (`roles/vpn-gateway.sh`).
- **Lockout state cannot be edited** (it is operational data in the directory). `verify.sh` deletes and re-adds `dr.lockout` to reset it.
- **The CA key is discarded** after setup, so no running node can issue certificates. No revocation list is simulated.
- **The directory is OpenLDAP, not Active Directory.** Lockout semantics are equivalent, not identical.
- **The gateway holds sensitive material** (its private key, the TOTP seeds, a writable login script). This is intentional: it is what S4 tests.

## Limits

- Containers on one Docker host give functional fidelity only. Timing and throughput are not those of a real network, so any latency result needs `netem.sh` with measured values.
- The simulation reproduces the pattern of a hospital CNA from published requirements. It does not claim to reproduce CHUV's configuration.
- 802.1X (the HIL preference for on-site machine authentication) is not simulated. The client certificate on the VPN is the remote equivalent.
- The first chat completion against the real model failed once and passed on the second run. The cause was not investigated.

## Repository layout

```
docker-compose.yml     networks, volumes, services, profiles
image/Dockerfile       one shared image, the role of each container is a script in roles/
roles/                 container start-up scripts, PKI, directory seed, VPN client scripts
llm/server.py          LLM stub and RCP forwarder, TLS on 8000, decoy on 8001
tests/                 verify, scenarios, s4, t5, t6, netem, list-rcp-models
.env.example           template for the RCP settings (copy to .env)
```