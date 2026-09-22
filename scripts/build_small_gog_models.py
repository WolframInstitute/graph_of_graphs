#!/usr/bin/env python3
"""Build the exact small graph-of-graphs data used by the Wolfram article.

The committed resource deliberately contains only quotient-level information:
canonical class codes, simple-support edges, and the integer Rule-A slot-count
matrix.  Concrete carrier rewrites remain the responsibility of
``gog_generate.py`` and its full transition JSON format.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REPOSITORY = Path(__file__).resolve().parents[1]
if str(REPOSITORY) not in sys.path:
    sys.path.insert(0, str(REPOSITORY))

from gog_generate import (  # noqa: E402
    code_to_string,
    generate_graph_of_graph_with_transitions,
    known_vertex_count,
)


DEFAULT_OUTPUT = (
    REPOSITORY
    / "Wolfram"
    / "GogFieldDynamics"
    / "Resources"
    / "Data"
    / "small-models.json"
)
SMALL_SIZES = (2, 4, 6, 8)


def build_model(n: int, backend: str) -> dict[str, Any]:
    nodes, edges, transitions, complete = generate_graph_of_graph_with_transitions(
        n,
        jobs=1,
        backend=backend,
    )
    ordered_nodes = sorted(nodes)
    index = {code: position for position, code in enumerate(ordered_nodes)}
    counts = [[0 for _ in ordered_nodes] for _ in ordered_nodes]
    for transition in transitions:
        counts[index[transition.source]][index[transition.target]] += 1

    expected_nodes = known_vertex_count(n)
    expected_slots = len(ordered_nodes) * 3 * n
    support_edges = {
        tuple(sorted((source, target)))
        for source, row in enumerate(counts)
        for target, multiplicity in enumerate(row)
        if source != target and multiplicity > 0
    }
    indexed_edges = {
        tuple(sorted((index[left], index[right]))) for left, right in edges
    }

    if not complete:
        raise RuntimeError(f"N={n} enumeration unexpectedly stopped early")
    if len(ordered_nodes) != expected_nodes:
        raise RuntimeError(
            f"N={n} has {len(ordered_nodes)} classes, expected {expected_nodes}"
        )
    if len(transitions) != expected_slots:
        raise RuntimeError(
            f"N={n} has {len(transitions)} slots, expected {expected_slots}"
        )
    if any(sum(row) != 3 * n for row in counts):
        raise RuntimeError(f"N={n} Rule-A row sum is not 3N")
    if support_edges != indexed_edges:
        raise RuntimeError(f"N={n} simple support disagrees with positive slots")

    return {
        "N": n,
        "complete": True,
        "edge_count": len(indexed_edges),
        "edges": [list(edge) for edge in sorted(indexed_edges)],
        "expected_node_count_A005967": expected_nodes,
        "expected_rule_a_slot_count": expected_slots,
        "node_count": len(ordered_nodes),
        "nodes": [code_to_string(code) for code in ordered_nodes],
        "rule_a_counts": counts,
        "rule_a_row_sum": 3 * n,
        "rule_a_slot_count": len(transitions),
    }


def build_resource(backend: str) -> dict[str, Any]:
    return {
        "canonical_backend": backend,
        "description": (
            "Complete unlabelled cubic-multigraph quotient models for the "
            "interactive Wolfram article; edge indices are zero-based."
        ),
        "generator": "scripts/build_small_gog_models.py",
        "models": {str(n): build_model(n, backend) for n in SMALL_SIZES},
        "schema_version": 1,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--backend",
        default="python",
        choices=("python", "native", "dreadnaut", "auto"),
        help="canonical-labelling backend (default: deterministic Python fallback)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"resource path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="regenerate in memory and fail unless the committed file is identical",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    data = build_resource(args.backend)
    rendered = json.dumps(data, indent=2, sort_keys=True) + "\n"

    if args.check:
        if not args.output.exists():
            raise SystemExit(f"missing resource: {args.output}")
        if args.output.read_text(encoding="utf-8") != rendered:
            raise SystemExit(
                f"small-model resource is stale; rebuild {args.output}"
            )
        print(f"verified {args.output}")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
