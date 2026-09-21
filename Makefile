PYTHON ?= python3
LATEXMK ?= latexmk
WOLFRAM_KERNEL ?= /Applications/Wolfram.app/Contents/MacOS/WolframKernel

.PHONY: all check paper computational-notes docs lean python-check \
	notebook-data-check notebook notebook-paclet-check notebook-check \
	computational-notes-notebook computational-notes-notebook-check clean

all: check

check: paper computational-notes docs lean python-check notebook-data-check

paper:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error whitehead-field-dynamics.tex

computational-notes:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error \
		whitehead-field-dynamics-computational-notes.tex

docs:
	$(MAKE) -C docs html SPHINXOPTS="-W --keep-going"

lean:
	cd lean && lake build

python-check:
	$(PYTHON) -m py_compile \
		gog_generate.py gog_ball_growth.py gog_degree_diagnostics.py \
		gog_edge_model_experiments.py gog_support_feature_analysis.py \
		scripts/build_small_gog_models.py

notebook-data-check:
	$(PYTHON) scripts/build_small_gog_models.py --check

notebook:
	"$(WOLFRAM_KERNEL)" -noinit -noprompt -script \
		scripts/build_math_notebook.wls

notebook-paclet-check:
	"$(WOLFRAM_KERNEL)" -noinit -noprompt -script \
		scripts/check_gog_paclet.wls

notebook-check: notebook-data-check notebook-paclet-check
	"$(WOLFRAM_KERNEL)" -noinit -noprompt -script \
		scripts/check_math_notebook.wls

computational-notes-notebook:
	"$(WOLFRAM_KERNEL)" -noinit -noprompt -script \
		scripts/build_computational_notes_notebook.wls

computational-notes-notebook-check: notebook-data-check
	"$(WOLFRAM_KERNEL)" -noinit -noprompt -script \
		scripts/check_computational_notes_notebook.wls

clean:
	$(LATEXMK) -c whitehead-field-dynamics.tex
	$(LATEXMK) -c whitehead-field-dynamics-computational-notes.tex
	$(MAKE) -C docs clean
