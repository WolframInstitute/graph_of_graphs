# Whitehead moves, periods and rewrite histories

This repository contains manuscripts in TeX and PDF, Wolfram notebooks,
and the code and data needed to reproduce their computations. LaTeX
intermediates, working notes and exploratory scripts are kept locally.

## Manuscripts

| Source | PDF | Contents |
|---|---|---|
| [Local Whitehead chain](rule-a-paper/local-whitehead-chain.tex) | [PDF](rule-a-paper/local-whitehead-chain.pdf) | Stationary distribution, spectral bounds, exact bridge conductance and mixing lower bounds for the local walk on cubic multigraphs. |
| [Field dynamics](whitehead-field-dynamics.tex) | [PDF](whitehead-field-dynamics.pdf) | Pair averaging on evolving cubic graphs, finite consensus schedules and contraction estimates. |
| [Computational companion](whitehead-field-dynamics-computational-notes.tex) | [PDF](whitehead-field-dynamics-computational-notes.pdf) | Worked finite calculations accompanying the field-dynamics manuscript and notebooks. |
| [Quartic period torsor](integral-torsor-paper/integral-torsor.tex) | [PDF](integral-torsor-paper/integral-torsor.pdf) | Local period series, finite matrix integrals and optimal positive moment bounds. |
| [Outer space](outer-space-paper/outer-space.tex) | [PDF](outer-space-paper/outer-space.pdf) | A proved cubic refinement-transfer identity, Euler observables and a certificate for the known first Morita class. Its topology and Euler formulas are established results; novelty of the transfer remains unestablished. |
| [Bessel recursion](bessel-recursion-paper/bessel-recursion.tex) | [PDF](bessel-recursion-paper/bessel-recursion.pdf) | Identification of the Broadhurst–Roberts recursion with the inverse de Rham pairing, including resonance, and factorial-scaled integrality. |
| [Histories and states](history-state-paper/history-states.tex) | [PDF](history-state-paper/history-states.pdf) | A single permutation torsor for bounded framed histories, schedule weights, a criterion for observable states to inherit the history median, minimal event-bit repairs and confluent systems with nontrivial state topology. |

The Whitehead manuscript also has a [review layout](rule-a-paper/local-whitehead-chain-review.pdf).

The history paper gives full finite proofs and credits the established
event-structure, median-algebra and cubical geometry. Its CAT(0) statement
concerns occurrence prefixes. Identifying equal observable states requires
a separate argument.

Each manuscript has a build target. The research papers have their own
folders. Bibliographies and figure sources are included; figures for the
history paper and the Outer space prism are drawn directly in TeX.
The manuscript PDFs are included; intermediate files and generated figure
PDFs are excluded from tracking.

## Build and reproduce

Python 3.11 or later, LaTeX with latexmk, pdflatex and BibTeX, and
abbrvurl.bst are required. The tested Python package versions are recorded
in [requirements-repro.txt](requirements-repro.txt):

    python3 -m pip install -r requirements-repro.txt
    make papers

To build one paper:

    make rule-a-paper
    make integral-torsor
    make outer-space-paper
    make bessel-recursion-paper
    make history-state-paper

The full non-notebook check builds the manuscripts, checks the Lean
identities and small-model resource, and runs the paper-specific exact
computations:

    make check

Use the interpreter in which the dependencies were installed. It can be
selected explicitly with make check PYTHON=/path/to/python3.

Individual checks are also available:

    python3 rule-a-paper/verify_rule_a.py 8 --backend python --jobs 1
    make integral-torsor-check
    make outer-space-check
    make bessel-recursion-check
    make history-state-check

The last command compares independent incidence and execution
enumerations, exhaustively tests 4,890 observation partitions, and checks
the additive criteria, repair sets and confluent counterexamples.
The Bessel checker compares the literal recursion, differential operator
and full connection elimination for 3 through 32 Bessel factors.
Quartic checks use exact rational arithmetic and Arb enclosures.
The Outer space checks include orientation signs, refinement
multiplicities and the cycle/cocycle certificate.

[Lean sources](lean/GogVerification/Averaging.lean) verify the specified
finite averaging and permutation identities and consensus schedules over
the rationals. They do not formalize the full graph or probability
arguments. The toolchain is fixed in [lean/lean-toolchain](lean/lean-toolchain).

## Whitehead computations

Rule A chooses one of the 3N/2 edges and one of its two Whitehead
resolutions, retaining multiplicities; choosing a loop leaves the graph
unchanged. Its stationary distribution is proportional to the reciprocal
of the full incidence automorphism order, including loop flips and
parallel-edge permutations. Rule B gives each distinct nonself neighbour
probability 1/(3N) and stays put on the remaining ticks; its stationary
distribution is uniform on unlabelled classes.

The complete unlabelled class counts for N=2,4,6,8,10,12,14 are
2, 5, 17, 71, 388, 2592, 21096.
For a small complete run:

    mkdir -p artifacts/csv
    python3 gog_generate.py 8 --backend auto --jobs 1 \
      --save artifacts/gog_N8.json \
      --save-transitions artifacts/transitions_N8.json
    python3 gog_edge_model_experiments.py artifacts/transitions_N8.json \
      --csv-dir artifacts/csv --summary-json artifacts/edge-summary-N8.json
    python3 gog_support_feature_analysis.py artifacts/transitions_N8.json \
      --max-cycle 4 --eigenvalues 6 \
      --summary-json artifacts/feature-summary-N8.json
    python3 gog_ball_growth.py --load artifacts/gog_N8.json \
      --max-radius 4 --sample 71

At N=8 the output contains 71 classes and 1,704 moves counted with
multiplicity. Complete tables give finite evidence; a sampled trajectory
does not establish an asymptotic claim. Truncated tables must not be used
as complete enumerations.

The pure Python canonicalizer handles small examples. Larger runs use
nauty/Traces, either through dreadnaut or the optional native bridge:

    python3 build_nauty_bridge.py
    python3 gog_degree_diagnostics.py artifacts/gog_N8.json --lowest 20

The degree diagnostic requires dreadnaut. Set NAUTY_PREFIX or pass
--nauty-prefix when the library is installed outside the usual locations.
The Outer backend-comparison check requires the compiled native bridge;
run the bridge build before make outer-space-check or make check.

## Wolfram notebooks

Both notebooks remain in the repository:

- [Interactive field-dynamics companion](whitehead-field-dynamics.nb)
- [Executable computational notes](whitehead-field-dynamics-computational-notes.nb)

They use Wolfram Language 14.3 or later and the local
[GogFieldDynamics package](Wolfram/GogFieldDynamics/Kernel/init.wl).
The bundled exact models cover N=2,4,6,8 and are checked with:

    make notebook-data-check
    make notebook-paclet-check
    make notebook-check

To rebuild and check the computational-notes notebook:

    make computational-notes-notebook
    make computational-notes-notebook-check

The interactive notebook build uses a Mathematica front end and has an
optional SetReplace path engine. SetReplace is not required by the
computational-notes notebook. Pass
WOLFRAM_KERNEL=/path/to/WolframKernel to make when needed.
The scripts under scripts/ build the notebooks, reproduce their text
outputs and check their evaluations; edit those sources for future
notebook changes.

## Submission bundles

    make rule-a-paper-packages

This builds the Whitehead figures and both paper layouts, then writes the
arXiv source and code archives under rule-a-paper/dist/. Submission archives,
LaTeX intermediates, downloaded reference copies and working research notes
are excluded from tracking. The published history retains manuscript sources
and PDFs, notebooks and reproducibility dependencies.
