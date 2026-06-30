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
- **2.8 ◆** No two conflicting movements are ever released together; conflicting phases are separated by an all-red clearance. — *MUTCD §4F.01 ¶03.F; §4I.06 ¶02; §4F.17*

# 3. Pedestrian Control Heads

- **3.1 ◇** A pedestrian signal head serves each marked crosswalk. — *MUTCD §4D.02 ¶03*
- **3.2 ✔** Each head presents either WALK and DON'T WALK. — *MUTCD §4I.01, §4I.02*
- **3.3 ✔** Pedestrian indications are displayed at all times except while in fault state (see §6). — *MUTCD §4I.06 ¶01*
- **3.4 ✔** Whenever a head shows steady WALK or flashing DON'T WALK, the conflicting perpendicular vehicular movement is held at steady RED. — *MUTCD §4I.06 ¶02*
- **3.5 ✔** Each crossing service runs WALK → flashing DON'T WALK (the pedestrian change interval) → a buffer interval of steady DON'T WALK lasting at least 2 s before any conflicting vehicular movement is released; the change and buffer intervals together are not shorter than the calculated pedestrian clearance time. — *MUTCD §4I.06 ¶04*
- **3.6 ◇** The WALK interval is fixed at 7 s. — *MUTCD §4I.06 ¶11*
- **3.7 ◆** The flashing DON'T WALK (pedestrian change) interval is fixed at 7 s, sufficient time to allow a pedestrian to complete the crossing; no countdown display is mandated. — *decision; MUTCD §4I.04 ¶01*
- **3.8 ◆** Pedestrian service runs concurrently with the parallel through-phase green, rather than as an exclusive pedestrian phase. — *decision; MUTCD §4I.06 ¶02*

# 4. Pedestrian Detection & Request

Pedestrian service is demand-led.

- **4.1 ◆** Service is pedestrian-actuated, with a push-button detector at each crosswalk. — *decision; MUTCD §4I.05*
- **4.2 ✔** A request indicator (pilot light) at the button stays dark until actuation, then remains illuminated until the WALK indication for that crosswalk is displayed. — *MUTCD §4I.05 ¶16*
- **4.3 ◆** A pending pedestrian request is served at the next parallel through-phase green for which it is registered before that green begins; a request arriving too late waits one full cycle. — *decision*

# 5. Operating Modes

- **5.1 ◆** The controller runs a single deterministic control mode (pretimed-like, with pedestrian and left-turn actuation). — *decision; cf. MUTCD §4D.01 ¶02*
- **5.2 ◆** There is no coordination, preemption, or priority control. — *decision*

# 6. Fault Detection & Safe State

- **6.1 ◆** On detection of a major fault the controller enters flashing operation. — *decision; MUTCD Ch. 4G*
- **6.2 ◆** In the flashing state the vehicular heads show flashing RED and the pedestrian heads are dark. — *MUTCD §4I.06 ¶01*
- **6.3 ◆** Recovery from the fault state requires a power cycle; the controller does not auto-recover. — *decision*

# References

- **MUTCD, 11th Edition, Revision 1** —
[Manual on Uniform Traffic Control Devices (FHWA)](https://mutcd.fhwa.dot.gov/pdfs/11th_Editionr1/mutcd11theditionr1hl.pdf)
Cited by part/section/paragraph.
