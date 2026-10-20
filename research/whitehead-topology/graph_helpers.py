"""Small exact graph calculations used by the research checks."""

from math import factorial


def automorphism_order(matrix: list[list[int]]) -> int:
    """Full incidence automorphisms, including loop flips and parallel edges."""
    n = len(matrix)
    signatures = [
        (matrix[u][u], tuple(sorted(matrix[u][v] for v in range(n) if v != u)))
        for u in range(n)
    ]
    candidates = [[v for v in range(n) if signatures[v] == signatures[u]] for u in range(n)]
    order = sorted(range(n), key=lambda u: len(candidates[u]))
    assigned: dict[int, int] = {}
    used: set[int] = set()

    def count(k: int) -> int:
        if k == n:
            return 1
        u = order[k]
        total = 0
        for v in candidates[u]:
            if v not in used and all(matrix[u][a] == matrix[v][b] for a, b in assigned.items()):
                assigned[u] = v
                used.add(v)
                total += count(k + 1)
                used.remove(v)
                del assigned[u]
        return total

    result = count(0)
    for u in range(n):
        result *= 2 ** matrix[u][u] * factorial(matrix[u][u])
        for v in range(u + 1, n):
            result *= factorial(matrix[u][v])
    return result


def forest_polynomial_minus_one(matrix: list[list[int]]) -> int:
    """Sum (-1)^|F| over all forests; parallel edges are distinct."""
    n = len(matrix)
    edges = [(u,v) for u in range(n) for v in range(u+1,n) for _ in range(matrix[u][v])]

    def visit(i: int, parents: tuple[int, ...]) -> int:
        if i == len(edges):
            return 1
        total = visit(i + 1, parents)
        u,v = edges[i]
        while parents[u] != u:
            u = parents[u]
        while parents[v] != v:
            v = parents[v]
        if u != v:
            modified = list(parents)
            modified[u] = v
            total -= visit(i + 1, tuple(modified))
        return total

    return visit(0, tuple(range(n)))
