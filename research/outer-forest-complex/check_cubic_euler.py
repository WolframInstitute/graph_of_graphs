#!/usr/bin/env python3
"""Recover the full virtual Euler characteristic as a cubic-chain observable.

For a forest F in a cubic graph G, divide the signed forest sum of G/F by
the number of labelled trivalent refinements of its vertices. This corrects
the multiplicity with which stable graphs occur as cubic contractions.
All arithmetic is exact. The reported variance assumes independent samples;
it does not incorporate autocorrelation of a Whitehead-chain trajectory.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from contextlib import redirect_stdout
from fractions import Fraction as Q
from math import prod
from pathlib import Path
import io
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import gog_generate as gog
from graph_helpers import automorphism_order, forest_polynomial_minus_one
from check_outer_euler import gaussian_euler_coefficients


def odd_double_factorial(n: int) -> int:
    return prod(range(1, n + 1, 2))


def forest_partitions(matrix: list[list[int]]) -> Counter:
    """Count forests by their vertex-component partitions, with distinct edges."""
    n = len(matrix)
    edges = [(u,v) for u in range(n) for v in range(u+1,n)
             for _ in range(matrix[u][v])]
    result = Counter()

    def visit(i: int, parents: tuple[int, ...]):
        def root(x):
            while parents[x] != x:
                x = parents[x]
            return x
        if i == len(edges):
            parts = defaultdict(list)
            for v in range(n):
                parts[root(v)].append(v)
            partition = tuple(sorted(tuple(p) for p in parts.values()))
            result[partition] += 1
            return
        visit(i+1, parents)
        u, v = map(root, edges[i])
        if u != v:
            updated = list(parents)
            updated[u] = v
            visit(i+1, tuple(updated))

    visit(0, tuple(range(n)))
    return result


def contract_partition(matrix: list[list[int]], partition: tuple) -> list[list[int]]:
    images = {v:i for i, part in enumerate(partition) for v in part}
    result = [[0] * len(partition) for _ in partition]
    for u, v in gog.edges_from_matrix(matrix):
        a, b = images[u], images[v]
        result[a][b] += 1
        if a != b:
            result[b][a] += 1
    for i, part in enumerate(partition):
        result[i][i] -= len(part) - 1
        assert result[i][i] >= 0
        assert sum(result[i]) + result[i][i] == len(part) + 2
    return result


def check(rank: int, backend: str, expected: Q) -> dict:
    n = 2*rank - 2
    with redirect_stdout(io.StringIO()):
        nodes, _, _, complete = gog.generate_graph_of_graph_with_transitions(n, jobs=1, backend=backend)
    assert complete and len(nodes) == gog.known_vertex_count(n)
    graphs = {code: gog.matrix_from_code(code, n) for code in sorted(nodes)}
    weights = {code: Q(1, automorphism_order(matrix)) for code, matrix in graphs.items()}
    total_weight = sum(weights.values(), Q(0))
    stable = {}
    refinement_weights = defaultdict(Q)
    first = second = Q(0)
    forests_checked = 0
    graph_rows = []
    for code, matrix in graphs.items():
        observable = Q(0)
        partitions = forest_partitions(matrix)
        for partition, multiplicity in partitions.items():
            contracted = contract_partition(matrix, partition)
            stable_code = (len(contracted), gog.canonical_code_from_matrix(contracted, backend=backend))
            refinements = prod(odd_double_factorial(2*len(part)-1) for part in partition)
            if stable_code not in stable:
                degrees = [sum(row) + row[i] for i, row in enumerate(contracted)]
                assert refinements == prod(odd_double_factorial(2*d-5) for d in degrees)
                stable[stable_code] = (forest_polynomial_minus_one(contracted),
                                       automorphism_order(contracted), refinements)
            forest_sum, _, same_refinements = stable[stable_code]
            assert refinements == same_refinements
            observable += Q(multiplicity * forest_sum, refinements)
            refinement_weights[stable_code] += multiplicity * weights[code]
            forests_checked += multiplicity
        first += weights[code] * observable
        second += weights[code] * observable**2
        graph_rows.append({'code': list(code), 'automorphism_order': weights[code].denominator,
                           'Euler_observable': str(observable),
                           'forests': sum(partitions.values())})
    for code, (_, aut, refinements) in stable.items():
        assert refinement_weights[code] == Q(refinements, aut), (rank, code)
    assert first == expected, (rank, first, expected)
    mean = first / total_weight
    variance = second / total_weight - mean**2
    relative_variance = variance / mean**2
    print(f'rank {rank}: chi={first}; {forests_checked} forests; '
          f'independent-sample relative variance={float(relative_variance):.5g}', flush=True)
    return {'rank': rank, 'cubic_vertices': n, 'cubic_classes': len(nodes),
            'stable_types_recovered': len(stable), 'forests_checked': forests_checked,
            'cubic_symmetry_weight': str(total_weight), 'virtual_euler_characteristic': str(first),
            'Euler_observable_mean': str(mean), 'Euler_observable_variance': str(variance),
            'independent_sample_relative_variance': str(relative_variance),
            'graphs': graph_rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--max-rank', type=int, default=5)
    parser.add_argument('--backend', choices=['native', 'python'], default='native')
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    if args.max_rank < 2:
        parser.error('--max-rank must be at least 2')
    expected = gaussian_euler_coefficients(args.max_rank)
    result = {'method': 'cubic refinements and forest multiplicity correction; exact rationals',
              'variance_scope': 'independent stationary samples, without Markov-chain autocorrelation',
              'results': [check(r, args.backend, expected[r-1]) for r in range(2,args.max_rank+1)]}
    if args.json:
        args.json.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
