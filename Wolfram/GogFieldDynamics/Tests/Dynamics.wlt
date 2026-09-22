VerificationTest[
  GogFieldDynamics`GogAvailableSizes[],
  {2, 4, 6, 8},
  TestID -> "bundled-sizes"
]

VerificationTest[
  GogFieldDynamics`GogValidateSmallModels[]["Valid"],
  True,
  TestID -> "small-model-integrity"
]

VerificationTest[
  GogFieldDynamics`GogTransitionCounts[2, "A"],
  {{3, 3}, {2, 4}},
  TestID -> "n2-rule-a-slot-counts"
]

VerificationTest[
  GogFieldDynamics`GogTransitionMatrix[2, "B"],
  {{5/6, 1/6}, {1/6, 5/6}},
  TestID -> "n2-rule-b-with-holds"
]

VerificationTest[
  GogFieldDynamics`GogTransitionMatrix[2, "BJump"],
  {{0, 1}, {1, 0}},
  TestID -> "n2-rule-b-jump-chain"
]

VerificationTest[
  GogFieldDynamics`GogDiffusionState[2, "A", 1, 1],
  {1/2, 1/2},
  TestID -> "exact-rule-a-diffusion"
]

VerificationTest[
  Module[
    {counts = GogFieldDynamics`GogTransitionCounts[4, "A"],
      rules = GogFieldDynamics`GogSetReplaceRules[4, "A"]},
    Table[
      Count[rules, {{source}} -> {{target}}],
      {source, Length[counts]},
      {target, Length[counts]}
    ] === counts
  ],
  True,
  TestID -> "n4-rule-a-rewrite-multiplicities"
]

VerificationTest[
  Module[
    {counts = GogFieldDynamics`GogTransitionCounts[4, "B"],
      rules = GogFieldDynamics`GogSetReplaceRules[4, "B"]},
    Table[
      Count[rules, {{source}} -> {{target}}],
      {source, Length[counts]},
      {target, Length[counts]}
    ] === counts && AllTrue[Total /@ counts, # === 12 &]
  ],
  True,
  TestID -> "n4-rule-b-rewrite-rules-with-holds"
]

VerificationTest[
  Module[{path = GogFieldDynamics`GogSetReplaceTrajectory[4, "A", 1, 8, 2026]},
    ListQ[path] && Length[path] === 9 &&
      AllTrue[path, IntegerQ[#] && 1 <= # <= 5 &]
  ],
  True,
  TestID -> "setreplace-sampled-trajectory"
]
