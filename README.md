# Whitehead field dynamics and reconfiguration graphs

This repository studies Whitehead moves on connected cubic multigraphs and a
scalar averaging field transported along those moves. Loops and parallel edges
are allowed. The project combines a theory manuscript, exact finite
enumeration, spectral diagnostics, and a small Lean verification layer.

The phrase “graph of graphs” is ambiguous here. Four objects are kept separate:

| Case | Object |
|---|---|
| 1 | A carrier cubic multigraph and its vertex-valued averaging field. |
| 2 | Li’s fixed-labelled simple graph of Whitehead moves. |
| 3 | GDPK’s unlabelled directed move-slot multigraph and reversible Rule-A chain. |
| 4 | The unlabelled simple support obtained by removing self-targets and multiplicity. |

Their clocks, stationary laws, Laplacians, and path counts are different. See
the [four-object dictionary](docs/overview.rst) before comparing results.

## Documentation

The Sphinx sources use plain reStructuredText and require no MyST plugin.

```sh
python3 -m pip install -r docs/requirements.txt
make -C docs html
```

Open `docs/_build/html/index.html`. The
[theorem-status page](docs/status.rst) separates proved results, conditional
results, finite computations, and conjectures.

## Canonical manuscript

The current synthesis is `whitehead-field-dynamics.tex`; its complete
finite-enumeration section records the reproducible data boundary.

```sh
latexmk -pdf -interaction=nonstopmode -halt-on-error \
  whitehead-field-dynamics.tex
```

## Computation

Generate a complete unlabelled transition table at a modest size:

```sh
mkdir -p artifacts
python3 gog_generate.py 8 --backend auto --jobs 1 \
  --save artifacts/gog_N8.json \
  --save-transitions artifacts/transitions_N8.json
python3 gog_edge_model_experiments.py artifacts/transitions_N8.json
python3 gog_support_feature_analysis.py artifacts/transitions_N8.json
```

Production canonical labelling uses nauty/Traces when available; NumPy and
SciPy are needed for the spectral analyses. Full unlabelled enumeration through
`N=14` contains 21,096 classes and is substantially more expensive than the example.
See [the computational guide](docs/computation.rst) for all scripts and outputs.

## Lean verification

```sh
cd lean
lake build
```

The Lean project uses exact rational arithmetic and proves finite averaging
identities, affine covariance, pullback algebra for supplied coordinate
permutations, the `K4`/`Q3` consensus schedules, and a three-state dyadic
obstruction. It does not formalize Whitehead enumeration, the construction of
settlements, stationary laws, asymptotics, or Lyapunov exponents. See
[the formalization boundary](docs/formalization.rst).
