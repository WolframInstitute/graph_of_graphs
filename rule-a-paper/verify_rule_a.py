#!/usr/bin/env python3
"""Reproduce the exact Rule-A counts and bridge conductance table.

The script deliberately uses only the transition generator and the Python
standard library.  For N=10,12,14, use a nauty/Traces canonical-labelling
backend; the pure-Python backend is intended only for small checks.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
import sys
import time
from collections import Counter, deque
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(1, str(SCRIPT_DIR.parent))

import gog_generate as generator_module
from gog_generate import (
    generate_graph_of_graph_with_transitions,
    known_vertex_count,
    matrix_from_code,
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def state_digest(codes: list[tuple[int, ...]]) -> str:
    digest = hashlib.sha256()
    for code in codes:
        digest.update(",".join(str(value) for value in code).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def transition_count_digest(counts: list[Counter[int]]) -> str:
    digest = hashlib.sha256()
    for source, row in enumerate(counts):
        for target, multiplicity in sorted(row.items()):
            digest.update(f"{source},{target},{multiplicity}\n".encode("ascii"))
    return digest.hexdigest()


def detected_nauty_version() -> str | None:
    commands = (
        ["pkg-config", "--modversion", "nauty"],
        ["brew", "list", "--versions", "nauty"],
    )
    for command in commands:
        try:
            result = subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
            )
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
        version = result.stdout.strip()
        if version.startswith("nauty "):
            version = version.removeprefix("nauty ")
        if version:
            return version
    return None


def bridge_count(matrix: list[list[int]]) -> int:
    """Return the number of bridges in an adjacency-multiplicity matrix."""

    n = len(matrix)
    result = 0
    for a in range(n):
        for b in range(a + 1, n):
            if matrix[a][b] != 1:
                continue
            seen = {a}
            queue: deque[int] = deque([a])
            while queue:
                u = queue.popleft()
                for v, multiplicity in enumerate(matrix[u]):
                    if u == v or multiplicity == 0:
                        continue
                    if (u == a and v == b) or (u == b and v == a):
                        continue
                    if v not in seen:
                        seen.add(v)
                        queue.append(v)
            if b not in seen:
                result += 1
    return result


def reversible_weights(
    counts: list[Counter[int]],
) -> list[Fraction]:
    """Recover exact stationary weights from transition reciprocity."""

    weights: list[Fraction | None] = [None] * len(counts)
    weights[0] = Fraction(1)
    queue: deque[int] = deque([0])
    while queue:
        u = queue.popleft()
        assert weights[u] is not None
        for v, m_uv in counts[u].items():
            if u == v:
                continue
            m_vu = counts[v][u]
            if m_vu == 0:
                raise AssertionError(f"transition {u}->{v} has no reverse")
            candidate = weights[u] * Fraction(m_uv, m_vu)
            if weights[v] is None:
                weights[v] = candidate
                queue.append(v)
            elif weights[v] != candidate:
                raise AssertionError(f"inconsistent reversible weight at class {v}")

    if any(weight is None for weight in weights):
        raise AssertionError("transition support is disconnected")
    return [weight for weight in weights if weight is not None]


def verify(
    n: int, backend: str, nauty_mode: str, jobs: int
) -> dict[str, object]:
    audit_started = time.perf_counter()
    generation_started = time.perf_counter()
    nodes, edges, transitions, complete = generate_graph_of_graph_with_transitions(
        n,
        jobs=jobs,
        backend=backend,
        nauty_mode=nauty_mode,
    )
    generation_seconds = time.perf_counter() - generation_started
    if not complete:
        raise AssertionError("enumeration is not complete")

    ordered = sorted(nodes)
    index = {code: i for i, code in enumerate(ordered)}
    expected_classes = known_vertex_count(n)
    if expected_classes is not None and len(ordered) != expected_classes:
        raise AssertionError(
            f"class count {len(ordered)} != A005967 value {expected_classes}"
        )

    slots = 3 * n
    if len(transitions) != slots * len(ordered):
        raise AssertionError("wrong total number of transition slots")
    counts = [Counter() for _ in ordered]
    for transition in transitions:
        counts[index[transition.source]][index[transition.target]] += 1
    if any(sum(row.values()) != slots for row in counts):
        raise AssertionError("a transition row does not have 3N slots")

    states_sha256 = state_digest(ordered)
    transition_counts_sha256 = transition_count_digest(counts)

    weights = reversible_weights(counts)
    total_weight = sum(weights, Fraction())
    bridges = [bridge_count(matrix_from_code(code, n)) for code in ordered]

    weight_b0 = sum(
        (weights[i] for i, value in enumerate(bridges) if value == 0),
        Fraction(),
    )
    weight_b1 = sum(
        (weights[i] for i, value in enumerate(bridges) if value == 1),
        Fraction(),
    )
    weight_b = total_weight - weight_b0

    exit_weight = Fraction()
    for u, bridge_total in enumerate(bridges):
        if bridge_total == 0:
            continue
        exit_slots = sum(
            multiplicity
            for v, multiplicity in counts[u].items()
            if bridges[v] == 0
        )
        expected_exit_slots = 2 if bridge_total == 1 else 0
        if exit_slots != expected_exit_slots:
            raise AssertionError(
                f"class {u} has {bridge_total} bridges but {exit_slots} exit slots"
            )
        exit_weight += weights[u] * exit_slots

    mass_b0 = weight_b0 / total_weight
    mass_b1 = weight_b1 / total_weight
    mass_b = weight_b / total_weight
    flow = exit_weight / (slots * total_weight)
    if flow != Fraction(2, slots) * mass_b1:
        raise AssertionError("the exact bridge-flow identity failed")
    conductance = flow / min(mass_b0, mass_b)
    finite_pattern = Fraction(2, 3 * n - 2)
    finite_pattern_matches = conductance == finite_pattern
    elapsed_seconds = time.perf_counter() - audit_started

    print(f"N = {n}")
    print(f"classes = {len(ordered)}")
    print(f"support edges = {len(edges)}")
    print(f"slots = {len(transitions)}")
    print(f"pi(B_0) = {mass_b0}")
    print(f"pi(B_1) = {mass_b1}")
    print(f"Q(B, B_0) = {flow}")
    print(f"Phi(B) = {conductance}")
    print(f"finite pattern 2/(3N-2) matches = {finite_pattern_matches}")
    print(f"generation seconds = {generation_seconds:.6f}")
    print(f"audit seconds = {elapsed_seconds:.6f}")
    return {
        "N": n,
        "classes": len(ordered),
        "support_edges": len(edges),
        "slots": len(transitions),
        "pi_B0": str(mass_b0),
        "pi_B1": str(mass_b1),
        "bridge_flow": str(flow),
        "bridge_conductance": str(conductance),
        "finite_pattern": str(finite_pattern),
        "finite_pattern_matches": finite_pattern_matches,
        "states_sha256": states_sha256,
        "transition_counts_sha256": transition_counts_sha256,
        "generation_seconds": round(generation_seconds, 6),
        "audit_seconds": round(elapsed_seconds, 6),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "N", nargs="+", type=int, help="one or more even carrier-vertex counts"
    )
    parser.add_argument(
        "--backend",
        choices=("auto", "native", "nauty", "python"),
        default="auto",
    )
    parser.add_argument(
        "--nauty-mode",
        choices=("dense", "sparse", "traces"),
        default="traces",
    )
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument(
        "--json",
        help="write a machine-readable audit summary after all requested runs pass",
    )
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    results = [
        verify(n, arguments.backend, arguments.nauty_mode, arguments.jobs)
        for n in arguments.N
    ]
    if arguments.json:
        generator_path = Path(generator_module.__file__).resolve()
        verifier_path = Path(__file__).resolve()
        payload = {
            "schema": "rule-a-enumeration-v2",
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "command": sys.argv,
            "backend": arguments.backend,
            "nauty_mode": arguments.nauty_mode,
            "jobs": arguments.jobs,
            "environment": {
                "python": platform.python_version(),
                "platform": platform.platform(),
                "nauty": detected_nauty_version(),
            },
            "source_sha256": {
                generator_path.name: sha256_file(generator_path),
                verifier_path.name: sha256_file(verifier_path),
            },
            "all_complete": True,
            "results": results,
        }
        with open(arguments.json, "w", encoding="utf-8") as output:
            json.dump(payload, output, indent=2, sort_keys=True)
            output.write("\n")
        print(f"wrote {arguments.json}")
