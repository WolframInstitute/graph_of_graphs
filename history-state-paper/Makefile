PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all check clean
all:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error history-states.tex

check:
	$(PYTHON) check_history_states.py

clean:
	$(LATEXMK) -c history-states.tex
