# CHUV corporate network access (CNA) simulation

Baseline for the semester project. It implements the approved assumptions: a traditional perimeter VPN, three zones, one simulated clinician device, one VPN gateway, one corporate segment, and one restricted clinical segment that holds only the LLM endpoint.

```
external-net 172.20.0.0/24      corp-net 10.20.0.0/24            clinical-net 10.30.0.0/24 (internal)
 clinician .10 --WireGuard--> vpn-gateway .2 (DMZ) ... corp-ws .20 ... corp-fw .254 --8000 only--> meditron-llm .10
```

## Run

```
cd sim
docker compose --profile stub up -d --build     # placeholder LLM, works anywhere
./tests/verify.sh                               # reachability matrix, expects passed=12 failed=0
./tests/scenarios.sh                            # threat-model evidence (stolen key, lateral movement, attribution)
docker compose --profile stub down -v
```

Real Meditron through the RCP cluster:

```
cp .env.example .env        # fill in RCP_API_KEY, then run ./tests/list-rcp-models.sh and set RCP_MODEL
docker compose --profile rcp up -d --build
./tests/verify.sh
```

You need to be on the EPFL network (or the EPFL VPN) for `inference.rcp.epfl.ch`. Docker Desktop with the WSL2 backend works. If the kernel has no WireGuard module, the scripts fall back to `wireguard-go`.

## How each assumption is enforced

| Assumption | Enforcement |
|---|---|
| Three zones, one Docker bridge each | `external-net`, `corp-net`, `clinical-net`. The DMZ is the gateway container, which spans external and corporate. |
| Perimeter VPN, key based, no continuous verification | WireGuard with one static key pair (`roles/vpn-init.sh`). After the handshake, everything in the tunnel is forwarded into `corp-net`. No posture check, no MFA, no re-verification. |
| Only the VPN port is exposed | `vpn-gateway` INPUT policy is DROP except UDP 51820 from the external side. |
| Corporate reaches the LLM on the inference port only | `corp-fw` FORWARD policy is DROP with a single ACCEPT for `10.30.0.10:8000/tcp`. Everything else is logged and dropped. |
| Clinical segment has no way out | `clinical-net` is `internal: true`. |
| Proof that the rule is port level | `meditron-llm` also listens on 8001 as a decoy. `verify.sh` expects it to be unreachable. |

## Simulation artifacts to mention in the report

- **Source attribution is lost.** Both the gateway and the firewall masquerade, so the LLM only ever sees the firewall address. This is realistic for a perimeter VPN and feeds the discussion on network position versus identity (NIST SP 800-207). `scenarios.sh` S3 shows it.
- **RCP egress.** In the `rcp` profile the LLM container gets a second network (`llm-egress`) so it can call RCP. A real on-premise server would not need this. It is outside the clinician access path and is not exercised by the tests, but it should be stated as a limitation.
- **`corp-ws`** is an extra host inside the corporate segment. It is there so the firewall rule can be tested from a non-VPN source and for the compromised-workstation scenario.
- **Latency.** Everything runs on one host, so there are no realistic delay or loss numbers yet. The clinician container already has `NET_ADMIN`, so `tc netem` can be added later for the mobility and connectivity conditions, and the same harness can be reused for the Swisscom MPN side.

## Status

Compose file, scripts, and the LLM server were checked for syntax and the LLM server was run locally. The full topology has not been brought up yet because the sandbox it was written in cannot pull container images. First run on your machine is the real test, so expect to fix small things in the first pass.
