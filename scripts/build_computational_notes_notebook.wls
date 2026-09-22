#!/usr/bin/env wolframscript

(* Build the executable computational notebook. *)

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
  fail["local package not found: " <> paperPacletDirectory]
];

Quiet @ Check[
  PacletDirectoryLoad[paperPacletDirectory];
  Needs["GogFieldDynamics`"],
  fail["the repo-local GogFieldDynamics package could not be loaded"]
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
  \"PackageLoaded\" -> NameQ[\"GogFieldDynamics`GogAvailableSizes\"]
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
<|
  \"Symmetric\" -> SymmetricMatrixQ[a],
  \"Idempotent\" -> (a . a === a),
  \"Preserves constant fields\" ->
    (a . ConstantArray[1, 4] === ConstantArray[1, 4])
|>";

code["resource-summary"] = "modelRows = Table[
  With[{m = GogSmallModel[n]},
    {n, m[\"NodeCount\"], m[\"EdgeCount\"],
     m[\"RuleASlotCount\"]}
  ],
  {n, GogAvailableSizes[]}
];
Grid[
  Prepend[
    modelRows,
    {\"N\", \"Graph types\", \"GoG edges\", \"Rule A outcomes\"}
  ],
  Frame -> All,
  Alignment -> Right
]";

code["validation"] = "r = GogValidateSmallModels[];
<|
  \"All bundled models valid\" -> r[\"Valid\"],
  \"Checks by N\" -> AssociationMap[
    r[\"Models\", #][\"Valid\"] &,
    GogAvailableSizes[]
  ]
|>";

code["class-atlas"] = "classAtlas = GogClassAtlas[4]";

code["class-explorer"] =
  "classExplorer = GogClassExplorer[\"InitialSize\" -> 8]";

code["rule-a-counts"] = "countsA = GogTransitionCounts[4, \"A\"];
Column[
  {
    MatrixForm[countsA],
    Row[{\"Row sums: \", Total /@ countsA}]
  },
  Spacings -> 0.5
]";

code["rule-a-stationary"] = "pA = GogTransitionMatrix[4, \"A\"];
piA = First[
  NullSpace[Transpose[pA] - IdentityMatrix[Length[pA]]]
];
stationaryA = piA/Total[piA];
Grid[
  Prepend[
    MapIndexed[{\"G\" <> ToString[First[#2]], #1} &, stationaryA],
    {\"Graph type\", \"Stationary probability\"}
  ],
  Frame -> All,
  Alignment -> Right
]";

code["rule-b-matrix"] = "pB = GogTransitionMatrix[4, \"B\"];
MatrixForm[pB]";

code["rule-b-spectrum"] = "eigenvaluesB = Sort[Eigenvalues[pB], Greater];
<|
  \"Eigenvalues of Rule B\" -> eigenvaluesB,
  \"Spectral gap\" -> FullSimplify[1 - eigenvaluesB[[2]]]
|>";

code["symmetry-stationarity"] = "u = ConstantArray[1/5, 5];
<|
  \"Symmetric matrix\" -> SymmetricMatrixQ[pB],
  \"Uniform distribution after one step\" -> (u . pB)
|>";

code["b-versus-jump"] = "Column[
  {
    Style[\"Rule B\", Bold],
    MatrixForm[GogTransitionMatrix[2, \"B\"]],
    Style[\"Jump chain obtained after removing holds\", Bold],
    MatrixForm[GogTransitionMatrix[2, \"BJump\"]]
  },
  Spacings -> 0.4
]";

code["diffusion-a"] = "p4A = GogDiffusionState[4, \"A\", 1, 4];
Grid[
  Prepend[
    MapIndexed[
      {\"G\" <> ToString[First[#2]], #1, N[#1, 5]} &,
      p4A
    ],
    {\"Graph type\", \"Exact probability\", \"Decimal\"}
  ],
  Frame -> All,
  Alignment -> Right
]";

code["diffusion-b"] = "p4B = GogDiffusionState[4, \"B\", 1, 4];
Grid[
  Prepend[
    MapIndexed[
      {\"G\" <> ToString[First[#2]], #1, N[#1, 5]} &,
      p4B
    ],
    {\"Graph type\", \"Exact probability\", \"Decimal\"}
  ],
  Frame -> All,
  Alignment -> Right
]";

code["diffusion-picture"] =
  "diffusionPicture = GogDiffusionSnapshot[
  8, \"A\", 1, 12, 273, \"PathSteps\" -> 48
]";

code["seeded-path"] = "samplePath =
  GogRandomTrajectory[8, \"A\", 1, 48, 273];
pathRows = MapIndexed[
  {First[#2] - 1, \"G\" <> ToString[#1]} &,
  samplePath
];
pathBlocks = Table[
  PadRight[
    Take[pathRows, {start, Min[start + 12, Length[pathRows]]}],
    13,
    {{\"\", \"\"}}
  ],
  {start, {1, 14, 27, 40}}
];
Column[
  {
    <|
      \"Transitions\" -> Length[samplePath] - 1,
      \"Distinct graph types visited\" ->
        Length[DeleteDuplicates[samplePath]],
      \"Holding steps\" ->
        Count[Partition[samplePath, 2, 1], {x_, x_}]
    |>,
    Grid[
      Prepend[
        MapThread[Join, pathBlocks],
        Flatten[ConstantArray[{\"t\", \"state\"}, 4]]
      ],
      Frame -> All,
      Alignment -> Right
    ]
  },
  Spacings -> 0.5
]";

code["matching-products"] = "matching[n_, edges_] :=
  Dot @@ (pairAverage[n, #] & /@ edges);

k4Product =
  matching[4, {{1, 3}, {2, 4}}] .
  matching[4, {{1, 2}, {3, 4}}];

q3Product =
  matching[8, {{1, 5}, {2, 6}, {3, 7}, {4, 8}}] .
  matching[8, {{1, 3}, {2, 4}, {5, 7}, {6, 8}}] .
  matching[8, {{1, 2}, {3, 4}, {5, 6}, {7, 8}}];

<|
  \"K4 reaches exact consensus\" ->
    (k4Product === ConstantArray[1/4, {4, 4}]),
  \"Q3 reaches exact consensus\" ->
    (q3Product === ConstantArray[1/8, {8, 8}])
|>";

code["k4-product"] = "k4Product // MatrixForm";

code["internal-checks"] = "notebookBuildChecks = <|
  \"PackageLoaded\" ->
    NameQ[\"GogFieldDynamics`GogSmallModel\"],
  \"AvailableSizes\" ->
    (GogAvailableSizes[] === {2, 4, 6, 8}),
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
  \"ClassPictures\" ->
    (MatchQ[classAtlas, _Column] &&
      MatchQ[classExplorer, _DynamicModule]),
  \"DiffusionPicture\" ->
    MatchQ[diffusionPicture, _Column],
  \"SeededTrajectory\" ->
    (GogRandomTrajectory[8, \"A\", 1, 48, 273] ===
      {1, 28, 24, 29, 29, 9, 54, 9, 54, 54, 34, 54, 25, 54,
       52, 20, 27, 20, 61, 61, 71, 69, 63, 63, 61, 61, 63, 36,
       37, 66, 37, 49, 64, 64, 64, 64, 64, 49, 49, 49, 45, 26,
       26, 26, 58, 51, 53, 55, 48}),
  \"FiniteConsensus\" ->
    (k4Product === ConstantArray[1/4, {4, 4}] &&
      q3Product === ConstantArray[1/8, {8, 8}])
|>;
<|
  \"ChecksPassed\" -> And @@ Values[notebookBuildChecks],
  \"Checks\" -> notebookBuildChecks
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
If[! TrueQ[results["internal-checks"]["ChecksPassed"]],
  fail["the internal notebook checks did not pass"]
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

numberedCell[text_String, id_String] := noteCell[
  text,
  "ItemNumbered",
  id,
  FontSize -> 12
];

formulaBoxCell[boxes_, id_String] := noteCell[
  BoxData[FormBox[boxes, TraditionalForm]],
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

cellHeading[topic_String, id_String] := With[
  {label = ToUpperCase[StringTake[topic, 1]] <> StringDrop[topic, 1]},
  noteCell[
    TextData[{
      StyleBox[label, FontWeight -> "Bold", FontColor -> $navy]
    }],
    "Text",
    id <> "Heading",
    ShowCellBracket -> False,
    CellMargins -> {{48, 48}, {14, 4}},
    TextAlignment -> Left,
    FontSize -> 11
  ]
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

cells = Flatten[
  {
    noteCell[
      "Whitehead Field Dynamics",
      "Title",
      "Title",
      TextAlignment -> Left,
      FontColor -> $navy,
      FontSize -> 28,
      CellMargins -> {{48, 48}, {24, 5}}
    ],
    noteCell[
      "Computational notes",
      "Subtitle",
      "Subtitle",
      TextAlignment -> Left,
      FontColor -> $muted,
      FontSize -> 16,
      CellMargins -> {{48, 48}, {2, 8}}
    ],
    noteCell[
      "Alexander Kolpakov  ·  September 2026",
      "Text",
      "Byline",
      TextAlignment -> Left,
      FontColor -> $muted,
      FontSize -> 10,
      CellMargins -> {{48, 48}, {2, 18}}
    ],
    textCell[
      "This notebook accompanies whitehead-field-dynamics-computational-" <>
      "notes.tex. It contains the exact calculations used in that note, " <>
      "together with drawings of the graph-of-graphs models, an interactive " <>
      "view of the cubic multigraph represented by each state, and an exact " <>
      "71-state diffusion calculation. Proofs remain in the full LaTeX " <>
      "manuscript.",
      "Abstract"
    ],

    noteCell["Start here", "Section", "SectionSetup"],
    textCell[
      "Keep this file in the repository root and choose Evaluation > Evaluate " <>
      "Notebook. The first cell loads the local GogFieldDynamics package; no " <>
      "global installation is needed. SetReplace is optional.",
      "SetupGuide"
    ],
    cellPair["load the companion package", "setup", True],

    noteCell["What is being computed", "Section", "SectionObjects"],
    textCell[
      "A cubic multigraph is a graph in which every vertex has degree three; " <>
      "loops count twice toward the degree, and parallel edges are allowed. " <>
      "A graph type is an isomorphism class obtained after vertex labels are " <>
      "forgotten. The graph of graphs (GoG) has one vertex for each connected " <>
      "graph type and joins two types when one Whitehead move relates them. " <>
      "Such a move selects a carrier edge, meaning a specific edge in a chosen " <>
      "representative, collapses it, and chooses one of the two other pairings " <>
      "of the four exposed half-edges. A field f in R^N travels with the graph; " <>
      "on a carrier with endpoints i and j, those values are replaced by their " <>
      "common mean.",
      "ObjectsIntro"
    ],
    formulaBoxCell[
      RowBox[{
        RowBox[{
          "(",
          SubscriptBox["f", "i"],
          ",",
          SubscriptBox["f", "j"],
          ")"
        }],
        "\[LongRightArrow]",
        RowBox[{
          "(",
          FractionBox[
            RowBox[{SubscriptBox["f", "i"], "+", SubscriptBox["f", "j"]}],
            "2"
          ],
          ",",
          FractionBox[
            RowBox[{SubscriptBox["f", "i"], "+", SubscriptBox["f", "j"]}],
            "2"
          ],
          ")"
        }]
      }],
      "FieldUpdateFormula"
    ],
    textCell[
      "Three computational objects must be kept separate.",
      "ObjectsListIntro"
    ],
    numberedCell[
      "The carrier field uses the concrete selected edge. After an unlabelled " <>
      "move, a settlement permutation is the relabelling that identifies the " <>
      "result with the stored representative of its graph type; the same " <>
      "permutation is applied to the field coordinates.",
      "ObjectCarrier"
    ],
    numberedCell[
      "Rule A keeps every local outcome slot after labels are forgotten. A " <>
      "cubic graph has 3N/2 edges and two resolutions per edge, hence 3N slots. " <>
      "Different slots leading to the same type retain their multiplicity. A " <>
      "slot returning to the current type is a holding event.",
      "ObjectRuleA"
    ],
    numberedCell[
      "Rule B gives one of the 3N equally weighted slots to each different " <>
      "adjacent graph type and assigns every unused slot to staying put. Its " <>
      "jump chain, called BJump in the code, is the conditional chain given " <>
      "that the graph type changes; removing the holds changes path " <>
      "probabilities and elapsed time.",
      "ObjectRuleB"
    ],
    textCell[
      "The local package contains every graph type, every one-move connection, " <>
      "and the exact transition counts for N=2,4,6,8. The N=8 model already " <>
      "has 71 states; larger data sets can be generated separately.",
      "ObjectsBoundary"
    ],

    noteCell[
      "The graph of graphs",
      "Section",
      "SectionVisualMap"
    ],
    textCell[
      "A GoG vertex represents an entire graph type, not one vertex of the " <>
      "underlying cubic multigraph. The small N=4 atlas makes this distinction " <>
      "visible: its five GoG vertices are shown together with the five cubic " <>
      "multigraphs they represent.",
      "VisualMapIntro"
    ],
    cellPair[
      "N=4 graph of graphs",
      "class-atlas"
    ],
    captionCell[
      "The upper diagram shows the one-move connections among G1 through G5. " <>
      "The drawings below it show the cubic multigraph represented by each " <>
      "of those five vertices.",
      "ClassAtlasCaption"
    ],
    textCell[
      "The next output is live and opens on the 71-vertex N=8 model. Choose " <>
      "N=2, 4, 6, or 8, then click any GoG vertex. Hovering gives its G-number; " <>
      "the panel on the right redraws the cubic multigraph represented there.",
      "VisualMapBoundary"
    ],
    cellPair["inspect a graph type", "class-explorer"],
    captionCell[
      "The selected GoG vertex is orange; its underlying cubic multigraph " <>
      "appears on the right. Labels are suppressed on the 71-state view to " <>
      "keep the graph legible, but every vertex remains clickable.",
      "ClassExplorerCaption"
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
    formulaBoxCell[
      RowBox[{
        SubscriptBox["A", RowBox[{"i", "j"}]],
        "=",
        SubscriptBox["I", "N"],
        "-",
        FractionBox["1", "2"],
        RowBox[{"(", SubscriptBox["e", "i"], "-", SubscriptBox["e", "j"], ")"}],
        SuperscriptBox[
          RowBox[{"(", SubscriptBox["e", "i"], "-", SubscriptBox["e", "j"], ")"}],
          "T"
        ]
      }],
      "AverageMatrixFormula"
    ],
    textCell[
      "It is symmetric, idempotent, and fixes the all-ones vector. The " <>
      "two-coordinate energy calculation can be checked without constructing " <>
      "the whole matrix.",
      "AverageProperties"
    ],
    cellPair["energy lost by averaging one pair", "pair-loss"],
    textCell[
      "Write the mean as f-bar and the centered energy as V(f). Pair " <>
      "averaging preserves the mean and has an exact one-step loss.",
      "VarianceIntro"
    ],
    formulaBoxCell[
      GridBox[
        {
          {
            RowBox[{
              OverscriptBox["f", "_"],
              "=",
              FractionBox["1", "N"],
              UnderoverscriptBox["\[Sum]", RowBox[{"k", "=", "1"}], "N"],
              SubscriptBox["f", "k"]
            }]
          },
          {
            RowBox[{
              RowBox[{"V", "(", "f", ")"}],
              "=",
              UnderoverscriptBox["\[Sum]", RowBox[{"k", "=", "1"}], "N"],
              SuperscriptBox[
                RowBox[{"(", SubscriptBox["f", "k"], "-", OverscriptBox["f", "_"], ")"}],
                "2"
              ]
            }]
          },
          {
            RowBox[{
              RowBox[{
                "V",
                "(",
                SubscriptBox["A", RowBox[{"i", "j"}]],
                "f",
                ")"
              }],
              "=",
              RowBox[{"V", "(", "f", ")"}],
              "-",
              FractionBox[
                SuperscriptBox[
                  RowBox[{"(", SubscriptBox["f", "i"], "-", SubscriptBox["f", "j"], ")"}],
                  "2"
                ],
                "2"
              ]
            }]
          }
        },
        GridBoxAlignment -> {"Columns" -> {{Center}}},
        GridBoxSpacings -> {"Rows" -> {{0.7}}}
      ],
      "VarianceFormula"
    ],
    cellPair["the averaging matrix", "averaging-matrix"],
    textCell[
      "A settlement is a permutation matrix. It preserves sums and Euclidean " <>
      "norms, so it cannot change this one-step variance identity. It can " <>
      "change which persistent pair of field coordinates is averaged later. " <>
      "A list of unlabelled graph types therefore does not contain enough " <>
      "information to reconstruct the later field values.",
      "SettlementBoundary"
    ],

    noteCell[
      "Bundled models",
      "Section",
      "SectionModels"
    ],
    textCell[
      "For each bundled size, the table records the number of graph types, " <>
      "the number of GoG edges, and the number of Rule A outcomes.",
      "ModelsIntro"
    ],
    cellPair["available small models", "resource-summary"],
    textCell[
      "The class counts 2, 5, 17, and 71 agree with the corresponding terms " <>
      "of OEIS A005967. Multiplying each class count by the 3N possible Rule A " <>
      "outcomes gives the totals below.",
      "SlotCheckText"
    ],
    formulaBoxCell[
      GridBox[
        {
          {RowBox[{SubscriptBox["c", "2"], "\[CenterDot]", "6", "=", "12"}]},
          {RowBox[{SubscriptBox["c", "4"], "\[CenterDot]", "12", "=", "60"}]},
          {RowBox[{SubscriptBox["c", "6"], "\[CenterDot]", "18", "=", "306"}]},
          {RowBox[{SubscriptBox["c", "8"], "\[CenterDot]", "24", "=", "1704"}]}
        },
        GridBoxAlignment -> {"Columns" -> {{Center}}},
        GridBoxSpacings -> {"Rows" -> {{0.55}}}
      ],
      "SlotCountFormula"
    ],
    textCell[
      "The next cell checks that every bundled table is complete, that the " <>
      "node and outcome counts agree, and that every transition row sums to " <>
      "one. It also checks Rule-B symmetry and verifies that a uniform " <>
      "starting distribution remains uniform after one step.",
      "ValidationIntro"
    ],
    cellPair["check the bundled models", "validation"],

    noteCell["An exact five-state example", "Section", "SectionFiveState"],
    textCell[
      "At N=4 there are five unlabelled graph types, shown above. Rule A " <>
      "counts every local move outcome, including repeated outcomes that lead " <>
      "to the same graph type.",
      "FiveStateIntro"
    ],
    cellPair["Rule A move counts", "rule-a-counts"],
    textCell[
      "Every row sums to 3N=12. Dividing the count matrix by 12 gives the " <>
      "exact Rule-A transition matrix. It is not symmetric.",
      "RuleAMatrixText"
    ],
    formulaBoxCell[
      RowBox[{
        SubscriptBox["P", "A"],
        "=",
        FractionBox[SubscriptBox["C", "A"], RowBox[{"3", "N"}]]
      }],
      "RuleAMatrix"
    ],
    textCell[
      "A stationary distribution is a probability row vector pi satisfying " <>
      "pi P = pi. The left 1-eigenspace of P_A gives it exactly.",
      "StationaryIntro"
    ],
    cellPair["stationary distribution for Rule A", "rule-a-stationary"],
    textCell[
      "The distribution is nonuniform because graph types with different " <>
      "numbers of labelled realizations receive different weights. Treating " <>
      "Rule A as uniform on graph types would change the process.",
      "StationaryMeaning"
    ],
    textCell[
      "Rule B assigns weight 1/(3N) to each adjacent graph type and puts the " <>
      "unused probability on the diagonal. Its support graph keeps one edge " <>
      "whenever a nonself move is possible and discards all multiplicities; " <>
      "L_supp below is the Laplacian of that simple graph.",
      "RuleBIntro"
    ],
    formulaBoxCell[
      GridBox[
        {
          {
            RowBox[{
              RowBox[{SubscriptBox["P", "B"], "(", "g", ",", "h", ")"}],
              "=",
              FractionBox["1", RowBox[{"3", "N"}]],
              ",",
              RowBox[{"g", "\[Tilde]", "h"}],
              ",",
              RowBox[{"g", "\[NotEqual]", "h"}]
            }]
          },
          {
            RowBox[{
              RowBox[{SubscriptBox["P", "B"], "(", "g", ",", "g", ")"}],
              "=",
              "1",
              "-",
              FractionBox[RowBox[{"deg", "(", "g", ")"}], RowBox[{"3", "N"}]]
            }]
          },
          {
            RowBox[{
              "I",
              "-",
              SubscriptBox["P", "B"],
              "=",
              FractionBox[SubscriptBox["L", "supp"], RowBox[{"3", "N"}]]
            }]
          }
        },
        GridBoxAlignment -> {"Columns" -> {{Center}}},
        GridBoxSpacings -> {"Rows" -> {{0.7}}}
      ],
      "RuleBDefinition"
    ],
    cellPair["Rule B transition matrix", "rule-b-matrix"],
    textCell[
      "The defining symmetry and stationarity checks can be made directly. " <>
      "For this symmetric transition matrix, the spectral gap means one minus " <>
      "its second-largest eigenvalue.",
      "RuleBChecksIntro"
    ],
    cellPair[
      "symmetry and stationarity",
      "symmetry-stationarity"
    ],
    cellPair[
      "Rule B eigenvalues and spectral gap",
      "rule-b-spectrum"
    ],
    formulaBoxCell[
      RowBox[{
        "1",
        "-",
        RowBox[{
          SubscriptBox["\[Lambda]", "2"],
          "(",
          SubscriptBox["P", "B"],
          ")"
        }],
        "=",
        FractionBox[RowBox[{"3", "-", SqrtBox["5"]}], "24"]
      }],
      "RuleBGapFormula"
    ],
    textCell[
      "A holding step leaves the graph type unchanged but still consumes one " <>
      "step. Already at N=2, Rule B and its jump chain allow the same changes " <>
      "to other types, yet assign different path probabilities and have " <>
      "different spectra.",
      "JumpChainIntro"
    ],
    cellPair["Rule B versus its jump chain", "b-versus-jump"],

    noteCell[
      "Exact diffusion and a sampled path",
      "Section",
      "SectionDiffusion"
    ],
    textCell[
      "Here diffusion means the evolution of a probability distribution over " <>
      "graph types: p_t = p_0 P^t. We first start at G1 in the five-state N=4 " <>
      "model and apply Rule A four times so that every exact probability can " <>
      "be inspected directly.",
      "DiffusionIntro"
    ],
    formulaBoxCell[
      GridBox[
        {
          {
            RowBox[{
              SubscriptBox["p", "t"],
              "=",
              SuperscriptBox[SubscriptBox["e", RowBox[{"G", "1"}]], "T"],
              SuperscriptBox["P", "t"]
            }]
          },
          {
            RowBox[{
              SubscriptBox["p", RowBox[{"t", "+", "1"}]],
              "=",
              SubscriptBox["p", "t"],
              "P",
              ",",
              UnderscriptBox[
                "\[Sum]",
                RowBox[{
                  "g",
                  "\[Element]",
                  SubscriptBox["\[ScriptCapitalG]", "4"]
                }]
              ],
              RowBox[{SubscriptBox["p", "t"], "(", "g", ")"}],
              "=",
              "1"
            }]
          }
        },
        GridBoxAlignment -> {"Columns" -> {{Center}}},
        GridBoxSpacings -> {"Rows" -> {{0.7}}}
      ],
      "DiffusionFormula"
    ],
    cellPair["Rule A after four steps", "diffusion-a"],
    textCell[
      "All five classes are reachable by time four, but the mass is far from " <>
      "the stationary vector. From the same starting point, Rule B retains " <>
      "much more probability at G1 because it more often stays in place.",
      "DiffusionComparisonIntro"
    ],
    cellPair["Rule B after four steps", "diffusion-b"],
    textCell[
      "These distributions live on graph types. Transporting a scalar field " <>
      "under Rule B additionally requires a rule for choosing the actual " <>
      "carrier edge to average. The next calculation moves to the complete " <>
      "N=8 GoG: blue encodes the exact 71-state distribution at t=12, while " <>
      "orange traces a separate 48-step sample.",
      "DiffusionBoundary"
    ],
    cellPair[
      "N=8 diffusion and a 48-step sample",
      "diffusion-picture"
    ],
    cellPair["path data used in the picture", "seeded-path"],
    captionCell[
      "The path visits 27 different graph types. Its 13 repeated consecutive " <>
      "labels are holding steps, and the fixed seed makes the sample " <>
      "reproducible.",
      "PathCaption"
    ],

    noteCell["Finite-time consensus", "Section", "SectionConsensus"],
    textCell[
      "Consensus means that every field coordinate equals the arithmetic mean " <>
      "of the initial field. Finite-time consensus means this happens after a " <>
      "finite product of pair-averaging matrices, equivalently that the product " <>
      "equals J_N. A perfect matching is a set of disjoint pairs covering all " <>
      "N coordinates. For such a matching, M denotes the product of its " <>
      "commuting pair averages; successive products act from right to left.",
      "ConsensusIntro"
    ],
    formulaBoxCell[
      GridBox[
        {
          {
            RowBox[{
              SubscriptBox["J", "N"],
              "=",
              FractionBox["1", "N"],
              SubscriptBox[StyleBox["1", FontWeight -> "Bold"], "N"],
              SuperscriptBox[
                SubscriptBox[StyleBox["1", FontWeight -> "Bold"], "N"],
                "T"
              ]
            }]
          },
          {
            RowBox[{
              SubscriptBox["J", "N"],
              "f",
              "=",
              OverscriptBox["f", "_"],
              SubscriptBox[StyleBox["1", FontWeight -> "Bold"], "N"]
            }]
          },
          {
            RowBox[{
              SubscriptBox["M", RowBox[{"13", "|", "24"}]],
              "=",
              SubscriptBox["A", "13"],
              SubscriptBox["A", "24"]
            }]
          },
          {
            RowBox[{
              SubscriptBox["M", RowBox[{"13", "|", "24"}]],
              SubscriptBox["M", RowBox[{"12", "|", "34"}]],
              "=",
              SubscriptBox["J", "4"]
            }]
          },
          {
            RowBox[{
              SubscriptBox["M", RowBox[{"15", "|", "26", "|", "37", "|", "48"}]],
              SubscriptBox["M", RowBox[{"13", "|", "24", "|", "57", "|", "68"}]],
              SubscriptBox["M", RowBox[{"12", "|", "34", "|", "56", "|", "78"}]],
              "=",
              SubscriptBox["J", "8"]
            }]
          }
        },
        GridBoxAlignment -> {"Columns" -> {{Center}}},
        GridBoxSpacings -> {"Rows" -> {{0.75}}}
      ],
      "ConsensusFormula"
    ],
    cellPair["verify the consensus products", "matching-products"],
    textCell[
      "For example, the K4 product is returned exactly as the consensus matrix.",
      "K4Intro"
    ],
    cellPair["the K4 product", "k4-product"],
    textCell[
      "Every initial field therefore reaches its exact mean after the stated " <>
      "schedule. This exceptional finite-time consensus should not be " <>
      "extrapolated to arbitrary N. Every entry of a finite product of pair " <>
      "averages has denominator a power of two, whereas the mean of (0,0,1) " <>
      "requires a factor 1/3.",
      "ConsensusBoundary"
    ],

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
      "Proofs are in whitehead-field-dynamics.tex.",
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
      "Edition" -> "ComputationalNotes",
      "SchemaVersion" -> 1,
      "Source" -> "whitehead-field-dynamics-computational-notes.tex"
    |>
  |>,
  ExpressionUUID -> uuidFromSeed["NotebookRoot"]
];

inputCount = Count[notebook, Cell[_, "Input", ___], Infinity];
outputCount = Count[notebook, Cell[_, "Output", ___], Infinity];
sectionCount = Count[notebook, Cell[_, "Section", ___], Infinity];
If[inputCount =!= Length[code] - 1,
  fail["expected " <> ToString[Length[code] - 1] <> " input cells"]
];
If[outputCount =!= Length[code] - 1,
  fail["every input cell must have a committed expected output"]
];
If[sectionCount =!= 9,
  fail["unexpected section count: " <> ToString[sectionCount]]
];
If[
  AnyTrue[Values[results], SameQ[#, $Failed] &],
  fail["a failed result entered the notebook"]
];

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

progress["saving the portable Notebook expression"];
saved = Quiet @ Check[
  Put[notebook, notebookFile];
  notebookFile,
  $Failed
];
If[saved =!= notebookFile || ! FileExistsQ[notebookFile],
  fail["the kernel did not save the notebook expression"]
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
  "InternalChecksPassed" -> results["internal-checks"]["ChecksPassed"],
  "DeterministicUUIDs" -> uuidCount,
  "NotebookSHA256" -> hash
|>;

Exit[0];
