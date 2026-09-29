PYTHON ?= python3
LATEXMK ?= latexmk
TABLE_JSON := rule-a-enumeration.json
TABLE_TEX := rule-a-enumeration-table.tex
FIGURE_TEX := fig-whitehead-move.tex fig-two-state-chain.tex \
	fig-loop-change.tex fig-bridge-resolution.tex
FIGURE_PDF := $(FIGURE_TEX:.tex=.pdf)

.PHONY: all figures table arxiv review packages clean

all: arxiv review

figures: $(FIGURE_PDF)

table: $(TABLE_TEX)

$(TABLE_TEX): $(TABLE_JSON) render_rule_a_table.py
	$(PYTHON) render_rule_a_table.py $(TABLE_JSON) $(TABLE_TEX)

fig-%.pdf: fig-%.tex
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error $<

arxiv: $(TABLE_TEX) $(FIGURE_PDF)
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error \
		local-whitehead-chain.tex

review: $(TABLE_TEX) $(FIGURE_PDF)
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error \
		-jobname=local-whitehead-chain-review local-whitehead-chain-review.tex

packages: all
	mkdir -p dist/arxiv/anc
	cp local-whitehead-chain.tex local-whitehead-chain.bib \
		local-whitehead-chain.bbl $(TABLE_TEX) $(FIGURE_PDF) dist/arxiv/
	cp ../gog_generate.py verify_rule_a.py ../build_nauty_bridge.py \
		../gog_nauty_bridge.c render_rule_a_table.py $(TABLE_JSON) \
		dist/arxiv/anc/
	cp REPRODUCIBILITY.md dist/arxiv/anc/README.md
	tar -czf dist/local-whitehead-chain-arxiv.tar.gz -C dist/arxiv \
		local-whitehead-chain.tex local-whitehead-chain.bib \
		local-whitehead-chain.bbl $(TABLE_TEX) $(FIGURE_PDF) \
		anc/README.md anc/gog_generate.py \
		anc/verify_rule_a.py anc/build_nauty_bridge.py \
		anc/gog_nauty_bridge.c anc/render_rule_a_table.py \
		anc/$(TABLE_JSON)
	tar -czf dist/local-whitehead-chain-code.tar.gz -C dist/arxiv anc
	cp local-whitehead-chain-review.pdf \
		dist/local-whitehead-chain-jgaa-review.pdf

clean:
	$(LATEXMK) -c local-whitehead-chain.tex
	$(LATEXMK) -c -jobname=local-whitehead-chain-review \
		local-whitehead-chain-review.tex
	$(LATEXMK) -c $(FIGURE_TEX)
