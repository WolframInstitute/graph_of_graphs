(* ::Package:: *)

BeginPackage["GogFieldDynamics`"];

GogDiffusionExplorer::usage =
  "GogDiffusionExplorer[] creates an interactive small-model laboratory for " <>
  "exact graph-of-graphs diffusion and sampled SetReplace trajectories.";

Begin["`Private`"];

$labNavy = RGBColor[0.075, 0.13, 0.22];
$labBlue = RGBColor[0.00, 0.45, 0.70];
$labSky = RGBColor[0.34, 0.71, 0.91];
$labGreen = RGBColor[0.00, 0.62, 0.45];
$labOrange = RGBColor[0.90, 0.62, 0.00];
$labPurple = RGBColor[0.57, 0.38, 0.74];
$labMuted = RGBColor[0.37, 0.42, 0.49];
$labLine = RGBColor[0.82, 0.85, 0.88];
$labWash = RGBColor[0.965, 0.975, 0.985];

labLabel[index_Integer] := "G" <> ToString[index];

labCoordinates[2] := {{-1.15, 0}, {1.15, 0}};
labCoordinates[4] := {
  {-0.80, 0.45}, {-1.60, -0.50}, {0.00, 0.00},
  {1.60, -0.40}, {0.80, 0.50}
};
labCoordinates[n_Integer] := labCoordinates[n] = Module[
  {model = GogSmallModel[n], graph, points, centered, scale},
  graph = Graph[
    Range[model["NodeCount"]],
    UndirectedEdge @@@ model["Edges"],
    GraphLayout -> "SpringElectricalEmbedding"
  ];
  points = N[GraphEmbedding[graph]];
  centered = (# - Mean[points]) & /@ points;
  scale = Max[Norm /@ centered];
  If[! NumericQ[scale] || scale == 0, scale = 1.];
  ({1.72, 1.34} #/scale) & /@ centered
];

labProbabilityColor[mass_, maximum_] := Blend[
  {$labWash, $labSky, $labBlue},
  Clip[If[maximum > 0, Sqrt[N[mass/maximum]], 0], {0, 1}]
];

labGraph[
  n_Integer,
  rule_String,
  probability_List,
  path_List,
  step_Integer
] := Module[
  {model = GogSmallModel[n], matrix, coordinates, edges, size, maximum,
    sampled, previous, prefixPairs, visitedPairs, activePair, baseRadius,
    edgeLayer, trailLayer, activeLayer, nodeLayer},
  matrix = GogTransitionMatrix[n, rule];
  coordinates = labCoordinates[n];
  edges = model["Edges"];
  size = model["NodeCount"];
  maximum = Max[probability];
  sampled = path[[Min[step + 1, Length[path]]]];
  previous = If[step > 0, path[[Min[step, Length[path]]]], sampled];
  prefixPairs = If[
    step > 0,
    Partition[Take[path, Min[step + 1, Length[path]]], 2, 1],
    {}
  ];
  visitedPairs = DeleteDuplicates[Sort /@ Select[prefixPairs, Unequal @@ # &]];
  activePair = If[previous =!= sampled, Sort[{previous, sampled}], None];
  baseRadius = If[size <= 5, 0.17, 0.105];

  edgeLayer = {
    Directive[$labLine, AbsoluteThickness[1.5]],
    Line[coordinates[[#]]] & /@ edges
  };
  trailLayer = {
    Directive[$labOrange, Opacity[0.42], AbsoluteThickness[3]],
    Line[coordinates[[#]]] & /@ visitedPairs
  };
  activeLayer = If[
    ListQ[activePair],
    {Directive[$labOrange, AbsoluteThickness[4.5]],
      Line[coordinates[[activePair]]]},
    {}
  ];
  nodeLayer = Table[
    With[
      {mass = probability[[index]], hold = matrix[[index, index]],
        code = model["Nodes"][[index]], point = coordinates[[index]],
        radius = baseRadius (0.78 + 0.42 Sqrt[N[probability[[index]]/maximum]]),
        selected = index === sampled},
      Tooltip[
        {
          If[
            selected,
            {Directive[$labOrange, AbsoluteThickness[3]],
              Circle[point, radius 1.22]},
            Nothing
          ],
          EdgeForm[Directive[$labLine, AbsoluteThickness[1.6]]],
          labProbabilityColor[mass, maximum],
          Disk[point, radius],
          Text[
            Style[
              labLabel[index],
              If[size <= 5, 9, 6.5],
              Bold,
              If[N[mass/maximum] > 0.34, White, $labNavy],
              FontFamily -> "Helvetica"
            ],
            point
          ]
        },
        Grid[
          {
            {Style["class", Bold], labLabel[index]},
            {"exact mass", NumberForm[N[mass], {4, 3}]},
            {"holding probability", NumberForm[N[hold], {4, 3}]},
            {"canonical code", Style[code, 8, FontFamily -> "Courier"]}
          },
          Alignment -> Left,
          Spacings -> {0.8, 0.35}
        ]
      ]
    ],
    {index, size}
  ];

  Graphics[
    {edgeLayer, trailLayer, activeLayer, nodeLayer},
    PlotRange -> {{-2.05, 2.05}, {-1.62, 1.62}},
    PlotRangePadding -> Scaled[0.03],
    ImageSize -> {248, 190},
    Background -> White
  ]
];

labMassBars[probability_List] := Module[
  {indices, maximum, count, rows},
  count = Min[5, Length[probability]];
  indices = TakeLargestBy[Range[Length[probability]], probability[[#]] &, count];
  maximum = Max[probability[[indices]]];
  rows = MapIndexed[
    Function[{index, position},
      With[
        {y = count - First[position] + 1, mass = probability[[index]],
          width = If[maximum > 0, N[probability[[index]]/maximum], 0]},
        {
          Text[
            Style[labLabel[index], 8, Bold, $labNavy,
              FontFamily -> "Helvetica"],
            {-0.05, y},
            {1, 0}
          ],
          {$labWash, Rectangle[{0, y - 0.22}, {1, y + 0.22}]},
          {labProbabilityColor[mass, maximum],
            Rectangle[{0, y - 0.22}, {width, y + 0.22}]},
          Text[
            Style[ToString[NumberForm[N[mass], {3, 2}]], 8, $labMuted,
              FontFamily -> "Helvetica"],
            {1.06, y},
            {-1, 0}
          ]
        }
      ]
    ],
    indices
  ];
  Graphics[
    rows,
    PlotRange -> {{-0.33, 1.34}, {0.45, count + 0.55}},
    ImageSize -> {116, 105},
    Background -> White
  ]
];

labMetric[label_String, value_, color_] := Framed[
  Column[
    {
      Style[label, 6.5, Bold, $labMuted, FontFamily -> "Helvetica"],
      Style[value, 9, Bold, color, FontFamily -> "Helvetica"]
    },
    Alignment -> Left,
    Spacings -> 0.1
  ],
  Background -> Blend[{White, color}, 0.06],
  FrameStyle -> Directive[Opacity[0.28], color],
  FrameMargins -> {{6, 6}, {4, 4}},
  ImageSize -> {56, 39}
];

labPathRibbon[path_List, step_Integer] := Module[
  {prefix, visible, labels},
  prefix = Take[path, Min[step + 1, Length[path]]];
  visible = Take[prefix, -Min[7, Length[prefix]]];
  labels = labLabel /@ visible;
  If[Length[prefix] > Length[visible], labels = Prepend[labels, "…"]];
  Row[
    Riffle[
      Style[#, 8, Bold, $labNavy, FontFamily -> "Helvetica"] & /@ labels,
      Style["  →  ", 9, Bold, $labOrange]
    ]
  ]
];

labEngineLabel[trajectory_Association] := Module[
  {engine = Lookup[trajectory, "Engine", "unknown"], version},
  version = Lookup[trajectory, "SetReplaceVersion", Missing[]];
  If[
    engine === "SetReplace" && StringQ[version],
    "SETREPLACE " <> version <> " PATH",
    ToUpperCase[engine] <> " PATH"
  ]
];

labPanel[
  n_Integer,
  rule_String,
  start_Integer,
  step_Integer,
  trajectory_Association
] := Module[
  {model = GogSmallModel[n], probability, matrix, path, expectedHold,
    sampled, ruleText},
  probability = GogDiffusionState[n, rule, start, step];
  matrix = GogTransitionMatrix[n, rule];
  path = trajectory["States"];
  sampled = path[[Min[step + 1, Length[path]]]];
  expectedHold = N[probability . Diagonal[matrix]];
  ruleText = If[
    rule === "A",
    "resolution slots · multiplicity · holding retained",
    "one tick per distinct target · unused ticks hold · uniform class law"
  ];

  Framed[
    Column[
      {
        Row[
          {
            Style["EXACT DIFFUSION", 7.5, Bold, $labBlue,
              FontFamily -> "Helvetica"],
            Spacer[12],
            Graphics[{$labBlue, Disk[]}, ImageSize -> 8],
            Style[" node fill = probability mass", 7.5, $labMuted,
              FontFamily -> "Helvetica"],
            Spacer[14],
            Graphics[
              {Directive[$labOrange, AbsoluteThickness[2]], Circle[]},
              ImageSize -> 8
            ],
            Style[" ring + trail = one sampled path", 7.5, $labMuted,
              FontFamily -> "Helvetica"]
          }
        ],
        Grid[
          {{
            labGraph[n, rule, probability, path, step],
            Column[
              {
                Style["LARGEST EXACT MASSES", 7, Bold, $labMuted,
                  FontFamily -> "Helvetica"],
                labMassBars[probability],
                Grid[
                  {{
                    labMetric["TIME", "t = " <> ToString[step], $labBlue],
                    labMetric["SAMPLE", labLabel[sampled], $labOrange]
                  }, {
                    labMetric[
                      "REACH",
                      ToString[Count[probability, _?Positive]] <> "/" <>
                        ToString[model["NodeCount"]],
                      $labGreen
                    ],
                    labMetric[
                      "HOLD",
                      ToString[NumberForm[expectedHold, {3, 2}]],
                      $labPurple
                    ]
                  }},
                  Spacings -> {0.25, 0.25}
                ]
              },
              Alignment -> Center,
              Spacings -> 0.35
            ]
          }},
          Alignment -> Center,
          Spacings -> {0.35, 0}
        ],
        Framed[
          Grid[
            {{
              Style[labEngineLabel[trajectory], 7, Bold, $labOrange,
                FontFamily -> "Helvetica"],
              labPathRibbon[path, step]
            }},
            Alignment -> {{Left, Center}},
            ItemSize -> {{10, 27}},
            Spacings -> {0.5, 0}
          ],
          Background -> Blend[{White, $labOrange}, 0.06],
          FrameStyle -> None,
          FrameMargins -> {{8, 8}, {4, 4}}
        ],
        Style[ruleText, 7.5, $labMuted, FontFamily -> "Helvetica"]
      },
      Alignment -> Center,
      Spacings -> 0.42
    ],
    Background -> White,
    FrameStyle -> Directive[$labLine],
    FrameMargins -> {{8, 8}, {7, 7}}
  ]
];

labControlLabel[text_String] := Style[
  text,
  7,
  Bold,
  $labMuted,
  FontFamily -> "Helvetica"
];

Options[GogDiffusionExplorer] = {
  "InitialSize" -> 4,
  "InitialRule" -> "A",
  "MaximumSteps" -> 12,
  "Seed" -> 2026
};

GogDiffusionExplorer[OptionsPattern[]] := Module[
  {validation = GogValidateSmallModels[]},
  If[FailureQ[validation] || ! TrueQ[validation["Valid"]], Return[validation]];
  DynamicModule[
  {n = OptionValue["InitialSize"], rule = OptionValue["InitialRule"],
    start = 1, step = 4, seed = OptionValue["Seed"],
    maximumSteps = OptionValue["MaximumSteps"], signature = None,
    trajectory = <||>, queuedSample = None, pathMethod = "Native"},
  Framed[
    Column[
      {
        Row[
          {
            Column[
              {
                Style[
                  "GRAPH-OF-GRAPHS DIFFUSION LAB",
                  13,
                  Bold,
                  $labNavy,
                  FontFamily -> "Helvetica"
                ],
                Style[
                  "exact quotient law + executable singleton-hypergraph path",
                  8,
                  $labMuted,
                  FontFamily -> "Helvetica"
                ]
              },
              Spacings -> 0.08
            ],
            Spacer[15],
            Framed[
              Style["NATIVE WOLFRAM LAB", 7, Bold, White,
                FontFamily -> "Helvetica"],
              Background -> $labBlue,
              FrameStyle -> None,
              FrameMargins -> {{7, 7}, {3, 3}}
            ]
          },
          Alignment -> Center
        ],
        Framed[
          Grid[
            {
              {
                labControlLabel["CARRIER SIZE"],
                SetterBar[
                  Dynamic[n, (n = #; start = 1; step = 0; signature = None) &],
                  {2 -> "N=2", 4 -> "N=4", 6 -> "N=6"}
                ],
                labControlLabel["CHAIN"],
                SetterBar[
                  Dynamic[rule, (rule = #; step = 0; signature = None) &],
                  {"A" -> "Rule A", "B" -> "Rule B · fixed clock"}
                ]
              },
              {
                labControlLabel["START CLASS"],
                Dynamic[
                  PopupMenu[
                    Dynamic[start, (start = #; step = 0; signature = None) &],
                    Thread[
                      Range[GogSmallModel[n]["NodeCount"]] ->
                        (labLabel /@ Range[GogSmallModel[n]["NodeCount"]])
                    ]
                  ],
                  TrackedSymbols :> {n}
                ],
                labControlLabel["PATH SEED"],
                InputField[
                  Dynamic[seed, If[IntegerQ[#], seed = #; signature = None] &],
                  Number,
                  FieldSize -> 5
                ]
              },
              {
                labControlLabel["PATH ENGINE"],
                PopupMenu[
                  Dynamic[pathMethod],
                  {"Native" -> "native", "SetReplace" -> "SetReplace"}
                ],
                Button[
                  "sample path",
                  seed++;
                  queuedSample = GogTrajectory[
                    n,
                    rule,
                    start,
                    maximumSteps,
                    seed,
                    Method -> pathMethod
                  ];
                  If[AssociationQ[queuedSample],
                    trajectory = queuedSample;
                    signature = {n, rule, start, seed};
                  ],
                  Appearance -> "Frameless",
                  BaseStyle -> {8, Bold, $labOrange},
                  Method -> "Queued"
                ],
                SpanFromLeft
              },
              {
                labControlLabel["DIFFUSION TIME"],
                Animator[
                  Dynamic[step],
                  {0, maximumSteps, 1},
                  AnimationRate -> 1,
                  AnimationRepetitions -> Infinity,
                  AnimationRunning -> False,
                  AppearanceElements -> {
                    "PlayPauseButton", "FasterSlowerButtons", "ProgressSlider"
                  },
                  ImageSize -> 205
                ],
                SpanFromLeft,
                Button[
                  "reset",
                  step = 0,
                  Appearance -> "Frameless",
                  BaseStyle -> {8, Bold, $labBlue}
                ]
              }
            },
            Alignment -> {{Right, Left, Right, Left}, Center},
            Spacings -> {0.3, 0.4}
          ],
          Background -> $labWash,
          FrameStyle -> None,
          FrameMargins -> {{8, 8}, {6, 6}}
        ],
        Dynamic[
          Module[{newSignature = {n, rule, start, seed}, sampled},
            If[newSignature =!= signature,
              sampled = GogTrajectory[
                n,
                rule,
                start,
                maximumSteps,
                seed,
                Method -> "Native"
              ];
              trajectory = If[
                AssociationQ[sampled],
                sampled,
                <|
                  "States" -> GogRandomTrajectory[
                    n, rule, start, maximumSteps, seed
                  ],
                  "Engine" -> "Native fallback"
                |>
              ];
              signature = newSignature;
            ];
            labPanel[n, rule, start, Round[step], trajectory]
          ],
          TrackedSymbols :> {n, rule, start, step, seed},
          SynchronousUpdating -> True
        ]
      },
      Alignment -> Center,
      Spacings -> 0.7
    ],
    Background -> $labWash,
    FrameStyle -> None,
    FrameMargins -> {{9, 9}, {10, 10}}
  ],
  Initialization :> Quiet[
    Check[
      Module[{directory, localKernel},
        directory = Quiet[Check[NotebookDirectory[], $Failed]];
        If[StringQ[directory],
          localKernel = FileNameJoin[
            {
              directory, "Wolfram", "GogFieldDynamics", "Kernel", "init.wl"
            }
          ];
          If[FileExistsQ[localKernel], Get[localKernel]];
        ];
        If[! NameQ["GogFieldDynamics`GogDiffusionState"],
          Needs["GogFieldDynamics`"]
        ];
      ],
      Null
    ]
  ],
  SynchronousInitialization -> True,
  SaveDefinitions -> True
  ]
];

End[];
EndPackage[];
