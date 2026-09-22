(* ::Package:: *)

BeginPackage["GogFieldDynamics`"];

GogAvailableSizes::usage =
  "GogAvailableSizes[] lists the complete small graph-type models bundled " <>
  "with the package.";

GogSmallModel::usage =
  "GogSmallModel[n] returns stored graph types, their connections, and exact " <>
  "Rule-A outcome counts for the complete n-vertex model.";

GogTransitionCounts::usage =
  "GogTransitionCounts[n, rule] returns integer event counts for Rule A, " <>
  "Rule B with stay-put outcomes, or the Rule-B jump chain.";

GogTransitionMatrix::usage =
  "GogTransitionMatrix[n, rule] returns the exact row-stochastic transition " <>
  "matrix for Rule A, Rule B, or \"BJump\".";

GogDiffusionState::usage =
  "GogDiffusionState[n, rule, start, steps] returns the exact distribution " <>
  "after the requested number of graph-type steps.";

GogRandomTrajectory::usage =
  "GogRandomTrajectory[n, rule, start, steps, seed] samples a path directly " <>
  "from the exact transition matrix.";

GogSetReplaceAvailableQ::usage =
  "GogSetReplaceAvailableQ[] reports whether the SetReplace paclet can be " <>
  "resolved by this Wolfram installation.";

GogSetReplaceVersion::usage =
  "GogSetReplaceVersion[] returns the resolved SetReplace paclet version.";

GogSetReplaceRules::usage =
  "GogSetReplaceRules[n, rule] encodes graph-type transitions as singleton " <>
  "hypergraph rewrite rules. Rule A retains slot multiplicity; Rule B " <>
  "retains one rule per neighbour and adds stay-put rules for unused outcomes.";

GogSetReplaceTrajectory::usage =
  "GogSetReplaceTrajectory[n, rule, start, steps, seed] samples one path " <>
  "using SetReplace with random event ordering.";

GogTrajectory::usage =
  "GogTrajectory[n, rule, start, steps, seed] returns a sampled path and its " <>
  "engine. Method may be Automatic, \"SetReplace\", or \"Native\".";

GogValidateSmallModels::usage =
  "GogValidateSmallModels[] checks bundled counts, supports, and stochastic " <>
  "normalizations and returns a validation report.";

Begin["`Private`"];

$packageFile = ExpandFileName[$InputFileName];
$pacletRoot = DirectoryName[DirectoryName[$packageFile]];
$smallModelFile = FileNameJoin[
  {$pacletRoot, "Resources", "Data", "small-models.json"}
];
$smallModelData = None;
$smallModelCache = <||>;
$setReplacePaclet = None;

failure[tag_String, message_String, details_: <||>] := Failure[
  tag,
  Join[<|"MessageTemplate" -> message|>, details]
];

loadSmallModelData[] := Module[{imported},
  If[AssociationQ[$smallModelData], Return[$smallModelData]];
  imported = Quiet[Check[Import[$smallModelFile, "RawJSON"], $Failed]];
  If[
    ! AssociationQ[imported],
    Return[failure[
      "SmallModelData",
      "Could not import the bundled small-model resource.",
      <|"File" -> $smallModelFile|>
    ]]
  ];
  $smallModelData = imported
];

GogAvailableSizes[] := Module[{data = loadSmallModelData[], models},
  If[FailureQ[data], Return[data]];
  models = Lookup[data, "models", <||>];
  Sort[ToExpression /@ Keys[models]]
];

GogSmallModel[n_Integer] := Module[{data, raw, model, key = ToString[n]},
  If[KeyExistsQ[$smallModelCache, key], Return[$smallModelCache[key]]];
  data = loadSmallModelData[];
  If[FailureQ[data], Return[data]];
  raw = Lookup[Lookup[data, "models", <||>], key, Missing["NotFound"]];
  If[
    MissingQ[raw],
    Return[failure[
      "UnknownSize",
      "No bundled complete small model exists for this carrier size.",
      <|"N" -> n, "AvailableSizes" -> GogAvailableSizes[]|>
    ]]
  ];
  model = <|
    "N" -> Lookup[raw, "N"],
    "Complete" -> TrueQ[Lookup[raw, "complete"]],
    "CanonicalBackend" -> Lookup[data, "canonical_backend", Missing[]],
    "Nodes" -> Lookup[raw, "nodes", {}],
    "NodeCount" -> Lookup[raw, "node_count", 0],
    "ExpectedNodeCount" ->
      Lookup[raw, "expected_node_count_A005967", Missing[]],
    "Edges" -> ((# + 1) & /@ Lookup[raw, "edges", {}]),
    "EdgeCount" -> Lookup[raw, "edge_count", 0],
    "RuleACounts" -> Lookup[raw, "rule_a_counts", {}],
    "RuleARowSum" -> Lookup[raw, "rule_a_row_sum", 0],
    "RuleASlotCount" -> Lookup[raw, "rule_a_slot_count", 0],
    "ExpectedRuleASlotCount" ->
      Lookup[raw, "expected_rule_a_slot_count", Missing[]]
  |>;
  AssociateTo[$smallModelCache, key -> model];
  model
];

GogSmallModel[n_] := failure[
  "InvalidSize",
  "The carrier size must be one of the bundled even integers.",
  <|"N" -> n|>
];

normalizeRule[rule_] := Switch[
  ToLowerCase[ToString[rule]],
  "a" | "rulea" | "rule a" | "multiplicity", "A",
  "b" | "ruleb" | "rule b" | "support", "B",
  "bjump" | "rule b jump" | "jump" | "neighbour" | "neighbor" |
    "simple neighbour" | "simple neighbor", "BJump",
  _, failure[
    "UnknownRule",
    "The quotient rule must be Rule A, Rule B, or the Rule-B jump chain.",
    <|"Rule" -> rule|>
  ]
];

ruleBSupport[counts_List] := MapIndexed[
  If[First[#2] =!= Last[#2] && #1 > 0, 1, 0] &,
  counts,
  {2}
];

ruleBClockCounts[counts_List, n_Integer] := Module[{support, degrees},
  support = ruleBSupport[counts];
  degrees = Total /@ support;
  support + DiagonalMatrix[3 n - degrees]
];

GogTransitionCounts[n_Integer, rule_: "A"] := Module[
  {model = GogSmallModel[n], normalized = normalizeRule[rule], counts},
  If[FailureQ[model], Return[model]];
  If[FailureQ[normalized], Return[normalized]];
  counts = model["RuleACounts"];
  Switch[
    normalized,
    "A", counts,
    "B", ruleBClockCounts[counts, n],
    "BJump", ruleBSupport[counts]
  ]
];

GogTransitionMatrix[n_Integer, rule_: "A"] := Module[
  {model = GogSmallModel[n], normalized = normalizeRule[rule], counts,
    support, degrees},
  If[FailureQ[model], Return[model]];
  If[FailureQ[normalized], Return[normalized]];
  counts = model["RuleACounts"];
  If[normalized === "A", Return[counts/model["RuleARowSum"]]];
  If[
    normalized === "B",
    Return[ruleBClockCounts[counts, n]/(3 n)]
  ];
  support = ruleBSupport[counts];
  degrees = Total /@ support;
  If[
    AnyTrue[degrees, # <= 0 &],
    Return[failure[
      "IsolatedClass",
      "The Rule-B jump chain is undefined at an isolated quotient class.",
      <|"N" -> n|>
    ]]
  ];
  MapThread[#1/#2 &, {support, degrees}]
];

validStartQ[model_Association, start_] :=
  IntegerQ[start] && 1 <= start <= model["NodeCount"];

GogDiffusionState[
  n_Integer,
  rule_: "A",
  start_Integer,
  steps_Integer?NonNegative
] := Module[{model = GogSmallModel[n], matrix},
  If[FailureQ[model], Return[model]];
  If[
    ! validStartQ[model, start],
    Return[failure[
      "InvalidStart",
      "The starting class index is outside the bundled quotient.",
      <|"N" -> n, "Start" -> start|>
    ]]
  ];
  matrix = GogTransitionMatrix[n, rule];
  If[FailureQ[matrix], Return[matrix]];
  Nest[# . matrix &, UnitVector[model["NodeCount"], start], steps]
];

GogDiffusionState[n_, rule_, start_, steps_] := failure[
  "InvalidDiffusionArguments",
  "Use an available size, an integer class index, and nonnegative steps.",
  <|"N" -> n, "Rule" -> rule, "Start" -> start, "Steps" -> steps|>
];

GogRandomTrajectory[
  n_Integer,
  rule_: "A",
  start_Integer,
  steps_Integer?NonNegative,
  seed_Integer: 1
] := Module[{model = GogSmallModel[n], matrix, states},
  If[FailureQ[model], Return[model]];
  If[
    ! validStartQ[model, start],
    Return[failure[
      "InvalidStart",
      "The starting class index is outside the bundled quotient.",
      <|"N" -> n, "Start" -> start|>
    ]]
  ];
  matrix = GogTransitionMatrix[n, rule];
  If[FailureQ[matrix], Return[matrix]];
  states = Range[model["NodeCount"]];
  BlockRandom[
    SeedRandom[seed];
    NestList[RandomChoice[matrix[[#]] -> states] &, start, steps]
  ]
];

resolveSetReplacePaclet[] := Module[{found, repository, candidates},
  If[Head[$setReplacePaclet] === PacletObject, Return[$setReplacePaclet]];
  found = Quiet[Check[PacletFind["SetReplace"], {}]];
  If[found === {},
    (* Some Wolfram 15 installations retain user paclets in the conventional
       repository without registering them in a -noinit kernel.  Loading only
       matching paclet roots makes that existing installation discoverable. *)
    repository = FileNameJoin[{$UserBaseDirectory, "Paclets", "Repository"}];
    candidates = If[
      DirectoryQ[repository],
      Select[FileNames["SetReplace-*", repository], DirectoryQ],
      {}
    ];
    Scan[
      Function[path, Quiet[Check[PacletDirectoryLoad[path], Null]]],
      candidates
    ];
    found = Quiet[Check[PacletFind["SetReplace"], {}]];
  ];
  If[found === {}, Missing["NotInstalled"], $setReplacePaclet = First[found]]
];

GogSetReplaceAvailableQ[] :=
  Head[resolveSetReplacePaclet[]] === PacletObject;

GogSetReplaceVersion[] := Module[{paclet = resolveSetReplacePaclet[]},
  If[Head[paclet] === PacletObject, paclet["Version"], Missing["NotInstalled"]]
];

GogSetReplaceRules[n_Integer, rule_: "A"] := Module[
  {counts = GogTransitionCounts[n, rule], size},
  If[FailureQ[counts], Return[counts]];
  size = Length[counts];
  Flatten[
    Table[
      ConstantArray[{{source}} -> {{target}}, counts[[source, target]]],
      {source, size},
      {target, size}
    ]
  ]
];

loadSetReplace[] := If[
  ! GogSetReplaceAvailableQ[],
  False,
  Quiet[
    Check[
      Needs["SetReplace`"];
      NameQ["SetReplace`SetReplaceList"],
      False
    ]
  ]
];

GogSetReplaceTrajectory[
  n_Integer,
  rule_: "A",
  start_Integer,
  steps_Integer?NonNegative,
  seed_Integer: 1
] := Module[{model = GogSmallModel[n], rules, evolution},
  If[FailureQ[model], Return[model]];
  If[
    ! validStartQ[model, start],
    Return[failure[
      "InvalidStart",
      "The starting class index is outside the bundled quotient.",
      <|"N" -> n, "Start" -> start|>
    ]]
  ];
  If[
    ! TrueQ[loadSetReplace[]],
    Return[failure[
      "SetReplaceUnavailable",
      "The SetReplace paclet is not available to this Wolfram kernel."
    ]]
  ];
  rules = GogSetReplaceRules[n, rule];
  If[FailureQ[rules], Return[rules]];
  evolution = BlockRandom[
    SeedRandom[seed];
    Quiet[
      Check[
        SetReplace`SetReplaceList[
          {{start}},
          rules,
          steps,
          "EventOrderingFunction" -> "Random"
        ],
        $Failed
      ]
    ]
  ];
  If[
    ! MatchQ[evolution, {{{_Integer}} ..}],
    Return[failure[
      "SetReplaceEvolution",
      "SetReplace did not return a singleton-state trajectory.",
      <|"N" -> n, "Rule" -> rule, "Steps" -> steps|>
    ]]
  ];
  evolution[[All, 1, 1]]
];

Options[GogTrajectory] = {Method -> Automatic};

GogTrajectory[
  n_Integer,
  rule_: "A",
  start_Integer,
  steps_Integer?NonNegative,
  seed_Integer: 1,
  OptionsPattern[]
] := Module[{method = OptionValue[Method], path},
  Switch[
    method,
    "Native",
      path = GogRandomTrajectory[n, rule, start, steps, seed];
      If[FailureQ[path], path, <|"States" -> path, "Engine" -> "Native"|>],
    "SetReplace",
      path = GogSetReplaceTrajectory[n, rule, start, steps, seed];
      If[
        FailureQ[path],
        path,
        <|
          "States" -> path,
          "Engine" -> "SetReplace",
          "SetReplaceVersion" -> GogSetReplaceVersion[]
        |>
      ],
    Automatic,
      path = GogSetReplaceTrajectory[n, rule, start, steps, seed];
      If[
        FailureQ[path],
        path = GogRandomTrajectory[n, rule, start, steps, seed];
        If[
          FailureQ[path],
          path,
          <|"States" -> path, "Engine" -> "Native fallback"|>
        ],
        <|
          "States" -> path,
          "Engine" -> "SetReplace",
          "SetReplaceVersion" -> GogSetReplaceVersion[]
        |>
      ],
    _,
      failure[
        "UnknownMethod",
        "Method must be Automatic, \"SetReplace\", or \"Native\".",
        <|"Method" -> method|>
      ]
  ]
];

GogValidateSmallModels[] := Module[{sizes, reports},
  sizes = GogAvailableSizes[];
  If[FailureQ[sizes], Return[sizes]];
  reports = AssociationMap[
    Function[n,
      Module[{model = GogSmallModel[n], counts, support, clockCounts,
        matrixA, matrixB, matrixBJump, edges, supportEdges, checks},
        counts = model["RuleACounts"];
        support = ruleBSupport[counts];
        clockCounts = ruleBClockCounts[counts, n];
        matrixA = GogTransitionMatrix[n, "A"];
        matrixB = GogTransitionMatrix[n, "B"];
        matrixBJump = GogTransitionMatrix[n, "BJump"];
        edges = Sort[Sort /@ model["Edges"]];
        supportEdges = Sort @ DeleteDuplicates @ Cases[
          MapIndexed[
            If[First[#2] < Last[#2] && #1 > 0, #2, Nothing] &,
            support,
            {2}
          ],
          {_Integer, _Integer},
          Infinity
        ];
        checks = <|
          "Complete" -> TrueQ[model["Complete"]],
          "NodeCount" ->
            (model["NodeCount"] === model["ExpectedNodeCount"] === Length[counts]),
          "RuleARowSums" ->
            AllTrue[Total /@ counts, # === 3 n &],
          "RuleASlotCount" ->
            (Total[Flatten[counts]] === model["RuleASlotCount"] ===
              model["ExpectedRuleASlotCount"]),
          "SupportEdges" -> (edges === supportEdges),
          "RuleAStochastic" -> AllTrue[Total /@ matrixA, # === 1 &],
          "RuleBClockRowSums" ->
            AllTrue[Total /@ clockCounts, # === 3 n &],
          "RuleBClockSymmetric" -> (clockCounts === Transpose[clockCounts]),
          "RuleBStochastic" -> AllTrue[Total /@ matrixB, # === 1 &],
          "RuleBUniformStationary" ->
            AllTrue[Total /@ Transpose[matrixB], # === 1 &],
          "RuleBJumpStochastic" ->
            AllTrue[Total /@ matrixBJump, # === 1 &]
        |>;
        <|"Valid" -> And @@ Values[checks], "Checks" -> checks|>
      ]
    ],
    sizes
  ];
  <|
    "Valid" -> AllTrue[Values[reports], TrueQ[#["Valid"]] &],
    "Models" -> reports
  |>
];

End[];
EndPackage[];
