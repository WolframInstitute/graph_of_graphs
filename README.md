# Whitehead field dynamics and reconfiguration graphs

This repository studies Whitehead moves on connected cubic multigraphs and a
scalar field averaged along the rewritten carrier edge. Loops and parallel
edges are allowed. The project combines a mathematical manuscript, complete
finite enumeration, spectral diagnostics, a computational Wolfram article,
and a deliberately small Lean verification layer.

This is a research repository, not a package release. Results have different
evidence levels: manuscript proofs, deductions from named external inputs,
complete finite computations, machine-checked finite algebra, and open
conjectures. The [claim-status ledger](docs/status.rst) records those
boundaries.

## Start here

| Artifact | Role |
|---|---|
| [`whitehead-field-dynamics.tex`](whitehead-field-dynamics.tex) | Canonical editable manuscript and source of record. |
| [`whitehead-field-dynamics.pdf`](whitehead-field-dynamics.pdf) | PDF built from the canonical LaTeX source. |
| [`whitehead-field-dynamics.nb`](whitehead-field-dynamics.nb) | Generated MathNotebook article with native figures and a playable graph-of-graphs diffusion lab. |
| [`Wolfram/GogFieldDynamics/`](Wolfram/GogFieldDynamics/) | Repo-local companion paclet for exact small quotients, diffusion, and SetReplace trajectories. |
| [`docs/`](docs/) | Project guide, conventions, evidence status, and reproducibility instructions. |
| [`gog_generate.py`](gog_generate.py) and analysis scripts | Exact finite enumeration and diagnostics. |
| [`lean/`](lean/) | Lean/Std proofs of a limited finite-algebra boundary. |

The notebook is a committed derived artifact, not a second manuscript source.
Its build must export byte-for-byte to the canonical UTF-8 LaTeX before it can
replace the file. Source-suppressed cells add navigation, five native visuals,
and the interactive lab without changing exported TeX.

## Four objects that must not be conflated

“Graph of graphs” refers to several related but inequivalent objects here.

| Case | State space | One-step convention | Natural law or operator |
|---|---|---|---|
| 1. Carrier field | A cubic multigraph `G` and a field `f` on its vertices | Average one carrier-edge pair, perform a Whitehead rewrite, then settle coordinates | Carrier Laplacian and a specified Rule-A or Rule-B lift |
| 2. Fixed-labelled simple GoG | Cubic multigraphs on the fixed vertex set `[N]` | Keep distinct nonself labelled targets from four endpoint-oriented moves | Degree-stationary simple walk, or a padded symmetric `6N` clock |
| 3. GDPK multiplicity chain | Unlabelled isomorphism classes | Retain two resolutions per edge object, including multiplicity and holding slots | `P_A(G,H)=m(G,H)/(3N)` and the configuration-model quotient law |
| 4. Unlabelled simple support | The same classes as Case 3 | Give every distinct nonself target one of `3N` ticks and use the remaining ticks for holding | Fixed-clock Rule B is symmetric and uniform; its jump chain has stationary mass proportional to `q(G)` |

Cases 3 and 4 share reachability after self-targets are removed, but not path
counts, probabilities, stationary measures, conductance, or normalized
spectra. Case 2 has a different state space and move clock. Case 1 is a field
cocycle over a chosen base chain, not another scalar walk on the quotient. See
the [convention dictionary](docs/overview.rst) before comparing results.

## Verification

The ordinary repository check builds the paper and Sphinx documentation,
checks Lean, compiles every Python entry point, and regenerates the committed
small Wolfram models in memory:

```sh
python3 -m pip install -r docs/requirements.txt
make check
```

It requires Python 3, a TeX distribution with `latexmk` and `pdflatex`, Sphinx
8 or 9, and the Lean toolchain pinned in `lean/lean-toolchain`.

Wolfram checks are separate because they require a licensed local installation
and a front end:

```sh
make notebook
make notebook-check
```

`make notebook-check` also runs the small-model regeneration check and nine
companion-paclet tests, including a real SetReplace trajectory.

## Wolfram computational article

The article conversion uses
[WolframInstitute/MathNotebook](https://github.com/WolframInstitute/MathNotebook)
`0.1.24` and Wolfram Language 14.3 or newer. Install the pinned-compatible
MathNotebook paclet from a Wolfram kernel:

```wolfram
PacletInstall[
  "https://www.wolframcloud.com/obj/hajek_pavel/MathNotebook.paclet",
  ForceVersionInstall -> True
]
Needs["WolframInstitute`MathNotebook`"]
```

The repo-local `GogFieldDynamics` paclet is loaded directly by the build; it
does not need to be installed globally. It bundles complete `N=2,4,6`
unlabelled quotient data derived from `gog_generate.py` and provides exact
Rule-A, fixed-clock Rule-B, and Rule-B jump-chain matrices, rational diffusion,
native random paths, and a singleton-hypergraph bridge to
[WolframInstitute/SetReplace](https://github.com/WolframInstitute/SetReplace).

In the lab:

- blue node fill is the exact distribution after `t` quotient steps;
- the orange ring and trail are one sampled trajectory;
- Rule A repeats a SetReplace rule once per resolution slot, so duplicates and
  holding events retain their exact multiplicity;
- Rule B uses one rule per distinct nonself support neighbour and pads every
  row to `3N` with holding rules;
- exact matrix diffusion remains separate from the sample path.

SetReplace is optional for opening the article and using exact/native
diffusion. It is required by `make notebook-paclet-check` and therefore by the
full `make notebook-check` used on this audited installation. The validated
local version is `0.3.196`.

The build adds a banner, eight section links, a visual abstract, the local
Whitehead move, exact consensus schedules, the diffusion lab, and enumeration
growth. It verifies all presentation IDs, rejects visible conversion debris,
normalizes cell UUIDs, saves through the Mathematica front end, reopens the
artifact, and requires exact LaTeX export both before and after saving. The
current notebook has 546 article cells, 766 inline formula cells, 169 display
formula cells, and five notebook-only visuals.

When the committed notebook already exports exactly to the current source, the
builder reuses that faithful conversion after removing old presentation cells.
This makes visual-only rebuilds fast without weakening the source contract.
Force a cold conversion after changing importer behavior with:

```sh
MATHNOTEBOOK_FORCE_RECONVERT=1 make notebook
```

Use a different kernel path when necessary:

```sh
make notebook WOLFRAM_KERNEL=/path/to/WolframKernel
make notebook-check WOLFRAM_KERNEL=/path/to/WolframKernel
```

The detailed paclet boundary, visualization-tool audit, editing policy, and
troubleshooting notes are in the [notebook guide](docs/notebook.rst).

## Computational reproduction

For a modest complete unlabelled table:

```sh
mkdir -p artifacts/csv
python3 gog_generate.py 8 --backend auto --jobs 1 \
  --save artifacts/gog_N8.json \
  --save-transitions artifacts/transitions_N8.json

python3 gog_edge_model_experiments.py \
  artifacts/transitions_N8.json \
  --csv-dir artifacts/csv \
  --summary-json artifacts/edge-summary-N8.json

python3 gog_support_feature_analysis.py \
  artifacts/transitions_N8.json \
  --max-cycle 4 --eigenvalues 6 \
  --summary-json artifacts/feature-summary-N8.json
```

The generator has a pure-Python fallback; production canonical labelling
should use nauty/Traces. A complete `N=8` run has 71 classes and 1,704 Rule-A
slot records. Enumeration through `N=14` has 21,096 classes and 886,032 slot
records. See the [computational guide](docs/computation.rst) for backends, file
contracts, expected counts, and interpretation guardrails.

## Editing discipline

When changing a result:

1. name which of the four objects it concerns;
2. state the move clock, normalization, and stationary law;
3. distinguish proof, external input, finite computation, and conjecture;
4. state the settlement convention for a transported-field claim;
5. update the status ledger and reproducibility notes with the manuscript;
6. rebuild the PDF and notebook before committing synchronized artifacts.

Edit notebook presentation code in `scripts/notebook_visuals.wl` or the
`GogFieldDynamics` paclet, never by hand in the generated `.nb`. Generated
large tables and local diagnostics belong under ignored `artifacts/`.
