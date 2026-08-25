#!/usr/bin/env python3
"""Diagnose low quotient degree in the graph of graphs.

The main question is whether very small GoG degree is explained by automorphism
folding of Whitehead move slots.  This script compares quotient degree with:

* automorphism group order of the colored incidence graph;
* loop count;
* parallel-edge excess.

It reads the JSON emitted by ``gog_generate.py --save``.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import statistics
import subprocess
from collections import Counter

from gog_generate import (
    _dreadnaut_partition,
    _incidence_graph_for_nauty,
    matrix_from_code,
)


def parse_code(text: str) -> tuple[int, ...]:
    return tuple(int(x) for x in text.split(",") if x)


def quotient_degrees(node_count: int, edges: list[list[int]]) -> list[int]:
    adj = [set() for _ in range(node_count)]
    for a, b in edges:
        if a == b:
            continue
        adj[a].add(b)
        adj[b].add(a)
    return [len(neigh) for neigh in adj]


def automorphism_order(code: tuple[int, ...], n: int) -> int:
    dreadnaut = shutil.which("dreadnaut")
    if dreadnaut is None:
        raise RuntimeError("dreadnaut is required for automorphism diagnostics")

    matrix = matrix_from_code(code, n)
    adjacency, colour_cells = _incidence_graph_for_nauty(matrix)
    lines = [f"n={len(adjacency)} g"]
    for vertex, neighbours in enumerate(adjacency):
        rhs = " ".join(str(v) for v in sorted(neighbours))
        lines.append(f"{vertex}: {rhs};" if rhs else f"{vertex}:;")
    lines.extend([f"f=[{_dreadnaut_partition(colour_cells)}]", "x", "q", ""])
    result = subprocess.run(
        [dreadnaut],
        input="\n".join(lines),
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr)
    match = re.search(r"grpsize=([0-9.eE+-]+)", result.stdout)
    if not match:
        raise RuntimeError(f"could not parse dreadnaut output:\n{result.stdout}")
    value = match.group(1)
    if any(ch in value for ch in ".eE"):
        return int(round(float(value)))
    return int(value)


def loop_and_parallel_excess(code: tuple[int, ...], n: int) -> tuple[int, int]:
    matrix = matrix_from_code(code, n)
    loops = sum(matrix[i][i] for i in range(n))
    parallel_excess = 0
    for i in range(n):
        for j in range(i + 1, n):
            if matrix[i][j] > 1:
                parallel_excess += matrix[i][j] - 1
    return loops, parallel_excess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json_path")
    parser.add_argument("--lowest", type=int, default=20)
    args = parser.parse_args()

    with open(args.json_path, "r", encoding="utf-8") as inp:
        data = json.load(inp)

    n = int(data["N"])
    codes = [parse_code(text) for text in data["nodes"]]
    degrees = quotient_degrees(len(codes), data["edges"])
    aut_orders = [automorphism_order(code, n) for code in codes]
    local_degen = [loop_and_parallel_excess(code, n) for code in codes]

    print(f"N vertices: {n}")
    print(f"node count: {len(codes)}")
    print(f"degree avg/min/max: {statistics.fmean(degrees):.6g}/{min(degrees)}/{max(degrees)}")
    print(f"automorphism order counts: {dict(sorted(Counter(aut_orders).items()))}")
    print()
    print("lowest quotient degrees:")
    print("idx  deg  aut  loops  parallel_excess")
    for idx in sorted(range(len(codes)), key=lambda i: (degrees[i], aut_orders[i], i))[: args.lowest]:
        loops, parallel_excess = local_degen[idx]
        print(f"{idx:4d} {degrees[idx]:4d} {aut_orders[idx]:4d} {loops:6d} {parallel_excess:16d}")

    asymmetric = [i for i, aut in enumerate(aut_orders) if aut == 1]
    if asymmetric:
        asym_degrees = [degrees[i] for i in asymmetric]
        print()
        print(
            "asymmetric degree avg/min/max: "
            f"{statistics.fmean(asym_degrees):.6g}/{min(asym_degrees)}/{max(asym_degrees)}"
        )
        low_asym = sorted(asymmetric, key=lambda i: (degrees[i], i))[: args.lowest]
        print("lowest asymmetric vertices:")
        print("idx  deg  loops  parallel_excess")
        for idx in low_asym:
            loops, parallel_excess = local_degen[idx]
            print(f"{idx:4d} {degrees[idx]:4d} {loops:6d} {parallel_excess:16d}")

    pairs = list(zip(degrees, [math.log(a) if a > 0 else 0.0 for a in aut_orders]))
    mean_d = statistics.fmean(d for d, _ in pairs)
    mean_loga = statistics.fmean(a for _, a in pairs)
    numerator = sum((d - mean_d) * (a - mean_loga) for d, a in pairs)
    denom_d = math.sqrt(sum((d - mean_d) ** 2 for d, _ in pairs))
    denom_a = math.sqrt(sum((a - mean_loga) ** 2 for _, a in pairs))
    if denom_d and denom_a:
        print()
        print(f"corr(degree, log automorphism order): {numerator / (denom_d * denom_a):.6g}")


if __name__ == "__main__":
    main()
