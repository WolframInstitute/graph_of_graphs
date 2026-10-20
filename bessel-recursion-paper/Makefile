PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all check clean
all:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error bessel-recursion.tex

check:
	$(PYTHON) ../research/bessel-recursion/check_bessel_recursion.py

clean:
	$(LATEXMK) -c bessel-recursion.tex
