# Whitehead field dynamics and reconfiguration graphs

This repository studies Whitehead moves on connected cubic multigraphs and a
scalar field averaged along the rewritten carrier edge. Loops and parallel
edges are allowed. The project combines a mathematical manuscript, exact
finite enumeration, spectral diagnostics, a Wolfram notebook edition, and a
small Lean verification layer.

This is a research repository, not a package release. Claims have different
evidence levels: proofs in the manuscript, deductions using named external
inputs, complete finite computations, machine-checked finite algebra, and open
conjectures. The [claim-status ledger](docs/status.rst) records those boundaries.

## Start here

| Artifact | Role |
|---|---|
| [`whitehead-field-dynamics.tex`](whitehead-field-dynamics.tex) | Canonical editable manuscript and source of record. |
| [`whitehead-field-dynamics.pdf`](whitehead-field-dynamics.pdf) | PDF built from the canonical LaTeX source. |
| [`whitehead-field-dynamics.nb`](whitehead-field-dynamics.nb) | Generated MathNotebook article with native diagrams, data graphics, and section navigation. |
| [`docs/`](docs/) | Project guide, conventions, evidence status, and reproducibility instructions. |
| [`gog_generate.py`](gog_generate.py) and analysis scripts | Exact finite enumeration and diagnostics. |
| [`lean/`](lean/) | Lean/Std proofs of a deliberately limited finite-algebra layer. |

The notebook is a committed derived artifact, not a second manuscript source.
Its build requires an exact LaTeX round trip before replacing the file. A
separate deterministic presentation layer adds a visual abstract, a local
Whitehead-move diagram, exact consensus schedules, an enumeration-growth plot,
and clickable section navigation without adding anything to the exported TeX.

## Four objects that must not be conflated

“Graph of graphs” refers to several related but inequivalent objects here.

| Case | State space | One-step convention | Natural law or operator |
|---|---|---|---|
| 1. Carrier field | A cubic multigraph `G` and a field `f` on its vertices | Average one carrier-edge pair, perform a Whitehead rewrite, then settle coordinates | Carrier Laplacian and a specified Rule-A or Rule-B lift |
| 2. Fixed-labelled simple GoG | Cubic multigraphs on the fixed vertex set `[N]` | Keep distinct nonself labelled targets from four endpoint-oriented moves | Degree-stationary simple walk, or a padded symmetric `6N` clock |
| 3. GDPK multiplicity chain | Unlabelled isomorphism classes | Retain two resolutions per edge object, including multiplicity and loop holding slots | `P_A(G,H)=m(G,H)/(3N)` and the configuration-model quotient law |
| 4. Unlabelled simple support | The same classes as Case 3 | Collapse positive nonself multiplicity to one support edge | Degree `q(G)` and Rule B, with `pi_B` proportional to `q(G)` |

Cases 3 and 4 share reachability after self-targets are removed, but they do
not share path counts, transition probabilities, stationary measures,
conductance, or normalized spectra. Case 2 has a different state space and a
different raw move clock. Case 1 is a field cocycle over a chosen base chain,
not another scalar walk on a graph of graphs. See the
[full convention dictionary](docs/overview.rst) before comparing results.

## Standard verification

The ordinary repository check builds the paper and documentation, checks the
Lean project, and compiles every Python entry point:

```sh
python3 -m pip install -r docs/requirements.txt
make check
```

Requirements are:

- Python 3;
- a TeX distribution providing `latexmk` and `pdflatex`;
- Sphinx 8 or 9 for the documentation;
- Lean through the toolchain pinned in `lean/lean-toolchain`.

The Wolfram notebook checks are intentionally separate because they require a
licensed local Wolfram installation and launch the Mathematica front end.

## Wolfram notebook edition

The notebook is built with
[WolframInstitute/MathNotebook](https://github.com/WolframInstitute/MathNotebook).
This repository pins MathNotebook `0.1.24`; the paclet requires Wolfram
Language 14.3 or newer and is currently experimental.

Install the pinned-compatible paclet from a Wolfram kernel:

```wolfram
PacletInstall[
  "https://www.wolframcloud.com/obj/hajek_pavel/MathNotebook.paclet",
  ForceVersionInstall -> True
]
Needs["WolframInstitute`MathNotebook`"]
```

On the current macOS setup, rebuild and front-end-check the notebook with:

```sh
make notebook
make notebook-check
```

On another installation, provide the kernel path explicitly:

```sh
make notebook WOLFRAM_KERNEL=/path/to/WolframKernel
make notebook-check WOLFRAM_KERNEL=/path/to/WolframKernel
```

The build script:

- converts sectioning, theorem environments, proofs, lists, citations, and
  mathematics into native notebook cells;
- expands the manuscript's private LaTeX macros for display while retaining
  their original `SourceTeX`;
- adds display-only title and author cells;
- cleans unsupported prose-formatting commands for display while preserving
  their complete original cell-level TeX;
- presents bibliography accents and URLs cleanly while retaining each original
  `\bibitem` payload;
- loads [`scripts/notebook_visuals.wl`](scripts/notebook_visuals.wl), which adds
  the banner, eight section links, and four source-suppressed native Wolfram
  visualizations;
- verifies that every required presentation element is present;
- assigns deterministic notebook cell identifiers for reviewable rebuilds;
- rejects visible raw-math, unsupported prose commands, and `$Failed`
  artifacts;
- saves, reopens, and requires an exact UTF-8 LaTeX round trip.

The front-end check resolves `MathNotebook/PlainArticle.nb`, renders a temporary
PDF, confirms that all six presentation components survived notebook
normalization, and repeats the exact round-trip test.

MathNotebook is the only visualization paclet required by the article build.
The figures use built-in `Graphics`, `GraphicsRow`, `Grid`, and notebook boxes so
their multigraph and move-slot semantics stay explicit and the output remains
editable. The repository audit also identifies
[WolframInstitute/Hypergraph](https://github.com/WolframInstitute/Hypergraph)
and
[WolframInstitute/DiagrammaticComputation](https://github.com/WolframInstitute/DiagrammaticComputation)
as useful optional tools for exploratory rewrite and compositional diagrams;
they are intentionally not runtime dependencies. The rationale, rejected
alternatives, and notebook editing policy are in the
[notebook guide](docs/notebook.rst).

## Computational reproduction

For a modest complete unlabelled table, run:

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

The generator itself has a pure-Python fallback. Production canonical
labelling should use nauty/Traces; the spectral consumers require NumPy and
SciPy. A complete `N=8` run has 71 classes and 1,704 Rule-A slot records.
Enumeration through `N=14` has 21,096 classes and 886,032 slot records, so the
largest runs are not quick-start commands. See the
[computational guide](docs/computation.rst) for backends, file contracts,
expected counts, and interpretation guardrails.

## Editing discipline

When changing a result:

1. name which of the four objects it concerns;
2. state the move clock, operator normalization, and stationary law;
3. distinguish a proof from an external input, finite computation, or
   conjecture;
4. state the settlement convention for a transported-field claim;
5. update the status ledger and reproducibility notes with the manuscript;
6. rebuild the PDF and notebook before committing synchronized artifacts.

Generated enumeration tables and local diagnostics belong under `artifacts/`,
which is ignored by Git. The source papers motivating the project are retained
under `sources-gdpk/` and `sources-li/` for local comparison.
