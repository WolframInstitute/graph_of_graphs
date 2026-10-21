"""Independent symbolic checks for the latent-rank curvature note.

This checks the metric calculation, normalization, boundary regularity,
and explicit alternatives. It is not a simulation of the asymptotic theorem.
"""

import json
from pathlib import Path

import sympy as s


u, v, t = s.symbols("u v t", real=True)
theta, lam, mu, h, gamma = s.symbols(
    "theta lambda mu h gamma", real=True
)

k = s.Rational(315, 256) * (1 - t**2)**4
assert s.integrate(k, (t, -1, 1)) == 1
assert s.integrate(t * k, (t, -1, 1)) == 0
for j in range(4):
    assert s.diff(k, t, j).subs(t, 1) == 0
    assert s.diff(k, t, j).subs(t, -1) == 0

f = lambda x: 1 - 2*x
p = lambda x: 6*x*x - 6*x + 1
c = 1 + theta * (
    f(u)*f(v) + lam*f(u)*p(v) + mu*p(u)*f(v)
)
assert s.integrate(c, (u, 0, 1)) == 1
assert s.integrate(c, (v, 0, 1)) == 1

# Construct Christoffel symbols and Ricci contraction directly from the
# metric, rather than evaluating only the claimed scalar-curvature formula.
metric = s.Matrix([[0, -c], [-c, 0]])
inverse = metric.inv()
x = [u, v]
christoffel = [
    [
        [
            s.simplify(sum(
                inverse[a, d] * (
                    s.diff(metric[d, b], x[e])
                    + s.diff(metric[d, e], x[b])
                    - s.diff(metric[b, e], x[d])
                ) / 2 for d in range(2)
            ))
            for e in range(2)
        ]
        for b in range(2)
    ]
    for a in range(2)
]
ricci = s.zeros(2, 2)
for b in range(2):
    for d in range(2):
        ricci[b, d] = sum(
            s.diff(christoffel[a][b][d], x[a])
            - s.diff(christoffel[a][b][a], x[d])
            + sum(
                christoffel[a][a][e] * christoffel[e][b][d]
                - christoffel[a][d][e] * christoffel[e][b][a]
                for e in range(2)
            )
            for a in range(2)
        )
curvature = s.factor(sum(
    inverse[b, d]*ricci[b, d] for b in range(2) for d in range(2)
))
claimed = 2*s.diff(c, u, v)/c**2 - 2*s.diff(c, u)*s.diff(c, v)/c**3
assert s.factor(curvature - claimed) == 0
centre = {u: s.Rational(1, 2), v: s.Rational(1, 2)}
central_curvature = s.factor(curvature.subs(centre))
assert s.expand(central_curvature - (8*theta - 2*theta**2*lam*mu)) == 0

# The parametric example has a separate order-probability computation.
fgm = 1 + theta*f(u)*f(v)
fgm_cdf = s.integrate(fgm, (u, 0, u), (v, 0, v))
comparability = s.integrate(
    2*s.expand(fgm_cdf*fgm), (u, 0, 1), (v, 0, 1)
)
assert s.expand(comparability - (s.Rational(1, 2) + theta/9)) == 0

# An odd compact bump with four matching zero boundary jets suffices for
# the C4 lower bound. Here we check its polynomial part on [-1,1].
q = t * (1-t*t)**5
assert s.integrate(q, (t, -1, 1)) == 0
assert s.diff(q, t).subs(t, 0) == 1
for j in range(5):
    assert s.diff(q, t, j).subs(t, 1) == 0
    assert s.diff(q, t, j).subs(t, -1) == 0
q2 = s.integrate(q*q, (t, -1, 1))
assert q2 > 0
bump = 1 + gamma*h**4*q.subs(t, (u-s.Rational(1,2))/h)*q.subs(t, (v-s.Rational(1,2))/h)
assert bump.subs(centre) == 1
assert s.diff(bump, u).subs(centre) == 0
assert s.diff(bump, v).subs(centre) == 0
assert s.diff(bump, u, v).subs(centre) == gamma*h**2

report = {
    "kernel_mass": "1",
    "kernel_first_moment": "0",
    "zero_kernel_boundary_jets": [0, 1, 2, 3],
    "asymmetric_density_marginals": ["1", "1"],
    "curvature_checked_from_metric": True,
    "asymmetric_central_curvature": str(central_curvature),
    "FGM_comparability_probability": str(comparability),
    "odd_bump_zero_boundary_jets": [0, 1, 2, 3, 4],
    "odd_bump_derivative_at_centre": "1",
    "odd_bump_squared_integral": str(q2),
    "alternative_squared_L2_distance": f"gamma^2 h^10 ({q2})^2",
}
root = Path(__file__).resolve().parent
(root / "curvature-checks.json").write_text(
    json.dumps(report, indent=2) + "\n"
)
print(json.dumps(report, indent=2))
