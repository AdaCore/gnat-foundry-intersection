---
title: "Traffic Light Controller — Concept of Operations"
subtitle: "Operational concept traced to the MUTCD (11th Edition, Revision 1)"
date: "2026-06-17"
---

# 0. Purpose & Authority

This Concept of Operations (ConOps) states the context in which this controller
is designed to operate, what this controller is intended to do, and (by
explicit omission) what it does not do. The ConOps is interposed between the
governing standard and the high-level requirements so that each requirement can
trace **upward** to one or more operational-concept statements here and,
through them, to one or more clauses of the standard.

The governing source is the **Manual on Uniform Traffic Control Devices
(MUTCD), 11th Edition, Revision 1** (FHWA), which can be found
[here](https://mutcd.fhwa.dot.gov/pdfs/11th_Editionr1/mutcd11theditionr1hl.pdf).
The MUTCD numbers every provision as a paragraph (`01`, `02`, …) under a
**Standard** ("shall"), **Guidance** ("should"), **Option** ("may"), or
**Support** (informative) heading; this document cites those paragraphs
directly (e.g. `§4I.06 ¶02`).

**The MUTCD is treated as an informative derivation source, not an approval
target.** This demonstration will not be submitted for FHWA or state
conformance and is **not for deployment on public roads**. We borrow the
MUTCD's structure and mandatory behaviors because they are a mature statement
of how a signal should behave.

Each leaf statement is marked by the kind of obligation it carries:

- **✔ must** — a MUTCD *Standard* ("shall") binding once the thing above it is scoped in.
- **◇ rec** — a MUTCD *Guidance* ("should") we choose to honor.
- **◆ dec** — a project scoping or design decision the MUTCD permits but does not compel; the citation shows what the decision is weighed against.

# 1. The Intersection

The physical site.

- **1.1 ◆** Four approaches meet at a single at-grade intersection crossing at 90°. — *decision*
- **1.2 ◆** Each approach has a dedicated left-turn lane. — *decision*
- **1.3 ◆** A marked crosswalk crosses each approach. — *decision; cf. MUTCD Ch. 3C*
- **1.4 ◆** The intersection is isolated — not coordinated or interconnected with adjacent signals. — *decision; MUTCD §4D.01*

# 2. Vehicle Traffic Control Signals

- **2.1 ✔** All vehicular movements are governed by steady (stop-and-go) signal operation. — *MUTCD §4F.01*
- **2.2 ✔** Through and right-turn movements are governed by circular red, yellow, and green indications with their standard meaning, color, and shape. — *MUTCD §4E.01*
- **2.3 ✔** Each signal face is vertical with the indications ordered red over yellow over green, top to bottom. — *MUTCD §4E.04*
- **2.4 ✔** Each approach is served by at least two signal faces. — *MUTCD §4D.05*
- **2.5 ✔** A green movement is terminated only through a yellow change interval, followed by a red clearance interval, before the conflicting movement is released. — *MUTCD §4F.17*
- **2.6 ◆** Left turns are signalized **protected-only**, on separate left-turn signal faces, and are skipped when no left-turn demand is present. — *decision; MUTCD §4F.06 ¶01*
- **2.7 ✔** Each separate left-turn signal face displays arrow indications only — steady left-turn RED ARROW, steady left-turn YELLOW ARROW, and left-turn GREEN ARROW — never circular indications. — *MUTCD §4F.06 ¶02*
- **2.8 ◆** No two conflicting movements are ever released together; conflicting phases are separated by an all-conflicting-phase red clearance. — *MUTCD §4F.01 ¶03.F; §4I.06 ¶02; §4F.17*
- **2.9 ◆** When the two opposing through movements of a street are served together as a common through phase, that phase is held for at least a both-through floor (`T_BOTH_MIN`), guaranteeing the street a minimum service interval whenever it is green. — *decision*
- **2.10 ◆** A protected left-turn green is bounded to less than half of the green-time budget allotted to its street, so the through movements always receive the larger share. — *decision*

# 3. Pedestrian Control Heads

- **3.1 ◇** A pedestrian signal head serves each marked crosswalk. — *MUTCD §4D.02 ¶03*
- **3.2 ✔** Each head presents either WALK and DON'T WALK. — *MUTCD §4I.01, §4I.02*
- **3.3 ✔** Each pedestrian head continuously presents exactly one of its defined indications — steady WALK, flashing DON'T WALK, or steady DON'T WALK — on its output, and is dark only while in the fault state (see §6). — *MUTCD §4I.06 ¶01*
- **3.4 ✔** Whenever a head shows steady WALK or flashing DON'T WALK, the conflicting perpendicular vehicular movement is held at steady RED. — *MUTCD §4I.06 ¶02*
- **3.5 ✔** Each crossing service runs WALK → flashing DON'T WALK (the pedestrian change interval) → a buffer interval of steady DON'T WALK lasting at least 2 s before any conflicting vehicular movement is released; the change and buffer intervals together are not shorter than the calculated pedestrian clearance time. — *MUTCD §4I.06 ¶04*
- **3.6 ◇** The WALK interval is fixed at 7 s. — *MUTCD §4I.06 ¶11*
- **3.7 ◆** The flashing DON'T WALK (pedestrian change) interval is fixed at 7 s, sufficient time to allow a pedestrian to complete the crossing; no countdown display is mandated. — *decision; MUTCD §4I.04 ¶01*
- **3.8 ◆** Pedestrian service runs concurrently with the parallel through-phase green, rather than as an exclusive pedestrian phase. — *decision; MUTCD §4I.06 ¶02*

- **3.9 ◆** For each crosswalk, the only non-conflicting vehicular movements are the through movements parallel to it (both directions) and the parallel-adjacent (clockwise) protected left turn; every perpendicular through and left movement conflicts with the crosswalk. Right turns — governed by the circular through indication (§2.2), not separately signalized — always yield to pedestrians and are never treated as conflicting vehicular traffic. — decision; MUTCD §4I.06 ¶02, §4F.06

  Example (non-normative). The North–South crosswalk on the East side of the intersection is non-conflicting with the northbound and southbound through movements and the northbound protected left turn (from the south approach, exiting west).

# 4. Pedestrian Detection & Request

Pedestrian service is demand-led.

- **4.1 ◆** Service is pedestrian-actuated, with a push-button detector at each crosswalk. — *decision; MUTCD §4I.05*
- **4.2 ✔** A request indicator (pilot light) at the button stays dark until actuation, then remains illuminated until the WALK indication for that crosswalk is displayed. — *MUTCD §4I.05 ¶16*
- **4.3 ◆** A pending pedestrian request is served at the next parallel through-phase green for which it is registered before that green begins; a request arriving too late waits one full cycle. — *decision*
- **4.4 ◆** A push-button actuation is acknowledged promptly: whenever an actuation registers a request (§4.2, §4.3), the request indicator illuminates within 0.2 s of that actuation. — *decision; cf. MUTCD §4I.05 ¶16*

# 5. Operating Modes

- **5.1 ◆** The controller runs a single deterministic control mode (pretimed-like, with pedestrian and left-turn actuation). — *decision; cf. MUTCD §4D.01 ¶02*
- **5.2 ◆** There is no coordination, preemption, or priority control. — *decision*
- **5.3 ✔** Power-on brings the controller up in a single defined state: it enters normal operation (§5.1) with no fault latched, the vehicle sequencer positioned at the steady all-red barrier that leads into North-South (major-street) service (per §5.4), all latched left-turn demand cleared, and every pedestrian head idle, showing steady DON'T WALK with no request pending. — *MUTCD §4G.04 ¶01.B; cf. §6.3. ¶01.B*
- **5.4 ◆** Controller initialization realizes the MUTCD flashing-to-steady transition. — *decision*

# 6. Fault Detection & Safe State

- **6.1 ◆** On detection of a major fault the controller enters flashing operation. — *decision; MUTCD Ch. 4G*
- **6.2 ◆** In the flashing state the vehicular heads show flashing RED and the pedestrian heads are dark. — *MUTCD §4I.06 ¶01*
- **6.3 ◆** Recovery from the fault state requires a manual reset; the controller does not auto-recover. — *decision*
- **6.4 ◆** While the controller is in the flashing (fault) state, the pedestrian request pilot lights (§4.2) are extinguished and no pedestrian request is held, consistent with the pedestrian heads being dark (§6.2): no crossing can be served until a manual reset, so no request is left pending. — *decision; cf. MUTCD §4I.05 ¶16, §4I.06 ¶01*

# References

- **MUTCD, 11th Edition, Revision 1** —
[Manual on Uniform Traffic Control Devices (FHWA)](https://mutcd.fhwa.dot.gov/pdfs/11th_Editionr1/mutcd11theditionr1hl.pdf)
Cited by part/section/paragraph.
