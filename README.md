# Broadband BNG System Validation Lab

**Automated system-level validation of broadband access, QinQ subscriber services, EVPN/VXLAN transport, PPPoE/RADIUS AAA, DHCP-based IPoE service, and end-to-end subscriber connectivity.**

This project is a hands-on broadband system-validation environment designed to validate subscriber services across the **access, transport, and BNG/service layers**.

The lab combines:

- **VOLTHA/BBSim** access simulation
- **QinQ (802.1ad / 802.1Q)** subscriber encapsulation
- **FRRouting EVPN/VXLAN** leaf-spine transport
- **Accel-PPP** virtual BNG/BRAS for PPPoE
- **FreeRADIUS** subscriber AAA
- **DHCP-based IPoE service validation**
- Linux subscriber/RG emulation
- Automated multi-layer acceptance testing

Two subscriber-service scenarios are currently validated:

| Service | S-VLAN | C-VLAN | Subscriber IP | Service termination |
|---|---:|---:|---|---|
| PPPoE | 900 | 900 | `10.10.10.10` | Accel-PPP + RADIUS |
| IPoE/DHCP | 900 | 901 | `10.20.20.10` | DHCP service edge |

Both services traverse the same **EVPN/VXLAN VNI 10100** transport environment.

---

## Architecture

```text
                         ACCESS SIMULATION

                     VOLTHA Controller
                            |
                      OpenOLT Adapter
                            |
                          BBSim
                   +-------------------+
                   | OLT 10            |
                   |  `-- PON 0        |
                   |      `-- ONU 1    |
                   |          `-- UNI  |
                   |              HSIA |
                   |          S900/C900|
                   +---------+---------+
                            |
                    Service lifecycle
                       validation
                            |
             --------------------------------
             Correlated with data-plane lab
             --------------------------------


                         DATA-PLANE LAB

       PPPoE Subscriber / RG                IPoE Subscriber / RG
       +-------------------+                +-------------------+
       | PPPoE client      |                | DHCP client       |
       | 10.10.10.10       |                | 10.20.20.10       |
       +---------+---------+                +---------+---------+
                 |                                    |
            S900 / C900                          S900 / C901
                 |                                    |
                 +----------------+  +----------------+
                                  |  |
                                  v  v
                              +---------+
                              |  Leaf1  |
                              | AS65101 |
                              +----+----+
                                  / \
                                 /   \
                     +----------+     +----------+
                     |                           |
                 +---+----+                  +---+----+
                 | Spine1 |                  | Spine2 |
                 | AS65000|                  | AS65000|
                 +---+----+                  +---+----+
                     |                           |
                     +-----------+   +-----------+
                                  \ /
                              +----+----+
                              |  Leaf2  |
                              | AS65102 |
                              +----+----+
                                   |
                         EVPN/VXLAN VNI 10100
                                   |
                     +-------------+-------------+
                     |                           |
                     v                           v
               +-------------+             +-------------+
               | Accel-PPP   |             | DHCP Server |
               | PPPoE BNG   |             | 10.20.20.1  |
               | 10.10.10.1  |             +-------------+
               +------+------+
                      |
                      | RADIUS
                      v
               +-------------+
               | FreeRADIUS  |
               | AAA         |
               +-------------+
```

The EVPN/VXLAN fabric provides Layer-2 transport between subscriber-facing and service-facing edges.

---

## Validated Service Matrix

| Area | PPPoE service | IPoE/DHCP service |
|---|---|---|
| Outer VLAN | S900 / 802.1ad | S900 / 802.1ad |
| Inner VLAN | C900 / 802.1Q | C901 / 802.1Q |
| Transport | EVPN/VXLAN VNI 10100 | EVPN/VXLAN VNI 10100 |
| Session/addressing | PPPoE + PPP/IPCP | DHCP DORA |
| AAA | RADIUS | Not claimed in current IPoE scope |
| Subscriber IP | 10.10.10.10 | 10.20.20.10 |
| Service peer/gateway | 10.10.10.1 | 10.20.20.1 |
| Connectivity | 0% packet loss | 0% packet loss |
| Status | PASS | PASS |

---

## PPPoE Subscriber Encapsulation

```text
Ethernet
   |
   +-- S-Tag 900
   |     802.1ad
   |     TPID 0x88a8
   |
   +-- C-Tag 900
         802.1Q
         TPID 0x8100
             |
             +-- PPPoE
                    |
                    +-- PPP
                         |
                         +-- IPv4
```

The PPPoE subscriber establishes a session through Accel-PPP, authenticates through RADIUS, negotiates IPCP, and receives:

```text
Subscriber IP : 10.10.10.10
BNG peer      : 10.10.10.1
```

Packet-level validation confirmed the double-tagged PPPoE service.

---

## IPoE/DHCP Subscriber Encapsulation

The IPoE scenario validates DHCP-based subscriber address acquisition over a separate customer VLAN.

```text
Ethernet
   |
   +-- S-Tag 900
   |     802.1ad
   |     TPID 0x88a8
   |
   +-- C-Tag 901
         802.1Q
         TPID 0x8100
             |
             +-- IPv4
                  |
                  +-- UDP
                       |
                       +-- DHCP
```

Validated DHCP lifecycle:

```text
Subscriber                         DHCP Server
    |                                  |
    |------ DHCPDISCOVER ------------->|
    |                                  |
    |<----- DHCPOFFER -----------------|
    |        10.20.20.10               |
    |                                  |
    |------ DHCPREQUEST -------------->|
    |                                  |
    |<----- DHCPACK -------------------|
    |        10.20.20.10               |
    |                                  |
    +------ IP service active ---------+
```

Validated parameters:

```text
S-VLAN          : 900 / 802.1ad
C-VLAN          : 901 / 802.1Q
Subscriber MAC  : 36:e5:59:39:52:0c
Subscriber IP   : 10.20.20.10/24
Gateway         : 10.20.20.1
DHCP lease      : 600 seconds
Connectivity    : 5/5 packets
Packet loss     : 0%
```

### Packet-Level QinQ Proof

A capture on the subscriber physical `eth1` interface confirmed DHCP traffic with both VLAN tags present:

```text
Ethernet
  ethertype 802.1Q-QinQ (0x88a8)
    vlan 900
      ethertype 802.1Q (0x8100)
        vlan 901
          ethertype IPv4
            UDP 68/67
              DHCP
```

The capture validated:

```text
DHCPDISCOVER   S900/C901
DHCPOFFER      S900/C901
DHCPREQUEST    S900/C901
DHCPACK        S900/C901
```

ARP was also observed after address assignment:

```text
10.20.20.1 -> Who has 10.20.20.10?
10.20.20.10 -> 36:e5:59:39:52:0c
```

This demonstrates the transition from DHCP address acquisition to normal IP forwarding.

---

## EVPN/VXLAN Transport

The broadband subscriber services are transported across a dual-spine EVPN/VXLAN fabric.

```text
                 Spine1 AS65000
                /              \
Leaf1 AS65101                  Leaf2 AS65102
                \              /
                 Spine2 AS65000
```

VTEPs:

```text
Leaf1 : 11.11.11.11
Leaf2 : 22.22.22.22
```

Service VNI:

```text
VNI 10100
```

Validated behavior:

- [x] 4/4 BGP EVPN adjacencies established
- [x] Leaf1 dual-spine EVPN connectivity
- [x] Leaf2 dual-spine EVPN connectivity
- [x] VNI 10100 operational on both VTEPs
- [x] Remote VTEP presence
- [x] Subscriber MAC local on Leaf1 and remote on Leaf2
- [x] BNG/service-side MAC local on Leaf2 and remote on Leaf1
- [x] VXLAN BUM replication entries

---

## VOLTHA / BBSim Access Validation

VOLTHA and BBSim provide the simulated broadband access environment.

```text
OLT 10
 `-- PON 0
      `-- ONU 1
           `-- UNI 0
                `-- HSIA
                     +-- S-Tag 900
                     +-- C-Tag 900
                     +-- GEM Port 1024
                     `-- Alloc-ID 1024
```

Validated access states include:

- [x] VOLTHA core running
- [x] OpenOLT adapter running
- [x] OpenONU adapter running
- [x] BBSim running
- [x] OLT `BBSIM_OLT_10` ENABLED / ACTIVE / REACHABLE
- [x] ONU `BBSM000a0001` ENABLED / ACTIVE / REACHABLE
- [x] ONU provisioning reached `omci-flows-pushed`
- [x] PON 0 / ONU 1 present
- [x] UNI 0 operational, PortNo 256
- [x] HSIA initialized
- [x] S-VLAN 900
- [x] C-VLAN 900
- [x] GEM Port 1024
- [x] EAPOL authentication successful
- [x] DHCP ACK observed in the BBSim HSIA lifecycle

### Access/Data-Plane Integration Boundary

VOLTHA/BBSim validates the **simulated access/control/service lifecycle**.

The dedicated subscriber/RG containers generate the actual QinQ PPPoE and DHCP/IPoE packets entering the EVPN/VXLAN data-plane lab.

Therefore, this project does **not** claim that the validated PPPoE or IPoE packets physically traverse the BBSim simulated NNI.

The access simulation and data-plane scenarios are correlated at the service-validation level. The primary BBSim HSIA scenario uses S900/C900 and aligns with the PPPoE service. The additional S900/C901 data-plane scenario is used for DHCP/IPoE validation.

---

## Current Validated Milestone

### Four-Phase System Acceptance: PASS

```text
PHASE 1
VOLTHA / BBSim Access
        |
        v
PHASE 2
EVPN / VXLAN Transport
        |
        v
PHASE 3
QinQ PPPoE / RADIUS
        |
        v
PHASE 4
QinQ IPoE / DHCP
        |
        v
SYSTEM ACCEPTANCE PASS
```

Latest validated result:

```text
PHASE 1 RESULT: PASS
PHASE 2 RESULT: PASS
PHASE 3 RESULT: PASS
PHASE 4 RESULT: PASS

============================================================
 BROADBAND BNG SYSTEM ACCEPTANCE: PASS
============================================================
```

---

## Automated Validation

Validation is deliberately split into layers so failures can be isolated rather than treating connectivity as a single PASS/FAIL result.

### Access validation

```bash
cd containerlab/broadband-evpn-vxlan
./validate_access.sh
```

Validates VOLTHA/BBSim component health, OLT/ONU state, UNI state, HSIA state, VLANs, GEM port, EAPOL and DHCP lifecycle state.

### EVPN/VXLAN validation

```bash
./validate_evpn.sh
```

Validates:

- BGP EVPN neighbor state
- VNI 10100
- Remote VTEPs
- Subscriber and BNG/service-side MAC forwarding
- VXLAN BUM replication

Expected result:

```text
EVPN/VXLAN ACCEPTANCE TEST: PASS
EVPN peers   : 4 established
Remote VTEPs : present
MAC learning : local + remote verified
BUM          : verified
```

### QinQ / PPPoE validation

```bash
./validate_pppoe.sh
```

Validates:

- Active Accel-PPP subscriber session
- PPP/IPCP state
- Subscriber-to-BNG data plane
- Physical access interfaces
- S-VLAN 900 / 802.1ad
- C-VLAN 900 / 802.1Q
- QinQ hierarchy and MTUs
- RADIUS-backed subscriber service
- 0% packet loss

Validated state:

```text
User         : user1
Subscriber   : 10.10.10.10
BNG          : 10.10.10.1
S-VLAN       : 900 / 802.1ad
C-VLAN       : 900 / 802.1Q
Access MTU   : 9000
S-VLAN MTU   : 8996
C-VLAN MTU   : 8992
Transport    : EVPN/VXLAN
VNI          : 10100
AAA          : RADIUS
Packet Loss  : 0%
```

### QinQ / IPoE-DHCP validation

```bash
./validate_ipoe.sh
```

Validates:

- Outer S-VLAN 900 / 802.1ad
- Inner C-VLAN 901 / 802.1Q
- DHCP subscriber address
- DHCP server process
- Active DHCP lease
- Gateway `10.20.20.1/24`
- Subscriber-to-gateway connectivity
- 0% packet loss

Validated result:

```text
IPoE/DHCP VALIDATION: PASS
Subscriber : 10.20.20.10
Gateway    : 10.20.20.1
QinQ       : S900 / C901
Transport  : EVPN/VXLAN
```

### Combined system acceptance

```bash
./validate_system.sh
```

Execution flow:

```text
validate_access.sh
       |
       v
validate_evpn.sh
       |
       v
validate_pppoe.sh
       |
       v
validate_ipoe.sh
       |
       v
SYSTEM PASS
```

Current validated service summary:

```text
Access Sim      : VOLTHA / BBSim
Transport       : EVPN/VXLAN
VNI             : 10100

PPPoE Service
  QinQ          : S900 / C900
  AAA           : RADIUS
  Subscriber IP : 10.10.10.10
  BNG IP        : 10.10.10.1
  Packet Loss   : 0%

IPoE/DHCP Service
  QinQ          : S900 / C901
  DHCP          : DORA validated
  Subscriber IP : 10.20.20.10
  Gateway       : 10.20.20.1
  Packet Loss   : 0%

SYSTEM ACCEPTANCE: PASS
```

---

## Test Strategy

The project follows a **system/solution-test approach** rather than validating protocols independently.

```text
Access lifecycle
       |
       v
QinQ encapsulation
       |
       v
EVPN control plane
       |
       v
VXLAN forwarding
       |
       +-----------------------+
       |                       |
       v                       v
    PPPoE                   IPoE/DHCP
       |                       |
       v                       v
    RADIUS                  DHCP DORA
       |                       |
       v                       v
     IPCP                 Dynamic IPv4
       |                       |
       +-----------+-----------+
                   |
                   v
          Subscriber data plane
```

This allows service failures to be isolated to the appropriate layer:

```text
Subscriber service failure
        |
        +-- Access state incorrect?
        +-- QinQ incorrect?
        +-- EVPN peers down?
        +-- VNI/VTEP missing?
        +-- MAC propagation failure?
        +-- PPPoE discovery failure?
        +-- RADIUS authentication failure?
        +-- IPCP failure?
        +-- DHCP DORA failure?
        +-- DHCP lease missing?
        `-- Data-plane forwarding failure?
```

---

## Project Components

| Component | Purpose |
|---|---|
| Containerlab | Network topology orchestration |
| FRRouting | BGP EVPN control plane |
| Linux VXLAN/bridge | VXLAN forwarding |
| Accel-PPP | Virtual BNG/BRAS and PPPoE termination |
| FreeRADIUS | PPPoE subscriber AAA |
| Linux PPP/PPPoE | PPPoE subscriber/RG emulation |
| ISC DHCP client | DHCP/IPoE subscriber emulation |
| ISC DHCP server | DHCP service edge |
| QinQ | Broadband S-tag/C-tag service encapsulation |
| VOLTHA | Broadband access control framework |
| BBSim | Simulated OLT/ONU access environment |
| Shell automation | Provisioning and acceptance validation |
| tcpdump | Packet-level QinQ/protocol verification |

---

## Repository Structure

```text
broadband-bng-validation/
|
+-- README.md
+-- kind-config.yaml
|
+-- containerlab/
|   `-- broadband-evpn-vxlan/
|       +-- evpn-vxlan.clab.yml
|       +-- evpn-vxlan/
|       |   `-- config/
|       +-- subscriber-image/
|       +-- ipoe-subscriber-image/
|       |   `-- Dockerfile
|       +-- dhcp-server-image/
|       |   `-- Dockerfile
|       +-- create_broadband_endpoints.sh
|       +-- attach_broadband_endpoints.sh
|       +-- init_broadband_evpn.sh
|       +-- start_radius.sh
|       +-- start_bng.sh
|       +-- start_subscriber.sh
|       +-- validate_access.sh
|       +-- validate_evpn.sh
|       +-- validate_pppoe.sh
|       +-- validate_ipoe.sh
|       `-- validate_system.sh
|
+-- bng/
|   +-- accel-ppp/
|   |   `-- config/
|   `-- radius/
|       `-- config/
|
`-- voltha/
```

Third-party source repositories used during development are intentionally not vendored into this repository.

---

## Configuration Security

Runtime credentials are deliberately excluded from Git.

Public example configurations should use placeholder credentials such as:

```text
CHANGE_ME
```

The RADIUS lab may contain compatibility settings required by the isolated test environment. Such settings must **not** be interpreted as production security guidance.

---

## Important IPoE Scope

The IPoE scenario validates a **DHCP-based subscriber IP service over QinQ and EVPN/VXLAN**.

It demonstrates:

```text
QinQ
  +
DHCP DORA
  +
Dynamic subscriber addressing
  +
ARP
  +
IP connectivity
```

It does **not** claim a full Accel-PPP IPoE subscriber session.

The Accel-PPP build contains userspace IPoE functionality, but complete Accel-PPP IPoE operation requires kernel-side IPoE support that is not available in the current WSL2 environment.

Rather than modifying the WSL kernel solely for this project, the lab validates the IPoE service path using a dedicated DHCP subscriber and DHCP service edge.

This limitation is intentionally documented so the demonstrated scope remains technically accurate.

---

## Platform Limitations

The lab runs using Linux containers under WSL2.

### MPLS

An earlier MPLS/VPLS experiment successfully validated OSPF/LDP control-plane behavior, but native MPLS forwarding was unavailable because the WSL2 kernel environment did not expose the required MPLS kernel functionality.

EVPN/VXLAN was therefore selected for the current end-to-end transport data plane.

### Accel-PPP IPoE

A complete Accel-PPP IPoE subscriber session requires kernel-side IPoE support unavailable in the current WSL2 lab.

The current IPoE milestone therefore validates DHCP/IP service behavior independently while preserving the same QinQ + EVPN/VXLAN transport architecture.

---

## Current Engineering Coverage

Completed:

- [x] VOLTHA/BBSim access lifecycle
- [x] OLT/ONU/UNI validation
- [x] HSIA service validation
- [x] QinQ subscriber encapsulation
- [x] EVPN/VXLAN leaf-spine transport
- [x] BGP EVPN validation
- [x] VNI/VTEP validation
- [x] MAC learning and propagation
- [x] VXLAN BUM validation
- [x] PPPoE subscriber establishment
- [x] RADIUS authentication
- [x] PPP/IPCP validation
- [x] PPPoE subscriber connectivity
- [x] DHCP/IPoE DORA
- [x] Dynamic IP assignment
- [x] DHCP lease validation
- [x] IPoE subscriber connectivity
- [x] Physical QinQ packet proof
- [x] Independent layer validation
- [x] Four-phase combined acceptance

---

## Roadmap

The **QinQ + EVPN/VXLAN + PPPoE/RADIUS + DHCP/IPoE baseline is complete**.

Future enhancements may include:

1. Multiple simultaneous subscribers
2. Subscriber scale testing: 10 / 50 / 100+
3. Session setup/teardown measurements
4. Access-link failure and recovery
5. EVPN/VXLAN transport failure and convergence
6. BNG restart and subscriber recovery
7. RADIUS failure scenarios
8. DHCP failure scenarios
9. Python/Pytest-based regression framework
10. Structured metrics and test reports
11. Automated failure classification
12. AI-assisted root-cause analysis
13. Additional subscriber-policy scenarios
14. Full BNG IPoE session validation on a compatible Linux kernel/platform

These are future enhancements and are not required for the current validated baseline.

---

## Engineering Focus

This project focuses on **network system and solution validation**, including:

- Multi-layer protocol validation
- Broadband subscriber lifecycle testing
- Access/control/data-plane correlation
- QinQ service validation
- EVPN/VXLAN transport validation
- PPPoE and DHCP/IPoE workflows
- AAA validation
- Packet-level verification
- Failure isolation
- Reproducible topology construction
- Automated acceptance testing
- Testability and troubleshooting

The goal is not simply to demonstrate that individual protocols can be configured. The goal is to build a repeatable validation methodology for an end-to-end broadband subscriber service and demonstrate how access, transport, subscriber control, AAA, addressing, and forwarding can be tested as one system.

---

## Status

**Current baseline: PASS**

```text
VOLTHA / BBSim
       +
QinQ
       +
EVPN / VXLAN
       +
  +----+----+
  |         |
PPPoE    IPoE/DHCP
  |         |
RADIUS    DORA
  |         |
IPCP    Dynamic IP
  |         |
  +----+----+
       |
Subscriber Connectivity
       |
       =
SYSTEM ACCEPTANCE PASS
```

Validated service matrix:

```text
PPPoE
  S900/C900
  RADIUS
  10.10.10.10 -> 10.10.10.1
  0% packet loss
  PASS

IPoE/DHCP
  S900/C901
  DHCP DORA
  10.20.20.10 -> 10.20.20.1
  0% packet loss
  PASS
```

The current milestone establishes a validated baseline for future subscriber scale, resiliency, automation-framework, performance, and RCA work.
