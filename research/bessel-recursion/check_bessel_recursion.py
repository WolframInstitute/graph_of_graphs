"""Independent exact constructions for the Broadhurst--Roberts recursion.

The first construction is the literal recursion (5.7)--(5.12) of their
2018 article. The second uses the symmetric-power Bessel operator.
Finite agreement checks the proposed general proof; it is not that proof.
"""
from fractions import Fraction as Q
from math import comb, factorial
from pathlib import Path
import json


def mul(a,b,n):
    return [sum((a[j]*b[k-j] for j in range(k+1)), Q(0)) for k in range(n+1)]


def divide(a,b,n):
    out=[]
    for k in range(n+1):
        out.append((a[k]-sum((b[j]*out[k-j] for j in range(1,k+1)),Q(0)))/b[0])
    return out


def auxiliary(n):
    j=[Q((-1)**k,factorial(k)**2) for k in range(n+3)]
    derivative=[(k+1)*j[k+1] for k in range(n+2)]
    jj=mul(j,j,n+2)
    jd=mul(j,derivative,n+1)
    c=[Q(2,3)*(-jj[k+2]+2*jd[k+1]) for k in range(n+1)]
    assert c[0]==1
    v=divide(jj,c,n)
    w=divide([-a for a in jd],c,n)
    assert v[:2]==[Q(1),Q(-34,27)]
    assert w[:2]==[Q(1),Q(-41,54)]
    return [v[k]*factorial(k) for k in range(n+1)], [w[k]*factorial(k) for k in range(n+1)]


def original(n,v,w):
    rank=(n-1)//2
    length=2*rank
    values={}
    for c in range(-rank,rank+1):
        y,z=Q(3*c,2),Q(n+2-2*c)
        h=[Q(1)]
        for s in range(1,length+1):
            previous=h[s-2] if s>=2 else 0
            value=z*h[s-1]-(s-1)*y*previous
            value-=sum((comb(s-1,k)*(v[k]*h[s-k]-w[k]*z*h[s-k-1])
                        for k in range(1,s)),Q(0))
            h.append(value)
        values[c]=[h[s]/(4**s*factorial(s)) for s in range(length+1)]
    return [[sum((values[-c][a-c]*values[c][b+c]*c**(n+1)
                  for c in range(-b,a+1)),Q(0))
             for b in range(1,rank+1)] for a in range(1,rank+1)]


def operator(n,sign=1):
    # Monomials x^j theta^k. theta x^j = x^j(theta+j).
    previous={(0,0):1}
    current={(0,1):1}
    for k in range(1,n+1):
        following={}
        for (j,ell),c in current.items():
            following[j,ell+1]=following.get((j,ell+1),0)+c
            following[j,ell]=following.get((j,ell),0)+j*c
        for (j,ell),c in previous.items():
            following[j+1,ell]=following.get((j+1,ell),0)+sign*k*(n+1-k)*c
        previous,current=current,{key:c for key,c in following.items() if c}
    return current


def coefficient_form(n):
    op=operator(n)
    rank=(n-1)//2
    return [[Q(sum(c*(-b)**ell for (j,ell),c in op.items() if j==a+b),4**(a+b))
             for b in range(1,rank+1)] for a in range(1,rank+1)]


def apply_operator(op,coefficients):
    out={}
    for degree,a in coefficients.items():
        for (j,ell),c in op.items():
            out[degree+j]=out.get(degree+j,Q(0))+a*c*degree**ell
    return {key:a for key,a in out.items() if a}


def connection_positive_matrix(n):
    """Formal primitive in the full Sym^n connection, independently eliminated.

    Work with theta e0=e1, theta e1=x e0 (modified Bessel).
    The coefficient of e1^n is eta. Recover every other component from
    the top down, then solve the lowest equation as a triangular Laurent
    system. The residue at infinity is minus the constant coefficient.
    """
    rank=(n-1)//2
    q=(n+1)//2
    components=[]
    for b in range(1,rank+1):
        f={n:{-b:Q(1)}}
        for a in range(n,0,-1):
            rhs={k:-k*v for k,v in f[a].items()}
            for k,v in f.get(a+1,{}).items():
                rhs[k+1]=rhs.get(k+1,Q(0))-(a+1)*v
            f[a-1]={k:v/Q(n-a+1) for k,v in rhs.items() if v}
        forcing={k:k*v for k,v in f[0].items()}
        for k,v in f[1].items():
            forcing[k+1]=forcing.get(k+1,Q(0))+v
        components.append([forcing.get(a,Q(0)) for a in range(1,rank+1)])
    from sympy import Matrix,Rational
    return Matrix([[Rational(components[b][a].numerator,components[b][a].denominator)
                 for b in range(rank)] for a in range(rank)])


def green_matrix(n):
    # Positive part of the lowest equation in the nonresonant cases.
    rank=(n-1)//2
    top=connection_positive_matrix(n)
    inv=top.inv()
    # S_ij= res_infinity <primitive_i, x^j e0^n> = -(-1)^n eta_(j,i).
    return [[Q(-(-1)**n)*Q(inv[j,i]) for j in range(rank)] for i in range(rank)]


def resonant_green(n):
    """Use FSY's independent I_0 K_0 asymptotic coefficients and middle sources."""
    from sympy import Matrix,Rational
    assert n%4==0
    rank=(n-1)//2
    excluded=n//4-1
    kept=[a for a in range(rank) if a!=excluded]
    length=rank-n//4
    asymptotic=[]
    odd_double=1
    for j in range(length+1):
        if j:
            odd_double*=2*j-1
        asymptotic.append(Q(odd_double**3,2**(5*j)*factorial(j)))
    power=[Q(1)]+[Q(0)]*length
    for _ in range(n//2):
        power=mul(power,asymptotic,length)
    h=Matrix([0 if a<excluded else Rational(power[a-excluded]) for a in range(rank)])
    top=connection_positive_matrix(n)
    assert top*h==Matrix.zeros(rank,1)
    sources=Matrix.zeros(rank,rank-1)
    for col,i in enumerate(kept):
        sources[i,col]=1
        sources[excluded,col]=-h[i]
    primitive=Matrix.zeros(rank,rank-1)
    middle=top.extract(kept,kept).inv()
    for a,i in enumerate(kept):
        for j in range(rank-1):
            primitive[i,j]=middle[a,j]
    assert top*primitive==sources
    pairing=-((sources.T*primitive).T)
    return pairing, h, kept


def main():
    from sympy import Matrix,Rational
    v,w=auxiliary(32)
    cases=[]
    for n in range(3,33):
        br=original(n,v,w)
        differential=coefficient_form(n)
        assert br==differential,n
        rank=len(br)
        assert all(br[a][b]==(-1)**(n+1)*br[b][a] for a in range(rank) for b in range(rank))
        matrix=Matrix([[Rational(t.numerator,t.denominator) for t in row] for row in br])
        raw=Matrix([[(-4)**(a+b+2)*matrix[a,b] for b in range(rank)] for a in range(rank)])
        assert connection_positive_matrix(n)==Q((-1)**n,factorial(n))*raw
        actual_rank=matrix.rank()
        assert actual_rank==rank-int(n%4==0),(n,actual_rank)
        if n%4:
            green=green_matrix(n)
            # Raw modified-Bessel coefficient form differs by signs and 4 powers.
            expected=-factorial(n)*raw.inv().T
            assert Matrix(green)==expected,n
            if n==5:
                assert Matrix(green)==Matrix([[0,Rational(8,15)],[Rational(8,15),Rational(208,3375)]])
            if n==6:
                assert Matrix(green)==Matrix([[0,Rational(-5,8)],[Rational(5,8),0]])
            pairing=Matrix(green)
        else:
            pairing,h,kept=resonant_green(n)
            reduced=raw.extract(kept,kept)
            assert pairing==-factorial(n)*reduced.inv().T
            assert raw*h==Matrix.zeros(rank,1)
            if rank>1:
                assert pairing==factorial(n)*reduced.inv()
        integral_inverse=factorial(n)*pairing.inv() if pairing.rows else Matrix.zeros(0,0)
        assert all(value.q==1 for value in integral_inverse)
        cases.append({'Bessel_factors':n,'matrix_size':rank,'rank':actual_rank,
                      'original_recursion_equals_operator_form':True,
                      'independent_full_connection_residue_check':True,
                      'resonance_and_middle_sources_checked':n%4==0,
                      'factorial_scaled_inverse_pairing_is_integral':True})
        print('N=',n,'exact recursion/operator/rank checks passed',flush=True)
    Path(__file__).with_name('bessel-recursion.json').write_text(json.dumps(cases,indent=2)+'\n')


if __name__=='__main__':
    main()
