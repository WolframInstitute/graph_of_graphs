#!/usr/bin/env python3
"""Generate the graph-of-graphs of cubic multigraphs under Whitehead moves.

This is deliberately independent of Sage.  By default, canonical labelling is
delegated to Brendan McKay's nauty/Traces, preferably through the in-process
native bridge and otherwise through ``dreadnaut``.  Loops and multiple edges are
encoded as a coloured simple incidence graph:

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
import ctypes
import itertools
import json
import math
import os
import re
import shutil
import subprocess
from collections import defaultdict, deque
from dataclasses import dataclass
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
NATIVE_BRIDGE_BASENAMES = (
    "gog_nauty_bridge.dylib",
    "gog_nauty_bridge.so",
)


@dataclass(frozen=True)
class Transition:
    """Concrete Whitehead transition data.

    ``canonical_order`` maps target canonical coordinates to raw target vertex
    coordinates, which are still the source canonical coordinates immediately
    after the local graph rewrite.  Thus a settled target field is obtained by
    ``f_target[a] = f_raw[canonical_order[a]]``.
    """

    source: Code
    target: Code
    edge_id: int
    source_edge: Edge
    resolution_id: int
    averaged_endpoints: Edge
    canonical_order: Tuple[int, ...]
    raw_to_canonical: Tuple[int, ...]
    trivial_loop: bool = False

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
    code, _order = python_canonical_code_and_order_from_matrix(matrix)
    return code


def python_canonical_code_and_order_from_matrix(matrix: Matrix) -> Tuple[Code, Tuple[int, ...]]:
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
    best_order: Tuple[int, ...] | None = None
    for choice in itertools.product(*permutation_blocks):
        order = tuple(v for block in choice for v in block)
        code = code_from_matrix(matrix, order)
        if best is None or code < best:
            best = code
            best_order = order
    assert best is not None
    assert best_order is not None
    return best, best_order


def nauty_available() -> bool:
    return shutil.which("dreadnaut") is not None


_native_bridge: ctypes.CDLL | None = None
_native_bridge_error: str | None = None


def _native_bridge_candidates() -> Iterator[str]:
    override = os.environ.get("GOG_NAUTY_BRIDGE")
    if override:
        yield override
    here = os.path.dirname(os.path.abspath(__file__))
    for basename in NATIVE_BRIDGE_BASENAMES:
        yield os.path.join(here, basename)


def _load_native_bridge() -> ctypes.CDLL:
    global _native_bridge, _native_bridge_error
    if _native_bridge is not None:
        return _native_bridge

    errors: List[str] = []
    for path in _native_bridge_candidates():
        if not os.path.exists(path):
            continue
        try:
            lib = ctypes.CDLL(path)
            lib.gog_nauty_bridge_version.argtypes = []
            lib.gog_nauty_bridge_version.restype = ctypes.c_int
            lib.gog_canonicalize_traces.argtypes = [
                ctypes.c_int,
                ctypes.POINTER(ctypes.c_int),
                ctypes.c_int,
                ctypes.POINTER(ctypes.c_int),
                ctypes.POINTER(ctypes.c_int),
                ctypes.c_char_p,
                ctypes.c_size_t,
            ]
            lib.gog_canonicalize_traces.restype = ctypes.c_int
            if lib.gog_nauty_bridge_version() != 1:
                raise RuntimeError("unsupported native bridge ABI version")
            _native_bridge = lib
            _native_bridge_error = None
            return lib
        except OSError as exc:
            errors.append(f"{path}: {exc}")
        except RuntimeError as exc:
            errors.append(f"{path}: {exc}")

    _native_bridge_error = "; ".join(errors) if errors else "native bridge library not found"
    raise RuntimeError(_native_bridge_error)


def native_bridge_available() -> bool:
    try:
        _load_native_bridge()
        return True
    except RuntimeError:
        return False


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
    code, _order = nauty_canonical_code_and_order_from_matrix(matrix, mode)
    return code


def nauty_canonical_code_and_order_from_matrix(
    matrix: Matrix,
    mode: str = DEFAULT_NAUTY_MODE,
) -> Tuple[Code, Tuple[int, ...]]:
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
    order = tuple(original_order)
    return code_from_matrix(matrix, order), order


def native_canonical_code_and_order_from_matrix(matrix: Matrix) -> Tuple[Code, Tuple[int, ...]]:
    """Canonical code via the in-process nauty/Traces bridge."""

    lib = _load_native_bridge()
    n = len(matrix)
    code = code_from_matrix(matrix)
    code_array = (ctypes.c_int * len(code))(*code)
    out_code = (ctypes.c_int * len(code))()
    out_order = (ctypes.c_int * n)()
    err = ctypes.create_string_buffer(4096)

    rc = lib.gog_canonicalize_traces(
        n,
        code_array,
        len(code),
        out_code,
        out_order,
        err,
        len(err),
    )
    if rc != 0:
        message = err.value.decode("utf-8", errors="replace") or "native bridge failed"
        raise RuntimeError(message)
    return tuple(out_code), tuple(out_order)


def native_canonical_code_from_matrix(matrix: Matrix) -> Code:
    code, _order = native_canonical_code_and_order_from_matrix(matrix)
    return code


def canonical_code_and_order_from_matrix(
    matrix: Matrix,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Tuple[Code, Tuple[int, ...]]:
    if backend not in {"auto", "native", "nauty", "python"}:
        raise ValueError("backend must be one of: auto, native, nauty, python")
    if backend == "native":
        return native_canonical_code_and_order_from_matrix(matrix)
    if backend == "python":
        return python_canonical_code_and_order_from_matrix(matrix)
    if backend == "nauty":
        return nauty_canonical_code_and_order_from_matrix(matrix, nauty_mode)
    if native_bridge_available():
        return native_canonical_code_and_order_from_matrix(matrix)
    if nauty_available():
        return nauty_canonical_code_and_order_from_matrix(matrix, nauty_mode)
    return python_canonical_code_and_order_from_matrix(matrix)


def canonical_code_from_matrix(
    matrix: Matrix,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Code:
    code, _order = canonical_code_and_order_from_matrix(matrix, backend, nauty_mode)
    return code


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


def _inverse_order(order: Sequence[int]) -> Tuple[int, ...]:
    inverse = [0] * len(order)
    for canonical_index, raw_index in enumerate(order):
        inverse[raw_index] = canonical_index
    return tuple(inverse)


def whitehead_transitions(
    code: Code,
    n: int,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
    include_trivial_loops: bool = True,
) -> List[Transition]:
    """Return concrete Whitehead transition records from one canonical class."""

    matrix = matrix_from_code(code, n)
    edges = edges_from_matrix(matrix)
    stub_vertex, edge_stubs = _stubs_from_edges(edges)

    incident: Dict[int, List[int]] = defaultdict(list)
    for stub, vertex in enumerate(stub_vertex):
        incident[vertex].append(stub)

    transitions: List[Transition] = []
    identity_order = tuple(range(n))
    for edge_id, (su, sv) in enumerate(edge_stubs):
        u, v = stub_vertex[su], stub_vertex[sv]
        source_edge = (u, v) if u <= v else (v, u)
        if u == v:
            if include_trivial_loops:
                for resolution_id in (0, 1):
                    transitions.append(
                        Transition(
                            source=code,
                            target=code,
                            edge_id=edge_id,
                            source_edge=source_edge,
                            resolution_id=resolution_id,
                            averaged_endpoints=source_edge,
                            canonical_order=identity_order,
                            raw_to_canonical=identity_order,
                            trivial_loop=True,
                        )
                    )
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

        for resolution_id, (u_pair, v_pair) in enumerate(resolutions):
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
            target_code, order = canonical_code_and_order_from_matrix(
                new_matrix,
                backend,
                nauty_mode,
            )
            transitions.append(
                Transition(
                    source=code,
                    target=target_code,
                    edge_id=edge_id,
                    source_edge=source_edge,
                    resolution_id=resolution_id,
                    averaged_endpoints=source_edge,
                    canonical_order=order,
                    raw_to_canonical=_inverse_order(order),
                )
            )

    return transitions


def whitehead_neighbors(
    code: Code,
    n: int,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Set[Code]:
    """Return canonical neighbours obtained by unlabelled Whitehead moves."""
    transitions = whitehead_transitions(
        code,
        n,
        backend,
        nauty_mode,
        include_trivial_loops=False,
    )
    return {transition.target for transition in transitions}


def initial_code(
    n: int,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Code:
    return canonical_code_from_edges(n, initial_cubic_edges(n), backend, nauty_mode)


def _expand_worker(args: Tuple[Code, int, str, str]) -> Set[Code]:
    code, n, backend, nauty_mode = args
    return whitehead_neighbors(code, n, backend, nauty_mode)


def _expand_transition_worker(args: Tuple[Code, int, str, str]) -> List[Transition]:
    code, n, backend, nauty_mode = args
    return whitehead_transitions(code, n, backend, nauty_mode)


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


def generate_graph_of_graph_with_transitions(
    n: int,
    jobs: int | None = None,
    max_classes: int | None = None,
    backend: str = DEFAULT_BACKEND,
    nauty_mode: str = DEFAULT_NAUTY_MODE,
) -> Tuple[Set[Code], Set[Tuple[Code, Code]], List[Transition], bool]:
    """Breadth-first generation, preserving concrete transition records."""

    start = initial_code(n, backend, nauty_mode)
    stored: Set[Code] = {start}
    frontier: Set[Code] = {start}
    gog_edges: Set[Tuple[Code, Code]] = set()
    transitions: List[Transition] = []
    complete = True

    print("Stored | Frontier | New | GoG edges | Transitions")

    def handle_results(frontier_list: List[Code], results: List[List[Transition]]) -> None:
        nonlocal stored, frontier, gog_edges, transitions, complete
        generated = {transition.target for result in results for transition in result}
        new = generated - stored
        if max_classes is not None and len(stored) + len(new) > max_classes:
            quota = max(0, max_classes - len(stored))
            new = set(sorted(new)[:quota])
            complete = False

        allowed = stored | new
        for source, result in zip(frontier_list, results):
            for transition in result:
                if transition.target not in allowed:
                    continue
                transitions.append(transition)
                if transition.target != source:
                    gog_edges.add(_edge_key(source, transition.target))

        print(
            f"{len(stored):6d} | {len(frontier):8d} | {len(new):3d} | "
            f"{len(gog_edges):9d} | {len(transitions):11d}"
        )
        stored.update(new)
        frontier = new

    if jobs == 1:
        while frontier:
            frontier_list = sorted(frontier)
            results = [
                _expand_transition_worker((code, n, backend, nauty_mode))
                for code in frontier_list
            ]
            handle_results(frontier_list, results)
            if not complete:
                break
    else:
        with Pool(processes=jobs) as pool:
            while frontier:
                frontier_list = sorted(frontier)
                results = pool.map(
                    _expand_transition_worker,
                    [(code, n, backend, nauty_mode) for code in frontier_list],
                )
                handle_results(frontier_list, results)
                if not complete:
                    break

    return stored, gog_edges, transitions, complete


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


def save_transition_json(
    path: str,
    n: int,
    nodes: Set[Code],
    edges: Set[Tuple[Code, Code]],
    transitions: Sequence[Transition],
    complete: bool,
) -> None:
    ordered_nodes = sorted(nodes)
    index = {code: i for i, code in enumerate(ordered_nodes)}
    transition_data = []
    for transition in transitions:
        if transition.source not in index or transition.target not in index:
            continue
        transition_data.append(
            {
                "source": index[transition.source],
                "target": index[transition.target],
                "edge_id": transition.edge_id,
                "source_edge": list(transition.source_edge),
                "resolution_id": transition.resolution_id,
                "averaged_endpoints": list(transition.averaged_endpoints),
                "canonical_order": list(transition.canonical_order),
                "raw_to_canonical": list(transition.raw_to_canonical),
                "trivial_loop": transition.trivial_loop,
            }
        )

    data = {
        "N": n,
        "complete": complete,
        "expected_node_count_A005967": known_vertex_count(n),
        "node_count": len(ordered_nodes),
        "edge_count": len(edges),
        "transition_count": len(transition_data),
        "expected_transition_count_if_complete": (
            len(ordered_nodes) * 3 * n if complete else None
        ),
        "nodes": [code_to_string(code) for code in ordered_nodes],
        "edges": [
            [index[a], index[b]]
            for a, b in sorted(edges)
            if a in index and b in index
        ],
        "transitions": transition_data,
    }
    with open(path, "w", encoding="utf-8") as out:
        json.dump(data, out, separators=(",", ":"))
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
        choices=("auto", "native", "nauty", "python"),
        default=DEFAULT_BACKEND,
        help=(
            "canonical labelling backend; auto tries the native nauty bridge, "
            "then dreadnaut, then the Python fallback"
        ),
    )
    parser.add_argument(
        "--nauty-mode",
        choices=("dense", "sparse", "traces"),
        default=DEFAULT_NAUTY_MODE,
        help="dreadnaut engine used by the nauty backend",
    )
    parser.add_argument("--save", help="write the generated GoG as JSON")
    parser.add_argument(
        "--save-transitions",
        help="write concrete Rule A transition records as compact JSON",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    transitions: List[Transition] | None = None
    if args.save_transitions:
        nodes, edges, transitions, complete = generate_graph_of_graph_with_transitions(
            args.N,
            jobs=args.jobs,
            max_classes=args.max_classes,
            backend=args.backend,
            nauty_mode=args.nauty_mode,
        )
    else:
        nodes, edges, complete = generate_graph_of_graph(
            args.N,
            jobs=args.jobs,
            max_classes=args.max_classes,
            backend=args.backend,
            nauty_mode=args.nauty_mode,
        )
    status = "complete" if complete else "partial"
    print(f"{status}: {len(nodes)} classes, {len(edges)} GoG edges")
    if transitions is not None:
        expected_transitions = len(nodes) * 3 * args.N if complete else None
        transition_verdict = (
            "OK" if expected_transitions == len(transitions) else "MISMATCH"
        )
        if expected_transitions is None:
            transition_verdict = "partial/not checked"
        print(
            f"Rule A transition records: {len(transitions)}"
            + (
                f" expected {expected_transitions} ({transition_verdict})"
                if expected_transitions is not None
                else f" ({transition_verdict})"
            )
        )
    expected = known_vertex_count(args.N)
    if expected is not None:
        verdict = "OK" if complete and len(nodes) == expected else "partial/not checked"
        if complete and len(nodes) != expected:
            verdict = "MISMATCH"
        print(f"A005967 expected classes for N={args.N}: {expected} ({verdict})")
    if args.save:
        save_json(args.save, args.N, nodes, edges, complete)
        print(f"wrote {args.save}")
    if args.save_transitions:
        assert transitions is not None
        save_transition_json(args.save_transitions, args.N, nodes, edges, transitions, complete)
        print(f"wrote {args.save_transitions}")


if __name__ == "__main__":
    main()
