#!/usr/bin/env python3
"""Oriented forested graph complexes of small-rank Outer space.

Loops and parallel edges are retained. Forest orientations are quotiented
by every vertex automorphism; an odd stabilizer kills a generator. Both
contraction and unmarking are computed before any homology is taken.
Requires python-flint and the repository's graph enumerator.
"""
from __future__ import annotations

import argparse
from collections import Counter, deque
from fractions import Fraction as Q
from functools import reduce
from hashlib import sha256
from itertools import combinations
from math import factorial, gcd, prod
from pathlib import Path
import json
import sys
import time

from flint import fmpz_mat, nmod_mat

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
import gog_generate as gog
from check_outer_euler import contract, gaussian_euler_coefficients, stable_graphs
from check_cubic_euler import contract_partition, forest_partitions, odd_double_factorial
from graph_helpers import automorphism_order


def parity(values):
    return (-1)**sum(a > b for i,a in enumerate(values) for b in values[i+1:])


def vertices_automorphisms(matrix):
    n = len(matrix)
    signature = [(matrix[u][u],tuple(sorted(matrix[u][v] for v in range(n) if v != u)))
                 for u in range(n)]
    candidates = [[v for v in range(n) if signature[u] == signature[v]] for u in range(n)]
    order = sorted(range(n),key=lambda u:len(candidates[u]))
    assigned,used = {},set()

    def visit(k):
        if k == n:
            yield tuple(assigned[u] for u in range(n))
            return
        u = order[k]
        for v in candidates[u]:
            if v not in used and all(matrix[u][a] == matrix[v][b] for a,b in assigned.items()):
                assigned[u] = v
                used.add(v)
                yield from visit(k+1)
                used.remove(v)
                del assigned[u]
    return list(visit(0))


def forest_masks(n,edges):
    result = []

    def visit(i,parent,mask):
        if i == len(edges):
            result.append(mask)
            return
        visit(i+1,parent,mask)
        u,v = edges[i]
        while parent[u] != u:
            u = parent[u]
        while parent[v] != v:
            v = parent[v]
        if u != v:
            updated = list(parent)
            updated[u] = v
            visit(i+1,tuple(updated),mask | (1<<i))
    visit(0,tuple(range(n)),0)
    return sorted(result)


def edge_connected(matrix,deleted=()):
    n = len(matrix)
    if n == 1:
        return True
    edges = gog.edges_from_matrix(matrix)
    adjacency = [[] for _ in range(n)]
    for i,(u,v) in enumerate(edges):
        if i not in deleted:
            adjacency[u].append(v)
            adjacency[v].append(u)
    seen,stack = {0},[0]
    while stack:
        for v in adjacency[stack.pop()]:
            if v not in seen:
                seen.add(v)
                stack.append(v)
    return len(seen) == n


class Graph:
    def __init__(self,key,matrix):
        self.key,self.matrix = key,matrix
        self.n = len(matrix)
        self.edges = [(u,v) for u in range(self.n) for v in range(u+1,self.n) if matrix[u][v]]
        self.edge_index = {edge:i for i,edge in enumerate(self.edges)}
        self.vertex_auts = vertices_automorphisms(matrix)
        self.internal_aut = prod(2**matrix[u][u]*factorial(matrix[u][u]) for u in range(self.n))
        self.internal_aut *= prod(factorial(matrix[u][v]) for u,v in self.edges)
        self.aut = len(self.vertex_auts)*self.internal_aut
        assert self.aut == automorphism_order(matrix)
        self.actions = [tuple(self.edge_index[tuple(sorted((perm[u],perm[v])))] for u,v in self.edges)
                        for perm in self.vertex_auts]
        self.masks = forest_masks(self.n,self.edges)
        self.lookup = {}
        self.killed = []
        self.orbit_aut = {}
        self.virtual = Q(0)
        self.orientation_counts = Counter()
        nonloops = [i for i,(u,v) in enumerate(gog.edges_from_matrix(matrix)) if u != v]
        self.bridge_edges = [self.edge_index[tuple(sorted(gog.edges_from_matrix(matrix)[i]))]
                             for i in nonloops if not edge_connected(matrix,(i,))]
        self.bridgeless = not self.bridge_edges
        self.three_connected = self.bridgeless and all(edge_connected(matrix,pair)
                                                       for pair in combinations(nonloops,2))
        self.contractions = {}

    def selected(self,mask):
        return [i for i in range(len(self.edges)) if mask>>i&1]

    def build_orbits(self,basis):
        for mask in self.masks:
            if mask in self.lookup:
                continue
            selected = self.selected(mask)
            images = {}
            odd,stabilizer = False,0
            for action in self.actions:
                image = [action[i] for i in selected]
                target = sum(1<<i for i in image)
                sign = parity(image)
                if target in images and images[target] != sign:
                    odd = True
                images[target] = sign
                stabilizer += target == mask
            assert len(images)*stabilizer == len(self.vertex_auts)
            internal_stabilizer = self.internal_aut//prod(self.matrix[u][v]
                                                        for i,(u,v) in enumerate(self.edges) if mask>>i&1)
            aut = stabilizer*internal_stabilizer
            self.orbit_aut[mask] = aut
            degree = len(selected)
            self.virtual += Q((-1)**degree,aut)
            self.orientation_counts[degree,odd] += 1
            if odd:
                self.killed.append(mask)
                for image in images:
                    self.lookup[image] = None
            else:
                index = len(basis[degree])
                basis[degree].append((self.key,mask))
                for image,sign in images.items():
                    self.lookup[image] = index,sign


def clean(column):
    return {i:c for i,c in column.items() if c}


def combine(first,second,sign=1):
    result = Counter(first)
    for i,c in second.items():
        result[i] += sign*c
    return clean(result)


class Complex:
    def __init__(self,rank,backend):
        self.rank,self.backend = rank,backend
        codes = stable_graphs(rank,backend)
        self.graphs = {(n,code):Graph((n,code),gog.matrix_from_code(code,n))
                       for n,values in sorted(codes.items()) for code in sorted(values)}
        self.basis = [[] for _ in range(2*rank-2)]
        for graph in self.graphs.values():
            graph.build_orbits(self.basis)
        self.C,self.R,self.D = [[[] for _ in self.basis] for _ in range(3)]
        for degree in range(1,len(self.basis)):
            for key,mask in self.basis[degree]:
                contraction,removal = self.boundary(self.graphs[key],mask)
                self.C[degree].append(contraction)
                self.R[degree].append(removal)
                self.D[degree].append(combine(contraction,removal,-1))
        for graph in self.graphs.values():
            for mask in graph.killed:
                contraction,removal = self.boundary(graph,mask)
                assert not contraction and not removal, (graph.key,mask)

    def contraction_data(self,graph,edge):
        if edge in graph.contractions:
            return graph.contractions[edge]
        u,v = graph.edges[edge]
        smaller = contract(graph.matrix,u,v)
        code,order = gog.canonical_code_and_order_from_matrix(smaller,backend=self.backend)
        assert gog.code_from_matrix(smaller,order) == code
        key = len(smaller),code
        target = self.graphs[key]
        vertices = [i for i in range(graph.n) if i != v]
        merged = {i:vertices.index(u if i == v else i) for i in range(graph.n)}
        canonical = {old:new for new,old in enumerate(order)}
        images = []
        for a,b in graph.edges:
            x,y = canonical[merged[a]],canonical[merged[b]]
            images.append(None if x == y else target.edge_index[tuple(sorted((x,y)))])
        graph.contractions[edge] = target,images
        return target,images

    def boundary(self,graph,mask):
        selected = graph.selected(mask)
        contraction,removal = Counter(),Counter()
        for position,edge in enumerate(selected):
            sign = (-1)**position
            remaining = [e for e in selected if e != edge]
            raw = graph.lookup[mask ^ (1<<edge)]
            if raw is not None:
                index,orientation = raw
                removal[index] += sign*orientation
            target,images = self.contraction_data(graph,edge)
            image = [images[e] for e in remaining]
            assert all(e is not None for e in image) and len(set(image)) == len(image)
            target_mask = sum(1<<e for e in image)
            raw = target.lookup[target_mask]
            if raw is not None:
                index,orientation = raw
                contraction[index] += sign*parity(image)*orientation
        return clean(contraction),clean(removal)

    def verify_squared(self):
        def compose(left,right):
            out = Counter()
            for middle,a in right.items():
                for row,b in left[middle].items():
                    out[row] += a*b
            return clean(out)
        count = 0
        for k in range(2,len(self.basis)):
            for j in range(len(self.basis[k])):
                assert not compose(self.D[k-1],self.D[k][j])
                assert not compose(self.C[k-1],self.C[k][j])
                assert not compose(self.R[k-1],self.R[k][j])
                cr = compose(self.C[k-1],self.R[k][j])
                rc = compose(self.R[k-1],self.C[k][j])
                assert not combine(cr,rc)
                count += 1
        return count

    def selection(self,family):
        return [[i for i,(key,_) in enumerate(group)
                 if family == 'full' or getattr(self.graphs[key],family)] for group in self.basis]


def matrix(columns,nrows,selected_columns=None,selected_rows=None):
    selected_columns = list(range(len(columns))) if selected_columns is None else selected_columns
    selected_rows = list(range(nrows)) if selected_rows is None else selected_rows
    row_indices = {i:j for j,i in enumerate(selected_rows)}
    result = fmpz_mat(len(selected_rows),len(selected_columns))
    for j,old in enumerate(selected_columns):
        for row,value in columns[old].items():
            if row in row_indices:
                result[row_indices[row],j] = value
    return result


def modular_rank(columns,selected_columns,selected_rows,prime=65521):
    """Exact sparse singleton/two-entry elimination, then a dense mod-p core."""
    row_names = {old:i for i,old in enumerate(selected_rows)}
    rows = [dict() for _ in selected_rows]
    for j,old in enumerate(selected_columns):
        for i,value in columns[old].items():
            if i in row_names and value % prime:
                rows[row_names[i]][j] = value % prime
    col_rows = [set() for _ in selected_columns]
    for i,row in enumerate(rows):
        for j in row:
            col_rows[j].add(i)
    queue = deque(i for i,row in enumerate(rows) if 0 < len(row) <= 2)
    col_queue = deque(j for j,values in enumerate(col_rows) if 0 < len(values) <= 2)
    pivots,duplicates = 0,0
    while True:
        while queue or col_queue:
            if queue:
                i = queue.popleft()
                if not 0 < len(rows[i]) <= 2:
                    continue
                pivot = min(rows[i],key=lambda j:len(col_rows[j]))
            else:
                pivot = col_queue.popleft()
                if not 0 < len(col_rows[pivot]) <= 2:
                    continue
                i = min(col_rows[pivot],key=lambda r:len(rows[r]))
            inverse = pow(rows[i][pivot],-1,prime)
            rest = {j:value*inverse % prime for j,value in rows[i].items() if j != pivot}
            for other in list(col_rows[pivot]):
                if other == i:
                    continue
                multiplier = rows[other].pop(pivot)
                for j,value in rest.items():
                    updated = (rows[other].get(j,0)-multiplier*value) % prime
                    if updated:
                        rows[other][j] = updated
                        col_rows[j].add(other)
                    else:
                        rows[other].pop(j,None)
                        col_rows[j].discard(other)
                    if 0 < len(col_rows[j]) <= 2:
                        col_queue.append(j)
                if 0 < len(rows[other]) <= 2:
                    queue.append(other)
            for j in rows[i]:
                col_rows[j].discard(i)
                if 0 < len(col_rows[j]) <= 2:
                    col_queue.append(j)
            rows[i].clear()
            col_rows[pivot].clear()
            pivots += 1
        # Proportional nonzero rows do not affect rank and can expose new
        # singleton/two-entry pivots. Everything here is exact in F_p.
        representatives = {}
        removed = 0
        for i,row in enumerate(rows):
            if not row:
                continue
            first = min(row)
            inverse = pow(row[first],-1,prime)
            signature = tuple((j,value*inverse % prime) for j,value in sorted(row.items()))
            if signature in representatives:
                for j in row:
                    col_rows[j].discard(i)
                    if 0 < len(col_rows[j]) <= 2:
                        col_queue.append(j)
                row.clear()
                removed += 1
            else:
                representatives[signature] = i
        duplicates += removed
        if not removed:
            break
        queue.extend(i for i,row in enumerate(rows) if 0 < len(row) <= 2)
    used_rows = [row for row in rows if row]
    used_columns = sorted({j for row in used_rows for j in row})
    indices = {old:j for j,old in enumerate(used_columns)}
    core = nmod_mat(len(used_rows),len(used_columns),prime)
    for i,row in enumerate(used_rows):
        for j,value in row.items():
            core[i,indices[j]] = value
    return pivots+core.rank(),{'sparse_pivots':pivots,'proportional_rows_removed':duplicates,
                               'dense_core_shape':[core.nrows(),core.ncols()]}


def homology(complex,selected,exact):
    dimensions = list(map(len,selected))
    ranks,modular = [0],[0]
    reductions = []
    for k in range(1,len(selected)):
        modrank,reduction = modular_rank(complex.D[k],selected[k],selected[k-1])
        rank = modrank
        if exact:
            M = matrix(complex.D[k],len(complex.basis[k-1]),selected[k],selected[k-1])
            rank = M.rank()
            assert rank == modrank
            assert nmod_mat(M,65521).rank() == modrank
        ranks.append(rank)
        modular.append(modrank)
        reductions.append(reduction)
    betti = [dimension-ranks[k]-(ranks[k+1] if k+1 < len(ranks) else 0)
             for k,dimension in enumerate(dimensions)]
    assert all(b >= 0 for b in betti)
    return {'chain_dimensions':dimensions,'boundary_ranks':ranks,
            'ranks_mod_65521':modular,'rational_betti' if exact else 'rational_betti_upper_bounds':betti,
            'sparse_rank_reductions':reductions,
            'ordinary_Euler_characteristic':sum((-1)**k*d for k,d in enumerate(dimensions))}


def homology_from_acyclic_quotient(selected,subcomplex,quotient,name):
    """The long exact sequence certifies homology, then determines all ranks."""
    assert not any(quotient['rational_betti_upper_bounds'])
    assert subcomplex['rational_homology_certified']
    betti = subcomplex['rational_betti_upper_bounds']
    dimensions = list(map(len,selected))
    ranks = [0]
    for k in range(len(dimensions)-1):
        ranks.append(dimensions[k]-betti[k]-ranks[-1])
    assert dimensions[-1]-ranks[-1] == betti[-1] and all(r >= 0 for r in ranks)
    return {'chain_dimensions':dimensions,'boundary_ranks':ranks,
            'rational_betti':betti,'rational_betti_upper_bounds':betti,
            'rational_homology_certified':True,
            'rank_method':'long exact sequence with certified acyclic quotient '+name,
            'ordinary_Euler_characteristic':sum((-1)**k*d for k,d in enumerate(dimensions))}


def bridge_quotient_certificate(complex,selections):
    """Contract the associated graded by averaging insertion of a bridge.

    With filtration given by the number of bridges, contracting a bridge
    lowers filtration. All other contractions preserve the bridge set.
    On a graph with b>0 bridges, h=-b^{-1}(sum bridge) wedge - gives
    D0 h+h D0=1. This is checked on every oriented quotient generator.
    """
    selected = [sorted(set(a)-set(b)) for a,b in zip(selections['full'],selections['bridgeless'])]
    h,D0 = [],[]
    for k,group in enumerate(complex.basis):
        h_group,d_group = [],[]
        for j,(key,mask) in enumerate(group):
            graph = complex.graphs[key]
            b = len(graph.bridge_edges)
            if k:
                assert all(len(complex.graphs[complex.basis[k-1][i][0]].bridge_edges) <= b
                           for i in complex.D[k][j])
            h_column = Counter()
            if b:
                for edge in graph.bridge_edges:
                    if not mask>>edge&1:
                        target = graph.lookup[mask | (1<<edge)]
                        if target is not None:
                            index,sign = target
                            ordered = [edge]+graph.selected(mask)
                            h_column[index] -= Q(sign*parity(ordered),b)
            h_group.append(clean(h_column))
            d_group.append({i:value for i,value in complex.D[k][j].items()
                            if len(complex.graphs[complex.basis[k-1][i][0]].bridge_edges) == b}
                           if k else {})
        h.append(h_group)
        D0.append(d_group)

    def action(columns,vector):
        result = Counter()
        for j,a in vector.items():
            for i,b in columns[j].items():
                result[i] += a*b
        return clean(result)

    count = 0
    for k,indices in enumerate(selected):
        for j in indices:
            first = action(D0[k+1],h[k][j]) if k+1 < len(h) else {}
            second = action(h[k-1],D0[k][j]) if k else {}
            assert combine(first,second) == {j:1},(complex.rank,k,j)
            count += 1
    dimensions = list(map(len,selected))
    ranks = [0]
    for k in range(len(dimensions)-1):
        ranks.append(dimensions[k]-ranks[-1])
    assert dimensions[-1] == ranks[-1] and all(r >= 0 for r in ranks)
    return {'chain_dimensions':dimensions,'boundary_ranks':ranks,
            'rational_betti':[0]*len(dimensions),'rational_betti_upper_bounds':[0]*len(dimensions),
            'rank_method':'finite bridge filtration with explicit associated-graded homotopy',
            'filtration_homotopy_columns_verified':count,
            'ordinary_Euler_characteristic':0}


def primitive(values):
    common = reduce(gcd,(abs(int(x)) for x in values if x),0)
    return [int(x)//common for x in values]


def excess_homology(complex,selected,exact):
    """C raises excess and preserves p=forest degree+excess."""
    limit = 2*complex.rank-2
    blocks = []
    for p in range(limit):
        groups = [[i for i in selected[p-excess]
                   if limit-complex.basis[p-excess][i][0][0] == excess]
                  for excess in range(p+1)]
        dimensions = list(map(len,groups))
        ranks = []
        for excess in range(p):
            degree = p-excess
            columns = complex.C[degree]
            allowed = set(groups[excess+1])
            assert all(set(columns[j]) <= allowed for j in groups[excess])
            rank,_ = modular_rank(columns,groups[excess],groups[excess+1])
            if exact:
                assert rank == matrix(columns,len(complex.basis[degree-1]),
                                      groups[excess],groups[excess+1]).rank()
            ranks.append(rank)
        betti = [d-(ranks[e] if e < p else 0)-(ranks[e-1] if e else 0)
                 for e,d in enumerate(dimensions)]
        assert all(b >= 0 for b in betti) and not any(betti[1:]),(complex.rank,p,betti)
        # Vanishing upper bounds at all positive excesses certify exact
        # rational ranks, working backwards from the last nonzero block.
        blocks.append({'p':p,'dimensions_by_excess':dimensions,
                       'contraction_ranks':ranks,'homology_by_excess':betti,
                       'rational_ranks_certified':True})
    return blocks


def verify_witness(complex,witness):
    """Re-read serialized terms, then check cycles and dual equations exactly."""
    degree = witness['degree']

    def decode(terms):
        values = Counter()
        for term in terms:
            key = term['vertices'],tuple(term['code'])
            graph = complex.graphs[key]
            ordered = [graph.edge_index[tuple(sorted(edge))] for edge in term['ordered_forest']]
            assert len(ordered) == degree and len(set(ordered)) == degree
            index,sign = graph.lookup[sum(1<<e for e in ordered)]
            values[index] += term['coefficient']*parity(ordered)*sign
        return clean(values)

    cycle,dual = decode(witness['cycle']),decode(witness['cocycle'])
    for operator in (complex.C,complex.R,complex.D):
        boundary = Counter()
        for j,a in cycle.items():
            for i,b in operator[degree][j].items():
                boundary[i] += a*b
        assert not clean(boundary)
    assert all(sum(dual.get(i,0)*b for i,b in col.items()) == 0
               for col in complex.D[degree+1])
    pairing = sum(a*dual.get(i,0) for i,a in cycle.items())
    assert pairing == witness['pairing'] and pairing != 0
    return cycle


def triangle_product(complex,witness):
    """The prism cycle is the nine-term product of two triangle cycles."""
    cycle = verify_witness(complex,witness)
    key,mask = complex.basis[4][next(iter(cycle))]
    graph = complex.graphs[key]
    assert graph.n == 6 and all(x <= 1 for row in graph.matrix for x in row)
    triangles = [t for t in combinations(range(6),3)
                 if all(graph.matrix[a][b] for a,b in combinations(t,2))]
    assert len(triangles) == 2 and set(triangles[0]).isdisjoint(triangles[1])
    local = []
    for triangle in triangles:
        edges = [graph.edge_index[e] for e in combinations(triangle,2)]
        local.append([(edges[:i]+edges[i+1:],(-1)**i) for i in range(3)])
    product = Counter()
    for top,a in local[0]:
        for bottom,b in local[1]:
            ordered = top+bottom
            target,sign = graph.lookup[sum(1<<e for e in ordered)]
            product[target] += a*b*parity(ordered)*sign
    product = clean(product)
    multiplier = Q(product[next(iter(cycle))],cycle[next(iter(cycle))])
    assert multiplier.denominator == 1
    assert product == {i:int(multiplier)*value for i,value in cycle.items()}
    return {'triangles':[list(t) for t in triangles],
            'nine_term_product_multiple_of_archived_cycle':int(multiplier)}


def ordinary_euler_observable(complex):
    """Transfer oriented-orbit Euler weights to the cubic stationary law."""
    epsilon = Counter()
    for k,group in enumerate(complex.basis):
        for key,_ in group:
            epsilon[key] += (-1)**k
    normalizer = first = second = Q(0)
    rows = []
    fibre_weights = Counter()
    for graph in complex.graphs.values():
        if graph.n != 2*complex.rank-2:
            continue
        weight = Q(1,graph.aut)
        observable = Q(0)
        forest_count = 0
        for partition,multiplicity in forest_partitions(graph.matrix).items():
            contracted = contract_partition(graph.matrix,partition)
            key = len(contracted),gog.canonical_code_from_matrix(contracted,backend=complex.backend)
            target = complex.graphs[key]
            refinements = prod(odd_double_factorial(2*len(part)-1) for part in partition)
            observable += Q(multiplicity*target.aut*epsilon[key],refinements)
            fibre_weights[key] += multiplicity*weight
            forest_count += multiplicity
        normalizer += weight
        first += weight*observable
        second += weight*observable**2
        rows.append({'code':list(graph.key[1]),'automorphism_order':graph.aut,
                     'observable':str(observable),'forests':forest_count})
    for key,graph in complex.graphs.items():
        degrees = [sum(row)+row[i] for i,row in enumerate(graph.matrix)]
        refinements = prod(odd_double_factorial(2*d-5) for d in degrees)
        assert fibre_weights[key] == Q(refinements,graph.aut)
    expected = sum(epsilon.values())
    assert first == expected and expected
    mean = first/normalizer
    variance = second/normalizer-mean**2
    return {'ordinary_Euler_characteristic':expected,'cubic_symmetry_weight':str(normalizer),
            'mean':str(mean),'variance':str(variance),
            'independent_sample_relative_variance':str(variance/mean**2),
            'graphs':rows}


def refinement_obstruction():
    """Admissibility of simultaneous vertex expansions is not a product rule."""
    matrices = [
        [[0,6],[6,0]],
        [[0,1,3],[1,0,3],[3,3,0]],
        [[0,1,3,0],[1,0,0,3],[3,0,0,1],[0,3,1,0]],
    ]
    graphs = [Graph((len(m),gog.code_from_matrix(m,tuple(range(len(m))))),m) for m in matrices]
    assert [g.three_connected for g in graphs] == [True,True,False]
    edges = gog.edges_from_matrix(matrices[-1])
    separating = [edges.index(edge) for edge in ((0,1),(2,3))]
    assert edge_connected(matrices[-1]) and not edge_connected(matrices[-1],separating)
    return {'rank':5,'six_parallel_edges':matrices[0],
            'one_three_plus_three_split':matrices[1],
            'two_aligned_splits':matrices[2],
            'three_edge_connected':[g.three_connected for g in graphs],
            'separating_pair':[[0,1],[2,3]]}


def rank_two_incidence(complex):
    """Distinguish cell boundaries from labelled resolution multiplicities."""
    assert complex.rank == 2
    rose = next(i for i,(key,_) in enumerate(complex.basis[0]) if key[0] == 1)
    rose_graph = complex.graphs[complex.basis[0][rose][0]]
    rows = []
    for j,(key,mask) in enumerate(complex.basis[1]):
        graph = complex.graphs[key]
        assert complex.C[1][j] == {rose:1}
        forest_aut = graph.orbit_aut[mask]
        rows.append({'source':'theta' if graph.matrix[0][0] == 0 else 'dumbbell',
                     'source_forest_automorphism_order':forest_aut,
                     'contraction_coefficient':1,
                     'labelled_resolution_multiplicity':rose_graph.aut//forest_aut})
    assert {v['source']:v['labelled_resolution_multiplicity'] for v in rows} == {'theta':2,'dumbbell':1}
    return {'target_automorphism_order':rose_graph.aut,'sources':rows}


def morita_witness(complex):
    k = 4
    eligible = [i for i,(key,_) in enumerate(complex.basis[k])
                if key[0] == 2*complex.rank-2 and complex.graphs[key].three_connected]
    D = matrix(complex.D[k],len(complex.basis[k-1]))
    Dnext = matrix(complex.D[k+1],len(complex.basis[k]))
    restricted = matrix(complex.D[k],len(complex.basis[k-1]),eligible)
    cycles,count = restricted.nullspace()
    cocycles,dual_count = Dnext.transpose().nullspace()
    best = None
    for i in range(count):
        local = primitive([cycles[j,i] for j in range(cycles.nrows())])
        c = [0]*len(complex.basis[k])
        for j,value in zip(eligible,local):
            c[j] = value
        for a in range(dual_count):
            dual = primitive([cocycles[j,a] for j in range(cocycles.nrows())])
            pairing = sum(x*y for x,y in zip(c,dual))
            if pairing:
                cost = sum(bool(x) for x in c)+sum(bool(x) for x in dual)
                if best is None or cost < best[0]:
                    best = cost,c,dual,pairing
    assert best is not None
    _,c,dual,pairing = best
    # Display the two-term prism class with positive coefficient on the
    # aligned-centre forest. The pairing then has the same sign.
    if pairing < 0:
        c = [-x for x in c]
        pairing = -pairing
    assert D*fmpz_mat(len(c),1,c) == fmpz_mat(D.nrows(),1)
    assert Dnext.transpose()*fmpz_mat(len(dual),1,dual) == fmpz_mat(Dnext.ncols(),1)

    def serialize(values):
        terms = []
        for i,value in enumerate(values):
            if value:
                key,mask = complex.basis[k][i]
                graph = complex.graphs[key]
                terms.append({'coefficient':value,'vertices':key[0],'code':list(key[1]),
                              'ordered_forest':[list(graph.edges[e]) for e in graph.selected(mask)]})
        return terms
    return {'degree':k,'cycle':serialize(c),'cocycle':serialize(dual),'pairing':pairing,
            'cycle_supported_on_three_edge_connected_cubic_graphs':True}


def check(rank,backend,exact):
    start = time.monotonic()
    X = Complex(rank,backend)
    squared = X.verify_squared()
    virtual = sum((g.virtual for g in X.graphs.values()),Q(0))
    assert virtual == gaussian_euler_coefficients(rank)[rank-1]
    if not exact:
        print(f'rank {rank}: complex built; dims={list(map(len,X.basis))}; '
              'checking smaller complex and successive quotients',flush=True)
    families = {}
    selections = {family:X.selection(family) for family in ('full','bridgeless','three_connected')}
    for family,selection in selections.items():
        for k in range(1,len(selection)):
            allowed = set(selection[k-1])
            assert all(set(X.D[k][j]) <= allowed for j in selection[k])
        assert selection[0] and all(sum(X.D[1][j].values()) == 0 for j in selection[1])
        if exact or family == 'three_connected':
            families[family] = homology(X,selection,exact)
    if not exact:
        data = families['three_connected']
        assert data['rational_betti_upper_bounds'] == [1]+[0]*(len(X.basis)-1)
        data['rational_homology_certified'] = True
        print(f'rank {rank}: three-edge-connected rational homology certified',flush=True)
    quotients = {}
    for large,small in (('full','bridgeless'),('bridgeless','three_connected')):
        selected = [sorted(set(a)-set(b)) for a,b in zip(selections[large],selections[small])]
        if large == 'full':
            certificate = bridge_quotient_certificate(X,selections)
            value = homology(X,selected,exact) if exact else certificate
            if exact:
                assert value['boundary_ranks'] == certificate['boundary_ranks']
                value['filtration_homotopy_columns_verified'] = certificate['filtration_homotopy_columns_verified']
        else:
            value = homology(X,selected,exact)
        key = 'rational_betti' if exact else 'rational_betti_upper_bounds'
        assert not any(value[key])
        quotients[large+'/'+small] = value
        if not exact:
            print(f'rank {rank}: quotient {large}/{small} is acyclic',flush=True)
    if not exact:
        for large,small in (('bridgeless','three_connected'),('full','bridgeless')):
            name = large+'/'+small
            families[large] = homology_from_acyclic_quotient(
                selections[large],families[small],quotients[name],name)
        families = {name:families[name] for name in selections}
    if not exact:
        print(f'rank {rank}: checking contraction homology by excess',flush=True)
    contractions = {family:excess_homology(X,selection,exact)
                    for family,selection in selections.items()}
    observable = ordinary_euler_observable(X)
    witness = morita_witness(X) if rank == 4 else None
    if witness:
        witness['triangle_product'] = triangle_product(X,witness)
    key = 'rational_betti' if exact else 'rational_betti_upper_bounds'
    for family,data in families.items():
        expected = [int(k == 0 or (rank == 4 and k == 4)) for k in range(len(X.basis))]
        assert data[key] == expected,(rank,family,data[key])
        # Mod-p ranks are lower bounds on rational ranks. If the resulting
        # upper bound vanishes in positive degrees, H0>=1 from augmentation
        # certifies equality in every degree without trusting two primes.
        data['rational_homology_certified'] = exact or (rank != 4 and data[key] == expected)
    hashes = []
    for k in range(1,len(X.basis)):
        entries = [(j,i,c) for j,column in enumerate(X.D[k]) for i,c in sorted(column.items())]
        hashes.append(sha256(json.dumps(entries,separators=(',',':')).encode()).hexdigest())
    print(f'rank {rank}: dims={list(map(len,X.basis))}; '
          f'H={families["full"][key]}; chi_virt={virtual}; '
          f'all identities and quotient checks pass ({time.monotonic()-start:.2f}s)',flush=True)
    return {'rank':rank,'stable_graph_types':len(X.graphs),
            'raw_simple_forest_masks':sum(len(g.masks) for g in X.graphs.values()),
            'orientation_reversing_orbits_killed':sum(len(g.killed) for g in X.graphs.values()),
            'd_squared_and_bicomplex_columns_checked':squared,
            'virtual_Euler_characteristic':str(virtual),'families':families,'quotients':quotients,
            'contraction_homology_by_excess':contractions,
            'ordinary_Euler_cubic_observable':observable,
            'rank_two_resolution_incidence':rank_two_incidence(X) if rank == 2 else None,
            'boundary_matrix_sha256':hashes,'degree_four_witness':witness}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--min-rank',type=int,default=2)
    parser.add_argument('--max-rank',type=int,default=4)
    parser.add_argument('--backend',choices=['native','python'],default='native')
    parser.add_argument('--json',type=Path,default=Path(__file__).with_name('forested-complex.json'))
    args = parser.parse_args()
    if not 2 <= args.min_rank <= args.max_rank <= 5:
        parser.error('rank range must be an interval between two and five')
    result = {'convention':'d=contraction-unmarking; forest-edge order gives orientation; loops allowed',
              'backend':args.backend,'prime_for_rank_lower_bounds':65521,
              'nonlocal_refinement_obstruction':refinement_obstruction(),
              'results':[check(rank,args.backend,exact=rank<=4)
                         for rank in range(args.min_rank,args.max_rank+1)]}
    args.json.write_text(json.dumps(result,indent=2)+'\n')


if __name__ == '__main__':
    main()
