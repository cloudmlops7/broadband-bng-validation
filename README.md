# Broadband BNG System Validation Lab

**Automated system-level validation of QinQ subscriber access, EVPN/VXLAN transport, PPPoE, RADIUS AAA and broadband service connectivity.**

This project is a hands-on broadband system-validation environment designed to validate subscriber services across access, transport and BNG layers.

The lab combines **VOLTHA/BBSim access simulation**, **QinQ (802.1ad/802.1Q)**, an **EVPN/VXLAN leaf-spine fabric**, **Accel-PPP BNG**, **FreeRADIUS AAA**, and automated acceptance testing.

The current validated scenario establishes a PPPoE subscriber over **S-VLAN 900 / C-VLAN 900**, transports the Layer-2 service across **EVPN/VXLAN VNI 10100**, authenticates the subscriber through RADIUS, assigns an IPv4 address using IPCP, and validates end-to-end subscriber connectivity.

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
                  Service correlation
                  (see limitation below)


                       DATA-PLANE LAB

 Subscriber / RG                                      Accel-PPP BNG
 +----------------+                                  +----------------+
 | PPPoE client   |                                  | PPPoE server   |
 | 10.10.10.10    |                                  | 10.10.10.1     |
 +-------+--------+                                  +--------+-------+
         |                                                    |
         | S900 / C900                              S900 / C900
         |                                                    |
         v                                                    v
      +-------+                                          +-------+
      | Leaf1 |                                          | Leaf2 |
      |AS65101|                                          |AS65102|
      +---+---+                                          +---+---+
          |\                                                /|
          | \                                              / |
          |  \                                            /  |
          |   +----------+                  +------------+   |
          +------------->|      Spine1      |<---------------+
                         |      AS65000     |
                         +------------------+

          +------------->+------------------+<---------------+
          |              |      Spine2      |                |
          |              |      AS65000     |                |
          |              +------------------+                |
          |                                                  |
          +========== EVPN / VXLAN VNI 10100 ================+

                                                       BNG eth0
                                                           |
                                                           v
                                                    +--------------+
                                                    |  FreeRADIUS  |
                                                    |     AAA      |
                                                    +--------------+
```

### Subscriber encapsulation

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
             +-- PPPoE Session
                    |
                    +-- PPP
                         |
                         +-- IPv4
```

Packet-level validation confirmed this double-tagged encapsulation on the physical BNG-facing interface.

---

## Current Validated Milestone

### System Acceptance: PASS

The current system acceptance suite validates both the EVPN/VXLAN transport and the QinQ PPPoE subscriber service.

### EVPN Control Plane

- [x] 4/4 BGP EVPN adjacencies established
- [x] Leaf1 dual-spine EVPN connectivity
- [x] Leaf2 dual-spine EVPN connectivity
- [x] VNI 10100 operational on both VTEPs
- [x] Remote VTEP presence validated

### EVPN/VXLAN Forwarding Plane

- [x] Subscriber MAC locally learned on Leaf1
- [x] Subscriber MAC remotely learned on Leaf2 through VXLAN
- [x] BNG MAC locally learned on Leaf2
- [x] BNG MAC remotely learned on Leaf1 through VXLAN
- [x] VXLAN BUM replication entries validated

### QinQ Subscriber Access

- [x] Physical subscriber/BNG interfaces operational
- [x] Parent MTU 9000
- [x] S-VLAN 900 using 802.1ad
- [x] C-VLAN 900 using 802.1Q
- [x] QinQ interface hierarchy validated
- [x] S-VLAN MTU 8996
- [x] C-VLAN MTU 8992

### PPPoE / Subscriber Lifecycle

- [x] PPPoE discovery and session establishment
- [x] RADIUS authentication
- [x] PPP session ACTIVE on BNG
- [x] IPCP address assignment
- [x] Subscriber IPv4: `10.10.10.10`
- [x] BNG PPP peer: `10.10.10.1`
- [x] End-to-end ICMP connectivity
- [x] 5/5 packets received
- [x] 0% packet loss

### Reproducibility

- [x] Clean subscriber/BNG reconstruction
- [x] Automated endpoint attachment
- [x] Idempotent QinQ creation
- [x] Automated BNG startup
- [x] Automated subscriber startup
- [x] Independent EVPN acceptance test
- [x] Independent QinQ/PPPoE acceptance test
- [x] Combined system acceptance test

---

## Automated Validation

The validation is intentionally split into layers so failures can be isolated rather than treating connectivity as a single PASS/FAIL result.

### EVPN/VXLAN validation

```bash
cd containerlab/broadband-evpn-vxlan
./validate_evpn.sh
```

Validates:

- BGP EVPN neighbor state
- VNI 10100
- Remote VTEP state
- Subscriber MAC forwarding
- BNG MAC forwarding
- VXLAN BUM replication

Expected result:

```text
==========================================
 EVPN/VXLAN ACCEPTANCE TEST: PASS
==========================================
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

- Active BNG subscriber session
- PPP/IPCP state
- Subscriber-to-BNG data plane
- Physical access state
- S-VLAN protocol, ID and MTU
- C-VLAN protocol, ID and MTU
- QinQ hierarchy

Expected result:

```text
==========================================
 QinQ PPPoE ACCEPTANCE TEST: PASS
==========================================
User        : user1
Subscriber  : 10.10.10.10
BNG         : 10.10.10.1
S-VLAN      : 900 / 802.1ad
C-VLAN      : 900 / 802.1Q
Transport   : EVPN/VXLAN
VNI         : 10100
AAA         : RADIUS
Packet Loss : 0%
```

### Combined system acceptance

```bash
./validate_system.sh
```

The current validated baseline completed both transport and subscriber-service phases successfully:

```text
============================================================
 BROADBAND BNG SYSTEM ACCEPTANCE: PASS
============================================================
Access       : QinQ
S-VLAN       : 900 / 802.1ad
C-VLAN       : 900 / 802.1Q
Transport    : EVPN/VXLAN
VNI          : 10100
Subscriber   : PPPoE
AAA          : RADIUS
Subscriber IP: 10.10.10.10
BNG IP       : 10.10.10.1
Packet Loss  : 0%
============================================================
```

---

## Test Strategy

The project follows a system-test approach rather than validating individual protocols in isolation.

```text
Access state
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
    v
PPPoE establishment
    |
    v
RADIUS authentication
    |
    v
IPCP address assignment
    |
    v
Subscriber data plane
```

This allows a service failure to be isolated to the appropriate layer.

For example:

```text
Subscriber failure
      |
      +-- QinQ incorrect?
      |
      +-- EVPN peers down?
      |
      +-- VNI/VTEP missing?
      |
      +-- MAC not propagated?
      |
      +-- PPPoE discovery failure?
      |
      +-- RADIUS authentication failure?
      |
      +-- IPCP failure?
      |
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
| FreeRADIUS | Subscriber AAA |
| Linux PPP/PPPoE | Subscriber/RG emulation |
| QinQ | Broadband S-tag/C-tag service encapsulation |
| VOLTHA | Broadband access control framework |
| BBSim | Simulated OLT/ONU access environment |
| Shell automation | Provisioning and acceptance validation |

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
|       +-- evpn-vxlan/config/
|       +-- subscriber-image/
|       +-- create_broadband_endpoints.sh
|       +-- attach_broadband_endpoints.sh
|       +-- init_broadband_evpn.sh
|       +-- start_radius.sh
|       +-- start_bng.sh
|       +-- start_subscriber.sh
|       +-- validate_evpn.sh
|       +-- validate_pppoe.sh
|       `-- validate_system.sh
|
`-- bng/
    +-- accel-ppp/config/
    `-- radius/config/
```

Third-party source repositories used during development are intentionally not vendored into this repository.

---

## Configuration Security

Runtime credentials are deliberately excluded from Git.

Public example configurations are provided as:

```text
bng/accel-ppp/config/accel-ppp.conf.example
bng/radius/config/authorize.example
bng/radius/config/clients.conf.example
containerlab/broadband-evpn-vxlan/subscriber-image/broadband.example
```

Replace `CHANGE_ME` values locally before starting the lab.

The RADIUS example currently contains:

```text
require_message_authenticator = no
```

This is a compatibility setting for the isolated lab environment and **must not be interpreted as production security guidance**.

---

## Access Simulation

VOLTHA and BBSim are used to validate the simulated broadband access lifecycle.

The current BBSim scenario includes:

```text
OLT 10
 `-- PON 0
      `-- ONU 1
           `-- UNI
                `-- HSIA
                     +-- S-Tag 900
                     +-- C-Tag 900
                     +-- GEM Port 1024
                     `-- Alloc-ID 1024
```

Validated access-side states include OLT/ONU discovery, ONU activation, OMCI initial MIB processing, service provisioning, GEM/Alloc-ID state, EAPOL success and DHCP completion.

### Current integration boundary

BBSim/VOLTHA currently validates the **simulated access/control/service lifecycle**, while the dedicated subscriber/RG emulator generates the QinQ PPPoE packets entering the EVPN/VXLAN data-plane lab.

Therefore this project does **not** claim that the validated PPPoE packets physically traverse the BBSim simulated NNI.

The S900/C900 service parameters are correlated between the access simulation and subscriber data-plane scenario.

---

## Known Platform Limitation

The lab runs using Linux containers under WSL2.

An earlier MPLS/VPLS experiment successfully validated OSPF/LDP control-plane behavior, but native MPLS forwarding was unavailable because the WSL2 kernel environment did not expose the required MPLS kernel functionality.

EVPN/VXLAN was therefore selected for the current end-to-end transport data plane.

---

## Roadmap

The current QinQ + EVPN/VXLAN + PPPoE + RADIUS baseline is complete.

Planned extensions:

1. VOLTHA/BBSim state correlation with system acceptance
2. IPoE / DHCP subscriber validation
3. Multiple subscribers
4. Subscriber scale testing
5. Session setup/teardown measurements
6. Access-link failure and recovery
7. EVPN/VXLAN transport failure and convergence
8. BNG restart and subscriber recovery
9. RADIUS/DHCP failure scenarios
10. Python/Pytest-based regression framework
11. Metrics and structured test reports
12. Automated failure classification / RCA assistance

---

## Engineering Focus

This project focuses on **network system and solution validation**, including:

- Multi-layer protocol validation
- Subscriber lifecycle testing
- Control-plane/data-plane correlation
- Failure isolation
- Reproducible topology creation
- Automated acceptance testing
- Broadband access and BNG workflows
- EVPN/VXLAN transport validation
- Testability and troubleshooting

The goal is not simply to demonstrate that individual protocols can be configured, but to build a repeatable framework for validating an end-to-end broadband subscriber service.

---

## Status

**Current baseline: PASS**

```text
QinQ
  +
EVPN/VXLAN
  +
PPPoE
  +
RADIUS
  +
IPCP
  +
Subscriber connectivity
  =
SYSTEM ACCEPTANCE PASS
```

Further subscriber, failure, scale and automation scenarios are under active development.
