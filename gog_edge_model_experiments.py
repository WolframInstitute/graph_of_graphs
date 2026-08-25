#!/usr/bin/env python3
"""Compare the multiplicity and simple-support graphs of Whitehead moves.

The input is a transition JSON written by::

    python3 gog_generate.py N --save-transitions transitions.json

That file describes the *unlabelled* state space and retains two formal
resolutions for every edge object.  Thus every source has exactly ``3*N``
slots (including the two trivial slots on a loop).  The script compares:

* Rule A: choose one of those compressed resolution slots uniformly;
* Rule B1: choose a distinct non-self target class uniformly, then choose a
  retained resolution record to that target uniformly.

This is deliberately not an experiment on Li's labelled simple graph, which
has a different vertex set and four labelled moves per non-loop edge.  The
distinction is printed prominently in the output.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import statistics
from collections import Counter, defaultdict, deque
from dataclasses import dataclass
from typing import Iterable, Sequence

import numpy as np
from scipy import sparse
from scipy.sparse.linalg import eigsh
from scipy.stats import pearsonr, spearmanr

from gog_degree_diagnostics import automorphism_order as incidence_automorphism_order
from gog_generate import code_from_matrix, edges_from_matrix, matrix_from_code


@dataclass
class ModelData:
    n: int
    codes: list[tuple[int, ...]]
    target_counts: list[Counter[int]]
    transitions: list[list[dict[str, object]]]
    simple_edges: list[tuple[int, int]]


def parse_code(text: str) -> tuple[int, ...]:
    return tuple(int(x) for x in text.split(",") if x)


def load_model(path: str) -> ModelData:
    with open(path, "r", encoding="utf-8") as inp:
        raw = json.load(inp)
    if not raw.get("complete", False):
        raise ValueError("experiments require a complete transition table")

    n = int(raw["N"])
    codes = [parse_code(text) for text in raw["nodes"]]
    by_source: list[list[dict[str, object]]] = [[] for _ in codes]
    target_counts: list[Counter[int]] = [Counter() for _ in codes]
    for transition in raw["transitions"]:
        source = int(transition["source"])
        target = int(transition["target"])
        by_source[source].append(transition)
        target_counts[source][target] += 1

    expected_slots = 3 * n
    bad = [i for i, row in enumerate(by_source) if len(row) != expected_slots]
    if bad:
        raise ValueError(
            f"{len(bad)} sources do not have the expected {expected_slots} slots"
        )

    simple_edges = [(int(a), int(b)) for a, b in raw["edges"]]
    return ModelData(n, codes, target_counts, by_source, simple_edges)


def bridge_profile(matrix: list[list[int]]) -> tuple[int, int]:
    """Return (bridge count, largest smaller-side size)."""

    n = len(matrix)
    bridges = 0
    largest_small_side = 0
    for a in range(n):
        for b in range(a + 1, n):
            if matrix[a][b] != 1:
                continue
            seen = {a}
            queue: deque[int] = deque([a])
            while queue:
                u = queue.popleft()
                for v, multiplicity in enumerate(matrix[u]):
                    if u == v or not multiplicity:
                        continue
                    if (u == a and v == b) or (u == b and v == a):
                        continue
                    if v not in seen:
                        seen.add(v)
                        queue.append(v)
            if b not in seen:
                bridges += 1
                largest_small_side = max(largest_small_side, min(len(seen), n - len(seen)))
    return bridges, largest_small_side


def laplacian_from_edge_weights(
    n: int,
    edges: Sequence[tuple[int, int]],
    weights: Sequence[float],
) -> np.ndarray:
    result = np.zeros((n, n), dtype=float)
    for (u, v), weight in zip(edges, weights):
        if u == v or weight == 0.0:
            continue
        result[u, u] += weight
        result[v, v] += weight
        result[u, v] -= weight
        result[v, u] -= weight
    return result


def labelled_simple_degree(matrix: list[list[int]]) -> int:
    """Degree in Li's fixed-labelled simple GoG for this representative.

    A non-loop central edge has four labelled endpoint-swap choices.  Targets
    are *not* canonicalized: vertex names remain fixed.  Duplicate and self
    targets are then collapsed, exactly as in a simple labelled graph.
    """

    edges = edges_from_matrix(matrix)
    stub_vertex: list[int] = []
    edge_stubs: list[tuple[int, int]] = []
    for u, v in edges:
        su = len(stub_vertex)
        stub_vertex.append(u)
        sv = len(stub_vertex)
        stub_vertex.append(v)
        edge_stubs.append((su, sv))
    incident: defaultdict[int, list[int]] = defaultdict(list)
    for stub, vertex in enumerate(stub_vertex):
        incident[vertex].append(stub)

    source_code = code_from_matrix(matrix)
    targets: set[tuple[int, ...]] = set()
    for su, sv in edge_stubs:
        u, v = stub_vertex[su], stub_vertex[sv]
        if u == v:
            continue
        u_other = [stub for stub in incident[u] if stub != su]
        v_other = [stub for stub in incident[v] if stub != sv]
        for u_stub in u_other:
            for v_stub in v_other:
                moved = list(stub_vertex)
                moved[u_stub] = v
                moved[v_stub] = u
                target_matrix = [[0 for _ in matrix] for _ in matrix]
                for a, b in edge_stubs:
                    x, y = moved[a], moved[b]
                    target_matrix[x][y] += 1
                    if x != y:
                        target_matrix[y][x] += 1
                target_code = code_from_matrix(target_matrix)
                if target_code != source_code:
                    targets.add(target_code)
    return len(targets)


def spectral_gap(matrix: np.ndarray) -> float:
    values = np.linalg.eigvalsh(matrix)
    if len(values) < 2:
        return 0.0
    return float(max(0.0, values[1]))


def reconstruct_rule_a_stationary(
    target_counts: Sequence[Counter[int]],
) -> tuple[np.ndarray, float, float]:
    """Use reciprocity ratios to reconstruct the reversible Rule-A law.

    Returns the normalized law, the maximum log detailed-balance residual, and
    the maximum asymmetry of the corresponding symmetric similarity transform.
    """

    count = len(target_counts)
    log_weight = np.full(count, np.nan)
    log_weight[0] = 0.0
    queue: deque[int] = deque([0])
    while queue:
        u = queue.popleft()
        for v, m_uv in target_counts[u].items():
            if v == u:
                continue
            m_vu = target_counts[v].get(u, 0)
            if not m_vu:
                raise ValueError(f"transition {u}->{v} has no reverse transition")
            candidate = log_weight[u] + math.log(m_uv) - math.log(m_vu)
            if math.isnan(log_weight[v]):
                log_weight[v] = candidate
                queue.append(v)
    if np.isnan(log_weight).any():
        raise ValueError("transition support is disconnected")

    residual = 0.0
    for u, row in enumerate(target_counts):
        for v, m_uv in row.items():
            if u == v:
                continue
            m_vu = target_counts[v][u]
            residual = max(
                residual,
                abs(log_weight[u] + math.log(m_uv) - log_weight[v] - math.log(m_vu)),
            )

    shifted = np.exp(log_weight - float(np.max(log_weight)))
    pi = shifted / float(np.sum(shifted))
    total_slots = sum(target_counts[0].values())
    rows: list[int] = []
    cols: list[int] = []
    values: list[float] = []
    for u, row in enumerate(target_counts):
        for v, multiplicity in row.items():
            rows.append(u)
            cols.append(v)
            values.append(
                math.sqrt(pi[u] / pi[v]) * multiplicity / total_slots
            )
    sym = sparse.csr_matrix((values, (rows, cols)), shape=(count, count))
    asymmetry = float(sparse.linalg.norm(sym - sym.T, ord=np.inf))
    return pi, residual, asymmetry


def markov_gap_rule_a(
    target_counts: Sequence[Counter[int]], pi: np.ndarray
) -> float:
    count = len(target_counts)
    if count <= 1:
        return 0.0
    total_slots = sum(target_counts[0].values())
    rows: list[int] = []
    cols: list[int] = []
    values: list[float] = []
    for u, row in enumerate(target_counts):
        for v, multiplicity in row.items():
            rows.append(u)
            cols.append(v)
            values.append(
                math.sqrt(pi[u] / pi[v]) * multiplicity / total_slots
            )
    sym = sparse.csr_matrix((values, (rows, cols)), shape=(count, count))
    if count <= 8:
        eigvals = np.linalg.eigvalsh(sym.toarray())
        second = eigvals[-2]
    else:
        eigvals = eigsh(sym, k=2, which="LA", return_eigenvectors=False, tol=1e-10)
        second = np.sort(eigvals)[-2]
    return float(1.0 - second)


def markov_gap_rule_b(simple_edges: Sequence[tuple[int, int]], count: int) -> float:
    if count <= 1:
        return 0.0
    degrees = np.zeros(count, dtype=float)
    for u, v in simple_edges:
        degrees[u] += 1.0
        degrees[v] += 1.0
    rows: list[int] = []
    cols: list[int] = []
    values: list[float] = []
    for u, v in simple_edges:
        value = 1.0 / math.sqrt(degrees[u] * degrees[v])
        rows.extend((u, v))
        cols.extend((v, u))
        values.extend((value, value))
    sym = sparse.csr_matrix((values, (rows, cols)), shape=(count, count))
    if count <= 8:
        eigvals = np.linalg.eigvalsh(sym.toarray())
        second = eigvals[-2]
    else:
        eigvals = eigsh(sym, k=2, which="LA", return_eigenvectors=False, tol=1e-10)
        second = np.sort(eigvals)[-2]
    return float(1.0 - second)


def simple_combinatorial_gap(
    simple_edges: Sequence[tuple[int, int]], count: int
) -> float:
    """Second eigenvalue of Li's unlabelled simple combinatorial Laplacian."""

    if count <= 1:
        return 0.0
    degrees = np.zeros(count, dtype=float)
    rows: list[int] = []
    cols: list[int] = []
    values: list[float] = []
    for u, v in simple_edges:
        degrees[u] += 1.0
        degrees[v] += 1.0
        rows.extend((u, v))
        cols.extend((v, u))
        values.extend((-1.0, -1.0))
    rows.extend(range(count))
    cols.extend(range(count))
    values.extend(float(value) for value in degrees)
    laplacian = sparse.csr_matrix((values, (rows, cols)), shape=(count, count))
    if count <= 8:
        eigenvalues = np.linalg.eigvalsh(laplacian.toarray())
        return float(max(0.0, eigenvalues[1]))
    eigenvalues = eigsh(
        laplacian, k=2, which="SM", return_eigenvectors=False, tol=1e-9
    )
    return float(max(0.0, np.sort(eigenvalues)[1]))


def edge_object_kernel(matrix: list[list[int]]) -> int:
    """Kernel from permutations of indistinguishable incidence edge-nodes."""

    result = 1
    n = len(matrix)
    for i in range(n):
        result *= math.factorial(matrix[i][i])
        for j in range(i + 1, n):
            result *= math.factorial(matrix[i][j])
    return result


def vertex_automorphism_order(code: tuple[int, ...], n: int) -> int:
    matrix = matrix_from_code(code, n)
    incidence_order = incidence_automorphism_order(code, n)
    kernel = edge_object_kernel(matrix)
    if incidence_order % kernel:
        raise ValueError(
            f"incidence automorphism order {incidence_order} is not divisible by {kernel}"
        )
    return incidence_order // kernel


def evenly_spaced_indices(length: int, sample: int) -> list[int]:
    if sample >= length:
        return list(range(length))
    if sample <= 0:
        return []
    if sample == 1:
        return [0]
    return sorted({round(i * (length - 1) / (sample - 1)) for i in range(sample)})


def reciprocity_automorphism_audit(
    model: ModelData,
    edge_sample: int,
) -> tuple[int, int, int, int]:
    sampled = [model.simple_edges[i] for i in evenly_spaced_indices(len(model.simple_edges), edge_sample)]
    vertices = sorted({vertex for edge in sampled for vertex in edge})
    vertex_aut: dict[int, int] = {}
    configuration_denominator: dict[int, int] = {}
    for vertex in vertices:
        code = model.codes[vertex]
        matrix = matrix_from_code(code, model.n)
        incidence_aut = incidence_automorphism_order(code, model.n)
        kernel = edge_object_kernel(matrix)
        if incidence_aut % kernel:
            raise ValueError("incidence automorphism group has an unexpected kernel")
        vertex_aut[vertex] = incidence_aut // kernel
        loop_count = sum(matrix[i][i] for i in range(model.n))
        # Apart from the constant (3!)^N, a labelled adjacency matrix has
        # configuration-model multiplicity
        #   1 / (prod m_ij! prod 2^loops loops!).
        # After quotienting vertices, the denominator is therefore
        # |Aut_vertices| * kernel * 2^loops = |Aut_incidence| * 2^loops.
        configuration_denominator[vertex] = incidence_aut * (2**loop_count)

    naive_failures = 0
    configuration_failures = 0
    for u, v in sampled:
        m_uv = model.target_counts[u][v]
        m_vu = model.target_counts[v][u]
        # The proposed inverse-vertex-automorphism law.
        if m_uv * vertex_aut[v] != m_vu * vertex_aut[u]:
            naive_failures += 1
        # The configuration-model law appropriate to the current two-resolution
        # unlabelled transition table.
        if (
            m_uv * configuration_denominator[v]
            != m_vu * configuration_denominator[u]
        ):
            configuration_failures += 1
    return len(sampled), len(vertices), naive_failures, configuration_failures


def weighted_mean(values: np.ndarray, weights: np.ndarray) -> float:
    mask = np.isfinite(values)
    if not np.any(mask):
        return math.nan
    return float(np.sum(values[mask] * weights[mask]) / np.sum(weights[mask]))


def safe_correlation(x: np.ndarray, y: np.ndarray) -> tuple[float, float]:
    mask = np.isfinite(x) & np.isfinite(y)
    if np.sum(mask) < 3 or np.ptp(x[mask]) == 0 or np.ptp(y[mask]) == 0:
        return math.nan, math.nan
    return float(pearsonr(x[mask], y[mask]).statistic), float(
        spearmanr(x[mask], y[mask]).statistic
    )


def summarize_array(values: np.ndarray) -> str:
    finite = values[np.isfinite(values)]
    if len(finite) == 0:
        return "n/a"
    return (
        f"mean={np.mean(finite):.8g} min={np.min(finite):.8g} "
        f"median={np.median(finite):.8g} max={np.max(finite):.8g}"
    )


def analyze(model: ModelData) -> tuple[list[dict[str, float | int]], dict[str, float | int]]:
    n = model.n
    node_count = len(model.codes)
    slot_count = 3 * n
    edge_objects = 3 * n // 2
    rows: list[dict[str, float | int]] = []
    multiplicity_histogram: Counter[int] = Counter()

    for source, (code, counts, transitions) in enumerate(
        zip(model.codes, model.target_counts, model.transitions)
    ):
        matrix = matrix_from_code(code, n)
        edges = edges_from_matrix(matrix)
        if len(edges) != edge_objects:
            raise ValueError(f"source {source} has {len(edges)} edge objects")
        per_edge_slot_counts = Counter(int(item["edge_id"]) for item in transitions)
        if set(per_edge_slot_counts.values()) != {2}:
            raise ValueError(f"source {source} does not have two slots per edge object")

        nonself = {target: m for target, m in counts.items() if target != source}
        q = len(nonself)
        support_with_self = len(counts)
        self_slots = counts.get(source, 0)
        nonself_slots = slot_count - self_slots
        collision_all = sum(m * (m - 1) // 2 for m in counts.values())
        collision_nonself = sum(m * (m - 1) // 2 for m in nonself.values())
        multiplicity_histogram.update(nonself.values())

        tv_full = 0.5 * self_slots / slot_count
        tv_conditional = 0.0
        if q:
            tv_full += 0.5 * sum(abs(m / slot_count - 1.0 / q) for m in nonself.values())
            if nonself_slots:
                tv_conditional = 0.5 * sum(
                    abs(m / nonself_slots - 1.0 / q) for m in nonself.values()
                )
                conditional_chi2 = (
                    q * (nonself_slots + 2 * collision_nonself) / (nonself_slots**2)
                    - 1.0
                )
            else:
                conditional_chi2 = math.nan
        else:
            tv_full = math.nan
            tv_conditional = math.nan
            conditional_chi2 = math.nan

        b_edge_weights = np.zeros(edge_objects, dtype=float)
        if q:
            for item in transitions:
                target = int(item["target"])
                if target == source:
                    continue
                edge_id = int(item["edge_id"])
                b_edge_weights[edge_id] += 1.0 / (q * counts[target])
            if not math.isclose(float(np.sum(b_edge_weights)), 1.0, rel_tol=1e-12, abs_tol=1e-12):
                raise ValueError(f"Rule B edge weights for source {source} do not sum to one")

        uniform_edge_weights = np.full(edge_objects, 1.0 / edge_objects)
        edge_weight_tv = 0.5 * float(np.sum(np.abs(b_edge_weights - uniform_edge_weights))) if q else math.nan
        zero_b_edges = int(np.sum(b_edge_weights < 1e-15)) if q else edge_objects
        max_b_edge_ratio = float(np.max(b_edge_weights) * edge_objects) if q else math.nan

        base_laplacian = laplacian_from_edge_weights(n, edges, np.ones(edge_objects))
        base_gap = spectral_gap(base_laplacian)
        rule_a_field_gap = (2.0 / slot_count) * base_gap
        rule_b_field_gap = spectral_gap(laplacian_from_edge_weights(n, edges, b_edge_weights)) if q else 0.0
        gap_ratio = rule_b_field_gap / rule_a_field_gap if rule_a_field_gap else math.nan

        loops = sum(matrix[i][i] for i in range(n))
        parallel_excess = sum(
            max(0, matrix[i][j] - 1)
            for i in range(n)
            for j in range(i + 1, n)
        )
        bridge_count, bridge_side = bridge_profile(matrix)
        labelled_q = labelled_simple_degree(matrix)
        configuration_log_denominator = loops * math.log(2.0)
        for i in range(n):
            configuration_log_denominator += math.lgamma(matrix[i][i] + 1)
            for j in range(i + 1, n):
                configuration_log_denominator += math.lgamma(matrix[i][j] + 1)

        rows.append(
            {
                "source": source,
                "q_nonself": q,
                "q_labelled_simple": labelled_q,
                "support_with_self": support_with_self,
                "self_slots": self_slots,
                "max_target_multiplicity": max(counts.values()),
                "collision_all": collision_all,
                "collision_nonself": collision_nonself,
                "tv_A_vs_B_full": tv_full,
                "tv_A_cond_nonself_vs_B": tv_conditional,
                "chi2_A_cond_nonself_vs_B": conditional_chi2,
                "edge_weight_tv_B_vs_uniform": edge_weight_tv,
                "zero_B_edge_objects": zero_b_edges,
                "max_B_edge_weight_ratio": max_b_edge_ratio,
                "base_cubic_gap": base_gap,
                "rule_A_field_gap": rule_a_field_gap,
                "rule_B_field_gap": rule_b_field_gap,
                "field_gap_ratio_B_over_A": gap_ratio,
                "loops": loops,
                "parallel_excess": parallel_excess,
                "bridges": bridge_count,
                "largest_bridge_small_side": bridge_side,
                "configuration_log_denominator": configuration_log_denominator,
            }
        )

    pi_a, balance_residual, sym_asymmetry = reconstruct_rule_a_stationary(model.target_counts)
    q_values = np.array([float(row["q_nonself"]) for row in rows])
    labelled_q_values = np.array([float(row["q_labelled_simple"]) for row in rows])
    pi_b = q_values / float(np.sum(q_values))
    uniform = np.full(node_count, 1.0 / node_count)
    # The current two-resolution GDPK law is the configuration-model law
    # pi_cfg(G) proportional to 1/(|Aut_vertices(G)| D(G)), where D is the
    # loop/parallel-edge denominator.  Multiplication by D recovers the class
    # weights proportional to 1/|Aut_vertices|, i.e. uniform labelled graphs.
    log_label_weight = np.log(pi_a) + np.array(
        [float(row["configuration_log_denominator"]) for row in rows]
    )
    label_weight = np.exp(log_label_weight - float(np.max(log_label_weight)))
    pi_label = label_weight / float(np.sum(label_weight))

    def column(name: str) -> np.ndarray:
        return np.array([float(row[name]) for row in rows])

    deficit = slot_count - q_values
    collision = column("collision_all")
    loops = column("loops")
    bridge_counts = column("bridges")
    bridged_mask = bridge_counts > 0
    bridgeless_mask = ~bridged_mask
    bridge_side = column("largest_bridge_small_side")
    field_ratio = column("field_gap_ratio_B_over_A")
    corr_deficit_collision = safe_correlation(deficit, collision)
    corr_deficit_loops = safe_correlation(deficit, loops)
    corr_ratio_bridge = safe_correlation(field_ratio, bridge_side)

    bridge_boundary_edges = sum(
        bool(bridged_mask[u]) != bool(bridged_mask[v]) for u, v in model.simple_edges
    )
    bridged_support_volume = float(np.sum(q_values[bridged_mask]))
    bridgeless_support_volume = float(np.sum(q_values[bridgeless_mask]))
    rule_b_bridge_conductance = bridge_boundary_edges / min(
        bridged_support_volume, bridgeless_support_volume
    )
    bridged_pi_a_mass = float(np.sum(pi_a[bridged_mask]))
    rule_a_bridge_flow = 0.0
    max_bridged_escape_slots = 0
    for source in np.flatnonzero(bridged_mask):
        escape_slots = sum(
            multiplicity
            for target, multiplicity in model.target_counts[source].items()
            if not bridged_mask[target]
        )
        max_bridged_escape_slots = max(max_bridged_escape_slots, escape_slots)
        rule_a_bridge_flow += pi_a[source] * escape_slots / slot_count
    rule_a_bridge_conductance = rule_a_bridge_flow / min(
        bridged_pi_a_mass, 1.0 - bridged_pi_a_mass
    )

    multiplicity_pairs = sum(multiplicity_histogram.values())
    summary: dict[str, float | int] = {
        "N": n,
        "node_count": node_count,
        "slot_count_per_source": slot_count,
        "simple_edge_count": len(model.simple_edges),
        "q_uniform_mean": float(np.mean(q_values)),
        "q_uniform_min": int(np.min(q_values)),
        "q_uniform_max": int(np.max(q_values)),
        "q_over_slots_uniform": float(np.mean(q_values) / slot_count),
        "q_piA_mean": weighted_mean(q_values, pi_a),
        "q_piB_mean": weighted_mean(q_values, pi_b),
        "q_simple_piLabel_mean": weighted_mean(q_values, pi_label),
        "q_labelled_uniform_class_mean": float(np.mean(labelled_q_values)),
        "q_labelled_uniform_class_min": int(np.min(labelled_q_values)),
        "q_labelled_uniform_class_max": int(np.max(labelled_q_values)),
        "q_labelled_over_raw_moves_uniform_class": float(
            np.mean(labelled_q_values) / (6 * n)
        ),
        "q_labelled_piLabel_mean": weighted_mean(labelled_q_values, pi_label),
        "q_labelled_piLabel_over_raw_moves": weighted_mean(
            labelled_q_values, pi_label
        )
        / (6 * n),
        "tv_piA_piB": 0.5 * float(np.sum(np.abs(pi_a - pi_b))),
        "tv_piA_uniform": 0.5 * float(np.sum(np.abs(pi_a - uniform))),
        "tv_piA_piLabel": 0.5 * float(np.sum(np.abs(pi_a - pi_label))),
        "collision_uniform_mean": float(np.mean(collision)),
        "collision_per_N_uniform": float(np.mean(collision) / n),
        "collision_per_N_bridged": float(np.mean(collision[bridged_mask]) / n),
        "collision_per_N_bridgeless": float(np.mean(collision[bridgeless_mask]) / n),
        "q_bridged_mean": float(np.mean(q_values[bridged_mask])),
        "q_bridgeless_mean": float(np.mean(q_values[bridgeless_mask])),
        "bridged_class_fraction": float(np.mean(bridged_mask)),
        "bridged_piA_mass": bridged_pi_a_mass,
        "bridged_piB_mass": float(np.sum(pi_b[bridged_mask])),
        "bridged_support_volume_fraction": float(
            np.sum(q_values[bridged_mask]) / np.sum(q_values)
        ),
        "bridge_boundary_edges": bridge_boundary_edges,
        "max_bridged_escape_slots": max_bridged_escape_slots,
        "rule_A_bridge_conductance": rule_a_bridge_conductance,
        "rule_B_bridge_conductance": rule_b_bridge_conductance,
        "self_probability_uniform": float(np.mean(column("self_slots")) / slot_count),
        "tv_A_B_full_uniform": float(np.nanmean(column("tv_A_vs_B_full"))),
        "tv_Acond_B_uniform": float(np.nanmean(column("tv_A_cond_nonself_vs_B"))),
        "chi2_Acond_B_uniform": float(
            np.nanmean(column("chi2_A_cond_nonself_vs_B"))
        ),
        "edge_weight_tv_uniform": float(np.nanmean(column("edge_weight_tv_B_vs_uniform"))),
        "zero_B_field_gap_count": int(np.sum(column("rule_B_field_gap") < 1e-12)),
        "field_gap_ratio_uniform": float(np.nanmean(field_ratio)),
        "field_gap_ratio_piA": weighted_mean(field_ratio, pi_a),
        "field_gap_ratio_piB": weighted_mean(field_ratio, pi_b),
        "multiplicity_gt1_fraction": (
            sum(count for m, count in multiplicity_histogram.items() if m > 1) / multiplicity_pairs
        ),
        "max_nonself_multiplicity": max(multiplicity_histogram) if multiplicity_histogram else 0,
        "balance_log_residual": balance_residual,
        "symmetric_transform_asymmetry": sym_asymmetry,
        "rule_A_markov_gap": markov_gap_rule_a(model.target_counts, pi_a),
        "rule_B_markov_gap": markov_gap_rule_b(model.simple_edges, node_count),
        "li_unlabelled_combinatorial_gap": simple_combinatorial_gap(
            model.simple_edges, node_count
        ),
        "corr_deficit_collision_pearson": corr_deficit_collision[0],
        "corr_deficit_collision_spearman": corr_deficit_collision[1],
        "corr_deficit_loops_pearson": corr_deficit_loops[0],
        "corr_deficit_loops_spearman": corr_deficit_loops[1],
        "corr_field_ratio_bridge_side_pearson": corr_ratio_bridge[0],
        "corr_field_ratio_bridge_side_spearman": corr_ratio_bridge[1],
    }

    for i, row in enumerate(rows):
        row["pi_A"] = float(pi_a[i])
        row["pi_B"] = float(pi_b[i])
        row["pi_labelled_uniform"] = float(pi_label[i])

    return rows, summary


def print_report(path: str, rows: list[dict[str, float | int]], summary: dict[str, float | int]) -> None:
    n = int(summary["N"])
    print()
    print(f"=== {path}: N={n} carrier vertices ===")
    print(
        "edge models: Li-labelled simple has <=6N raw labelled moves; "
        "this table is GDPK unlabelled multiplicity with exactly 3N slots; "
        "Rule B uses its deduplicated non-self support"
    )
    print(
        f"classes={summary['node_count']} slots/source={summary['slot_count_per_source']} "
        f"simple_edges={summary['simple_edge_count']}"
    )
    print(
        "simple q: "
        f"mean/min/max={summary['q_uniform_mean']:.8g}/"
        f"{summary['q_uniform_min']}/{summary['q_uniform_max']} "
        f"mean/(3N)={summary['q_over_slots_uniform']:.8g}"
    )
    print(
        "mean q under stationary laws: "
        f"uniform classes={summary['q_uniform_mean']:.8g} "
        f"GDPK={summary['q_piA_mean']:.8g} RuleB={summary['q_piB_mean']:.8g} "
        f"uniform-labelled projection={summary['q_simple_piLabel_mean']:.8g}"
    )
    print(
        "Li-labelled simple degree (one representative per unlabelled class): "
        f"mean/min/max={summary['q_labelled_uniform_class_mean']:.8g}/"
        f"{summary['q_labelled_uniform_class_min']}/"
        f"{summary['q_labelled_uniform_class_max']} "
        f"mean/(6N raw moves)={summary['q_labelled_over_raw_moves_uniform_class']:.8g}; "
        f"uniform-labelled mean={summary['q_labelled_piLabel_mean']:.8g} "
        f"ratio={summary['q_labelled_piLabel_over_raw_moves']:.8g}"
    )
    print(
        f"TV(piA,piB)={summary['tv_piA_piB']:.8g} "
        f"TV(piA,uniform)={summary['tv_piA_uniform']:.8g} "
        f"TV(piA,uniform-labelled projection)={summary['tv_piA_piLabel']:.8g}"
    )
    print(
        f"collision C1: mean={summary['collision_uniform_mean']:.8g} "
        f"mean/N={summary['collision_per_N_uniform']:.8g}; "
        f"nonself support pairs with multiplicity>1={summary['multiplicity_gt1_fraction']:.8g}; "
        f"max multiplicity={summary['max_nonself_multiplicity']}"
    )
    print(
        "bridge split: "
        f"mean C1/N bridged/bridgeless="
        f"{summary['collision_per_N_bridged']:.8g}/"
        f"{summary['collision_per_N_bridgeless']:.8g}; "
        f"mean q bridged/bridgeless={summary['q_bridged_mean']:.8g}/"
        f"{summary['q_bridgeless_mean']:.8g}; "
        f"bridged class/support-volume fractions="
        f"{summary['bridged_class_fraction']:.8g}/"
        f"{summary['bridged_support_volume_fraction']:.8g}"
    )
    print(
        "bridge cut: "
        f"boundary support edges={summary['bridge_boundary_edges']} "
        f"max Rule-A escape slots/source={summary['max_bridged_escape_slots']}; "
        f"conductance RuleA/RuleB={summary['rule_A_bridge_conductance']:.8g}/"
        f"{summary['rule_B_bridge_conductance']:.8g}"
    )
    print(
        f"mean self probability under Rule A={summary['self_probability_uniform']:.8g}; "
        f"mean TV(A,B)={summary['tv_A_B_full_uniform']:.8g}; "
        f"mean TV(A|nonself,B)={summary['tv_Acond_B_uniform']:.8g}"
    )
    print(
        "conditional multiplicity divergence: "
        f"mean chi^2(A|nonself || B)={summary['chi2_Acond_B_uniform']:.8g}"
    )
    print(
        f"field edge-weight mean TV(B,uniform)={summary['edge_weight_tv_uniform']:.8g}; "
        f"zero Rule-B weighted gaps={summary['zero_B_field_gap_count']}"
    )
    print(
        "field gap ratio B/A: "
        f"uniform={summary['field_gap_ratio_uniform']:.8g} "
        f"piA={summary['field_gap_ratio_piA']:.8g} "
        f"piB={summary['field_gap_ratio_piB']:.8g}"
    )
    print(
        f"base-chain Markov gaps: RuleA={summary['rule_A_markov_gap']:.8g} "
        f"RuleB={summary['rule_B_markov_gap']:.8g}; "
        f"Li-unlabelled combinatorial lambda2="
        f"{summary['li_unlabelled_combinatorial_gap']:.8g}"
    )
    print(
        f"reciprocity residual(log)={summary['balance_log_residual']:.3g}; "
        f"symmetric-transform asymmetry={summary['symmetric_transform_asymmetry']:.3g}"
    )
    print(
        "corr((3N-q), C1) Pearson/Spearman="
        f"{summary['corr_deficit_collision_pearson']:.6g}/"
        f"{summary['corr_deficit_collision_spearman']:.6g}; "
        "corr((3N-q), loops)="
        f"{summary['corr_deficit_loops_pearson']:.6g}/"
        f"{summary['corr_deficit_loops_spearman']:.6g}"
    )
    print(
        "corr(field gap ratio B/A, largest bridge side) Pearson/Spearman="
        f"{summary['corr_field_ratio_bridge_side_pearson']:.6g}/"
        f"{summary['corr_field_ratio_bridge_side_spearman']:.6g}"
    )

    for name in (
        "q_nonself",
        "q_labelled_simple",
        "collision_all",
        "tv_A_vs_B_full",
        "edge_weight_tv_B_vs_uniform",
        "field_gap_ratio_B_over_A",
        "loops",
        "bridges",
        "largest_bridge_small_side",
    ):
        print(f"  {name}: {summarize_array(np.array([float(row[name]) for row in rows]))}")


def write_csv(path: str, rows: Iterable[dict[str, float | int]]) -> None:
    rows = list(rows)
    if not rows:
        return
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("transition_json", nargs="+")
    parser.add_argument(
        "--csv-dir",
        help="optionally write one per-node diagnostic CSV per input",
    )
    parser.add_argument(
        "--aut-edge-sample",
        type=int,
        default=0,
        help="exactly audit reciprocity on this many evenly spaced support edges using dreadnaut",
    )
    parser.add_argument(
        "--summary-json",
        help="optionally write the collected one-row-per-N summaries",
    )
    args = parser.parse_args()

    summaries: list[dict[str, float | int]] = []
    for path in args.transition_json:
        model = load_model(path)
        rows, summary = analyze(model)
        print_report(path, rows, summary)
        if args.aut_edge_sample:
            edge_count, vertex_count, naive_failures, configuration_failures = reciprocity_automorphism_audit(
                model, args.aut_edge_sample
            )
            print(
                f"exact automorphism reciprocity audit: edges={edge_count} "
                f"endpoint automorphism groups={vertex_count} "
                f"failures[1/|Aut_vertices|]={naive_failures} "
                f"failures[configuration weight]={configuration_failures}"
            )
            summary["aut_audit_edges"] = edge_count
            summary["aut_audit_vertices"] = vertex_count
            summary["aut_audit_inverse_vertex_aut_failures"] = naive_failures
            summary["aut_audit_configuration_weight_failures"] = configuration_failures
        if args.csv_dir:
            csv_path = os.path.join(args.csv_dir, f"gog_edge_models_N{model.n}.csv")
            write_csv(csv_path, rows)
            print(f"wrote {csv_path}")
        summaries.append(summary)

    if args.summary_json:
        with open(args.summary_json, "w", encoding="utf-8") as out:
            json.dump(summaries, out, indent=2, sort_keys=True)
            out.write("\n")
        print(f"wrote {args.summary_json}")


if __name__ == "__main__":
    main()
