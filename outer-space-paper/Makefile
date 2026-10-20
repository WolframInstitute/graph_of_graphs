PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all check clean
all:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error outer-space.tex

check:
	$(PYTHON) ../research/outer-forest-complex/check_outer_euler.py --max-rank 4
	$(PYTHON) ../research/outer-forest-complex/check_cubic_euler.py --max-rank 4
	$(MAKE) -C .. outer-forest-check

clean:
	$(LATEXMK) -c outer-space.tex
