#!/usr/bin/env python3
"""Exact rewrite graphs, tree/forest counts and certified quartic bounds.

The graph model and its limitations are specified in integral-torsor.tex,
Section 8, Fields on rewrite graphs and hypergraphs.
No sampled integral values enter the quadrature. Requires python-flint.
"""
from __future__ import annotations

import argparse
import json
from collections import deque
from fractions import Fraction
from itertools import combinations
from math import comb, factorial, floor, ceil, prod
from pathlib import Path

from flint import arb, ctx, fmpq, fmpq_mat

from check_restrictions import (ball, kernel_sum, rat, reference_moments,
                                rising, rule_pair, scalar_coefficients,
                                scalar_reference, stieltjes_moments)


def block_lengths(word):
    assert word.startswith('A')
    return tuple(len(block) for block in word.split('A')[1:])


def rewrite_interval(capacities):
    """Apply A -> AB to strings, retaining precisely the requested interval."""
    initial = 'A' * len(capacities)
    states = {initial}
    arrows = set()
    queue = deque([initial])
    while queue:
        word = queue.popleft()
        for index, letter in enumerate(word):
            if letter != 'A':
                continue
            result = word[:index] + 'AB' + word[index+1:]
            if any(a > b for a, b in zip(block_lengths(result), capacities)):
                continue
            arrows.add((word, result))
            if result not in states:
                states.add(result)
                queue.append(result)
    words = sorted(states, key=lambda word: (len(word), word))
    indices = {word: i for i, word in enumerate(words)}
    edges = sorted((indices[a], indices[b], fmpq(1)) for a, b in arrows)
    target = ''.join('A' + 'B'*n for n in capacities)
    histories = {initial: 1}
    for word in words:
        histories.setdefault(word, 0)
        for a, b in arrows:
            if a == word:
                histories[b] = histories.get(b, 0) + histories[a]
    return words, edges, indices[target], histories[target]


def directed_path_word(edges):
    """Canonical form under directed, edge-color-preserving isomorphism."""
    successors = {u: (v, color) for u, v, color in edges}
    assert len(successors) == len(edges)
    incoming = {v for _, v, _ in edges}
    assert len(incoming) == len(edges)
    sources = set(successors)-incoming
    assert len(sources) == 1
    node = sources.pop()
    letters = []
    seen = set()
    while node in successors:
        assert node not in seen
        seen.add(node)
        node, color = successors[node]
        letters.append(color)
    assert len(letters) == len(edges)
    return ''.join(letters)


def check_path_rewriting(capacities, words, edges):
    # A directed A-edge u->v becomes u->w of color A and w->v of color B.
    # Canonicalization removes all dependence on the temporary vertex names.
    initial = tuple((i, i+1, 'A') for i in range(len(capacities)))
    states = {directed_path_word(initial): initial}
    queue = deque([initial])
    arrows = set()
    while queue:
        path = queue.popleft()
        word = directed_path_word(path)
        # Reverse the vertex names, not the directed edges.
        renamed = [(17-3*u, 17-3*v, color) for u, v, color in path]
        assert directed_path_word(renamed) == word
        new_vertex = 1+max(max(u, v) for u, v, _ in path)
        for edge in path:
            u, v, color = edge
            if color != 'A':
                continue
            result = tuple(e for e in path if e != edge)+((u, new_vertex, 'A'),
                                                          (new_vertex, v, 'B'))
            target = directed_path_word(result)
            if any(a > b for a, b in zip(block_lengths(target), capacities)):
                continue
            arrows.add((word, target))
            if target not in states:
                states[target] = result
                queue.append(result)
    assert set(states) == set(words)
    assert arrows == {(words[u], words[v]) for u, v, _ in edges}


def laplacian(size, edges):
    matrix = fmpq_mat(size, size)
    for u, v, weight in edges:
        assert u != v and weight > 0
        matrix[u, u] += weight
        matrix[v, v] += weight
        matrix[u, v] -= weight
        matrix[v, u] -= weight
    return matrix


def forest_weight(size, edges, components, separate=None):
    total = fmpq(0)
    for selection in combinations(edges, size-components):
        parent = list(range(size))

        def find(u):
            while parent[u] != u:
                u = parent[u]
            return u

        weight = fmpq(1)
        for u, v, conductance in selection:
            a, b = find(u), find(v)
            if a == b:
                break
            parent[a] = b
            weight *= conductance
        else:
            assert len({find(u) for u in range(size)}) == components
            if separate is None or find(separate[0]) != find(separate[1]):
                total += weight
    return total


def graph_data(name, words, edges, target, histories=None):
    size = len(words)
    matrix = laplacian(size, edges)
    grounded = fmpq_mat(size-1, size-1,
                        [matrix[i, j] for i in range(1, size) for j in range(1, size)])
    trees = grounded.det()
    assert trees > 0
    inverse = grounded.inv()
    resistance = inverse[target-1, target-1]
    if size <= 8:
        assert trees == forest_weight(size, edges, 1)
        assert trees*resistance == forest_weight(size, edges, 2, (0, target))
    return {'name': name, 'states_or_vertices': words,
            'edges': [[u, v, str(w)] for u, v, w in edges],
            'initial_vertex': 0, 'terminal_vertex': target,
            'histories_to_terminal': histories,
            'spanning_tree_weight': str(trees),
            'terminal_effective_resistance': str(resistance),
            'separating_two_forest_weight': str(trees*resistance),
            'forests_enumerated_independently': size <= 8,
            'dimension': size-1, 'exact_Stieltjes_order': str(fmpq(size-1, 4))}


def leaf_histories(leaves, events):
    # Ordered histories: at step j there are leaves + 4j choices.
    return prod(leaves+4*j for j in range(events))


def outward(value, places, lower):
    scale = 10**places
    number = (floor if lower else ceil)(float(value)*scale)
    while not (ball(fmpq(number, scale)) <= value.lower() if lower
               else ball(fmpq(number, scale)) >= value.upper()):
        number += -1 if lower else 1
    return f'{number/scale:.{places}f}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--nodes', type=int, default=16)
    parser.add_argument('--json', type=Path,
                        default=Path(__file__).with_name('rewrite-examples.json'))
    parser.add_argument('--tex', type=Path,
                        default=Path(__file__).with_name('rewrite-table.tex'))
    args = parser.parse_args()
    if args.nodes < 8:
        parser.error('--nodes must be at least eight')
    ctx.prec = 768
    graphs = []
    for k in range(1, 5):
        words, edges, target, histories = rewrite_interval((1,)*k)
        check_path_rewriting((1,)*k, words, edges)
        assert len(words) == 2**k and len(edges) == k*2**(k-1)
        assert histories == factorial(k)
        assert all(sum(a != b for a, b in zip(block_lengths(words[u]),
                                             block_lengths(words[v]))) == 1
                   for u, v, _ in edges)
        data = graph_data(f'Q{k}', words, edges, target, histories)
        tree_formula = 2**(2**k-k-1)*prod(j**comb(k, j) for j in range(1, k+1))
        resistance_formula = fmpq(2, 2**k)*sum(
            (fmpq(comb(k, j), j) for j in range(1, k+1, 2)), fmpq(0))
        assert rat(data['spanning_tree_weight']) == tree_formula
        assert rat(data['terminal_effective_resistance']) == resistance_formula
        graphs.append(data)
    words, edges, target, histories = rewrite_interval((3,))
    check_path_rewriting((3,), words, edges)
    path = graph_data('P4', words, edges, target, histories)
    assert path['spanning_tree_weight'] == '1'
    assert path['terminal_effective_resistance'] == '3'
    graphs.insert(2, path)

    # Retain the full incidence graph, with vertices and hyperedges distinct.
    hyperedges = ((0, 1, 2), (1, 2, 3))
    incidence = [(v, 4+i, fmpq(1)) for i, edge in enumerate(hyperedges) for v in edge]
    data = graph_data('incidence', ['v0', 'v1', 'v2', 'v3', 'e0', 'e1'],
                      incidence, 3)
    assert data['spanning_tree_weight'] == '4'
    assert data['terminal_effective_resistance'] == '3'
    data['hyperedges'] = [list(edge) for edge in hyperedges]
    graphs.append(data)

    # Independent forest and walk expansions of the same graph factor.
    walks = []
    for graph in (graphs[1], path):
        size = len(graph['states_or_vertices'])
        matrix = laplacian(size, [(u, v, rat(w)) for u, v, w in graph['edges']])
        transition = fmpq_mat(size-1, size-1,
            [fmpq(0) if i == j else -matrix[i, j]/matrix[i, i]
             for i in range(1, size) for j in range(1, size)])
        target = graph['terminal_vertex']-1
        power = fmpq_mat([[int(i == j) for j in range(size-1)] for i in range(size-1)])
        partial = fmpq(0)
        terms = []
        for j in range(11):
            term = power[target, target]/matrix[target+1, target+1]
            expected = fmpq(1, 2**(j+1)) if graph['name'] == 'Q2' else (
                fmpq(1) if j == 0 else fmpq(1, 2)*fmpq(3, 4)**(j-1))
            assert term == expected
            terms.append(str(term))
            partial += term
            power = power*transition*transition
        tail = fmpq(1, 2**11) if graph['name'] == 'Q2' else 2*fmpq(3, 4)**10
        assert partial+tail == rat(graph['terminal_effective_resistance'])
        walks.append({'graph': graph['name'], 'even_return_terms': terms,
                      'partial_sum': str(partial), 'exact_remaining_tail': str(tail)})

    dimensions = sorted({graph['dimension']+shift for graph in graphs for shift in (0, 2)})
    couplings = (Fraction(1, 10), Fraction(1), Fraction(10))
    reference = {}
    for coupling in couplings:
        q0, q2 = reference_moments(ball(coupling))
        moments = {0: q0, 2: q2}
        for j in range(0, max(dimensions)-2, 2):
            moments[j+4] = ((j+1)*moments[j]-moments[j+2])/ball(coupling)
        for d in dimensions:
            ref = scalar_reference(2, (d-1)//2, coupling, order=224)
            recurrence = moments[d-1]/prod(range(1, d-1, 2))
            assert ref.overlaps(recurrence)
            reference[d, str(coupling)] = ref

    rows = []
    bounds = {}
    node_counts = sorted({2, 4, 8, args.nodes})
    for d in dimensions:
        a = fmpq(d, 4)
        wick = scalar_coefficients(2, 2*args.nodes, (d-1)//2)
        for n, coefficient in enumerate(wick):
            assert coefficient == 4**n*rising(a, n)*rising(a+fmpq(1, 2), n)/factorial(n)
            assert coefficient == fmpq(leaf_histories(d, n)*leaf_histories(d+2, n),
                                        4**n*factorial(n))
        orders = sorted({a, a+1} | ({fmpq(1)} if a <= 1 else set()))
        by_order = {}
        for beta in orders:
            mu = stieltjes_moments(wick, beta)
            if beta == a:
                assert mu == [4**n*rising(a+fmpq(1, 2), n) for n in range(len(mu))]
            records = []
            previous = {}
            for n in node_counts:
                rules = rule_pair(mu, n)
                for coupling in couplings:
                    key = str(coupling)
                    lo, hi = (kernel_sum(rule, coupling, beta) for rule in rules)
                    ref = reference[d, key]
                    assert lo.upper() < ref.lower() and ref.upper() < hi.lower()
                    if key in previous:
                        oldlo, oldhi = previous[key]
                        assert oldlo.upper() < lo.lower() and hi.upper() < oldhi.lower()
                    previous[key] = lo, hi
                    bounds[d, str(beta), n, key] = lo, hi
                    records.append({'nodes': n, 'coupling': key,
                                    'lower_ball': lo.str(120), 'upper_ball': hi.str(120),
                                    'width_upper_bound': str((hi.upper()-lo.lower()).upper()),
                                    'reference_ball': ref.str(40)})
            by_order[str(beta)] = records
        for low_order, high_order in zip(orders, orders[1:]):
            for n in node_counts:
                for coupling in couplings:
                    lo, hi = bounds[d, str(low_order), n, str(coupling)]
                    other_lo, other_hi = bounds[d, str(high_order), n, str(coupling)]
                    assert other_lo.upper() < lo.lower() and hi.upper() < other_hi.lower()
        rows.append({'dimension': d, 'exact_order': str(a),
                     'unsigned_Wick_coefficients': [str(w) for w in wick],
                     'quadrature_by_order': by_order})
        print(f'd={d}, minimal order={a}: coefficients, recurrence and bounds checked', flush=True)

    # Five coefficients already disprove an ordinary Stieltjes realization
    # for the eight-state cube; this does not rely on a numerical fit.
    ordinary_moments = stieltjes_moments(scalar_coefficients(2, 4, 3), 1)
    obstruction = fmpq_mat(3, 3, [ordinary_moments[i+j]
                                  for i in range(3) for j in range(3)]).det()
    assert obstruction == -fmpq(3745374633, 65536)

    correlations = []
    for graph in graphs:
        d = graph['dimension']
        resistance = rat(graph['terminal_effective_resistance'])
        for n in node_counts:
            for coupling in couplings:
                key = str(coupling)
                lo, hi = bounds[d, str(fmpq(d, 4)), n, key]
                numlo, numhi = bounds[d+2, str(fmpq(d+2, 4)), n, key]
                lower, upper = ball(resistance)*numlo/hi, ball(resistance)*numhi/lo
                ref = ball(resistance)*reference[d+2, key]/reference[d, key]
                assert lower.upper() < ref.lower() and ref.upper() < upper.lower()
                correlations.append({'graph': graph['name'], 'nodes': n, 'coupling': key,
                                     'lower_ball': lower.str(120), 'upper_ball': upper.str(120),
                                     'reference_ball': ref.str(40)})

    # A genuinely edge-local interaction on the serial rewrite graph.
    # Tree edge differences are independent Gaussians, so its period is q0^3.
    scalar_wick = scalar_coefficients(2, 2*args.nodes)
    local_wick = [fmpq(1)] + [fmpq(0)]*(2*args.nodes)
    for _ in range(3):
        local_wick = [sum((local_wick[j]*scalar_wick[n-j] for j in range(n+1)), fmpq(0))
                      for n in range(len(local_wick))]
    local = {}
    for beta in (fmpq(3, 4), fmpq(1), fmpq(7, 4)):
        mu = stieltjes_moments(local_wick, beta)
        rules = rule_pair(mu, args.nodes)
        lo, hi = (kernel_sum(rule, 1, beta) for rule in rules)
        ref = reference[1, '1']**3
        assert lo.upper() < ref.lower() and ref.upper() < hi.lower()
        local[str(beta)] = {'lower_ball': lo.str(120), 'upper_ball': hi.str(120),
                            'reference_ball': ref.str(40)}
    for first, second in (('3/4', '1'), ('1', '7/4')):
        assert ball(local[first]['lower_ball']).lower() > ball(local[second]['lower_ball']).upper()
        assert ball(local[first]['upper_ball']).upper() < ball(local[second]['upper_ball']).lower()

    result = {'precision_bits': ctx.prec, 'maximum_nodes': args.nodes,
              'directed_colored_path_rewriting_verified': True,
              'graphs': graphs, 'walk_expansions': walks, 'radial_quadratures': rows,
              'terminal_difference_variances': correlations,
              'Q3_ordinary_Stieltjes_obstruction': {
                  'moments': [str(w) for w in ordinary_moments],
                  'Hankel_determinant_size_3': str(obstruction)},
              'edge_local_P4': {'unsigned_Wick_coefficients': [str(w) for w in local_wick],
                               'nodes': args.nodes, 'coupling': '1', 'quadratures': local}}
    args.json.write_text(json.dumps(result, indent=2)+'\n')
    labels = {'Q1': '$Q_1$', 'Q2': '$Q_2=C_4$', 'P4': '$P_4$',
              'Q3': '$Q_3$', 'Q4': '$Q_4$', 'incidence': r'$B_{\mathcal H}$'}
    lines = [r'\begin{tabular}{lrrrrr}', r'\toprule',
             r'$H$ & $\tau(H)$ & $R(u,v)$ & $a$ & lower $Z_d(1)$ & upper $Z_d(1)$\\',
             r'\midrule']
    for graph in graphs:
        d = graph['dimension']
        lo, hi = bounds[d, str(fmpq(d, 4)), args.nodes, '1']
        tex_order = str(fmpq(d, 4))
        resistance = graph['terminal_effective_resistance']
        lines.append(f"{labels[graph['name']]} & {graph['spanning_tree_weight']} & "
                     f"${resistance}$ & ${tex_order}$ & {outward(lo, 8, True)} & "
                     f"{outward(hi, 8, False)}\\\\")
    lines += [r'\bottomrule', r'\end{tabular}']
    args.tex.write_text('\n'.join(lines)+'\n')
    print(f'{len(graphs)} graphs; exact tree, forest, walk and period checks passed', flush=True)


if __name__ == '__main__':
    main()
