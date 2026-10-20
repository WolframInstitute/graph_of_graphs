#!/usr/bin/env python3
"""One quartic differential period torsor, several local series realizations.

Checks rational formal identities, a matrix-size-two differential equation,
modular finite jets and p-curvature, then compares rigorously bounded weak-
and strong-coupling approximations using Arb real ball arithmetic.

Requires python-flint; SymPy verifies the symmetric-square elimination.
The optional plot requires matplotlib. This is a worked example using
established period/differential-Galois machinery, not a novelty claim.
"""

from __future__ import annotations

import argparse
from fractions import Fraction as Q
from math import factorial, prod
from pathlib import Path
import json
import os
import tempfile

from flint import arb, ctx


def ball(q) -> arb:
    q = Q(q)
    return arb(q.numerator) / q.denominator


def multiply(a: list[Q], b: list[Q], degree: int) -> list[Q]:
    return [sum((a[j]*b[k-j] for j in range(k+1)), Q(0)) for k in range(degree+1)]


def hypergeometric_coefficients(a: Q, b: Q, order: int) -> list[Q]:
    values = [Q(1)]
    for j in range(order):
        values.append(values[-1] * (a+j) / ((b+j)*(j+1)*4))
    return values


def weak_coefficients(dimension: int, order: int) -> list[Q]:
    values = [Q(1)]
    if dimension == 1:
        for k in range(order):
            values.append(values[-1]*Q((4*k+1)*(4*k+3),4*(k+1)))
    else:
        assert dimension == 2
        for k in range(order):
            previous = values[k-1] if k else Q(0)
            values.append(Q((2*k+1)*(2*k+3),4*(k+1))*(3*values[k]-2*k*previous))
    assert all(c > 0 for c in values)
    return values


def formal_checks(order: int = 24) -> dict:
    a = weak_coefficients(1,order+1)
    signed = [(-1)**k*c for k,c in enumerate(a)]
    # The other weak solution is exp(1/(4t)) times the positive series a(-t).
    for k in range(order):
        assert (4*k+1)*(4*k+3)*signed[k]+4*(k+1)*signed[k+1] == 0
        assert (4*k+1)*(4*k+3)*a[k]-4*(k+1)*a[k+1] == 0
    product = multiply(signed,a,order)
    derivative_signed = [(k+1)*signed[k+1] for k in range(order+1)]
    derivative_a = [(k+1)*a[k+1] for k in range(order+1)]
    cross1 = multiply(signed,derivative_a,order)
    cross2 = multiply(a,derivative_signed,order)
    for k in range(order+1):
        coefficient = product[k]
        if k >= 2:
            coefficient -= 4*(cross1[k-2]-cross2[k-2])
        assert coefficient == (1 if k == 0 else 0)

    A = hypergeometric_coefficients(Q(1,4),Q(1,2),order)
    B = hypergeometric_coefficients(Q(3,4),Q(3,2),order)
    C = hypergeometric_coefficients(Q(5,4),Q(3,2),order)
    D = hypergeometric_coefficients(Q(3,4),Q(1,2),order)
    for beta, coefficients in ((Q(-1,4),A),(Q(-3,4),B)):
        for k in range(1,order+1):
            exponent = beta-k
            assert (4*exponent+1)*(4*exponent+3)*coefficients[k] + \
                   4*(exponent+1)*coefficients[k-1] == 0
    AD, BC = multiply(A,D,order), multiply(B,C,order)
    for k in range(order+1):
        assert AD[k]-(BC[k-1]/4 if k else 0) == Q(1,4**k*factorial(k))

    # Independent convolution of the two weak scalar moments for Z_2(lambda).
    m2 = [(4*k+1)*a[k] for k in range(order+1)]
    convolution = multiply(a,m2,order)
    assert [convolution[k]/2**k for k in range(order+1)] == weak_coefficients(2,order)

    import sympy as s
    lam = s.symbols('lambda')
    t = lam/2
    connection = s.Matrix([[-1/(4*t),1/(4*t)],
                           [1/(4*t*t),-(1+3*t)/(4*t*t)]])/2
    aa,bb,cc,dd = connection[0,0],connection[0,1],connection[1,0],connection[1,1]
    symmetric_square = s.Matrix([[2*aa,2*bb,0],[cc,aa+dd,bb],[0,2*cc,2*dd]])
    rows = [s.Matrix([[0,1,0]])]
    for _ in range(3):
        rows.append((rows[-1].diff(lam)+rows[-1]*symmetric_square).applyfunc(s.factor))
    operator = [3*(10*lam+3),2*(55*lam**2+18*lam+2),
                4*lam**2*(16*lam+3),8*lam**4]
    assert all(s.factor(value) == 0 for value in sum(
        (coefficient*row for coefficient,row in zip(operator,rows)),s.zeros(1,3)))

    modular = []
    for prime in (53,59,61):
        # All displayed rational denominators are units through this order.
        def reduce(q):
            q = Q(q)
            return q.numerator * pow(q.denominator,-1,prime) % prime
        for aa0,bb0,coefficients in ((Q(1,4),Q(1,2),A),(Q(3,4),Q(3,2),B)):
            modular_coefficients = [1]
            for k in range(order):
                modular_coefficients.append(modular_coefficients[-1] * reduce(aa0+k) *
                                            pow(reduce(bb0+k)*(k+1)*4,-1,prime) % prime)
            assert modular_coefficients == [reduce(q) for q in coefficients]
        modular.append({'prime':prime,'rational_strong_basis_jets_checked_through_order':order})
    return {'exact_formal_order':order,'weak_Wronskian':'-t^(-1) exp(1/(4t))',
            'strong_Wronskian':'-2 t^(-1) exp(1/(4t))',
            'matrix_size_two_ODE': "8 lambda^4 Z''' + 4 lambda^2 (16 lambda+3) Z'' "
                "+ 2 (55 lambda^2+18 lambda+2) Z' + 3 (10 lambda+3) Z = 0",
            'finite_field_jet_checks':modular}


def p_curvature(prime: int) -> dict:
    # Laurent polynomials use exponent e for t^(-e).
    def add(a,b,sign=1):
        result = dict(a)
        for e,c in b.items():
            result[e] = (result.get(e,0)+sign*c) % prime
        return {e:c for e,c in result.items() if c}
    def times(a,b):
        result = {}
        for e,c in a.items():
            for f,d in b.items():
                result[e+f] = (result.get(e+f,0)+c*d) % prime
        return {e:c for e,c in result.items() if c}
    def derivative(a):
        return {e+1:-e*c % prime for e,c in a.items() if -e*c % prime}
    quarter = pow(4,-1,prime)
    A = [[{1:-quarter % prime},{1:quarter}],
         [{2:quarter},{1:-3*quarter % prime,2:-quarter % prime}]]
    curvature = [[{0:1},{}],[{},{0:1}]]
    for _ in range(prime):
        curvature = [[add(derivative(curvature[i][j]),
                          add(times(A[i][0],curvature[0][j]),
                              times(A[i][1],curvature[1][j])),sign=-1)
                      for j in range(2)] for i in range(2)]
    trace = add(curvature[0][0],curvature[1][1])
    assert trace == {2*prime:quarter}, (prime,trace)
    determinant = add(times(curvature[0][0],curvature[1][1]),
                      times(curvature[0][1],curvature[1][0]),sign=-1)
    return {'prime':prime,'trace':{str(e):c for e,c in sorted(trace.items())},
            'determinant':{str(e):c for e,c in sorted(determinant.items())},
            'Laurent_exponent_convention':'e denotes t^(-e)',
            'full_horizontal_frame_over_Fp_Laurent_series':False}


def strong_coefficients(dimension: int, order: int) -> list[arb]:
    ga,gb = ball(Q(1,4)).gamma(),ball(Q(3,4)).gamma()
    if dimension == 1:
        values = [ga,gb]
        for k in range(order-1):
            values.append(values[k]*ball(Q(2*k+1,4*(k+1)*(k+2))))
        return values[:order+1]
    assert dimension == 2
    values = [ga*gb,ga*ga/4+gb*gb,3*ga*gb/4,ga*ga/12+gb*gb/2]
    for n in range(4,order+1):
        values.append((3*(n-1)*(n-3)*values[n-2]-(n-2)*values[n-4])/
                      (2*n*(n-1)*(n-3)))
    # Independent convolution checks the symmetric-square recurrence.
    scalar0 = strong_coefficients(1,min(order,24))
    scalar2 = [gb,ga/4]
    for k in range(min(order,24)-1):
        scalar2.append(scalar2[k]*ball(Q(2*k+3,4*(k+1)*(k+2))))
    for n in range(min(order,24)+1):
        independent = sum((scalar0[k]*scalar2[n-k] for k in range(n+1)),arb(0))
        assert (independent-values[n]).contains(0)
    return values


def reference_moments(t: arb) -> tuple[arb,arb]:
    z = 1/(8*t)
    K1 = z.bessel_k(ball(Q(1,4)),scaled=True)
    K3 = z.bessel_k(ball(Q(3,4)),scaled=True)
    factor = 1/(2*(arb.pi()*t).sqrt())
    return factor*K1,factor*4*z*(K3-K1)


def strong_frame_check(t: arb):
    z,u = 1/(4*t),1/t.sqrt()
    A = z.hypgeom_1f1(ball(Q(1,4)),ball(Q(1,2)))
    B = z.hypgeom_1f1(ball(Q(3,4)),ball(Q(3,2)))
    C = z.hypgeom_1f1(ball(Q(5,4)),ball(Q(3,2)))
    D = z.hypgeom_1f1(ball(Q(3,4)),ball(Q(1,2)))
    ga,gb = ball(Q(1,4)).gamma(),ball(Q(3,4)).gamma()
    quarter_power = t.sqrt().sqrt()
    q0 = (ga*A-u*gb*B)/(2*arb.pi().sqrt()*quarter_power)
    q2 = (gb*D-u*ga*C/4)/(arb.pi().sqrt()*quarter_power**3)
    q0_reference,q2_reference = reference_moments(t)
    assert (q0-q0_reference).contains(0)
    assert (q2-q2_reference).contains(0)
    assert (A*D-z*B*C-z.exp()).contains(0)


def ordinary_coefficients(dimension: int, order: int) -> list[arb]:
    """Taylor series at lambda=1, from rational horizontal transport."""
    q0,q2 = reference_moments(ball(Q(1,dimension)))
    moments0,moments2 = [q0],[q2]
    for n in range(order):
        next0,next2 = arb(0),arb(0)
        for k in range(n+1):
            sign = (-1)**k
            x,y = moments0[n-k],moments2[n-k]
            next0 += sign*(-x+y)/4
            next2 += sign*(dimension*(k+1)*x-(dimension*(k+1)+3)*y)/4
        moments0.append(next0/(n+1))
        moments2.append(next2/(n+1))
    if dimension == 1:
        return moments0
    return [sum((moments0[k]*moments2[n-k] for k in range(n+1)),arb(0))
            for n in range(order+1)]


def approximation_rows(dimension: int, coupling: Q, weak: list[Q], strong: list[arb],
                       ordinary: list[arb], tolerance: arb) -> dict:
    lam = ball(coupling)
    t = lam/dimension
    q0,q2 = reference_moments(t)
    reference = q0 if dimension == 1 else q0*q2
    strong_frame_check(t)
    strong_u = 1/t.sqrt()
    prefactor = (1/(2*arb.pi().sqrt()*t.sqrt().sqrt()) if dimension == 1
                 else 1/(2*arb.pi()*t))
    outcomes = {}
    for method,coefficients,parameter,scale in (
            ('weak',weak,lam,arb(1)),('strong',strong,strong_u,prefactor)):
        total = arb(0)
        power = arb(1)
        selected = []
        first_certified = None
        best_bound = None
        best_order = None
        for k in range(len(coefficients)-1):
            coefficient = ball(coefficients[k]) if method == 'weak' else coefficients[k]
            total += (-1)**k*power*coefficient
            next_coefficient = ball(coefficients[k+1]) if method == 'weak' else coefficients[k+1]
            bound = scale*power*parameter*next_coefficient
            approximation = scale*total
            if best_bound is None or bound.upper() < best_bound.upper():
                best_bound,best_order = bound,k
            certified = (bound.upper()+approximation.rad()).upper() < tolerance
            if certified and first_certified is None:
                first_certified = k
            if k in (8,16) or (certified and first_certified == k):
                if k % 2 == 0:
                    lower,upper = (approximation.lower()-bound.upper()).lower(),approximation.upper()
                else:
                    lower,upper = approximation.lower(),(approximation.upper()+bound.upper()).upper()
                assert lower <= reference.lower() and reference.upper() <= upper
                selected.append({'order':k,'terms':k+1,
                                 'approximation_ball':approximation.str(35),
                                 'absolute_remainder_bound_ball':bound.str(25),
                                 'certified_lower_endpoint':lower.str(40),
                                 'certified_upper_endpoint':upper.str(40)})
            power *= parameter
        outcomes[method] = {'first_order_certifying_absolute_error_below_tolerance':first_certified,
                            'best_order_within_search':best_order,
                            'best_absolute_remainder_bound_ball':best_bound.str(25),
                            'selected_approximations':selected}
    # On |lambda-1|=R<1, |Z_M(lambda)| <= 1. Cauchy's bound controls the tail.
    h = coupling-1
    radius = Q(9,10)
    if abs(h) < radius:
        ratio = ball(abs(h)/radius)
        total,power = arb(0),arb(1)
        first_certified = None
        selected = []
        for k,coefficient in enumerate(ordinary):
            total += coefficient*power
            bound = ratio**(k+1)/(1-ratio)
            certified = (bound.upper()+total.rad()).upper() < tolerance
            if certified and first_certified is None:
                first_certified = k
            if k in (8,16) or (certified and first_certified == k):
                lower,upper = (total.lower()-bound.upper()).lower(),(total.upper()+bound.upper()).upper()
                assert lower <= reference.lower() and reference.upper() <= upper
                selected.append({'order':k,'terms':k+1,'approximation_ball':total.str(35),
                                 'absolute_remainder_bound_ball':bound.str(25)})
            power *= ball(h)
        outcomes['ordinary_at_one'] = {
            'first_order_certifying_absolute_error_below_tolerance':first_certified,
            'Cauchy_circle_radius':str(radius),'selected_approximations':selected,
            'seed_period_evaluation_required':True}
    else:
        outcomes['ordinary_at_one'] = {'outside_chosen_Cauchy_circle':True,
            'first_order_certifying_absolute_error_below_tolerance':None}
    print(f'M={dimension}, lambda={coupling}: Z={reference.str(18)}; '
          f'orders for 1e-10: weak={outcomes["weak"]["first_order_certifying_absolute_error_below_tolerance"]}, '
          f'strong={outcomes["strong"]["first_order_certifying_absolute_error_below_tolerance"]}, '
          f'ordinary={outcomes["ordinary_at_one"]["first_order_certifying_absolute_error_below_tolerance"]}',flush=True)
    return {'matrix_dimension':dimension,'coupling':str(coupling),
            'reference_Bessel_ball':reference.str(45),'methods':outcomes}


def plot_bounds(path: Path, weak: dict, strong: dict):
    plot_cache = tempfile.TemporaryDirectory(prefix='gog-torsor-plot-')
    os.environ['MPLCONFIGDIR'] = plot_cache.name
    os.environ['XDG_CACHE_HOME'] = plot_cache.name
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    couplings = np.logspace(-2,2,180)
    figure,axes = plt.subplots(1,2,figsize=(10,3.7),sharey=True)
    for dimension,axis in zip((1,2),axes):
        for order,style in ((8,'--'),(16,'-')):
            weak_values = [float(ball(weak[dimension][order+1])*ball(str(x))**(order+1))
                           for x in couplings]
            strong_values = []
            for x in couplings:
                t = ball(str(x))/dimension
                prefactor = (1/(2*arb.pi().sqrt()*t.sqrt().sqrt()) if dimension == 1
                             else 1/(2*arb.pi()*t))
                strong_values.append(float(prefactor*strong[dimension][order+1]/
                                           t.sqrt()**(order+1)))
            axis.loglog(couplings,weak_values,color='#b05220',ls=style,label=f'Gaussian, {order+1} terms')
            axis.loglog(couplings,strong_values,color='#185c8d',ls=style,label=f'Quartic, {order+1} terms')
        axis.axhline(1e-10,color='#777777',lw=.8)
        axis.set_title(f'Matrix size {dimension}')
        axis.set_xlabel('Coupling λ')
        axis.grid(True,which='major',alpha=.2)
        axis.set_ylim(1e-30,1e30)
    axes[0].set_ylabel('Rigorous absolute remainder bound')
    axes[1].legend(fontsize=8,loc='lower left')
    figure.tight_layout()
    path.parent.mkdir(parents=True,exist_ok=True)
    figure.savefig(path)
    figure.savefig(path.with_suffix('.png'),dpi=180)
    plt.close(figure)
    plot_cache.cleanup()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json',type=Path)
    parser.add_argument('--plot',type=Path)
    args = parser.parse_args()
    ctx.prec = 2048
    formal = formal_checks()
    curvature = [p_curvature(p) for p in (3,5,7,11)]
    weak = {m:weak_coefficients(m,129) for m in (1,2)}
    strong = {m:strong_coefficients(m,1025) for m in (1,2)}
    ordinary = {m:ordinary_coefficients(m,128) for m in (1,2)}
    assert (ball(Q(1,4)).gamma()*ball(Q(3,4)).gamma()-arb.pi()*arb(2).sqrt()).contains(0)
    results = [approximation_rows(m,lam,weak[m],strong[m],ordinary[m],arb('1e-10'))
               for m in (1,2) for lam in (Q(1,100),Q(1,10),Q(9,10),Q(1),Q(11,10),Q(10),Q(100))]
    output = {'model':'stable Hermitian quartic integral',
              'torsor':'GL2 frame torsor with the quartic rank-two differential connection',
              'local_fields':['Qbar((t))(exp(1/(4t)))','Qbar((t-1/M))','Qbar((t^(-1/4)))'],
              'arithmetic_precision_bits':ctx.prec,'formal_checks':formal,
              'p_curvature_checks':curvature,
              'error_bounds':'Taylor integral remainders, including Arb rounding enclosures',
              'absolute_error_target':'1e-10','results':results}
    if args.json:
        args.json.write_text(json.dumps(output,indent=2)+'\n')
    if args.plot:
        plot_bounds(args.plot,weak,strong)


if __name__ == '__main__':
    main()
