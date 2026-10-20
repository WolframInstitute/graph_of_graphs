# Whitehead moves on cubic graphs

This repository contains papers and computations on Whitehead moves on
connected cubic multigraphs. A Whitehead move collapses a non-loop edge and expands
the resulting four-valent vertex in one of two other ways. Loops and parallel
edges are allowed.

The paper in [`rule-a-paper/`](rule-a-paper/) studies the random walk obtained
by choosing an edge and one of its two Whitehead moves uniformly. It
determines the stationary distribution, bounds the spectrum, and proves that
the bridged--bridgeless cut has conductance `1/(3N/2-1)`. Loops and bridges
give lower bounds for relaxation and mixing times. The
accompanying code enumerates the full chain for every even number of vertices
from 2 through 14.

[`whitehead-field-dynamics.tex`](whitehead-field-dynamics.tex) studies a related
process in which a scalar field is averaged across an edge before the graph
is changed. Mathematica notebooks illustrate both the graph walk and the
field dynamics.

## Papers and code

| File or directory | Contents |
|---|---|
| [`rule-a-paper/local-whitehead-chain.pdf`](rule-a-paper/local-whitehead-chain.pdf) | The local Whitehead-chain paper; [LaTeX source](rule-a-paper/local-whitehead-chain.tex). |
| [`integral-torsor-paper/integral-torsor.pdf`](integral-torsor-paper/integral-torsor.pdf) | The quartic period torsor, optimal positive moment bounds, and worked examples on rewrite graphs and hypergraph incidence graphs; [source and checks](integral-torsor-paper/README.md). |
| [`straight-cycle-paper/straight-cycle-bound.pdf`](straight-cycle-paper/straight-cycle-bound.pdf) | A short proof of the straight-circuit inequality conjectured by Carrozza, Ferrari, Tanasa and Valette, with a rank refinement; [source, checks and priority assessment](straight-cycle-paper/README.md). |
| [`whitehead-field-dynamics.pdf`](whitehead-field-dynamics.pdf) | The field-dynamics manuscript; [LaTeX source](whitehead-field-dynamics.tex). |
| [`whitehead-field-dynamics.nb`](whitehead-field-dynamics.nb) | A short Mathematica companion with figures and an interactive random walk. |
| [`whitehead-field-dynamics-computational-notes.pdf`](whitehead-field-dynamics-computational-notes.pdf) | Worked computations, also available as [LaTeX](whitehead-field-dynamics-computational-notes.tex) and an [executable notebook](whitehead-field-dynamics-computational-notes.nb). |
| [`gog_generate.py`](gog_generate.py) | Enumeration of cubic multigraphs and Whitehead moves, with Python and nauty/Traces backends. |
| [`Wolfram/GogFieldDynamics/`](Wolfram/GogFieldDynamics/) | Wolfram Language code for exact transition matrices, diffusion, and random paths. |
| [`lean/`](lean/) | Lean proofs of the finite algebraic identities described in its README. |
| [`docs/`](docs/) | Mathematical conventions, computation instructions, and notebook documentation. |
| [`research/whitehead-topology/`](research/whitehead-topology/PLAN.md) | Research plan, proof notes, literature, and exact checks for the ribbon, Outer-space, and matrix-model extensions. |
| [`research/integral-torsor/`](research/integral-torsor/README.md) | A quartic differential period torsor with three local series, certified approximation bounds, and prime-field checks. |
| [`research/graph-local-periods/`](research/graph-local-periods/README.md) | Local quartic fields on cyclic rewrite graphs: exact scalar-period transforms, graph-polynomial bounds, exponent selection and certified acceptance decisions. |
| [`research/outer-forest-complex/`](research/outer-forest-complex/README.md) | Oriented forested complexes of Outer space, a checked two-term Morita cycle, and ordinary Euler characteristics under the cubic walk. |
| [`research/tanasa-schemes/`](research/tanasa-schemes/README.md) | Quartic chain boundary operators, their field restrictions, exact scheme weights and certified chain tails, with a reversible scheme-chain check. |

The [status page](docs/status.rst) lists the proved results, finite
computations, and conjectures. The Lean files cover only the identities
specified there.

## Random walks used here

Different ways of choosing a move give different random walks. The papers and
code use the following conventions, with `N` denoting the number of vertices.

| Walk | States and transition rule | Stationary distribution |
|---|---|---|
| Rule A | Unlabelled isomorphism classes. Choose one of the `3N/2` edges, then one of its two Whitehead moves. A move on a loop leaves the graph unchanged. Different moves leading to the same class are counted separately. | The cubic configuration model, conditioned on connectedness and projected to isomorphism classes. |
| Rule B | The same classes. Assign probability `1/(3N)` to each distinct neighbour other than the current state, and use the remaining probability to stay put. | Uniform on isomorphism classes. The jump chain instead has mass proportional to the number of neighbours. |
| Walk on labelled graphs | Graphs on the fixed vertex set `[N]`. Retain each distinct target other than the current state from the four endpoint-oriented moves on each edge, and choose a neighbour uniformly. | Proportional to degree. The alternative symmetric chain with `6N` equally likely choices, allowing the state to remain unchanged, has uniform stationary distribution. |

Rules A and B have the same adjacent classes, but their transition
probabilities and stationary distributions differ. For the field process,
one must also specify how the field is transported when the graph changes.
The details are in the [mathematical overview](docs/overview.rst).

## Building the papers

The LaTeX builds require `latexmk` and `pdflatex`. To build the Whitehead-chain
paper and a double-spaced copy with line numbers, run:

```sh
make rule-a-paper
```

To prepare the arXiv source archive and a code supplement containing the
enumeration programs and data:

```sh
make rule-a-paper-packages
```

The files are written to `rule-a-paper/dist/`. See the
[submission notes](rule-a-paper/SUBMISSION.md) for their contents.

The other LaTeX documents can be built separately:

```sh
make paper
make computational-notes
make integral-torsor
```

## Reproducing the computations

The [reproduction notes](rule-a-paper/REPRODUCIBILITY.md) give the commands for
the exact tables in the Whitehead-chain paper. For a small run without
nauty/Traces:

```sh
python3 rule-a-paper/verify_rule_a.py 8 --backend python --jobs 1
```

For enumeration followed by the repository's spectral and graph-statistic
analyses:

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

At `N=8` there are 71 isomorphism classes and 1,704 Whitehead moves counted
with multiplicity. At `N=14` there are 21,096 classes and 886,032 moves.
The Python backend suffices for small examples; nauty/Traces is faster for
larger enumerations. See the [computational guide](docs/computation.rst) for
installation and file formats.

## Mathematica notebooks

The notebooks use Wolfram Language 14.3 or later and the local
`GogFieldDynamics` package. They include exact models for `N=2,4,6,8`,
transition matrices for Rules A and B, and comparisons of exact distributions
with sampled paths.

To rebuild and check the computational notebook:

```sh
make computational-notes-notebook
make computational-notes-notebook-check
```

It can also be evaluated with **Evaluation > Evaluate Notebook** in
Mathematica. SetReplace is not required for this notebook.

The shorter companion includes an optional
[SetReplace](https://github.com/WolframInstitute/SetReplace) simulation. For
Rule A, repeated rules account for the multiplicity of Whitehead moves; for
Rule B, there is one rule per distinct neighbour, with additional rules that
leave the state unchanged. Its build requires a Mathematica front end, and
the full check also tests SetReplace:

```sh
make notebook
make notebook-check
```

To use a kernel at another location, pass
`WOLFRAM_KERNEL=/path/to/WolframKernel` to `make`. The
[notebook guide](docs/notebook.rst) describes the builds and dependencies.
Edit the notebook-building scripts rather than the generated `.nb` files.

## Repository checks

The checks build both papers, the computational notes, and the Sphinx
documentation; compile the Python entry points; check the Lean proofs; and
compare regenerated small Wolfram models with the saved data:

```sh
python3 -m pip install -r docs/requirements.txt
make check
```

This requires Python 3, LaTeX, Sphinx 8 or 9, and the Lean toolchain specified
in [`lean/lean-toolchain`](lean/lean-toolchain). The Mathematica notebook
checks are run separately with the commands above.
