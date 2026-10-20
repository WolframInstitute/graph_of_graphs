PYTHON ?= python3
LATEXMK ?= latexmk
WOLFRAM_KERNEL ?= /Applications/Wolfram.app/Contents/MacOS/WolframKernel

.PHONY: all check paper computational-notes docs lean python-check \
	notebook-data-check notebook notebook-paclet-check notebook-check \
	computational-notes-notebook computational-notes-notebook-check \
	rule-a-paper rule-a-paper-packages integral-torsor integral-torsor-check \
	straight-cycle-paper straight-cycle-check tanasa-check graph-local-check \
	outer-forest-check tanasa-scheme-check tanasa-sampler-check sextic-sd-check \
	matrix-resurgence-check clean

all: check

check: paper rule-a-paper computational-notes docs lean python-check notebook-data-check

paper:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error whitehead-field-dynamics.tex

computational-notes:
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error \
		whitehead-field-dynamics-computational-notes.tex

rule-a-paper:
	$(MAKE) -C rule-a-paper all

rule-a-paper-packages:
	$(MAKE) -C rule-a-paper packages

integral-torsor:
	$(MAKE) -C integral-torsor-paper all

integral-torsor-check:
	$(MAKE) -C integral-torsor-paper check

straight-cycle-paper:
	$(MAKE) -C straight-cycle-paper all

straight-cycle-check:
	$(MAKE) -C straight-cycle-paper check

graph-local-check:
	$(PYTHON) research/graph-local-periods/check_local_bounds.py --nodes 16

outer-forest-check:
	$(PYTHON) research/outer-forest-complex/check_forested_complex.py --max-rank 4
	$(PYTHON) research/outer-forest-complex/check_witness.py
	$(PYTHON) research/outer-forest-complex/check_backends.py

tanasa-scheme-check:
	$(PYTHON) research/tanasa-schemes/check_chain_schemes.py \
		--max-pairs 3 --word-length 8

tanasa-sampler-check:
	$(PYTHON) research/tanasa-schemes/check_decoration_sampler.py \
		--max-pairs 3 --walk-steps 300

sextic-sd-check:
	$(PYTHON) research/sextic-sd/check_sextic_sd.py

matrix-resurgence-check:
	$(PYTHON) research/matrix-resurgence/check_seed_transport.py

tanasa-check:
	$(PYTHON) research/whitehead-topology/check_tanasa_bipartite.py \
		--max-pairs 3 --switches \
		--json research/whitehead-topology/tanasa-bipartite.json

docs:
	$(MAKE) -C docs html SPHINXOPTS="-W --keep-going"

lean:
	cd lean && lake build

python-check:
	$(PYTHON) -m py_compile \
		gog_generate.py gog_ball_growth.py gog_degree_diagnostics.py \
		gog_edge_model_experiments.py gog_support_feature_analysis.py \
		scripts/build_small_gog_models.py rule-a-paper/verify_rule_a.py \
		rule-a-paper/render_rule_a_table.py

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
	$(MAKE) -C rule-a-paper clean
	$(MAKE) -C docs clean
