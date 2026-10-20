"""Exact quartic Wick coefficients used by the manuscript checks.

Enumerate all pairings of labelled quartic incidences and count connected
components and ribbon faces independently of the moment determinant.
"""
from collections import Counter
from math import prod


def permutation_cycles(permutation):
    seen = set()
    result = []
    for start in range(len(permutation)):
        if start in seen:
            continue
        cycle = []
        current = start
        while current not in seen:
            seen.add(current)
            cycle.append(current)
            current = permutation[current]
        result.append(tuple(cycle))
    return result


def moments_by_topology(vertices):
    """Count pairings by (components, total genus, ribbon faces)."""
    size = 4 * vertices
    pairing = [-1] * size
    rotation = tuple(4 * (d // 4) + (d + 1) % 4 for d in range(size))
    result = Counter()

    def visit(unpaired):
        if not unpaired:
            parents = list(range(vertices))

            def root(vertex):
                while parents[vertex] != vertex:
                    vertex = parents[vertex]
                return vertex

            for incidence in range(size):
                parents[root(incidence // 4)] = root(pairing[incidence] // 4)
            components = len({root(v) for v in range(vertices)})
            faces = len(permutation_cycles(tuple(rotation[pairing[d]] for d in range(size))))
            assert (vertices - faces) % 2 == 0
            genus = components + (vertices - faces) // 2
            assert genus >= 0
            result[components, genus, faces] += 1
            return
        first = unpaired[0]
        for index in range(1, len(unpaired)):
            second = unpaired[index]
            pairing[first], pairing[second] = second, first
            visit(unpaired[1:index] + unpaired[index + 1:])

    visit(tuple(range(size)))
    assert sum(result.values()) == prod(range(1, size, 2))
    return result
