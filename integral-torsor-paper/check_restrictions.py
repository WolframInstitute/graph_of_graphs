#!/usr/bin/env python3
"""Exact Wick coefficients and certified generalized Stieltjes quadrature.

The proof is in integral-torsor.tex. Rational Hankel systems construct monic
orthogonal polynomials; Arb isolates their roots and encloses positive
Christoffel weights and kernel evaluations. No fitted integral values enter
the quadrature. Requires python-flint. Run from any working directory.
"""
from __future__ import annotations

import argparse
import json
import sys
from fractions import Fraction as Q
from itertools import permutations
from math import factorial, prod
from pathlib import Path

from flint import arb, arb_mat, ctx, fmpq, fmpq_mat, fmpq_poly

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'research' / 'integral-torsor'))
from check_quartic_torsor import reference_moments, weak_coefficients
from wick_pairings import moments_by_topology


def rat(x):
    return fmpq(str(x))


def ball(x):
    return arb(str(x))


def rising(a, n):
    return prod((rat(a) + k for k in range(n)), start=fmpq(1))


def wick_coefficients(size, order):
    """Unsigned coefficients of Z_size(lambda), by the moment determinant."""
    moments = {}
    for j in range(0, 2*size-1, 2):
        values = [fmpq(prod(range(1, j, 2)))]
        for k in range(order):
            values.append(values[-1] * fmpq((j+4*k+1)*(j+4*k+3),
                                             4*size*(k+1)))
        moments[j] = fmpq_poly(values)
    determinant = fmpq_poly([])
    for perm in permutations(range(size)):
        if any((i+j) % 2 for i, j in enumerate(perm)):
            continue
        sign = (-1)**sum(perm[i] > perm[j] for i in range(size) for j in range(i+1,size))
        term = fmpq_poly([sign])
        for i, j in enumerate(perm):
            term = (term*moments[i+j]).truncate(order+1)
        determinant += term
    determinant /= prod(factorial(j) for j in range(size))
    values = [determinant[k] for k in range(order+1)]
    assert values[0] == 1 and all(x > 0 for x in values)
    assert values[1] == fmpq(2*size*size+1,4)
    if size <= 2:
        assert values == [rat(x) for x in weak_coefficients(size,order)]
    return values


def scalar_coefficients(degree, order, insertion=0):
    """Normalized X^(2k)-weighted integral for a standard real Gaussian."""
    return [fmpq(prod(range(1, 2*insertion+2*degree*n, 2)),
                 prod(range(1,2*insertion,2))*(2*degree)**n*factorial(n))
            for n in range(order+1)]


def scalar_reference(degree,insertion,coupling,order=160):
    """Independent convergent strong series, enclosed by its integral remainder."""
    a = fmpq(2*insertion+1,2*degree)
    lam = ball(coupling)
    u = (2*degree/lam)**ball(fmpq(1,degree))/2
    prefactor = (2*degree/lam)**ball(a)/(degree*(2*arb.pi()).sqrt()*
                                                      prod(range(1,2*insertion,2)))
    total = arb(0)
    for j in range(order+1):
        total += (-u)**j*ball(a+fmpq(j,degree)).gamma()/factorial(j)
    bound = prefactor*u**(order+1)*ball(a+fmpq(order+1,degree)).gamma()/factorial(order+1)
    assert bound.upper() < arb('1e-80')
    return prefactor*total+arb(0,bound.upper())


def stieltjes_moments(wick, beta):
    return [factorial(k)*c/rising(beta,k) for k,c in enumerate(wick)]


def orthogonal_polynomial(moments, degree, calculate_norm=True):
    if degree == 0:
        return fmpq_poly([1]), moments[0]
    H = fmpq_mat(degree,degree,[moments[i+j] for i in range(degree) for j in range(degree)])
    assert H.det() > 0
    rhs = fmpq_mat(degree,1,[-moments[degree+i] for i in range(degree)])
    solution = H.solve(rhs)
    polynomial = fmpq_poly([solution[i,0] for i in range(degree)]+[1])
    norm = None
    if calculate_norm:
        norm = sum((polynomial[i]*polynomial[j]*moments[i+j]
                    for i in range(degree+1) for j in range(degree+1)),fmpq(0))
        assert norm > 0
    assert all(sum((polynomial[j]*moments[j+k] for j in range(degree+1)),fmpq(0)) == 0
               for k in range(degree))
    return polynomial,norm


def evaluate(poly, x):
    result = arb(0)
    for k in range(poly.degree(),-1,-1):
        result = result*x+ball(poly[k])
    return result


def gauss_rule(moments, degree):
    # The degree-n polynomial needs moments only through 2n-1. Its norm
    # is not used in Christoffel weights, so do not request moment 2n.
    polynomials = [orthogonal_polynomial(moments,k,calculate_norm=(k<degree))
                   for k in range(degree+1)]
    roots = polynomials[-1][0].complex_roots()
    assert len(roots) == degree and all(mult == 1 and z.imag == 0 and z.real > 0 for z,mult in roots)
    nodes = sorted([z.real for z,mult in roots],key=float)
    assert all(nodes[i].upper() < nodes[i+1].lower() for i in range(degree-1))
    weights = [1/sum((evaluate(p,x)**2/ball(h) for p,h in polynomials[:-1]),arb(0)) for x in nodes]
    assert all(w > 0 for w in weights)
    for k in range(2*degree):
        assert (sum((w*x**k for x,w in zip(nodes,weights)),arb(0))-ball(moments[k])).contains(0)
    return nodes,weights


def rule_pair(moments, degree):
    lower = gauss_rule(moments,degree)
    # The nonzero Radau nodes are Gauss nodes for s d rho(s).
    nodes,weights = gauss_rule(moments[1:],degree)
    radau_weights = [w/x for x,w in zip(nodes,weights)]
    at_zero = ball(moments[0])-sum(radau_weights,arb(0))
    assert at_zero > 0
    upper = ([arb(0)]+nodes,[at_zero]+radau_weights)
    for k in range(2*degree+1):
        assert (sum((w*x**k for x,w in zip(*upper)),arb(0))-ball(moments[k])).contains(0)
    return lower,upper


def kernel_sum(rule, coupling, beta):
    return sum((w*(1+ball(coupling)*x)**(-ball(beta)) for x,w in zip(*rule)),arb(0))


def reference(size,coupling):
    t = ball(coupling)/size
    q0,q2 = reference_moments(t)
    values = {0:q0,2:q2}
    for j in range(0,2*size-4,2):
        values[j+4] = ((j+1)*values[j]-values[j+2])/t
    matrix = arb_mat(size,size,[values[i+j] if (i+j)%2 == 0 else arb(0)
                               for i in range(size) for j in range(size)])
    return matrix.det()/prod(factorial(j) for j in range(size))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json',type=Path,default=Path(__file__).with_name('restrictions.json'))
    parser.add_argument('--tex',type=Path,default=Path(__file__).with_name('quadrature-table.tex'))
    parser.add_argument('--nodes',type=int,default=16)
    args = parser.parse_args()
    ctx.prec = 768
    maximum = args.nodes
    if maximum < 4:
        parser.error('--nodes must be at least 4 for the comparison table')
    independent = {k:moments_by_topology(k) for k in range(1,4)}
    rows = []
    table = []
    for size in (1,2,3,4):
        wick = wick_coefficients(size,2*maximum)
        for k,topologies in independent.items():
            pairing_sum = sum((count*fmpq(size)**(faces-k)
                               for (_,_,faces),count in topologies.items()),fmpq(0))
            assert wick[k] == pairing_sum/(4**k*factorial(k))
        a = fmpq(size*size,4)
        order_rows = {}
        orders = sorted(set((a,max(fmpq(1),a),a+1,a+2)))
        for beta in orders:
            mu = stieltjes_moments(wick,beta)
            order_rows[str(beta)] = []
            previous = {}
            for n in range(1,maximum+1):
                rules = rule_pair(mu,n)
                for coupling in (Q(1,100),Q(1,10),Q(1),Q(10),Q(100)):
                    lo,hi = [kernel_sum(rule,coupling,beta) for rule in rules]
                    ref = reference(size,coupling)
                    assert lo.upper() < ref.lower() and ref.upper() < hi.lower()
                    if coupling in previous:
                        oldlo,oldhi = previous[coupling]
                        assert oldlo.upper() < lo.lower() and hi.upper() < oldhi.lower()
                    previous[coupling] = lo,hi
                    order_rows[str(beta)].append({'nodes_in_Gauss_rule':n,'coupling':str(coupling),
                        'lower_ball':lo.str(120),'upper_ball':hi.str(120),
                        'enclosure_width_upper_bound':str((hi.upper()-lo.lower()).upper()),
                        'width_float':float(hi.upper()-lo.lower()),
                        'reference_ball':ref.str(35)})
            if beta == a:
                at_one = [r for r in order_rows[str(beta)] if r['coupling'] == '1' and r['nodes_in_Gauss_rule'] in (2,4,maximum)]
                table += [(size,r['nodes_in_Gauss_rule'],r['lower_ball'],r['upper_ball'],r['width_float']) for r in at_one]
        # The order-selection theorem is a strict inequality for these examples.
        for p,q in zip(orders,orders[1:]):
            for low_order,high_order in zip(order_rows[str(p)],order_rows[str(q)]):
                context = (size,str(p),str(q),low_order['coupling'],low_order['nodes_in_Gauss_rule'])
                assert ball(low_order['lower_ball']).lower() > ball(high_order['lower_ball']).upper(),context
                assert ball(low_order['upper_ball']).upper() < ball(high_order['upper_ball']).lower(),context
        rows.append({'matrix_size':size,'exact_Stieltjes_order':str(a),
                     'unsigned_Wick_coefficients':[str(x) for x in wick],
                     'quadrature_by_order':order_rows})
        best = order_rows[str(a)][-3]
        print(f'M={size}, exact order={a}, n={maximum}, lambda=1, width={best["width_float"]:.4g}',flush=True)

    # A sextic test uses no special-function seed. Two independent constructions
    # give the representing moments, and positive quadrature brackets the same integral.
    sextic = []
    denominator_bounds = {}
    for insertion in range(4):
        degree = 3
        a = fmpq(2*insertion+1,6)
        wick = scalar_coefficients(degree,2*maximum,insertion)
        mu = stieltjes_moments(wick,a)
        assert mu == [36**k*rising(a+fmpq(1,3),k)*rising(a+fmpq(2,3),k)
                      for k in range(len(mu))]
        for n in (2,4,maximum):
            rules = rule_pair(mu,n)
            for coupling in (Q(1,10),Q(1),Q(10)):
                lo,hi = [kernel_sum(rule,coupling,a) for rule in rules]
                ref = scalar_reference(degree,insertion,coupling)
                assert lo.upper() < ref.lower() and ref.upper() < hi.lower()
                if insertion == 0:
                    denominator_bounds[n,coupling] = lo,hi
                den_lo,den_hi = denominator_bounds[n,coupling]
                moment = prod(range(1,2*insertion,2))
                corr_lo,corr_hi = moment*lo/den_hi,moment*hi/den_lo
                corr_ref = moment*ref/scalar_reference(degree,0,coupling)
                assert corr_lo.upper() < corr_ref.lower() and corr_ref.upper() < corr_hi.lower()
                sextic.append({'insertion_power':2*insertion,'nodes':n,'coupling':str(coupling),
                               'lower_ball':lo.str(100),'upper_ball':hi.str(100),
                               'reference_ball':ref.str(100),
                               'correlation_lower_ball':corr_lo.str(100),
                               'correlation_upper_ball':corr_hi.str(100),
                               'correlation_reference_ball':corr_ref.str(100),
                               'width_float':float(hi.upper()-lo.lower())})
    sd_intersections = []
    for n in (2,4,maximum):
        for coupling in (Q(1,10),Q(1),Q(10)):
            cases = {row['insertion_power']:row for row in sextic
                     if row['nodes']==n and row['coupling']==str(coupling)}
            lo2,hi2 = [ball(cases[2][key]) for key in ('correlation_lower_ball','correlation_upper_ball')]
            lo6,hi6 = [ball(cases[6][key]) for key in ('correlation_lower_ball','correlation_upper_ball')]
            # Exact integration by parts: <x^2> + lambda <x^6> = 1.
            improved_lo = max(lo2.lower(),(1-ball(coupling)*hi6.upper()).lower())
            improved_hi = min(hi2.upper(),(1-ball(coupling)*lo6.lower()).upper())
            ref2,ref6 = [ball(cases[k]['correlation_reference_ball']) for k in (2,6)]
            assert (ref2+ball(coupling)*ref6-1).contains(0)
            assert improved_lo < ref2.lower() and ref2.upper() < improved_hi
            sd_intersections.append({'nodes':n,'coupling':str(coupling),
                'lower_endpoint':improved_lo.str(100),'upper_endpoint':improved_hi.str(100),
                'width_before':float(hi2.upper()-lo2.lower()),
                'width_after':float(improved_hi-improved_lo)})
    # Gauss/Radau measures have exact matching moments: elementary Hermite
    # interpolation gives their signs. Theorems, rather than numerical agreement,
    # certify the brackets and their optimality within the stated moment classes.
    output = {'precision_bits':ctx.prec,'largest_Gauss_rule':maximum,
              'independent_pairing_counts':{str(k):sum(counts.values()) for k,counts in independent.items()},
              'matrix_results':rows,'sextic_test':sextic,'sextic_SD_intersections':sd_intersections,
              'certification':'exact rational orthogonality; isolated Arb roots; positive Christoffel weights; '
                  'moment matching; theorem gives lower/upper signs and order dominance'}
    args.json.write_text(json.dumps(output,indent=2)+'\n')
    lines = [r'\begin{tabular}{rrrrr}',r'\toprule',
             r'$M$ & $n$ & lower bound & upper bound & width $< $\\',r'\midrule']
    for size,n,lo,hi,width in table:
        lower = float(ball(lo).lower())
        upper = float(ball(hi).upper())
        # Displayed endpoints round outward to eight decimal places.
        from math import floor,ceil
        lower = floor(lower*1e8)/1e8
        upper = ceil(upper*1e8)/1e8
        assert ball(f'{lower:.8f}') <= ball(lo).lower()
        assert ball(hi).upper() <= ball(f'{upper:.8f}')
        unit = 10**(floor(__import__('math').log10(width))-2)
        width_upper = (floor(width/unit)+1)*unit
        mantissa,exponent = f'{width_upper:.2e}'.split('e')
        assert ball(mantissa)*ball(10)**int(exponent) > ball(hi).upper()-ball(lo).lower()
        width_tex = f'${mantissa}\\times10^{{{int(exponent)}}}$'
        lines.append(f'{size} & {n} & {lower:.8f} & {upper:.8f} & {width_tex}\\\\')
    lines += [r'\bottomrule',r'\end{tabular}']
    args.tex.write_text('\n'.join(lines)+'\n')


if __name__ == '__main__':
    main()
