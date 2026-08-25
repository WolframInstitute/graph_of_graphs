import Std.Tactic

/-!
# Kernel-checked finite averaging identities

The project intentionally uses only Lean and `Std`: the environment did not
permit downloading Mathlib.  All scalar identities are over Lean's exact
rational numbers (`Rat`), so no floating-point reasoning is involved.

This file models pair averaging and the finite matching schedules on `K4` and
`Q3`.  It does not model Whitehead moves or any probabilistic/asymptotic claim.
-/

namespace GogVerification

/-- Exact multiplication by one half. -/
def half (x : Rat) : Rat := x * (1 / 2)

/-- The arithmetic mean of two exact rational values. -/
def midpoint (x y : Rat) : Rat := half (x + y)

theorem midpoint_symm (x y : Rat) : midpoint x y = midpoint y x := by
  simp [midpoint, half, Rat.add_comm]

theorem midpoint_self (x : Rat) : midpoint x x = x := by
  simp [midpoint, half]
  grind

/-- Arithmetic means commute with every affine scalar transformation. -/
theorem midpoint_affine (a b x y : Rat) :
    midpoint (a * x + b) (a * y + b) = a * midpoint x y + b := by
  simp [midpoint, half]
  grind

/-- Replace coordinates `i` and `j` by their arithmetic mean. -/
def pairAverage {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) : ι → Rat := fun k =>
  if k = i ∨ k = j then midpoint (x i) (x j) else x k

@[simp] theorem pairAverage_apply_left {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) :
    pairAverage i j x i = midpoint (x i) (x j) := by
  simp [pairAverage]

@[simp] theorem pairAverage_apply_right {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) :
    pairAverage i j x j = midpoint (x i) (x j) := by
  simp [pairAverage]

@[simp] theorem pairAverage_apply_other {ι : Type} [DecidableEq ι]
    {i j k : ι} (x : ι → Rat) (hki : k ≠ i) (hkj : k ≠ j) :
    pairAverage i j x k = x k := by
  simp [pairAverage, hki, hkj]

theorem pairAverage_symm {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) :
    pairAverage i j x = pairAverage j i x := by
  funext k
  simp [pairAverage, midpoint_symm, or_comm]

/-- Pair averaging commutes with pointwise affine changes of coordinates. -/
theorem pairAverage_affine {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) (a b : Rat) :
    pairAverage i j (fun k => a * x k + b) =
      fun k => a * pairAverage i j x k + b := by
  funext k
  by_cases hk : k = i ∨ k = j
  · simp [pairAverage, hk, midpoint, half]
    grind
  · simp [pairAverage, hk]

/-- Every constant field is fixed by every pair average. -/
theorem pairAverage_constant {ι : Type} [DecidableEq ι]
    (i j : ι) (c : Rat) :
    pairAverage i j (fun _ => c) = fun _ => c := by
  funext k
  by_cases hk : k = i ∨ k = j
  · simp [pairAverage, hk, midpoint, half]
    grind
  · simp [pairAverage, hk]

/-- A pair already at consensus is pointwise fixed. -/
theorem pairAverage_eq_self_of_eq {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) (hij : x i = x j) :
    pairAverage i j x = x := by
  funext k
  by_cases hk : k = i ∨ k = j
  · rcases hk with rfl | rfl <;>
      simp [pairAverage, midpoint, half, hij] <;> grind
  · simp [pairAverage, hk]

/-- Centering at an arbitrary affine mean commutes with pair averaging. -/
theorem pairAverage_center {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) (μ : Rat) :
    pairAverage i j (fun k => x k - μ) =
      fun k => pairAverage i j x k - μ := by
  simpa [Rat.sub_eq_add_neg] using pairAverage_affine i j x 1 (-μ)

/-- The two modified coordinates have exactly the same sum as before. -/
theorem pairAverage_pair_sum {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) :
    pairAverage i j x i + pairAverage i j x j = x i + x j := by
  simp [midpoint, half]
  grind

/-- Sum preservation with an arbitrary unchanged remainder. -/
theorem pairAverage_sum_with_rest {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) (rest : Rat) :
    rest + pairAverage i j x i + pairAverage i j x j =
      rest + x i + x j := by
  simp [midpoint, half]
  grind

/-- Applying the same pair average twice changes nothing the second time. -/
theorem pairAverage_idempotent {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) :
    pairAverage i j (pairAverage i j x) = pairAverage i j x := by
  funext k
  by_cases hk : k = i ∨ k = j
  · simp [pairAverage, hk, midpoint, half]
    grind
  · simp [pairAverage, hk]

/-- A local sum-of-squares identity, equivalent to the exact norm drop. -/
theorem pairAverage_pair_sq_drop {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) :
    pairAverage i j x i * pairAverage i j x i +
        pairAverage i j x j * pairAverage i j x j =
      x i * x i + x j * x j - half ((x i - x j) * (x i - x j)) := by
  simp [midpoint, half, Rat.sub_eq_add_neg]
  grind

/-- Exact squared-norm drop with an arbitrary unchanged squared-norm remainder. -/
theorem pairAverage_sqNorm_drop_with_rest {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) (restSq : Rat) :
    restSq + pairAverage i j x i * pairAverage i j x i +
        pairAverage i j x j * pairAverage i j x j =
      restSq + x i * x i + x j * x j -
        half ((x i - x j) * (x i - x j)) := by
  simp [midpoint, half, Rat.sub_eq_add_neg]
  grind

/-- Exact variance drop around any fixed centre `μ`. -/
theorem pairAverage_variance_drop_with_rest {ι : Type} [DecidableEq ι]
    (i j : ι) (x : ι → Rat) (μ restVariance : Rat) :
    restVariance +
        (pairAverage i j x i - μ) * (pairAverage i j x i - μ) +
        (pairAverage i j x j - μ) * (pairAverage i j x j - μ) =
      restVariance + (x i - μ) * (x i - μ) + (x j - μ) * (x j - μ) -
        half ((x i - x j) * (x i - x j)) := by
  simp [midpoint, half, Rat.sub_eq_add_neg]
  grind

/-- Averages on two vertex-disjoint pairs commute exactly. -/
theorem pairAverage_commute_of_disjoint {ι : Type} [DecidableEq ι]
    {i j k l : ι} (x : ι → Rat)
    (hik : i ≠ k) (hil : i ≠ l) (hjk : j ≠ k) (hjl : j ≠ l) :
    pairAverage i j (pairAverage k l x) =
      pairAverage k l (pairAverage i j x) := by
  funext a
  by_cases haij : a = i ∨ a = j
  · rcases haij with rfl | rfl <;>
      simp [pairAverage, midpoint, half, hik, hil, hjk, hjl] <;> grind
  · by_cases hakl : a = k ∨ a = l
    · rcases hakl with rfl | rfl <;>
        simp [pairAverage, midpoint, half,
          hik.symm, hil.symm, hjk.symm, hjl.symm] <;> grind
    · simp [pairAverage, haij, hakl]

section Pullback

/-- Minimal self-contained permutation structure used for settlement algebra. -/
structure Permutation (ι : Type) where
  toFun : ι → ι
  invFun : ι → ι
  left_inv : Function.LeftInverse invFun toFun
  right_inv : Function.RightInverse invFun toFun

theorem Permutation.injective {ι : Type} (σ : Permutation ι) :
    Function.Injective σ.toFun :=
  σ.left_inv.injective

def Permutation.inverse {ι : Type} (σ : Permutation ι) : Permutation ι where
  toFun := σ.invFun
  invFun := σ.toFun
  left_inv := σ.right_inv
  right_inv := σ.left_inv

def Permutation.identity (ι : Type) : Permutation ι where
  toFun := fun k => k
  invFun := fun k => k
  left_inv := fun _ => rfl
  right_inv := fun _ => rfl

/-- Composition is ordered so that `(σ.compose τ)(k)=σ(τ(k))`. -/
def Permutation.compose {ι : Type} (σ τ : Permutation ι) : Permutation ι where
  toFun := fun k => σ.toFun (τ.toFun k)
  invFun := fun k => τ.invFun (σ.invFun k)
  left_inv := by
    intro k
    dsimp
    rw [σ.left_inv (τ.toFun k), τ.left_inv k]
  right_inv := by
    intro k
    dsimp
    rw [τ.right_inv (σ.invFun k), σ.right_inv k]

/-- Pull a field back along a coordinate permutation. -/
def pullback {ι : Type} (σ : Permutation ι) (x : ι → Rat) : ι → Rat :=
  fun k => x (σ.toFun k)

theorem pullback_identity {ι : Type} (x : ι → Rat) :
    pullback (Permutation.identity ι) x = x := by
  rfl

theorem pullback_compose {ι : Type} (σ τ : Permutation ι) (x : ι → Rat) :
    pullback (σ.compose τ) x = pullback τ (pullback σ x) := by
  rfl

theorem pullback_inverse {ι : Type} (σ : Permutation ι) (x : ι → Rat) :
    pullback σ.inverse (pullback σ x) = x := by
  funext k
  simp [pullback, Permutation.inverse, σ.right_inv k]

theorem inverse_pullback {ι : Type} (σ : Permutation ι) (x : ι → Rat) :
    pullback σ (pullback σ.inverse x) = x := by
  funext k
  simp [pullback, Permutation.inverse, σ.left_inv k]

theorem pullback_constant {ι : Type} (σ : Permutation ι) (c : Rat) :
    pullback σ (fun _ => c) = fun _ => c := by
  rfl

theorem pullback_affine {ι : Type} (σ : Permutation ι)
    (x : ι → Rat) (a b : Rat) :
    pullback σ (fun k => a * x k + b) =
      fun k => a * pullback σ x k + b := by
  rfl

/-- Relabelling conjugates a pair average to the average on the pulled-back pair. -/
theorem pullback_pairAverage {ι : Type} [DecidableEq ι]
    (σ : Permutation ι) (i j : ι) (x : ι → Rat) :
    pullback σ (pairAverage (σ.toFun i) (σ.toFun j) x) =
      pairAverage i j (pullback σ x) := by
  funext k
  have hinj := σ.injective
  simp [pullback, pairAverage, hinj.eq_iff]

end Pullback

section BlockConsensus

/-- Average the first Boolean coordinate; its fibres are disjoint pairs. -/
def averageFirst {ι : Type} (x : Bool × ι → Rat) : Bool × ι → Rat := fun p =>
  midpoint (x (false, p.2)) (x (true, p.2))

/-- Average the second Boolean coordinate; its fibres are disjoint pairs. -/
def averageSecond {ι : Type} (x : ι × Bool → Rat) : ι × Bool → Rat := fun p =>
  midpoint (x (p.1, false)) (x (p.1, true))

theorem averageFirst_idempotent {ι : Type} (x : Bool × ι → Rat) :
    averageFirst (averageFirst x) = averageFirst x := by
  funext p
  rcases p with ⟨b, a⟩
  cases b <;> simp [averageFirst, midpoint, half] <;> grind

theorem averageSecond_idempotent {ι : Type} (x : ι × Bool → Rat) :
    averageSecond (averageSecond x) = averageSecond x := by
  funext p
  rcases p with ⟨a, b⟩
  cases b <;> simp [averageSecond, midpoint, half] <;> grind

/-- The two coordinate matchings on `K4` commute. -/
theorem k4_matchings_commute (x : Bool × Bool → Rat) :
    averageSecond (averageFirst x) = averageFirst (averageSecond x) := by
  funext p
  rcases p with ⟨a, b⟩
  cases a <;> cases b <;>
    simp [averageFirst, averageSecond, midpoint, half] <;> grind

/-- Explicit total of a four-coordinate state. -/
def k4Total (x : Bool × Bool → Rat) : Rat :=
  x (false, false) + x (true, false) +
    x (false, true) + x (true, true)

theorem k4_averageFirst_preserves_total (x : Bool × Bool → Rat) :
    k4Total (averageFirst x) = k4Total x := by
  simp [k4Total, averageFirst, midpoint, half]
  grind

theorem k4_averageSecond_preserves_total (x : Bool × Bool → Rat) :
    k4Total (averageSecond x) = k4Total x := by
  simp [k4Total, averageSecond, midpoint, half]
  grind

theorem averageFirst_constant_on_pair {ι : Type} (x : Bool × ι → Rat)
    (a : ι) : averageFirst x (false, a) = averageFirst x (true, a) := by
  rfl

theorem averageSecond_constant_on_pair {ι : Type} (x : ι × Bool → Rat)
    (a : ι) : averageSecond x (a, false) = averageSecond x (a, true) := by
  rfl

/-- Two transverse perfect matchings on `Bool × Bool` (`K4`) give consensus. -/
theorem k4_two_matchings_consensus (x : Bool × Bool → Rat) :
    averageSecond (averageFirst x) = fun _ =>
      (x (false, false) + x (true, false) +
        x (false, true) + x (true, true)) * (1 / 4) := by
  funext p
  rcases p with ⟨a, b⟩
  cases a <;> cases b <;>
    simp [averageFirst, averageSecond, midpoint, half] <;> grind

/-- The two-matching `K4` schedule as a reusable operator. -/
def k4Schedule (x : Bool × Bool → Rat) : Bool × Bool → Rat :=
  averageSecond (averageFirst x)

theorem k4Schedule_idempotent (x : Bool × Bool → Rat) :
    k4Schedule (k4Schedule x) = k4Schedule x := by
  funext p
  rcases p with ⟨a, b⟩
  cases a <;> cases b <;>
    simp [k4Schedule, averageFirst, averageSecond, midpoint, half] <;> grind

theorem k4Schedule_fixed_by_first (x : Bool × Bool → Rat) :
    averageFirst (k4Schedule x) = k4Schedule x := by
  funext p
  rcases p with ⟨a, b⟩
  cases a <;> cases b <;>
    simp [k4Schedule, averageFirst, averageSecond, midpoint, half] <;> grind

theorem k4Schedule_fixed_by_second (x : Bool × Bool → Rat) :
    averageSecond (k4Schedule x) = k4Schedule x := by
  funext p
  rcases p with ⟨a, b⟩
  cases a <;> cases b <;>
    simp [k4Schedule, averageFirst, averageSecond, midpoint, half] <;> grind

theorem k4Schedule_fixes_constant (c : Rat) :
    k4Schedule (fun _ => c) = fun _ => c := by
  funext p
  rcases p with ⟨a, b⟩
  cases a <;> cases b <;>
    simp [k4Schedule, averageFirst, averageSecond, midpoint, half] <;> grind

/-- Average the first coordinate on the Boolean cube `Q3`. -/
def cubeAverage0 (x : Bool × Bool × Bool → Rat) : Bool × Bool × Bool → Rat :=
  fun p => midpoint (x (false, p.2.1, p.2.2)) (x (true, p.2.1, p.2.2))

/-- Average the second coordinate on the Boolean cube `Q3`. -/
def cubeAverage1 (x : Bool × Bool × Bool → Rat) : Bool × Bool × Bool → Rat :=
  fun p => midpoint (x (p.1, false, p.2.2)) (x (p.1, true, p.2.2))

/-- Average the third coordinate on the Boolean cube `Q3`. -/
def cubeAverage2 (x : Bool × Bool × Bool → Rat) : Bool × Bool × Bool → Rat :=
  fun p => midpoint (x (p.1, p.2.1, false)) (x (p.1, p.2.1, true))

theorem cubeAverage0_idempotent (x : Bool × Bool × Bool → Rat) :
    cubeAverage0 (cubeAverage0 x) = cubeAverage0 x := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [cubeAverage0, midpoint, half] <;> grind

theorem cubeAverage1_idempotent (x : Bool × Bool × Bool → Rat) :
    cubeAverage1 (cubeAverage1 x) = cubeAverage1 x := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [cubeAverage1, midpoint, half] <;> grind

theorem cubeAverage2_idempotent (x : Bool × Bool × Bool → Rat) :
    cubeAverage2 (cubeAverage2 x) = cubeAverage2 x := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [cubeAverage2, midpoint, half] <;> grind

theorem cubeAverage01_commute (x : Bool × Bool × Bool → Rat) :
    cubeAverage1 (cubeAverage0 x) = cubeAverage0 (cubeAverage1 x) := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [cubeAverage0, cubeAverage1, midpoint, half] <;> grind

theorem cubeAverage02_commute (x : Bool × Bool × Bool → Rat) :
    cubeAverage2 (cubeAverage0 x) = cubeAverage0 (cubeAverage2 x) := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [cubeAverage0, cubeAverage2, midpoint, half] <;> grind

theorem cubeAverage12_commute (x : Bool × Bool × Bool → Rat) :
    cubeAverage2 (cubeAverage1 x) = cubeAverage1 (cubeAverage2 x) := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [cubeAverage1, cubeAverage2, midpoint, half] <;> grind

/-- Explicit total of an eight-coordinate cube state. -/
def q3Total (x : Bool × Bool × Bool → Rat) : Rat :=
  x (false, false, false) + x (true, false, false) +
  x (false, true, false) + x (true, true, false) +
  x (false, false, true) + x (true, false, true) +
  x (false, true, true) + x (true, true, true)

theorem q3_average0_preserves_total (x : Bool × Bool × Bool → Rat) :
    q3Total (cubeAverage0 x) = q3Total x := by
  simp [q3Total, cubeAverage0, midpoint, half]
  grind

theorem q3_average1_preserves_total (x : Bool × Bool × Bool → Rat) :
    q3Total (cubeAverage1 x) = q3Total x := by
  simp [q3Total, cubeAverage1, midpoint, half]
  grind

theorem q3_average2_preserves_total (x : Bool × Bool × Bool → Rat) :
    q3Total (cubeAverage2 x) = q3Total x := by
  simp [q3Total, cubeAverage2, midpoint, half]
  grind

/-- The three coordinate perfect matchings of `Q3` give exact consensus. -/
theorem q3_three_matchings_consensus (x : Bool × Bool × Bool → Rat) :
    cubeAverage2 (cubeAverage1 (cubeAverage0 x)) = fun _ =>
      (x (false, false, false) + x (true, false, false) +
       x (false, true, false) + x (true, true, false) +
       x (false, false, true) + x (true, false, true) +
       x (false, true, true) + x (true, true, true)) * (1 / 8) := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [cubeAverage0, cubeAverage1, cubeAverage2, midpoint, half] <;> grind

/-- The three-coordinate `Q3` schedule as a reusable operator. -/
def q3Schedule (x : Bool × Bool × Bool → Rat) : Bool × Bool × Bool → Rat :=
  cubeAverage2 (cubeAverage1 (cubeAverage0 x))

theorem q3Schedule_idempotent (x : Bool × Bool × Bool → Rat) :
    q3Schedule (q3Schedule x) = q3Schedule x := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [q3Schedule, cubeAverage0, cubeAverage1, cubeAverage2,
      midpoint, half] <;> grind

theorem q3Schedule_fixed_by_axis0 (x : Bool × Bool × Bool → Rat) :
    cubeAverage0 (q3Schedule x) = q3Schedule x := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [q3Schedule, cubeAverage0, cubeAverage1, cubeAverage2,
      midpoint, half] <;> grind

theorem q3Schedule_fixed_by_axis1 (x : Bool × Bool × Bool → Rat) :
    cubeAverage1 (q3Schedule x) = q3Schedule x := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [q3Schedule, cubeAverage0, cubeAverage1, cubeAverage2,
      midpoint, half] <;> grind

theorem q3Schedule_fixed_by_axis2 (x : Bool × Bool × Bool → Rat) :
    cubeAverage2 (q3Schedule x) = q3Schedule x := by
  funext p
  rcases p with ⟨a, b, c⟩
  cases a <;> cases b <;> cases c <;>
    simp [q3Schedule, cubeAverage0, cubeAverage1, cubeAverage2,
      midpoint, half] <;> grind

theorem q3Schedule_fixes_constant (c : Rat) :
    q3Schedule (fun _ => c) = fun _ => c := by
  funext p
  rcases p with ⟨a, b, d⟩
  cases a <;> cases b <;> cases d <;>
    simp [q3Schedule, cubeAverage0, cubeAverage1, cubeAverage2,
      midpoint, half] <;> grind

end BlockConsensus

section MatrixIdentity

/-- A concrete `2 x 2` matrix type, indexed by `Bool`. -/
abbrev Matrix2 := Bool → Bool → Rat

/-- Exact `2 x 2` matrix multiplication. -/
def Matrix2.mul (A B : Matrix2) : Matrix2 := fun i j =>
  A i false * B false j + A i true * B true j

/-- Exact matrix-vector multiplication. -/
def Matrix2.mulVec (A : Matrix2) (x : Bool → Rat) : Bool → Rat := fun i =>
  A i false * x false + A i true * x true

/-- The `2 x 2` pair-averaging matrix. -/
def pairAverageMatrix : Matrix2 := fun _ _ => 1 / 2

/-- The averaging matrix is idempotent. -/
theorem pairAverageMatrix_idempotent :
    Matrix2.mul pairAverageMatrix pairAverageMatrix = pairAverageMatrix := by
  funext i j
  cases i <;> cases j <;>
    simp [Matrix2.mul, pairAverageMatrix] <;> native_decide

/-- The averaging matrix preserves the all-ones vector. -/
theorem pairAverageMatrix_mulVec_one :
    Matrix2.mulVec pairAverageMatrix (fun _ => 1) = fun _ => 1 := by
  funext i
  cases i <;>
    simp [Matrix2.mulVec, pairAverageMatrix] <;> native_decide

/-- Matrix multiplication agrees exactly with the coordinate definition. -/
theorem pairAverageMatrix_mulVec_eq_pairAverage (x : Bool → Rat) :
    Matrix2.mulVec pairAverageMatrix x = pairAverage false true x := by
  funext i
  cases i <;>
    simp [Matrix2.mulVec, pairAverageMatrix, pairAverage, midpoint, half] <;> grind

end MatrixIdentity

section DyadicObstruction

/-- An odd denominator coprime to two cannot divide a power of two. -/
theorem coprime_denominator_not_power_two (q k : Nat)
    (hq : q ≠ 1) (hcop : Nat.Coprime q 2) :
    ¬ ∃ numerator : Nat, q * numerator = 2 ^ k := by
  intro h
  rcases h with ⟨numerator, hn⟩
  have hcPow : Nat.Coprime q (2 ^ k) := hcop.pow_right k
  have hdiv : q ∣ 2 ^ k := ⟨numerator, hn.symm⟩
  exact hq (hcPow.eq_one_of_dvd hdiv)

/-- Cross-multiplied form of: `1/3` has no power-of-two denominator. -/
theorem one_third_not_power_two_fraction (k : Nat) :
    ¬ ∃ numerator : Nat, 3 * numerator = 2 ^ k := by
  exact coprime_denominator_not_power_two 3 k (by decide) (by decide)

/-- The three possible averaging pairs on three coordinates. -/
inductive Pair3 where
  | ab
  | ac
  | bc
  deriving DecidableEq, Repr

/-- Three nonnegative numerators over one common power-of-two denominator. -/
structure TripleNat where
  a : Nat
  b : Nat
  c : Nat
  deriving DecidableEq, Repr

def TripleNat.total (x : TripleNat) : Nat := x.a + x.b + x.c

def TripleNat.IsConsensus (x : TripleNat) : Prop := x.a = x.b ∧ x.b = x.c

/--
One pair-average step in a common-denominator encoding.  The denominator is
doubled.  The selected numerators are added; every untouched numerator is
doubled so that it represents the same rational value at the finer scale.
-/
def dyadicStep : Pair3 → TripleNat → TripleNat
  | .ab, x => ⟨x.a + x.b, x.a + x.b, 2 * x.c⟩
  | .ac, x => ⟨x.a + x.c, 2 * x.b, x.a + x.c⟩
  | .bc, x => ⟨2 * x.a, x.b + x.c, x.b + x.c⟩

theorem dyadicStep_total (p : Pair3) (x : TripleNat) :
    (dyadicStep p x).total = 2 * x.total := by
  cases p <;> simp [dyadicStep, TripleNat.total] <;> omega

/-- Apply a finite schedule; list order is immaterial for the obstruction. -/
def dyadicRun : List Pair3 → TripleNat → TripleNat
  | [], x => x
  | p :: ps, x => dyadicStep p (dyadicRun ps x)

theorem dyadicRun_total (schedule : List Pair3) (x : TripleNat) :
    (dyadicRun schedule x).total = 2 ^ schedule.length * x.total := by
  induction schedule with
  | nil => simp [dyadicRun]
  | cons p ps ih =>
      simp [dyadicRun, dyadicStep_total, ih, Nat.pow_succ,
        Nat.mul_assoc, Nat.mul_comm]

theorem TripleNat.total_eq_three_mul_of_consensus (x : TripleNat)
    (h : x.IsConsensus) : x.total = 3 * x.a := by
  rcases h with ⟨hab, hbc⟩
  simp [TripleNat.total, hab, ← hbc]
  omega

/-- Initial data of total one, representing `(0,0,1)`. -/
def thirdObstructionInitial : TripleNat := ⟨0, 0, 1⟩

/--
No finite schedule of pair averages can take `(0,0,1)` to exact consensus on
three coordinates.  At depth `k`, a consensus numerator would force
`3*n = 2^k`, contradicting the power-of-two denominator lemma.
-/
theorem three_state_no_finite_pair_average_consensus (schedule : List Pair3) :
    ¬ (dyadicRun schedule thirdObstructionInitial).IsConsensus := by
  intro hcons
  let y := dyadicRun schedule thirdObstructionInitial
  have htotal : y.total = 2 ^ schedule.length := by
    simpa [y, thirdObstructionInitial, TripleNat.total] using
      dyadicRun_total schedule thirdObstructionInitial
  have hthree : y.total = 3 * y.a :=
    y.total_eq_three_mul_of_consensus hcons
  apply one_third_not_power_two_fraction schedule.length
  exact ⟨y.a, hthree.symm.trans htotal⟩

end DyadicObstruction

end GogVerification
