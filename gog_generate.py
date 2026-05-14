#!/usr/bin/env python3
"""Generate the graph-of-graphs of cubic multigraphs under Whitehead moves.

This is deliberately independent of Sage.  By default, canonical labelling is
delegated to Brendan McKay's nauty/Traces through ``dreadnaut``.  Loops and
multiple edges are encoded as a coloured simple incidence graph:

* original vertices form one colour class;
* non-loop edge objects form a second colour class;
* loop edge objects form a third colour class.

The canonical order of the original-vertex colour class gives a canonical
upper-triangular adjacency code for the cubic multigraph.  This is the path
intended for McKay-scale computations.  A pure-Python colour-refinement fallback
is kept under ``--backend python`` only for debugging or machines without nauty.

Loops and multiple edges are allowed.  A loop contributes two to the degree.
Whitehead moves are generated in the half-edge model: a non-loop edge uv is
chosen, the two other incident stubs at u and v are redistributed in the two
unlabelled resolutions, and the result is canonicalized.
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import re
import shutil
import subprocess
from collections import defaultdict, deque
from typing import Dict, Iterable, Iterator, List, Sequence, Set, Tuple

try:  # The user's older code used the third-party multiprocess package.
    from multiprocess import Pool
except ImportError:  # Fall back to the standard library.
    from multiprocessing import Pool


Edge = Tuple[int, int]
Code = Tuple[int, ...]
Matrix = List[List[int]]

DEFAULT_BACKEND = "auto"
DEFAULT_NAUTY_MODE = "traces"

# OEIS A005967: number of isomorphism classes of connected 3-regular
# multigraphs of order 2n, loops allowed.
A005967_BY_HALF_ORDER: Dict[int, int] = {
    1: 2,
    2: 5,
    3: 17,
    4: 71,
    5: 388,
    6: 2592,
    7: 21096,
    8: 204638,
    9: 2317172,
    10: 30024276,
    11: 437469859,
    12: 7067109598,
    13: 125184509147,
    14: 2410455693765,
    15: 50101933643655,
    16: 1117669367609605,
    17: 26629298567576331,
    18: 674793598023809924,
    19: 18119844622209998036,
}


def known_vertex_count(n: int) -> int | None:
    if n % 2:
        return None
    return A005967_BY_HALF_ORDER.get(n // 2)


def initial_cubic_edges(n: int) -> List[Edge]:
    """Return a connected cubic multigraph with loops and double edges.

    For n >= 4 this is a path with loops on the two endpoints and one extra
    parallel edge on every other path edge:

        loop--0--1==2--3==4-- ... --n-2--n-1--loop

    The graph is cubic because loops count twice.  For n=2 we use the unique
    connected cubic multigraph on two vertices, namely three parallel edges.
    """

    if n < 2 or n % 2:
        raise ValueError("A cubic graph has an even number of vertices.")
    if n == 2:
        return [(0, 1), (0, 1), (0, 1)]

    edges: List[Edge] = [(i, i + 1) for i in range(n - 1)]
    edges.extend([(0, 0), (n - 1, n - 1)])
    edges.extend((i, i + 1) for i in range(1, n - 2, 2))
    return edges


def matrix_from_edges(n: int, edges: Iterable[Edge]) -> Matrix:
    matrix = [[0 for _ in range(n)] for _ in range(n)]
    for u, v in edges:
        if not (0 <= u < n and 0 <= v < n):
            raise ValueError(f"edge {(u, v)} is outside the vertex set")
        if u == v:
            matrix[u][u] += 1
        else:
            a, b = sorted((u, v))
            matrix[a][b] += 1
            matrix[b][a] += 1
    return matrix


def edges_from_matrix(matrix: Matrix) -> List[Edge]:
    n = len(matrix)
    edges: List[Edge] = []
    for i in range(n):
        edges.extend((i, i) for _ in range(matrix[i][i]))
        for j in range(i + 1, n):
            edges.extend((i, j) for _ in range(matrix[i][j]))
    return edges


def code_from_matrix(matrix: Matrix, order: Sequence[int] | None = None) -> Code:
    n = len(matrix)
    if order is None:
        order = tuple(range(n))
    code: List[int] = []
    for a in range(n):
        i = order[a]
        for b in range(a, n):
            j = order[b]
            code.append(matrix[i][j])
    return tuple(code)


def matrix_from_code(code: Code, n: int) -> Matrix:
    expected = n * (n + 1) // 2
    if len(code) != expected:
        raise ValueError(f"code length {len(code)} does not match n={n}")
    matrix = [[0 for _ in range(n)] for _ in range(n)]
    k = 0
    for i in range(n):
        for j in range(i, n):
            matrix[i][j] = code[k]
            matrix[j][i] = code[k]
            k += 1
    return matrix


def degrees(matrix: Matrix) -> List[int]:
    n = len(matrix)
    return [
        2 * matrix[i][i] + sum(matrix[i][j] for j in range(n) if j != i)
        for i in range(n)
    ]


def is_connected(matrix: Matrix) -> bool:
    n = len(matrix)
    seen = {0}
    queue: deque[int] = deque([0])
    while queue:
        i = queue.popleft()
        for j in range(n):
            if i != j and matrix[i][j] and j not in seen:
                seen.add(j)
                queue.append(j)
    return len(seen) == n


def validate_cubic_connected(matrix: Matrix) -> None:
    deg = degrees(matrix)
    if any(d != 3 for d in deg):
        raise ValueError(f"not cubic: degrees are {deg}")
    if not is_connected(matrix):
        raise ValueError("graph is not connected")


def fallback_color_classes(matrix: Matrix) -> List[List[int]]:
    """Colour-refinement classes used only by the pure-Python fallback."""

    n = len(matrix)
    initial = [(matrix[i][i], degrees(matrix)[i]) for i in range(n)]
    initial_palette = {sig: rank for rank, sig in enumerate(sorted(set(initial)))}
    colors = tuple(initial_palette[sig] for sig in initial)
    while True:
        signatures = []
        for i in range(n):
            neigh = []
            for j in range(n):
                if i != j and matrix[i][j]:
                    neigh.append((colors[j], matrix[i][j]))
            signatures.append((colors[i], matrix[i][i], tuple(sorted(neigh))))

        palette = {sig: rank for rank, sig in enumerate(sorted(set(signatures)))}
        new_colors = tuple(palette[sig] for sig in signatures)
        if new_colors == colors:
            break
        colors = new_colors

    classes_by_color: Dict[int, List[int]] = defaultdict(list)
    for vertex, color in enumerate(colors):
        classes_by_color[color].append(vertex)
    return [classes_by_color[color] for color in sorted(classes_by_color)]


def python_canonical_code_from_matrix(matrix: Matrix) -> Code:
    """Return an exact fallback isomorphism-invariant code.

    The returned tuple is the lexicographically smallest upper-triangular code
    among permutations that preserve the final color-refinement classes.  This
    is a canonical certificate: every isomorphism preserves the color classes,
    and all residual ambiguity inside them is exhaustively enumerated.

    This is not the production backend.  It can become factorial on symmetric
    inputs and is kept only as a Sage-free fallback when nauty is unavailable.
    """

    classes = fallback_color_classes(matrix)
    permutation_blocks = [itertools.permutations(cls) for cls in classes]
    best: Code | None = None
    for choice in itertools.product(*permutation_blocks):
        order = tuple(v for block in choice for v in block)
        code = code_from_matrix(matrix, order)
        if best is None or code < best:
            best = code
    assert best is not None
    return best


def nauty_available() -> bool:
    return shutil.which("dreadnaut") is not None


def _incidence_graph_for_nauty(matrix: Matrix) -> Tuple[List[Set[int]], List[List[int]]]:
    """Encode a cubic multigraph as a coloured simple incidence graph."""

    n = len(matrix)
    nonloop_edges: List[Edge] = []
    loop_edges: List[Edge] = []
    for i in range(n):
        loop_edges.extend((i, i) for _ in range(matrix[i][i]))
        for j in range(i + 1, n):
            nonloop_edges.extend((i, j) for _ in range(matrix[i][j]))

    total = n + len(nonloop_edges) + len(loop_edges)
    adjacency: List[Set[int]] = [set() for _ in range(total)]

    next_edge_node = n
    for u, v in nonloop_edges:
        edge_node = next_edge_node
        next_edge_node += 1
        adjacency[edge_node].update((u, v))
        adjacency[u].add(edge_node)
        adjacency[v].add(edge_node)

    loop_start = next_edge_node
    for (u, _) in loop_edges:
        edge_node = next_edge_node
        next_edge_node += 1
        adjacency[edge_node].add(u)
        adjacency[u].add(edge_node)

    colour_cells = [list(range(n))]
    if nonloop_edges:
        colour_cells.append(list(range(n, loop_start)))
    if loop_edges:
        colour_cells.append(list(range(loop_start, total)))

    return adjacency, colour_cells


def _dreadnaut_partition(cells: Sequence[Sequence[int]]) -> str:
    return "|".join(",".join(str(v) for v in cell) for cell in cells if cell)


def _dreadnaut_mode_command(mode: str) -> str:
    if mode == "dense":
        return "An"
    if mode == "sparse":
        return "As"
    if mode == "traces":
        return "At"
    raise ValueError(f"unknown nauty mode: {mode}")


def _parse_dreadnaut_mapping(output: str, total: int) -> List[int]:
    mapping_re = re.compile(r"^\s*(?:\d+\s+){" + str(total - 1) + r"}\d+\s*$")
    for line in output.splitlines():
        if mapping_re.match(line):
            mapping = [int(x) for x in line.split()]
            if len(mapping) == total:
                return mapping
    raise RuntimeError(f"could not parse dreadnaut canonical mapping:\n{output}")


def nauty_canonical_code_from_matrix(
    matrix: Matrix,
    mode: str = DEFAULT_NAUTY_MODE,
) -> Code:
    """Canonical code using nauty/Traces on a coloured incidence graph.

    The returned code is still the upper-triangular adjacency tuple of the
    original multigraph.  The order of original vertices is obtained from
    nauty's canonical labelling of the first colour class.
    """

    dreadnaut = shutil.which("dreadnaut")
    if dreadnaut is None:
        raise RuntimeError("dreadnaut is not installed; install nauty or use --backend python")

    adjacency, colour_cells = _incidence_graph_for_nauty(matrix)
    total = len(adjacency)
    n = len(matrix)

    lines = [
        _dreadnaut_mode_command(mode),
        f"n={total} -a -m +c g",
    ]
    for vertex, neighbours in enumerate(adjacency):
        if neighbours:
            rhs = " ".join(str(v) for v in sorted(neighbours))
            lines.append(f"{vertex}: {rhs};")
        else:
            lines.append(f"{vertex}:;")
    lines.extend(
        [
            f"f=[{_dreadnaut_partition(colour_cells)}]",
            "x",
            "b",
            "q",
            "",
        ]
    )
    script = "\n".join(lines)
    result = subprocess.run(
        [dreadnaut],
        input=script,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "dreadnaut failed\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    canonical_to_old = _parse_dreadnaut_mapping(result.stdout, total)
    original_order = canonical_to_old[:n]
    if sorted(original_order) != list(range(n)):
        raise RuntimeError(
            "nauty colour partition did not keep original vertices in the first cell:\n"
            f"mapping={canonical_to_old}\noutput:\n{result.stdout}"
        )
    return code_from_matrix(matrix, original_order)


def canonical_code_from_matrix(
    matrix: Matrix,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Code:
    if backend not in {"auto", "nauty", "python"}:
        raise ValueError("backend must be one of: auto, nauty, python")
    if backend == "python":
        return python_canonical_code_from_matrix(matrix)
    if backend == "nauty":
        return nauty_canonical_code_from_matrix(matrix, nauty_mode)
    if nauty_available():
        return nauty_canonical_code_from_matrix(matrix, nauty_mode)
    return python_canonical_code_from_matrix(matrix)


def canonical_code_from_edges(
    n: int,
    edges: Iterable[Edge],
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Code:
    matrix = matrix_from_edges(n, edges)
    validate_cubic_connected(matrix)
    return canonical_code_from_matrix(matrix, backend, nauty_mode)


def _stubs_from_edges(edges: Sequence[Edge]) -> Tuple[List[int], List[Tuple[int, int]]]:
    stub_vertex: List[int] = []
    edge_stubs: List[Tuple[int, int]] = []
    for u, v in edges:
        s0 = len(stub_vertex)
        stub_vertex.append(u)
        s1 = len(stub_vertex)
        stub_vertex.append(v)
        edge_stubs.append((s0, s1))
    return stub_vertex, edge_stubs


def _edges_from_stubs(
    stub_vertex: Sequence[int],
    edge_stubs: Sequence[Tuple[int, int]],
) -> List[Edge]:
    edges = []
    for s0, s1 in edge_stubs:
        u, v = stub_vertex[s0], stub_vertex[s1]
        edges.append((u, v) if u <= v else (v, u))
    return edges


def whitehead_neighbors(
    code: Code,
    n: int,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Set[Code]:
    """Return canonical neighbours obtained by unlabelled Whitehead moves."""

    matrix = matrix_from_code(code, n)
    edges = edges_from_matrix(matrix)
    stub_vertex, edge_stubs = _stubs_from_edges(edges)

    incident: Dict[int, List[int]] = defaultdict(list)
    for stub, vertex in enumerate(stub_vertex):
        incident[vertex].append(stub)

    neighbours: Set[Code] = set()
    for edge_id, (su, sv) in enumerate(edge_stubs):
        u, v = stub_vertex[su], stub_vertex[sv]
        if u == v:
            continue

        u_other = [s for s in incident[u] if s != su]
        v_other = [s for s in incident[v] if s != sv]
        if len(u_other) != 2 or len(v_other) != 2:
            raise ValueError("the half-edge incidence is not cubic")

        # The two unlabelled resolutions.  The two missing labelled resolutions
        # are obtained by swapping u and v, hence give the same isomorphism
        # classes after canonicalization.
        resolutions = (
            ((u_other[0], v_other[0]), (u_other[1], v_other[1])),
            ((u_other[0], v_other[1]), (u_other[1], v_other[0])),
        )

        for u_pair, v_pair in resolutions:
            new_stub_vertex = list(stub_vertex)
            new_stub_vertex[su] = u
            new_stub_vertex[sv] = v
            for stub in u_pair:
                new_stub_vertex[stub] = u
            for stub in v_pair:
                new_stub_vertex[stub] = v

            new_edges = _edges_from_stubs(new_stub_vertex, edge_stubs)
            new_matrix = matrix_from_edges(n, new_edges)
            validate_cubic_connected(new_matrix)
            neighbours.add(canonical_code_from_matrix(new_matrix, backend, nauty_mode))

    return neighbours


def initial_code(
    n: int,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Code:
    return canonical_code_from_edges(n, initial_cubic_edges(n), backend, nauty_mode)


def _expand_worker(args: Tuple[Code, int, str, str]) -> Set[Code]:
    code, n, backend, nauty_mode = args
    return whitehead_neighbors(code, n, backend, nauty_mode)


def _edge_key(a: Code, b: Code) -> Tuple[Code, Code]:
    return (a, b) if a <= b else (b, a)


def generate_graph_of_graph(
    n: int,
    jobs: int | None = None,
    max_classes: int | None = None,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Tuple[Set[Code], Set[Tuple[Code, Code]], bool]:
    """Breadth-first generation from the standard initial graph.

    Filtering of already stored classes is done in the parent process.  Workers
    are stateless: they receive one canonical code and return its canonical
    neighbours.
    """

    start = initial_code(n, backend, nauty_mode)
    stored: Set[Code] = {start}
    frontier: Set[Code] = {start}
    gog_edges: Set[Tuple[Code, Code]] = set()
    complete = True

    print("Stored | Frontier | New | GoG edges")

    def handle_results(frontier_list: List[Code], results: List[Set[Code]]) -> None:
        nonlocal stored, frontier, gog_edges, complete
        generated: Set[Code] = set().union(*results) if results else set()
        new = generated - stored
        if max_classes is not None and len(stored) + len(new) > max_classes:
            quota = max(0, max_classes - len(stored))
            new = set(sorted(new)[:quota])
            complete = False

        allowed = stored | new
        for source, neighbours in zip(frontier_list, results):
            for target in neighbours:
                if target != source and target in allowed:
                    gog_edges.add(_edge_key(source, target))

        print(f"{len(stored):6d} | {len(frontier):8d} | {len(new):3d} | {len(gog_edges):9d}")
        stored.update(new)
        frontier = new

    if jobs == 1:
        while frontier:
            frontier_list = sorted(frontier)
            results = [_expand_worker((code, n, backend, nauty_mode)) for code in frontier_list]
            handle_results(frontier_list, results)
            if not complete:
                break
    else:
        with Pool(processes=jobs) as pool:
            while frontier:
                frontier_list = sorted(frontier)
                results = pool.map(
                    _expand_worker,
                    [(code, n, backend, nauty_mode) for code in frontier_list],
                )
                handle_results(frontier_list, results)
                if not complete:
                    break

    return stored, gog_edges, complete


def code_to_string(code: Code) -> str:
    return ",".join(str(x) for x in code)


def save_json(
    path: str,
    n: int,
    nodes: Set[Code],
    edges: Set[Tuple[Code, Code]],
    complete: bool,
) -> None:
    ordered_nodes = sorted(nodes)
    index = {code: i for i, code in enumerate(ordered_nodes)}
    data = {
        "N": n,
        "complete": complete,
        "expected_node_count_A005967": known_vertex_count(n),
        "node_count": len(ordered_nodes),
        "edge_count": len(edges),
        "nodes": [code_to_string(code) for code in ordered_nodes],
        "edges": [
            [index[a], index[b]]
            for a, b in sorted(edges)
            if a in index and b in index
        ],
    }
    with open(path, "w", encoding="utf-8") as out:
        json.dump(data, out, indent=2, sort_keys=True)
        out.write("\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("N", type=int, help="number of vertices, necessarily even")
    parser.add_argument(
        "--jobs",
        type=int,
        default=None,
        help="worker count; use 1 for deterministic single-process debugging",
    )
    parser.add_argument(
        "--max-classes",
        type=int,
        default=None,
        help="stop after this many isomorphism classes; output is then partial",
    )
    parser.add_argument(
        "--backend",
        choices=("auto", "nauty", "python"),
        default=DEFAULT_BACKEND,
        help="canonical labelling backend; auto uses nauty/Traces when available",
    )
    parser.add_argument(
        "--nauty-mode",
        choices=("dense", "sparse", "traces"),
        default=DEFAULT_NAUTY_MODE,
        help="dreadnaut engine used by the nauty backend",
    )
    parser.add_argument("--save", help="write the generated GoG as JSON")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    nodes, edges, complete = generate_graph_of_graph(
        args.N,
        jobs=args.jobs,
        max_classes=args.max_classes,
        backend=args.backend,
        nauty_mode=args.nauty_mode,
    )
    status = "complete" if complete else "partial"
    print(f"{status}: {len(nodes)} classes, {len(edges)} GoG edges")
    expected = known_vertex_count(args.N)
    if expected is not None:
        verdict = "OK" if complete and len(nodes) == expected else "partial/not checked"
        if complete and len(nodes) != expected:
            verdict = "MISMATCH"
        print(f"A005967 expected classes for N={args.N}: {expected} ({verdict})")
    if args.save:
        save_json(args.save, args.N, nodes, edges, complete)
        print(f"wrote {args.save}")


if __name__ == "__main__":
    main()
