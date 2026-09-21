#!/usr/bin/env wolframscript

(* Build an executable mini-notebook from the computational-notes narrative. *)

$requiredGogFieldDynamicsVersion = "0.2.0";
$minimumWolframVersion = 14.3;

fail[message_String] := (
  WriteString[
    "stderr",
    "Computational-notes notebook build failed: " <> message <> "\n"
  ];
  Exit[1]
);

progress[message_String] :=
  Print["Computational-notes notebook build: " <> message];

scriptFile = If[
  StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[
    {Directory[], "scripts", "build_computational_notes_notebook.wls"}
  ]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
notebookFile = FileNameJoin[
  {repositoryDirectory, "whitehead-field-dynamics-computational-notes.nb"}
];
paperPacletDirectory = FileNameJoin[
  {repositoryDirectory, "Wolfram", "GogFieldDynamics"}
];

If[$VersionNumber < $minimumWolframVersion,
  fail["Wolfram Language 14.3 or newer is required; found " <> $Version]
];
If[! DirectoryQ[paperPacletDirectory],
  fail["local paclet not found: " <> paperPacletDirectory]
];

Quiet @ Check[
  PacletDirectoryLoad[paperPacletDirectory];
  Needs["GogFieldDynamics`"],
  fail["the repo-local GogFieldDynamics paclet could not be loaded"]
];

paperPaclet = Quiet[Check[PacletObject["GogFieldDynamics"], $Failed]];
If[
  Head[paperPaclet] =!= PacletObject ||
    paperPaclet["Version"] =!= $requiredGogFieldDynamicsVersion,
  fail["GogFieldDynamics 0.2.0 is required"]
];

SetDirectory[repositoryDirectory];

code = <||>;

code["setup"] = "repo = Quiet[Check[NotebookDirectory[], $Failed]];
If[
  ! StringQ[repo] ||
    ! DirectoryQ[FileNameJoin[{repo, \"Wolfram\", \"GogFieldDynamics\"}]],
  repo = Directory[]
];
PacletDirectoryLoad[
  FileNameJoin[{repo, \"Wolfram\", \"GogFieldDynamics\"}]
];
Needs[\"GogFieldDynamics`\"];
<|
  \"GogFieldDynamicsVersion\" ->
    PacletObject[\"GogFieldDynamics\"][\"Version\"],
  \"PacletLoaded\" -> NameQ[\"GogFieldDynamics`GogAvailableSizes\"]
|>";

code["pair-loss"] = "Clear[x, y];
FullSimplify[
  x^2 + y^2 - 2 ((x + y)/2)^2,
  Assumptions -> Element[{x, y}, Reals]
]";

code["averaging-matrix"] = "pairAverage[n_, {i_, j_}] := ReplacePart[
  IdentityMatrix[n],
  {{i, i} -> 1/2, {i, j} -> 1/2,
   {j, i} -> 1/2, {j, j} -> 1/2}
];

a = pairAverage[4, {1, 3}];
{
  SymmetricMatrixQ[a],
  a . a === a,
  a . ConstantArray[1, 4] === ConstantArray[1, 4]
}";

code["resource-summary"] = "Table[
  With[{m = GogSmallModel[n]},
    {n, m[\"NodeCount\"], m[\"EdgeCount\"],
     m[\"RuleASlotCount\"]}
  ],
  {n, GogAvailableSizes[]}
]";

code["validation"] = "r = GogValidateSmallModels[];
{
  r[\"Valid\"],
  AssociationMap[
    r[\"Models\", #][\"Valid\"] &,
    GogAvailableSizes[]
  ]
}";

code["rule-a-counts"] = "countsA = GogTransitionCounts[4, \"A\"];
{countsA, Total /@ countsA}";

code["rule-a-stationary"] = "pA = GogTransitionMatrix[4, \"A\"];
piA = First[
  NullSpace[Transpose[pA] - IdentityMatrix[Length[pA]]]
];
piA/Total[piA]";

code["fixed-clock-b"] = "pB = GogTransitionMatrix[4, \"B\"];
MatrixForm[pB]";

code["symmetry-stationarity"] = "u = ConstantArray[1/5, 5];
{SymmetricMatrixQ[pB], u . pB}";

code["b-versus-jump"] = "{
  GogTransitionMatrix[2, \"B\"],
  GogTransitionMatrix[2, \"BJump\"]
}";

code["diffusion-a"] = "p4A = GogDiffusionState[4, \"A\", 1, 4];
{p4A, N[p4A, 6]}";

code["diffusion-b"] = "p4B = GogDiffusionState[4, \"B\", 1, 4];
{p4B, N[p4B, 6]}";

code["seeded-path"] =
  "GogRandomTrajectory[4, \"A\", 1, 12, 2026]";

code["matching-products"] = "matching[n_, edges_] :=
  Dot @@ (pairAverage[n, #] & /@ edges);

k4Word =
  matching[4, {{1, 3}, {2, 4}}] .
  matching[4, {{1, 2}, {3, 4}}];

q3Word =
  matching[8, {{1, 5}, {2, 6}, {3, 7}, {4, 8}}] .
  matching[8, {{1, 3}, {2, 4}, {5, 7}, {6, 8}}] .
  matching[8, {{1, 2}, {3, 4}, {5, 6}, {7, 8}}];

{
  k4Word === ConstantArray[1/4, {4, 4}],
  q3Word === ConstantArray[1/8, {8, 8}]
}";

code["k4-product"] = "k4Word // MatrixForm";

code["self-test"] = "miniNotebookChecks = <|
  \"PacletLoaded\" ->
    NameQ[\"GogFieldDynamics`GogSmallModel\"],
  \"AvailableSizes\" ->
    (GogAvailableSizes[] === {2, 4, 6}),
  \"ModelsValidate\" ->
    TrueQ[GogValidateSmallModels[][\"Valid\"]],
  \"PairLoss\" ->
    (FullSimplify[
       x^2 + y^2 - 2 ((x + y)/2)^2,
       Assumptions -> Element[{x, y}, Reals]
     ] === (x - y)^2/2),
  \"Projection\" ->
    And @@ {
      SymmetricMatrixQ[a],
      a . a === a,
      a . ConstantArray[1, 4] === ConstantArray[1, 4]
    },
  \"RuleARowSums\" ->
    (Total /@ GogTransitionCounts[4, \"A\"] ===
      ConstantArray[12, 5]),
  \"RuleBUniform\" ->
    (SymmetricMatrixQ[pB] &&
      ConstantArray[1/5, 5] . pB === ConstantArray[1/5, 5]),
  \"DiffusionMass\" ->
    (Total[p4A] === 1 && Total[p4B] === 1),
  \"SeededTrajectory\" ->
    (GogRandomTrajectory[4, \"A\", 1, 12, 2026] ===
      {1, 3, 1, 3, 3, 3, 3, 5, 3, 1, 2, 2, 1}),
  \"FiniteConsensus\" ->
    (k4Word === ConstantArray[1/4, {4, 4}] &&
      q3Word === ConstantArray[1/8, {8, 8}])
|>;
<|
  \"AllTestsPassed\" -> And @@ Values[miniNotebookChecks],
  \"Checks\" -> miniNotebookChecks
|>";

progress["evaluating all executable cell sources"];
results = <||>;
Scan[
  Function[id,
    value = Quiet[Check[ToExpression[code[id], InputForm], $Failed]];
    If[value === $Failed, fail["cell evaluation failed: " <> id]];
    AssociateTo[results, id -> value]
  ],
  Keys[code]
];
If[! TrueQ[results["self-test"]["AllTestsPassed"]],
  fail["the final notebook self-test did not pass"]
];

$navy = RGBColor[0.075, 0.13, 0.22];
$blue = RGBColor[0.00, 0.45, 0.70];
$green = RGBColor[0.00, 0.62, 0.45];
$orange = RGBColor[0.90, 0.62, 0.00];
$muted = RGBColor[0.37, 0.42, 0.49];
$line = RGBColor[0.82, 0.85, 0.88];
$wash = RGBColor[0.965, 0.975, 0.985];
$outputWash = RGBColor[0.992, 0.976, 0.935];

uuidFromSeed[seed_] := Module[{hex},
  hex = StringTake[
    IntegerString[
      Hash[{"gog-computational-notes", seed}, "SHA256"],
      16,
      64
    ],
    32
  ];
  StringRiffle[
    (StringTake[hex, #] &) /@ {
      {1, 8}, {9, 12}, {13, 16}, {17, 20}, {21, 32}
    },
    "-"
  ]
];

noteCell[content_, style_String, id_String, options___] := Cell[
  content,
  style,
  TaggingRules -> <|
    "GoGComputationalNotes" -> <|"ID" -> id, "Generated" -> True|>
  |>,
  CellTags -> {"GoGComputationalNotes", id},
  ExpressionUUID -> uuidFromSeed[id],
  options
];

textCell[text_String, id_String] := noteCell[
  text,
  "Text",
  id,
  FontSize -> 12,
  LineSpacing -> {1.15, 2}
];

captionCell[text_String, id_String] := noteCell[
  text,
  "Caption",
  id,
  FontColor -> $muted,
  CellMargins -> {{72, 72}, {3, 14}},
  ShowCellBracket -> False
];

bulletCell[text_String, id_String] := noteCell[
  text,
  "Item",
  id,
  FontSize -> 12
];

numberedCell[text_String, id_String] := noteCell[
  text,
  "ItemNumbered",
  id,
  FontSize -> 12
];

SetAttributes[formulaCell, HoldAllComplete];
formulaCell[expression_, id_String] := noteCell[
  BoxData[ToBoxes[expression, TraditionalForm]],
  "DisplayFormula",
  id,
  ShowCellBracket -> False,
  TextAlignment -> Center,
  FontSize -> 15
];

codeBoxes[source_String] := ToBoxes[
  ToExpression["(" <> source <> ")", InputForm, Defer],
  StandardForm
];

cellHeading[topic_String, id_String] := noteCell[
  TextData[{
    StyleBox[
      "MATHEMATICA CELLS: ",
      FontWeight -> "Bold",
      FontColor -> $blue
    ],
    topic
  }],
  "Text",
  id <> "Heading",
  ShowCellBracket -> False,
  CellMargins -> {{48, 48}, {12, 3}},
  TextAlignment -> Center,
  FontSize -> 10,
  FontColor -> $muted
];

inputCell[source_String, id_String, initialization_: False] := noteCell[
  BoxData[codeBoxes[source]],
  "Input",
  id <> "Input",
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{9, 9}, {8, 8}},
  Background -> $wash,
  FontSize -> 11,
  InitializationCell -> initialization
];

outputCell[value_, id_String] := noteCell[
  BoxData[ToBoxes[value, StandardForm]],
  "Output",
  id <> "Output",
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{9, 9}, {8, 8}},
  Background -> $outputWash,
  FontSize -> 11,
  GeneratedCell -> True,
  CellAutoOverwrite -> True
];

cellPair[topic_String, id_String, initialization_: False] := {
  cellHeading[topic, id],
  CellGroupData[
    {
      inputCell[code[id], id, initialization],
      outputCell[results[id], id]
    },
    Open
  ]
};

programCell[text_String, id_String] := noteCell[
  text,
  "Program",
  id,
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{9, 9}, {8, 8}},
  Background -> $wash,
  FontSize -> 10
];

visualMapCell[] := noteCell[
  TextData[{
    StyleBox["Visual abstract. ", FontWeight -> "Bold", FontColor -> $navy],
    "Separates carrier field, fixed-labelled moves, multiplicity, and support.\n",
    StyleBox["Whitehead move. ", FontWeight -> "Bold", FontColor -> $navy],
    "Shows the selected edge, exposed half-edges, and two resolutions.\n",
    StyleBox["Variance drop. ", FontWeight -> "Bold", FontColor -> $navy],
    "Turns one pair average into the exact loss (f_i-f_j)^2/2.\n",
    StyleBox["Consensus schedules. ", FontWeight -> "Bold", FontColor -> $navy],
    "Displays finite consensus layers on K4 and Q3.\n",
    StyleBox["Transition heat maps. ", FontWeight -> "Bold", FontColor -> $navy],
    "Compares Rule A and fixed-clock Rule B at N=4.\n",
    StyleBox["Diffusion laboratory. ", FontWeight -> "Bold", FontColor -> $navy],
    "Separates exact rational mass from one sampled path.\n",
    StyleBox["Enumeration growth. ", FontWeight -> "Bold", FontColor -> $navy],
    "Compares class and Rule-A slot counts through N=14."
  }],
  "Text",
  "VisualMapTable",
  ShowCellBracket -> False,
  CellMargins -> {{48, 48}, {8, 14}},
  CellFrame -> True,
  CellFrameStyle -> Directive[$line],
  CellFrameMargins -> {{12, 12}, {10, 10}},
  Background -> $wash,
  FontSize -> 11,
  LineSpacing -> {1.1, 2}
];

bannerCell[] := noteCell[
  TextData[{
    StyleBox[
      "EXECUTABLE MINI-NOTEBOOK",
      FontFamily -> "Helvetica",
      FontWeight -> "Bold",
      FontColor -> $blue
    ],
    StyleBox["   •   ", FontColor -> $line],
    StyleBox[
      "exact cells • local paclet • built-in self-test",
      FontFamily -> "Helvetica",
      FontColor -> $muted
    ]
  }],
  "Text",
  "EditionBanner",
  ShowCellBracket -> False,
  TextAlignment -> Center,
  CellFrame -> True,
  CellFrameStyle -> Directive[$line],
  CellFrameMargins -> {{12, 12}, {8, 8}},
  Background -> $wash
];

cells = Flatten[
  {
    noteCell[
      "Whitehead Field Dynamics",
      "Title",
      "Title",
      TextAlignment -> Center,
      FontColor -> $navy
    ],
    noteCell[
      "Computational Notes — Executable Mini-Notebook",
      "Subtitle",
      "Subtitle",
      TextAlignment -> Center,
      FontColor -> $muted
    ],
    noteCell[
      "Alexander Kolpakov",
      "Author",
      "Author",
      TextAlignment -> Center
    ],
    noteCell[
      "September 21, 2026",
      "Affiliation",
      "Date",
      TextAlignment -> Center,
      FontColor -> $muted
    ],
    bannerCell[],
    textCell[
      "This mini-notebook is the executable counterpart of " <>
      "whitehead-field-dynamics-computational-notes.tex. It records the " <>
      "local pair-averaging calculation, the exact small graph-of-graphs " <>
      "models, the two transition clocks, exact diffusion snapshots, one " <>
      "seeded path, and finite consensus products for K4 and Q3. Every " <>
      "displayed number is computed exactly before a decimal approximation " <>
      "is requested. Proofs remain in the full LaTeX manuscript.",
      "Abstract"
    ],

    noteCell["Start here", "Section", "SectionSetup"],
    textCell[
      "Keep this notebook in the repository root. Choose Evaluation > " <>
      "Evaluate Notebook to run the cells in order. The setup cell loads the " <>
      "repo-local GogFieldDynamics paclet; no global installation and no " <>
      "MathNotebook paclet are needed. SetReplace is optional and is not used " <>
      "by the displayed native sample path.",
      "SetupGuide"
    ],
    cellPair["local paclet", "setup", True],
    captionCell[
      "The final section contains a self-test. A successful complete run ends " <>
      "with AllTestsPassed -> True.",
      "SetupCaption"
    ],

    noteCell["What is being computed", "Section", "SectionObjects"],
    textCell[
      "The state space consists of isomorphism classes of connected cubic " <>
      "multigraphs on an even number N of vertices; loops and parallel edges " <>
      "are allowed. A Whitehead move selects a carrier edge, collapses it, " <>
      "and chooses one of the two other pairings of the four exposed " <>
      "half-edges. A scalar field f in R^N is carried along with the graph. " <>
      "If the selected edge has endpoints i and j, their values are replaced " <>
      "by their common mean.",
      "ObjectsIntro"
    ],
    formulaCell[
      HoldForm[
        {Subscript[f, i], Subscript[f, j]} ->
          {
            (Subscript[f, i] + Subscript[f, j])/2,
            (Subscript[f, i] + Subscript[f, j])/2
          }
      ],
      "FieldUpdateFormula"
    ],
    textCell[
      "Three computational objects must be kept separate.",
      "ObjectsListIntro"
    ],
    numberedCell[
      "The carrier field uses a concrete edge and, after an unlabelled move, " <>
      "a settlement permutation for its coordinates.",
      "ObjectCarrier"
    ],
    numberedCell[
      "Rule A is the quotient chain that retains all 3N compressed resolution " <>
      "slots, including multiplicity and holding slots.",
      "ObjectRuleA"
    ],
    numberedCell[
      "Fixed-clock Rule B gives one of the same 3N ticks to each distinct " <>
      "nonself quotient neighbour and turns unused ticks into holds. BJump is " <>
      "Rule B conditioned on moving and is a different chain.",
      "ObjectRuleB"
    ],
    textCell[
      "The interactive laboratory in whitehead-field-dynamics.nb bundles " <>
      "complete quotient data only for N=2,4,6. Larger finite tables come " <>
      "from the Python enumeration pipeline and are not part of the compact " <>
      "notebook resource.",
      "ObjectsBoundary"
    ],

    noteCell["A visual map of the companion", "Section", "SectionVisualMap"],
    textCell[
      "The separate visual companion whitehead-field-dynamics.nb is " <>
      "deliberately not a copy of the paper. Its seven pictures provide entry " <>
      "points into the following computational questions.",
      "VisualMapIntro"
    ],
    visualMapCell[],
    textCell[
      "This mini-notebook keeps the fuller explanatory text and executable " <>
      "transcript. Every input/output pair has one shared MATHEMATICA CELLS " <>
      "heading. Inputs are pale blue and exact outputs are warm cream.",
      "VisualMapBoundary"
    ],

    noteCell[
      "The local averaging calculation",
      "Section",
      "SectionLocalAverage"
    ],
    textCell[
      "For a non-loop pair {i,j}, the averaging matrix is the orthogonal " <>
      "projection onto the hyperplane f_i=f_j.",
      "AverageIntro"
    ],
    formulaCell[
      HoldForm[
        Subscript[A, i, j] ==
          Subscript[identity, n] -
            1/2 (Subscript[e, i] - Subscript[e, j])
              Superscript[(Subscript[e, i] - Subscript[e, j]), T]
      ],
      "AverageMatrixFormula"
    ],
    textCell[
      "It is symmetric, idempotent, and fixes the all-ones vector. The " <>
      "two-coordinate energy calculation can be checked without constructing " <>
      "the whole matrix.",
      "AverageProperties"
    ],
    cellPair["one-pair loss", "pair-loss"],
    textCell[
      "The sum and therefore the mean are unchanged. Applied to the centered " <>
      "field, the identity is an exact Lyapunov law.",
      "VarianceIntro"
    ],
    formulaCell[
      HoldForm[
        V[Subscript[A, i, j] f] ==
          V[f] -
            (Subscript[f, i] - Subscript[f, j])^2/2
      ],
      "VarianceFormula"
    ],
    cellPair["averaging matrix", "averaging-matrix"],
    textCell[
      "A settlement is a permutation matrix. It preserves sums and Euclidean " <>
      "norms, so it cannot change this one-step variance identity. It can " <>
      "change which persistent coordinate pair is averaged later; a quotient " <>
      "trajectory alone therefore does not reconstruct the full field cocycle.",
      "SettlementBoundary"
    ],

    noteCell[
      "Loading and validating the notebook models",
      "Section",
      "SectionModels"
    ],
    textCell[
      "The setup cell loaded the local companion paclet. For each bundled " <>
      "size, the next query records {N, number of classes, support edges, " <>
      "total Rule-A slots}.",
      "ModelsIntro"
    ],
    cellPair["resource summary", "resource-summary"],
    textCell[
      "The class counts 2, 5, and 17 agree with the corresponding first terms " <>
      "of OEIS A005967. The total slot counts independently satisfy classes " <>
      "times 3N: 2*6=12, 5*12=60, and 17*18=306.",
      "SlotCheckText"
    ],
    textCell[
      "The paclet validator checks completeness metadata, node and slot " <>
      "counts, support edges, row sums, stochasticity, Rule-B symmetry, and " <>
      "uniform Rule-B stationarity.",
      "ValidationIntro"
    ],
    cellPair["compact validation report", "validation"],
    captionCell[
      "These are complete finite checks of the bundled data and implemented " <>
      "matrix conventions; they are not an asymptotic theorem.",
      "ValidationBoundary"
    ],

    noteCell["An exact five-state example", "Section", "SectionFiveState"],
    textCell[
      "At N=4 there are five unlabelled carrier classes. Rule A retains the " <>
      "integer multiplicity of every compressed resolution.",
      "FiveStateIntro"
    ],
    cellPair["Rule-A counts", "rule-a-counts"],
    textCell[
      "Every row sums to 3N=12. Dividing the count matrix by 12 gives the " <>
      "exact Rule-A transition matrix. It is not symmetric.",
      "RuleAMatrixText"
    ],
    formulaCell[HoldForm[Subscript[P, A] == MatrixForm[pA]], "RuleAMatrix"],
    textCell[
      "Solving pi_A P_A = pi_A with exact arithmetic gives a nonuniform law.",
      "StationaryIntro"
    ],
    cellPair["Rule-A stationary law", "rule-a-stationary"],
    textCell[
      "This is the finite N=4 instance of the projected cubic " <>
      "configuration-model law. Treating Rule A as uniform on isomorphism " <>
      "classes would change the process.",
      "StationaryMeaning"
    ],
    textCell[
      "For fixed-clock Rule B, every distinct nonself support neighbour has " <>
      "probability 1/12 and the remaining ticks hold.",
      "RuleBIntro"
    ],
    cellPair["fixed-clock Rule B", "fixed-clock-b"],
    textCell[
      "The defining symmetry and stationarity checks can be made directly.",
      "RuleBChecksIntro"
    ],
    cellPair[
      "symmetry and stationarity",
      "symmetry-stationarity"
    ],
    formulaCell[
      HoldForm[
        IdentityMatrix[n] - Subscript[P, B] ==
          Subscript[L, supp]/(3 n)
      ],
      "RuleBLaplacianFormula"
    ],
    textCell[
      "Holding cannot simply be discarded. Already at N=2, the fixed clock " <>
      "and the chain conditioned on moving have the same nonself support but " <>
      "different clocks, spectra, and path probabilities.",
      "JumpChainIntro"
    ],
    cellPair["Rule B versus its jump chain", "b-versus-jump"],

    noteCell[
      "Exact diffusion and a sampled path",
      "Section",
      "SectionDiffusion"
    ],
    textCell[
      "The blue node fill in the visual laboratory is exact row-vector matrix " <>
      "evolution. Its default view uses N=4, Rule A, start class 1, and t=4.",
      "DiffusionIntro"
    ],
    cellPair["default exact snapshot", "diffusion-a"],
    textCell[
      "All five classes are reachable by time four, but the mass is far from " <>
      "the stationary vector. The same initial condition under fixed-clock " <>
      "Rule B retains much more mass at the starting class.",
      "DiffusionComparisonIntro"
    ],
    cellPair["Rule-B comparison", "diffusion-b"],
    textCell[
      "This compares quotient clocks; it does not specify a Rule-B lift that " <>
      "chooses which concrete carrier edge to average. The orange trail in " <>
      "the visual notebook is one random realization, not an estimate of the " <>
      "blue exact distribution.",
      "DiffusionBoundary"
    ],
    cellPair["one reproducible trajectory", "seeded-path"],
    captionCell[
      "Repeated class labels are genuine holding events. The fixed seed makes " <>
      "this native sample reproducible.",
      "PathCaption"
    ],

    noteCell["Finite consensus words", "Section", "SectionConsensus"],
    textCell[
      "Pair averages on disjoint edges commute, so a perfect matching is one " <>
      "block. Two matching layers on K4 and three coordinate matchings on Q3 " <>
      "give exact finite consensus.",
      "ConsensusIntro"
    ],
    formulaCell[
      HoldForm[
        Subscript[J, 4] == ConstantArray[1/4, {4, 4}] &&
          Subscript[J, 8] == ConstantArray[1/8, {8, 8}]
      ],
      "ConsensusFormula"
    ],
    cellPair["matching products", "matching-products"],
    textCell[
      "For example, the K4 word is returned exactly as the consensus matrix.",
      "K4Intro"
    ],
    cellPair["the K4 product", "k4-product"],
    textCell[
      "Every initial field therefore reaches its exact mean after the stated " <>
      "schedule. This exceptional finite-time consensus should not be " <>
      "extrapolated to arbitrary N: pair averaging has a dyadic denominator " <>
      "obstruction, and (0,0,1) cannot reach its mean after a finite word of " <>
      "pair averages.",
      "ConsensusBoundary"
    ],

    noteCell["Interpretation limits", "Section", "SectionLimits"],
    textCell[
      "The executable transcript supports the following precise conclusions.",
      "LimitsPositiveIntro"
    ],
    bulletCell[
      "Pair averaging is an orthogonal projection with exact variance loss.",
      "LimitPositive1"
    ],
    bulletCell[
      "Each Rule-A row contains exactly 3N resolution slots.",
      "LimitPositive2"
    ],
    bulletCell[
      "The N=4 Rule-A class law is nonuniform.",
      "LimitPositive3"
    ],
    bulletCell[
      "Fixed-clock Rule B is symmetric and has uniform class stationarity.",
      "LimitPositive4"
    ],
    bulletCell[
      "Diffusion is exact rational matrix evolution, and the K4/Q3 schedules " <>
      "are exact finite consensus words.",
      "LimitPositive5"
    ],
    textCell[
      "There are also three important non-conclusions.",
      "LimitsNegativeIntro"
    ],
    numberedCell[
      "The bundled quotient model omits carrier edges, resolution identifiers, " <>
      "and settlement permutations, so it cannot by itself produce a pathwise " <>
      "transported field or Lyapunov exponent.",
      "LimitNegative1"
    ],
    numberedCell[
      "A single sampled trajectory does not approximate the exact distribution.",
      "LimitNegative2"
    ],
    numberedCell[
      "Complete finite checks through N=6 here or N=14 in the Python tables " <>
      "do not prove an asymptotic spectral or mixing statement.",
      "LimitNegative3"
    ],

    noteCell["Reproduction and self-test", "Section", "SectionReproduction"],
    textCell[
      "The transcript was regenerated with Wolfram 15.0.0 for macOS ARM. The " <>
      "following shell commands reproduce the textual transcript, byte-check " <>
      "the small-model resource, rebuild the TeX note, and validate this " <>
      "mini-notebook. They are shown as program text rather than Mathematica " <>
      "input cells.",
      "ReproductionIntro"
    ],
    programCell[
      "/Applications/Wolfram.app/Contents/MacOS/WolframKernel -noinit " <>
      "-noprompt -script scripts/notebook_report_outputs.wls",
      "TranscriptCommand"
    ],
    programCell[
      "python3 scripts/build_small_gog_models.py --check",
      "DataCheckCommand"
    ],
    programCell[
      "latexmk -pdf -interaction=nonstopmode -halt-on-error " <>
      "whitehead-field-dynamics-computational-notes.tex",
      "TeXCommand"
    ],
    programCell[
      "make computational-notes-notebook-check",
      "NotebookCheckCommand"
    ],
    textCell[
      "Run the final Mathematica cell after evaluating the notebook. Every " <>
      "entry in Checks should be True, and the first line should report " <>
      "AllTestsPassed -> True.",
      "SelfTestIntro"
    ],
    cellPair["complete mini-notebook self-test", "self-test"],

    noteCell["References", "Section", "SectionReferences"],
    textCell[
      "Laura Grave de Peralta and Alexander Kolpakov, Expansion properties " <>
      "of Whitehead moves on cubic graphs, Comptes Rendus Mathematique 362 " <>
      "(2024), 1825-1836. https://doi.org/10.5802/crmath.691",
      "ReferenceGDPK"
    ],
    textCell[
      "Michael Li, Increasingly Many Bounded Eigenvalues of the Graph of " <>
      "Whitehead Moves, arXiv:2405.14592. https://arxiv.org/abs/2405.14592",
      "ReferenceLi"
    ],
    captionCell[
      "Mathematical proofs remain in whitehead-field-dynamics.tex. The claim " <>
      "ledger remains in docs/status.rst.",
      "ClosingBoundary"
    ]
  },
  1
];

notebook = Notebook[
  cells,
  WindowTitle -> "Whitehead Field Dynamics — Computational Notes",
  StyleDefinitions -> "Default.nb",
  CellContext -> Notebook,
  InitializationCellEvaluation -> False,
  ShowCellLabel -> False,
  Saveable -> True,
  WindowSize -> {1040, 900},
  PrintingOptions -> {"PrintCellBrackets" -> False},
  TaggingRules -> <|
    "GoGComputationalNotes" -> <|
      "Edition" -> "ExecutableMiniNotebook",
      "SchemaVersion" -> 1,
      "Source" -> "whitehead-field-dynamics-computational-notes.tex",
      "SelfTestExpected" -> True
    |>
  |>,
  ExpressionUUID -> uuidFromSeed["NotebookRoot"]
];

inputCount = Count[notebook, Cell[_, "Input", ___], Infinity];
outputCount = Count[notebook, Cell[_, "Output", ___], Infinity];
sectionCount = Count[notebook, Cell[_, "Section", ___], Infinity];
If[inputCount =!= Length[code],
  fail["expected " <> ToString[Length[code]] <> " input cells"]
];
If[outputCount =!= Length[code],
  fail["every input cell must have a committed expected output"]
];
If[sectionCount < 9 || sectionCount > 12,
  fail["unexpected section count: " <> ToString[sectionCount]]
];
If[! FreeQ[notebook, $Failed], fail["a failed result entered the notebook"]];

$uuidPattern = RegularExpression[
  "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-" <>
  "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
];

normalizeSerializedUUIDs[file_String] := Module[
  {input, bytes, serialized, existing, replacements, association, normalized,
    output},
  input = Quiet[Check[OpenRead[file, BinaryFormat -> True], $Failed]];
  If[Head[input] =!= InputStream, fail["could not reopen serialized notebook"]];
  bytes = BinaryReadList[input, "Byte"];
  Close[input];
  serialized = FromCharacterCode[bytes, "UTF-8"];
  existing = DeleteDuplicates[StringCases[serialized, $uuidPattern]];
  replacements = MapIndexed[#1 -> uuidFromSeed[First[#2]] &, existing];
  association = Association[replacements];
  normalized = StringReplace[
    serialized,
    value : $uuidPattern :> Lookup[association, value]
  ];
  output = OpenWrite[file, BinaryFormat -> True];
  BinaryWrite[output, ToCharacterCode[normalized, "UTF-8"], "Byte"];
  Close[output];
  Length[existing]
];

progress["saving through the Mathematica front end"];
saved = Quiet @ Check[
  UsingFrontEnd[
    notebookObject = NotebookPut[notebook];
    NotebookSave[notebookObject, notebookFile];
    NotebookClose[notebookObject];
    notebookFile
  ],
  $Failed
];
If[saved =!= notebookFile || ! FileExistsQ[notebookFile],
  fail["the front end did not save the notebook"]
];

uuidCount = normalizeSerializedUUIDs[notebookFile];
hash = FileHash[notebookFile, "SHA256", "HexString"];

Print @ <|
  "Notebook" -> notebookFile,
  "WolframVersion" -> $Version,
  "Cells" -> Count[notebook, _Cell, Infinity],
  "Sections" -> sectionCount,
  "InputCells" -> inputCount,
  "ExpectedOutputs" -> outputCount,
  "SelfTestPassed" -> results["self-test"]["AllTestsPassed"],
  "DeterministicUUIDs" -> uuidCount,
  "NotebookSHA256" -> hash
|>;

Exit[0];
