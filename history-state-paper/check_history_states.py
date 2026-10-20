"""Reproduce the finite examples in history-states.tex.

Compares torsor restrictions with sequential execution and tests the observation
criterion against the definition of a descended median, not just its formula.
Only the Python standard library is required.
"""
from collections import Counter, deque
from fractions import Fraction
from itertools import combinations, permutations, product
from math import factorial, prod
from pathlib import Path
import json


def profile_permutations(profile):
    return [p for p in permutations(range(len(profile)))
            if all(profile[i] == profile[p[i]] for i in range(len(profile)))]


def graph_case(degrees, arities):
    av = [v for v, d in enumerate(degrees) for _ in range(d)]
    be = [e for e, k in enumerate(arities) for _ in range(k)]
    assert len(av) == len(be)
    nr, nc = len(degrees), len(arities)
    rows, cols = profile_permutations(degrees), profile_permutations(arities)

    def canonical(mat):
        return min(tuple(mat[p[i] * nc + q[j]] for i in range(nr) for j in range(nc))
                   for p in rows for q in cols)

    counts = Counter()
    for wire in permutations(range(len(av))):
        mat = [0] * (nr * nc)
        for i, j in enumerate(wire):
            mat[av[i] * nc + be[j]] += 1
        counts[canonical(mat)] += 1

    group_order = prod(factorial(d) for d in degrees) * len(rows)
    group_order *= prod(factorial(k) for k in arities) * len(cols)
    types = []
    for mat, count in sorted(counts.items()):
        # Independent automorphism count from the incidence multiplicity matrix.
        block_aut = sum(all(mat[i * nc + j] == mat[p[i] * nc + q[j]]
                            for i in range(nr) for j in range(nc))
                        for p in rows for q in cols)
        aut = block_aut * prod(factorial(a) for a in mat)
        assert Fraction(count, group_order) == Fraction(1, aut)
        types.append({'matrix': [list(mat[i * nc:(i + 1) * nc]) for i in range(nr)],
                      'bijections': count, 'incidence_automorphisms': aut})
    mass = sum((Fraction(1, a['incidence_automorphisms']) for a in types), Fraction())
    assert mass == Fraction(factorial(len(av)), group_order)
    return {'degrees': degrees, 'arities': arities, 'types': types, 'mass': str(mass)}


def all_distances(adjacency):
    answer = {}
    for root in adjacency:
        dist, queue = {root: 0}, deque([root])
        while queue:
            u = queue.popleft()
            for v in adjacency[u]:
                if v not in dist:
                    dist[v] = dist[u] + 1
                    queue.append(v)
        answer[root] = dist
    return answer


def poset_case(n, rel):
    orders = [p for p in permutations(range(n))
              if all(p.index(i) < p.index(j) for i, j in rel)]
    order_set = set(orders)
    adjacency = {p: [] for p in orders}
    for p in orders:
        for i in range(n - 1):
            q = p[:i] + (p[i + 1], p[i]) + p[i + 2:]
            if q in order_set:
                adjacency[p].append(q)
    distances = all_distances(adjacency)
    for p in orders:
        for q in orders:
            inversions = sum((p.index(i) < p.index(j)) != (q.index(i) < q.index(j))
                             for i, j in combinations(range(n), 2))
            assert distances[p][q] == inversions

    ideals = [bits for bits in range(1 << n)
              if all(not (bits >> j & 1) or bits >> i & 1 for i, j in rel)]
    graph = {u: [v for v in ideals if (u ^ v).bit_count() == 1] for u in ideals}
    dist = all_distances(graph)
    for u in ideals:
        for v in ideals:
            assert dist[u][v] == (u ^ v).bit_count()
            for w in ideals:
                med = (u & v) | (v & w) | (w & u)
                interval_intersection = [z for z in ideals
                                         if all(dist[a][z] + dist[z][b] == dist[a][b]
                                                for a, b in [(u, v), (v, w), (w, u)])]
                assert interval_intersection == [med]
    return len(orders), len(ideals)


def check_posets():
    checked = []
    for n in range(1, 5):
        possible = list(combinations(range(n), 2))
        relations = set()
        for bits in range(1 << len(possible)):
            rel = {pair for i, pair in enumerate(possible) if bits >> i & 1}
            for middle in range(n):
                rel |= {(i, j) for i in range(n) for j in range(n)
                        if (i, middle) in rel and (middle, j) in rel}
            relations.add(tuple(sorted(rel)))
        for rel in relations:
            poset_case(n, rel)
        checked.append({'events': n, 'distinct_naturally_labelled_posets': len(relations)})
    return checked


def naturally_labelled_posets(n):
    possible = list(combinations(range(n), 2))
    relations = set()
    for bits in range(1 << len(possible)):
        rel = {pair for i, pair in enumerate(possible) if bits >> i & 1}
        for middle in range(n):
            rel |= {(i, j) for i in range(n) for j in range(n)
                    if (i, middle) in rel and (middle, j) in rel}
        relations.add(tuple(sorted(rel)))
    return sorted(relations)


def partitions(n):
    """Restricted-growth strings, each set partition exactly once."""
    if not n:
        yield ()
        return

    def extend(prefix, highest):
        if len(prefix) == n:
            yield tuple(prefix)
            return
        for value in range(highest + 2):
            yield from extend(prefix + [value], max(value, highest))

    yield from extend([0], 0)


def median(u, v, w):
    return (u & v) | (v & w) | (w & u)


def ideal_data(n, rel):
    ideals = [bits for bits in range(1 << n)
              if all(not (bits >> j & 1) or bits >> i & 1 for i, j in rel)]
    index = {bits: i for i, bits in enumerate(ideals)}
    edges = [(index[u], index[u | (1 << e)], e)
             for u in ideals for e in range(n)
             if not u >> e & 1 and u | (1 << e) in index]
    triples = [(i, j, k, index[median(u, v, w)])
               for i, u in enumerate(ideals)
               for j, v in enumerate(ideals) if j >= i
               for k, w in enumerate(ideals) if k >= j]
    return ideals, edges, triples


def median_descends(labels, triples):
    outputs = {}
    for i, j, k, med in triples:
        inputs = tuple(sorted((labels[i], labels[j], labels[k])))
        if inputs in outputs and outputs[inputs] != labels[med]:
            return False
        outputs[inputs] = labels[med]
    return True


def coordinate_criterion(n, ideals, edges, labels):
    discarded = 0
    for i, j, event in edges:
        if labels[i] == labels[j]:
            discarded |= 1 << event
    visible = ((1 << n) - 1) ^ discarded
    return all((labels[i] == labels[j]) == ((u ^ v) & visible == 0)
               for i, u in enumerate(ideals) for j, v in enumerate(ideals))


def geometric_criterion(n, ideals, edges, labels):
    for event in range(n):
        collapsed = {labels[i] == labels[j] for i, j, e in edges if e == event}
        if len(collapsed) != 1:
            return False
    for i, u in enumerate(ideals):
        for j, v in enumerate(ideals):
            if labels[i] == labels[j]:
                for k, w in enumerate(ideals):
                    if (u ^ w).bit_count() + (v ^ w).bit_count() == (u ^ v).bit_count():
                        if labels[k] != labels[i]:
                            return False
    return True


def check_observations():
    partition_count = 0
    compatible_count = 0
    projection_count = 0
    additive_count = 0
    witness_count = 0
    repair_count = 0
    for n in range(1, 5):
        for rel in naturally_labelled_posets(n):
            ideals, edges, triples = ideal_data(n, rel)
            if n <= 3:
                accepted = 0
                for labels in partitions(len(ideals)):
                    descended = median_descends(labels, triples)
                    assert descended == coordinate_criterion(n, ideals, edges, labels)
                    assert descended == geometric_criterion(n, ideals, edges, labels)
                    partition_count += 1
                    accepted += descended
                assert accepted == 2**n
                compatible_count += accepted
            for visible in range(1 << n):
                labels = [u & visible for u in ideals]
                assert median_descends(labels, triples)
                images = sorted(set(labels))
                actual_edges = {tuple(sorted((labels[i], labels[j])))
                                for i, j, _ in edges if labels[i] != labels[j]}
                target_edges = {(u, v) for u in images for v in images
                                if u < v and (u ^ v).bit_count() == 1}
                assert actual_edges == target_edges
                for bottom in images:
                    low = bottom
                    for i, j in rel:
                        if bottom >> j & 1:
                            low |= 1 << i
                    blocked = visible & ~bottom
                    high = (1 << n) - 1
                    for i in range(n):
                        if blocked >> i & 1:
                            high &= ~(1 << i)
                            for a, b in rel:
                                if a == i:
                                    high &= ~(1 << b)
                    fibre = [u for u in ideals if u & visible == bottom]
                    assert fibre == [u for u in ideals if u & low == low and u & ~high == 0]
                    enabled = sum(1 << e for e in range(n)
                                  if visible >> e & 1 and not bottom >> e & 1
                                  and bottom | (1 << e) in images)
                    for toggles in range(1 << n):
                        if toggles & ~enabled:
                            continue
                        assert any(all(u | (1 << e) in ideals for e in range(n)
                                       if toggles >> e & 1) for u in fibre)
                projection_count += 1
            graph = {u: [] for u in ideals}
            for i, j, _ in edges:
                graph[ideals[i]].append(ideals[j])
                graph[ideals[j]].append(ideals[i])
            for effect in product([-1, 0, 1], repeat=n):
                labels = [sum(effect[e] for e in range(n) if u >> e & 1) for u in ideals]
                visible = sum(1 << e for e in range(n) if effect[e])
                collisions = {u ^ v
                              for i, u in enumerate(ideals) for j, v in enumerate(ideals)
                              if labels[i] == labels[j] and (u ^ v) & visible}
                assert median_descends(labels, triples) == (not collisions)
                additive_count += 1
                if collisions:
                    i, j = next((i, j) for i, u in enumerate(ideals) for j, v in enumerate(ideals)
                                if labels[i] == labels[j] and (u ^ v) & visible)
                    start, target = ideals[i], ideals[j]
                    previous, queue = {start: None}, deque([start])
                    while target not in previous:
                        u = queue.popleft()
                        for v in graph[u]:
                            if v not in previous:
                                previous[v] = u
                                queue.append(v)
                    path, u = [], target
                    while u is not None:
                        path.append(u)
                        u = previous[u]
                    vertex = next(u for u in path if labels[ideals.index(u)] != labels[i])
                    assert median(start, target, vertex) == vertex
                    assert median(start, start, vertex) == start
                    witness_count += 1
                if n <= 3 or effect == (1,) * n:
                    for retained in range(1 << n):
                        augmented = [(label, u & retained) for u, label in zip(ideals, labels)]
                        hitting = all(retained & collision for collision in collisions)
                        assert median_descends(augmented, triples) == hitting
                        repair_count += 1
    for n in range(2, 7):
        candidates = [mask for mask in range(1 << n)
                      if all(mask & ((1 << a) | (1 << b)) for a, b in combinations(range(n), 2))]
        assert min(mask.bit_count() for mask in candidates) == n - 1
    return {'partitions_tested': partition_count, 'compatible_partitions': compatible_count,
            'coordinate_quotients_and_cube_lifts': projection_count,
            'additive_observations': additive_count, 'explicit_failure_witnesses': witness_count,
            'repair_sets_checked': repair_count, 'equal_effect_minimum_bits_checked_through': 6}


def check_schedule_bias():
    producer = [-1, -1, 0, 1, 2, 3]
    consumer = [0, 1, 2, 3, 4, 4]
    out_types = ['x', 'x', 'x', 'y', 'z', 'w']
    in_types = ['x', 'x', 'x', 'y', 'z', 'w']
    fibres = Counter()
    for wire in permutations(range(6)):
        if any(out_types[o] != in_types[i] for o, i in enumerate(wire)):
            continue
        for order in permutations(range(4)):
            time = {event: t for t, event in enumerate(order)} | {-1: -1, 4: 4}
            if all(time[producer[o]] < time[consumer[i]] for o, i in enumerate(wire)):
                fibres[wire] += 1
    assert sorted(fibres.values()) == [4, 4, 6, 6]
    ordered_total = sum(fibres.values())
    biased = sum(Fraction(count, ordered_total) for count in fibres.values() if count == 4)
    numerator = sum(Fraction(1, ordered_total) for count in fibres.values() if count == 4)
    denominator = sum(Fraction(1, ordered_total) for _ in fibres)
    assert biased == Fraction(2, 5)
    assert numerator / denominator == Fraction(1, 2)
    return {'causal_wirings': len(fibres), 'schedules': ordered_total,
            'schedule_counts': sorted(fibres.values()),
            'ordered_probability_of_first_type': str(biased),
            'debiased_probability_of_first_type': str(numerator / denominator)}


def check_confluent_family():
    records = []
    for branches in range(2, 6):
        for length in range(3, 7):
            source, target = ('s', 0), ('t', length)
            directed = {source: [], target: []}
            for branch in range(branches):
                path = [source] + [(branch, level) for level in range(1, length)] + [target]
                for u, v in zip(path, path[1:]):
                    directed.setdefault(u, []).append(v)
                    directed.setdefault(v, [])
            descendants = {}
            for u in sorted(directed, key=lambda u: u[1], reverse=True):
                descendants[u] = {u} | set().union(*(descendants[v] for v in directed[u]))
                assert target in descendants[u]
                assert all(v[1] == u[1] + 1 for v in directed[u])
            assert all(descendants[v] & descendants[w]
                       for u in directed for v in descendants[u] for w in descendants[u])
            graph = {u: [] for u in directed}
            for u, following in directed.items():
                for v in following:
                    graph[u].append(v)
                    graph[v].append(u)
            distances = all_distances(graph)
            edge_count = sum(len(v) for v in directed.values())
            rank = edge_count - len(directed) + 1
            assert rank == branches - 1
            triple = [source, (0, length - 1), (1, 2)]
            assert not [m for m in graph
                        if all(distances[u][m] + distances[m][v] == distances[u][v]
                               for u, v in combinations(triple, 2))]
            girth = min(1 + all_distances({u: [v for v in adj if {u, v} != {a, b}]
                                          for u, adj in graph.items()})[a][b]
                        for a in graph for b in graph[a])
            assert girth == 2 * length
            records.append({'branches': branches, 'history_length': length,
                            'vertices': len(directed), 'edges': edge_count,
                            'first_betti_number': rank, 'girth': girth,
                            'terminating_confluent': True, 'state_graph_is_median': False})
    return records


def check_histories():
    # Outputs 0,1 are initial x; 2,3 are y born at A,B; 4,5 z born at C,D.
    # Inputs 0,1 consume x at A,B; 2,3 consume y at C,D; 4,5 are final z.
    producer = [-1, -1, 0, 1, 2, 3]
    consumer = [0, 1, 2, 3, 4, 4]
    token_type = ['x', 'x', 'y', 'y', 'z', 'z']
    restricted = set()
    fibres = Counter()
    for wire in permutations(range(6)):
        if any(token_type[o] != token_type[i] for o, i in enumerate(wire)):
            continue
        for order in permutations(range(4)):
            time = {event: t for t, event in enumerate(order)} | {-1: -1, 4: 4}
            if all(time[producer[o]] < time[consumer[i]] for o, i in enumerate(wire)):
                restricted.add((wire, order))
                fibres[wire] += 1

    executed = set()

    def execute(order, available, wire):
        if len(order) == 4:
            assert len(available) == 2
            for final in permutations(available):
                complete = dict(wire) | {o: i + 4 for i, o in enumerate(final)}
                executed.add((tuple(complete[o] for o in range(6)), tuple(order)))
            return
        for event in range(4):
            if event in order:
                continue
            needed = 'x' if event < 2 else 'y'
            for token in available:
                if token_type[token] == needed:
                    execute(order + [event], (available - {token}) | {event + 2},
                            dict(wire) | {token: event})

    execute([], {0, 1}, {})
    assert restricted == executed
    assert len(restricted) == 48 and len(fibres) == 8
    assert set(fibres.values()) == {6}
    return {'framed_histories': len(executed), 'causal_wirings': len(fibres),
            'orders_per_wiring': 6, 'sequential_execution_equals_torsor_restriction': True}


def main():
    graphs = [graph_case([3, 3], [2, 2, 2]), graph_case([2, 2], [2, 2]),
              graph_case([2, 2, 2], [3, 3])]
    assert sorted((t['incidence_automorphisms'], t['bijections']) for t in graphs[0]['types']) == [(8, 432), (12, 288)]
    posets = check_posets()
    histories = check_histories()
    observations = check_observations()
    schedule_bias = check_schedule_bias()
    confluent_family = check_confluent_family()
    cycle = {i: [(i - 1) % 6, (i + 1) % 6] for i in range(6)}
    dist = all_distances(cycle)
    assert not [z for z in cycle
                if all(dist[a][z] + dist[z][b] == dist[a][b]
                       for a, b in [(0, 2), (2, 4), (4, 0)])]
    # Exhaustively check the characteristic-independent permutation equations.
    for prime in [2, 3, 5]:
        for entries in product([0, 1], repeat=9):
            row = [entries[3 * i:3 * i + 3] for i in range(3)]
            col = list(zip(*row))
            equations = all(sum(a) % prime == 1 and all(x * y == 0 for x, y in combinations(a, 2))
                            for a in row + col)
            permutation = all(sum(a) == 1 for a in row + col)
            assert equations == permutation
    out = {'incidence_cases': graphs, 'posets': posets, 'histories': histories,
           'observations': observations, 'schedule_bias': schedule_bias,
           'confluent_family': confluent_family,
           'confluent_six_cycle_is_not_median': True,
           'permutation_equations_checked_over': [2, 3, 5]}
    Path(__file__).with_name('history-states.json').write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps(out, indent=2))


if __name__ == '__main__':
    main()
