PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all check paper docs lean python-check clean

all: check

check: paper docs lean python-check

paper:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error whitehead-field-dynamics.tex

docs:
	$(MAKE) -C docs html SPHINXOPTS="-W --keep-going"

lean:
	cd lean && lake build

python-check:
	$(PYTHON) -m py_compile \
		gog_generate.py gog_ball_growth.py gog_degree_diagnostics.py \
		gog_edge_model_experiments.py gog_support_feature_analysis.py

clean:
	$(LATEXMK) -c whitehead-field-dynamics.tex
	$(MAKE) -C docs clean
