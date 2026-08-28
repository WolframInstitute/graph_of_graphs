#!/usr/bin/env python3
"""Measure local-feature cuts in the unlabelled Whitehead support.

For each class indicator, the script divides its one-step Dirichlet energy by
its stationary variance for four related operators:

* the reversible GDPK/Rule-A multiplicity chain;
* fixed-clock Rule B, with one of ``3*N`` ticks per support neighbour;
* the degree-normalized Rule-B jump chain, obtained by conditioning on moving;
* the combinatorial Laplacian of Li's unlabelled simple GoG.

Inputs are complete transition JSON files emitted by ``gog_generate.py``.
Cycle length one means a loop, length two means a parallel-edge pair, and
length at least three means a vertex-simple cycle in the underlying support of
the carrier multigraph.
"""

from __future__ import annotations

import argparse
import json
import math
from typing import Sequence

import numpy as np
from scipy import sparse
from scipy.sparse.linalg import eigsh

from gog_edge_model_experiments import load_model, reconstruct_rule_a_stationary
from gog_generate import matrix_from_code


def smallest_eigenvalues(matrix: sparse.csr_matrix, count: int) -> list[float]:
    """Return the smallest eigenvalues of a real symmetric sparse matrix."""

    n = matrix.shape[0]
    count = min(count, n)
    if count == n or n <= 10:
        values = np.linalg.eigvalsh(matrix.toarray())[:count]
    else:
        values = np.sort(
            eigsh(matrix, k=count, which="SM", return_eigenvectors=False, tol=1e-9)
        )
    return [float(max(0.0, value)) for value in values]


def low_spectra(
    model, pi_a: np.ndarray, q: np.ndarray, count: int
) -> dict[str, list[float]]:
    """Build the four symmetric Laplacians on the common class set."""

    node_count = len(model.codes)
    slot_count = 3 * model.n

    a_rows: list[int] = []
    a_cols: list[int] = []
    a_values: list[float] = []
    for source, targets in enumerate(model.target_counts):
        for target, multiplicity in targets.items():
            a_rows.append(source)
            a_cols.append(target)
            a_values.append(
                math.sqrt(pi_a[source] / pi_a[target]) * multiplicity / slot_count
            )
    a_sym = sparse.csr_matrix(
        (a_values, (a_rows, a_cols)), shape=(node_count, node_count)
    )
    a_laplacian = sparse.eye(node_count, format="csr") - a_sym

    b_rows: list[int] = []
    b_cols: list[int] = []
    b_values: list[float] = []
    c_rows: list[int] = []
    c_cols: list[int] = []
    c_values: list[float] = []
    for u, v in model.simple_edges:
        normalized = 1.0 / math.sqrt(q[u] * q[v])
        b_rows.extend((u, v))
        b_cols.extend((v, u))
        b_values.extend((-normalized, -normalized))
        c_rows.extend((u, v))
        c_cols.extend((v, u))
        c_values.extend((-1.0, -1.0))
    b_rows.extend(range(node_count))
    b_cols.extend(range(node_count))
    b_values.extend([1.0] * node_count)
    b_laplacian = sparse.csr_matrix(
        (b_values, (b_rows, b_cols)), shape=(node_count, node_count)
    )
    c_rows.extend(range(node_count))
    c_cols.extend(range(node_count))
    c_values.extend(float(value) for value in q)
    c_laplacian = sparse.csr_matrix(
        (c_values, (c_rows, c_cols)), shape=(node_count, node_count)
    )

    return {
        "rule_A": smallest_eigenvalues(a_laplacian, count),
        "rule_B_fixed": smallest_eigenvalues(c_laplacian / slot_count, count),
        "rule_B_jump": smallest_eigenvalues(b_laplacian, count),
        "support_combinatorial": smallest_eigenvalues(c_laplacian, count),
    }


def has_cycle(matrix: list[list[int]], length: int) -> bool:
    """Return whether the cubic multigraph has a cycle of the given length."""

    n = len(matrix)
    if length == 1:
        return any(matrix[i][i] > 0 for i in range(n))
    if length == 2:
        return any(matrix[i][j] > 1 for i in range(n) for j in range(i + 1, n))
    if length < 1 or length > n:
        return False

    # Take the starting vertex to be the least vertex on the cycle.  This is
    # only an existence test, so suppressing the reverse orientation is not
    # necessary.
    for start in range(n):
        path = [start]
        used = {start}

        def extend() -> bool:
            if len(path) == length:
                return matrix[path[-1]][start] > 0
            u = path[-1]
            for v in range(start + 1, n):
                if v in used or matrix[u][v] == 0:
                    continue
                used.add(v)
                path.append(v)
                if extend():
                    return True
                path.pop()
                used.remove(v)
            return False

        if extend():
            return True
    return False


def covariance_min_eigenvalue(masks: Sequence[np.ndarray], weights: np.ndarray) -> float:
    """Smallest eigenvalue of the centered feature Gram matrix."""

    if not masks:
        return math.nan
    values = np.column_stack([mask.astype(float) for mask in masks])
    means = weights @ values
    centered = values - means
    gram = centered.T @ (weights[:, None] * centered)
    return float(max(0.0, np.linalg.eigvalsh(gram)[0]))


def analyze(path: str, max_cycle: int, eigenvalue_count: int) -> dict[str, object]:
    model = load_model(path)
    node_count = len(model.codes)
    slot_count = 3 * model.n
    q = np.array(
        [
            sum(1 for target in row if target != source)
            for source, row in enumerate(model.target_counts)
        ],
        dtype=float,
    )
    total_volume = float(np.sum(q))
    pi_a, balance_residual, _asymmetry = reconstruct_rule_a_stationary(model.target_counts)
    uniform = np.full(node_count, 1.0 / node_count)
    pi_b_jump = q / total_volume if total_volume else uniform

    matrices = [matrix_from_code(code, model.n) for code in model.codes]
    masks = [
        np.array([has_cycle(matrix, length) for matrix in matrices], dtype=bool)
        for length in range(1, max_cycle + 1)
    ]

    feature_rows: list[dict[str, float | int]] = []
    for length, mask in enumerate(masks, start=1):
        complement = ~mask
        class_count = int(np.sum(mask))
        complement_count = node_count - class_count
        boundary = sum(bool(mask[u]) != bool(mask[v]) for u, v in model.simple_edges)
        volume = float(np.sum(q[mask]))
        complement_volume = total_volume - volume

        a_mass = float(np.sum(pi_a[mask]))
        b_fixed_mass = class_count / node_count
        b_jump_mass = volume / total_volume if total_volume else b_fixed_mass
        a_flow = 0.0
        for source in np.flatnonzero(mask):
            a_flow += sum(
                pi_a[source] * multiplicity / slot_count
                for target, multiplicity in model.target_counts[source].items()
                if not mask[target]
            )

        combinatorial_energy_over_variance = (
            boundary * node_count / (class_count * complement_count)
            if class_count and complement_count
            else math.nan
        )
        rule_b_fixed_energy_over_variance = (
            combinatorial_energy_over_variance / slot_count
            if class_count and complement_count
            else math.nan
        )
        rule_b_jump_energy_over_variance = (
            boundary * total_volume / (volume * complement_volume)
            if volume and complement_volume
            else math.nan
        )
        rule_a_energy_over_variance = (
            a_flow / (a_mass * (1.0 - a_mass))
            if 0.0 < a_mass < 1.0
            else math.nan
        )
        feature_rows.append(
            {
                "cycle_length": length,
                "class_fraction": class_count / node_count,
                "boundary_edges": boundary,
                "boundary_per_feature_class": (
                    boundary / class_count if class_count else math.nan
                ),
                "mean_q_feature": volume / class_count if class_count else math.nan,
                "mean_q_complement": (
                    complement_volume / complement_count if complement_count else math.nan
                ),
                "pi_A_mass": a_mass,
                "pi_B_fixed_mass": b_fixed_mass,
                "pi_B_jump_mass": b_jump_mass,
                "support_laplacian_energy_over_variance": (
                    combinatorial_energy_over_variance
                ),
                "rule_B_fixed_energy_over_variance": (
                    rule_b_fixed_energy_over_variance
                ),
                "rule_B_jump_energy_over_variance": (
                    rule_b_jump_energy_over_variance
                ),
                "rule_A_energy_over_variance": rule_a_energy_over_variance,
            }
        )

    return {
        "N": model.n,
        "node_count": node_count,
        "balance_log_residual": balance_residual,
        "uniform_feature_covariance_min_eigenvalue": covariance_min_eigenvalue(
            masks, uniform
        ),
        "pi_A_feature_covariance_min_eigenvalue": covariance_min_eigenvalue(
            masks, pi_a
        ),
        "pi_B_fixed_feature_covariance_min_eigenvalue": (
            covariance_min_eigenvalue(masks, uniform)
        ),
        "pi_B_jump_feature_covariance_min_eigenvalue": (
            covariance_min_eigenvalue(masks, pi_b_jump)
        ),
        "low_eigenvalues": low_spectra(model, pi_a, q, eigenvalue_count),
        "features": feature_rows,
    }


def print_report(path: str, result: dict[str, object]) -> None:
    print(f"\n=== {path}: N={result['N']}, classes={result['node_count']} ===")
    print(
        "smallest eigenvalue of the centered cycle-indicator covariance: "
        f"uniform={result['uniform_feature_covariance_min_eigenvalue']:.6g}; "
        f"Rule A={result['pi_A_feature_covariance_min_eigenvalue']:.6g}; "
        f"Rule B={result['pi_B_fixed_feature_covariance_min_eigenvalue']:.6g}; "
        f"B jump={result['pi_B_jump_feature_covariance_min_eigenvalue']:.6g}"
    )
    print("smallest eigenvalues (including zero):")
    for name, values in result["low_eigenvalues"].items():
        print(f"  {name}: " + ", ".join(f"{value:.7g}" for value in values))
    print(
        "j  class-frac  boundary/|X|  mean-q X/Xc  "
        "energy/variance[A,B-fixed,B-jump,support-L]  "
        "mass[piA,piB-fixed,piB-jump]"
    )
    for row in result["features"]:
        print(
            f"{row['cycle_length']:d}  {row['class_fraction']:.6f}  "
            f"{row['boundary_per_feature_class']:.6g}  "
            f"{row['mean_q_feature']:.6g}/{row['mean_q_complement']:.6g}  "
            f"{row['rule_A_energy_over_variance']:.6g},"
            f"{row['rule_B_fixed_energy_over_variance']:.6g},"
            f"{row['rule_B_jump_energy_over_variance']:.6g},"
            f"{row['support_laplacian_energy_over_variance']:.6g}  "
            f"{row['pi_A_mass']:.6g},"
            f"{row['pi_B_fixed_mass']:.6g},"
            f"{row['pi_B_jump_mass']:.6g}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("transition_json", nargs="+")
    parser.add_argument("--max-cycle", type=int, default=4)
    parser.add_argument("--eigenvalues", type=int, default=6)
    parser.add_argument("--summary-json")
    args = parser.parse_args()

    results = [
        analyze(path, args.max_cycle, args.eigenvalues) for path in args.transition_json
    ]
    for path, result in zip(args.transition_json, results):
        print_report(path, result)
    if args.summary_json:
        with open(args.summary_json, "w", encoding="utf-8") as out:
            json.dump(results, out, indent=2, sort_keys=True)
            out.write("\n")
        print(f"wrote {args.summary_json}")


if __name__ == "__main__":
    main()
