PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all check clean
all:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error integral-torsor.tex

check:
	$(PYTHON) check_restrictions.py --nodes 16
	$(PYTHON) ../research/integral-torsor/check_quartic_torsor.py \
		--json /private/tmp/gog-quartic-torsor-recheck.json

clean:
	$(LATEXMK) -c integral-torsor.tex
