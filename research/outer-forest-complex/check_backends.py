#!/usr/bin/env python3
"""Check the signed chain isomorphism between the two canonicalizers."""
from collections import Counter
from check_forested_complex import Complex, clean, gog, parity

for rank in range(2,5):
    python = Complex(rank,'python')
    native = Complex(rank,'native')
    graph_maps = {}
    for key,graph in python.graphs.items():
        code,order = gog.canonical_code_and_order_from_matrix(graph.matrix,backend='native')
        target = native.graphs[graph.n,code]
        vertices = {old:new for new,old in enumerate(order)}
        edge_images = [target.edge_index[tuple(sorted((vertices[u],vertices[v])))]
                       for u,v in graph.edges]
        graph_maps[key] = target,edge_images
    chain_map = []
    for degree,group in enumerate(python.basis):
        images = []
        for key,mask in group:
            graph = python.graphs[key]
            target,edges = graph_maps[key]
            selected = [edges[e] for e in graph.selected(mask)]
            index,sign = target.lookup[sum(1<<e for e in selected)]
            images.append((index,sign*parity(selected)))
        assert sorted(i for i,_ in images) == list(range(len(native.basis[degree])))
        chain_map.append(images)
    count = 0
    for name in ('C','R','D'):
        for degree in range(1,len(python.basis)):
            for j,column in enumerate(getattr(python,name)[degree]):
                left = Counter()
                for old,value in column.items():
                    index,sign = chain_map[degree-1][old]
                    left[index] += sign*value
                target,sign = chain_map[degree][j]
                right = {i:sign*value for i,value in getattr(native,name)[degree][target].items()}
                assert clean(left) == right,(rank,name,degree,j)
                count += 1
    print(f'Rank {rank}: signed change of basis intertwines {count} C, R and D columns.')
