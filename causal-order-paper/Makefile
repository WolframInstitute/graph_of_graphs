PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all check clean

all:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error causal-order.tex

check:
	$(PYTHON) check_rank_ambiguity.py
	$(PYTHON) check_curvature.py

clean:
	$(LATEXMK) -c causal-order.tex
