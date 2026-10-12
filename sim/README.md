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

## How each assumption is enforced

| Assumption | Enforcement |
|---|---|
| Three zones, one Docker bridge each | `external-net`, `corp-net`, `clinical-net`. The DMZ is the gateway container, which spans external and corporate. |
| Perimeter VPN, key based, no continuous verification | WireGuard with one static key pair (`roles/vpn-init.sh`). After the handshake, everything in the tunnel is forwarded into `corp-net`. No posture check, no MFA, no re-verification. |
| Only the VPN port is exposed | `vpn-gateway` INPUT policy is DROP except UDP 51820 from the external side. |
| Corporate reaches the LLM on the inference port only | `corp-fw` FORWARD policy is DROP with a single ACCEPT for `10.30.0.10:8000/tcp`. Everything else is logged and dropped. |
| Clinical segment has no way out | `clinical-net` is `internal: true`. |
| Proof that the rule is port level | `meditron-llm` also listens on 8001 as a decoy. `verify.sh` expects it to be unreachable. |

