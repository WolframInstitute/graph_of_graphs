"""Exact checks of the rank bound for every two-realizer through size seven."""

import itertools
import json
from pathlib import Path


def largest_interval(perm):
    n = len(perm)
    largest = 1
    for i in range(n):
        lo = hi = perm[i]
        for j in range(i + 1, n):
            lo, hi = min(lo, perm[j]), max(hi, perm[j])
            size = j - i + 1
            if size < n and hi - lo + 1 == size:
                largest = max(largest, size)
    return largest


def extensions(pred):
    n = len(pred)
    full = (1 << n) - 1

    def generate(order, mask):
        if mask == full:
            yield order
            return
        for v in range(n):
            bit = 1 << v
            if not mask & bit and pred[v] & mask == pred[v]:
                yield from generate(order + (v,), mask | bit)
    yield from generate((), 0)


reports = []
for n in range(4, 8):
    bases = checked = 0
    max_distance = 0
    for perm in itertools.permutations(range(n)):
        bound = largest_interval(perm)
        if 2 * bound >= n:
            continue
        bases += 1
        pred = [0] * n
        for i in range(n):
            for j in range(i + 1, n):
                if perm[i] < perm[j]:
                    pred[j] |= 1 << i
        for order in extensions(pred):
            first = [0] * n
            for rank, v in enumerate(order):
                first[v] = rank
            second = [0] * n
            for i in range(n):
                for j in range(i + 1, n):
                    if perm[i] < perm[j]:
                        second[j] += 1
                    elif first[i] < first[j]:
                        second[i] += 1
                    else:
                        second[j] += 1
            # A tournament is transitive iff its indegrees are 0,...,n-1.
            if len(set(second)) != n:
                continue
            direct = max(max(abs(first[v] - v), abs(second[v] - perm[v])) for v in range(n))
            swapped = max(max(abs(second[v] - v), abs(first[v] - perm[v])) for v in range(n))
            distance = min(direct, swapped)
            assert distance <= bound - 1, (perm, order, first, second, bound, distance)
            checked += 1
            max_distance = max(max_distance, distance)
    record = {
        "size": n, "base_permutations_with_small_proper_intervals": bases,
        "ordered_two_realizers_checked": checked, "largest_rank_discrepancy": max_distance,
        "deterministic_bound": "largest proper common interval minus one",
    }
    reports.append(record)
    print(json.dumps(record), flush=True)

root = Path(__file__).resolve().parent
(root / "rank-ambiguity-checks.json").write_text(json.dumps(reports, indent=2) + "\n")
