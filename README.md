# GNAT Foundry: Intersection

How can we trust the correctness of high-integrity software developed using
agentic AI? Through the output of traditional, non-AI tools that are designed
to furnish that trust.

*GNAT Foundry: Intersection* demonstrates trustworthy AI development in two
steps:

1. demonstrating a *baseline* high-integrity system in which all deterministic
   evidence is furnished for all elements, establishing the initial trust
   basis; and

2. demonstrating agent-driven execution of a *change request* that develops
   new functionality and provides updates to the deterministic evidence,
   reestablishing trust in the system.

## Quickstart

Prerequisites:

* Ubuntu 24.04 on x86_64 or aarch64
* `git`, `make`, `curl`, `tar`, `unzip` and a Bash shell
* Network access for the `make setup-community` step (and probably so your
  agent can make API calls)
* About 10 GB of free disk. Everything installs under `install/` in the
  checkout; nothing is installed system-wide, and `make reset-hard` removes
  it all
* For the change request (step 4): Claude Code or Codex, signed in to an
  account with credit available

Optional:

* `qemu-system-arm`, for the bare-metal Arm targets (`make build-target`,
  `make test-target`) — the setup targets do not provision it
* For `make setup-pro`: a GNAT Tracker account, with the pro tarballs staged
  under `pro-downloads/` — or the pro tools already on your `PATH`

Then:

1. clone this repo
2. set up the tools that you'll need: `make setup-community` or, if you're a
   GNAT Pro, SPARK Pro, and GNAT DAS customer: `make setup-pro`.
3. run the baseline: `make run-native` and view the report: `make report` and
   open `reports/report/html/index.html` (the first time you do this will take
   several minutes)
4. run the change request: in Claude Code or Codex, `@demo/demo-prompt.md`;
   when the agent is done, `make run-native` to see the result and view the
   report with `make report` and refresh or open
   `reports/report/html/index.html`

***Note: the change request takes about two hours to complete and costs about
$50 using frontier models.*** We recommend creating a branch for this or
setting up a git worktree. The agent will write new HLRs, LLRs, code, and
requirements-based tests; run the proofs, repairing any as needed; and
ensure coverage is complete.

## The Demo

*GNAT Foundry: Intersection* is a demonstration of a controller for a four-way
intersection with protected left turns and pedestrian crosswalks. *This demo is
not for public roads nor certified to any safety standard.*

* The left turns follow *lead-lag* scheduling. Rather than releasing both left
  turns together, each is released alongside the through movement beside it: on
  the north-south axis, the northbound left and northbound through go first (the
  *lead*), then both through movements run together, then the southbound left
  and southbound through go last (the *lag*). East-west mirrors it.

* The left turns are demand-led: they are only released when there is a
  vehicle present.

* The pedestrian crosswalks are demand-led: they are only released when a call
  button is pressed.

* The pedestrian crosswalks feature a call light: it turns on when pressed and
  turns off when the walk signal is given.

* Initially, no countdown timer is displayed when the pedestrian control head
  shows flashing DON'T WALK; the change request adds a countdown timer.

To get started, we built a set of comprehensive systems- and
software-engineering artifacts:

* a Concept of Operations (CONOPS)
* High-Level Requirements (HLRs)
* a software architecture
* Low-Level Requirements (LLRs)
* a software implementation targeting native or a bare-metal Arm 32-bit target

The CONOPS is derived from and traces to the
[US Department of Transportation Manual on Uniform Traffic Control Devices.](https://mutcd.fhwa.dot.gov)

For demonstration purposes, we added a simulation harness that stands in for
the physical hardware with which the software would interact. The simulation
harness runs on Linux, but the Ada code can just as well be run on a
microcontroller, with an RTOS, or bare-board, without an RTOS.

We then developed comprehensive artifacts that verify the LLRs:

* proofs of absence of runtime errors, using SPARK (SPARK Silver)
* selected proofs of correctness (LLRs verified by proof), using SPARK (SPARK
  Gold)
* compile-time verifications, using Ada's support for the same
* requirements-based tests sufficient to yield 100% MC/DC and statement
  coverage of the controller

Finally, we developed a comprehensive traceability matrix that is presented
through an interactive HTML report.

The report clearly identifies where human review is required:

* the CONOPS, as the root of the chain of trust
* the CONOPS elements not traced to software
* the derived requirements in the HLRs

Aside from this trust core, the report relies entirely on evidence produced
deterministically by AdaCore's tools to establish trust in the software.

## Digging In

The Makefile is self-documenting, so to see a comprehensive list of targets,
run:

```shell
make help
```

The repository is organized as follows:

| Directory | Purpose |
|-----------|---------|
| demo | contains the demo prompt and the patch representing the change request |
| design | design documents for the controller |
| engine | reusable components of the demo, including the agentic workflow employed |
| requirements | systems-engineering artifacts for the controller |
| scripts | setup scripts called by the Makefile |
| src | the Ada sources for the controller (`core`, `types`) and the simulation harness (`app`, `hal`) and the proof harness for generics (`proof`) |
| tests | the requirements-based tests for the LLRs (`reqs`) and for selected HLRs (`system`) |

## Additional Resources

To learn more about this demo and what we're doing with it, check out our
[blog](https://blog.adacore.com).
