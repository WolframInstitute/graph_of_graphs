(* ::Package:: *)

BeginPackage["GogFieldDynamics`"];

GogDiffusionExplorer::usage =
  "GogDiffusionExplorer[] creates an interactive small-model laboratory for " <>
  "exact graph-of-graphs diffusion and sampled SetReplace trajectories.";

GogClassAtlas::usage =
  "GogClassAtlas[n] draws the bundled n-vertex graph of graphs with each " <>
  "GoG vertex replaced by the cubic multigraph that it represents.";

GogClassExplorer::usage =
  "GogClassExplorer[] creates an interactive viewer: click a graph-of-graphs " <>
  "vertex to inspect the cubic multigraph represented by that vertex.";

GogDiffusionSnapshot::usage =
  "GogDiffusionSnapshot[n, rule, start, step, seed] draws one exact " <>
  "probability distribution together with one independently sampled path. " <>
  "Use \"PathSteps\" to make the sample longer than the diffusion time.";

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

classAdjacencyMatrix[n_Integer, code_String] := Module[
  {values, matrix, position = 1},
  values = Quiet[Check[ToExpression /@ StringSplit[code, ","], $Failed]];
  If[
    values === $Failed || Length[values] =!= n (n + 1)/2 ||
      ! AllTrue[values, IntegerQ[#] && NonNegative[#] &],
    Return[$Failed]
  ];
  matrix = ConstantArray[0, {n, n}];
  Do[
    matrix[[i, j]] = values[[position]];
    matrix[[j, i]] = values[[position]];
    position++,
    {i, n}, {j, i, n}
  ];
  matrix
];

classEdgeList[matrix_List] := Module[{n = Length[matrix]},
  Flatten @ Join[
    Table[
      ConstantArray[UndirectedEdge[i, i], matrix[[i, i]]],
      {i, n}
    ],
    Flatten[
      Table[
        ConstantArray[UndirectedEdge[i, j], matrix[[i, j]]],
        {i, n}, {j, i + 1, n}
      ],
      1
    ]
  ]
];

classCarrierGraph[n_Integer, index_Integer, imageSize_: {170, 135}] :=
 Module[{model = GogSmallModel[n], matrix, coordinates},
  If[FailureQ[model], Return[model]];
  If[! Between[index, {1, model["NodeCount"]}], Return[$Failed]];
  matrix = classAdjacencyMatrix[n, model["Nodes"][[index]]];
  If[matrix === $Failed, Return[$Failed]];
  coordinates = If[n == 2, {{-0.9, 0}, {0.9, 0}}, CirclePoints[n]];
  Graph[
    Range[n],
    classEdgeList[matrix],
    VertexCoordinates -> coordinates,
    VertexLabels -> Placed["Name", Center],
    VertexLabelStyle -> Directive[8, Bold, White, FontFamily -> "Helvetica"],
    VertexStyle -> $labBlue,
    VertexSize -> If[n <= 4, 0.24, 0.18],
    EdgeStyle -> Directive[$labNavy, AbsoluteThickness[1.8]],
    GraphLayout -> "CircularEmbedding",
    PlotRangePadding -> Scaled[0.22],
    ImageSize -> imageSize,
    Background -> White,
    PerformanceGoal -> "Quality"
  ]
];

classSummary[n_Integer, index_Integer] := Module[
  {model = GogSmallModel[n], matrix, loops, parallelPairs},
  matrix = classAdjacencyMatrix[n, model["Nodes"][[index]]];
  loops = Tr[matrix];
  parallelPairs = Count[
    Flatten[Table[matrix[[i, j]], {i, n}, {j, i + 1, n}]],
    value_ /; value > 1
  ];
  Grid[
    {
      {"Loops", loops},
      {"Vertex pairs joined more than once", parallelPairs}
    },
    Alignment -> {{Left, Right}},
    Spacings -> {1.2, 0.25},
    BaseStyle -> {9, $labMuted, FontFamily -> "Helvetica"}
  ]
];

labCoordinates[2] := {{-1.15, 0}, {1.15, 0}};
labCoordinates[4] := {
  {-0.80, 0.45}, {-1.60, -0.50}, {0.00, 0.00},
  {1.60, -0.40}, {0.80, 0.50}
};
labCoordinates[n_Integer] := labCoordinates[n] = Module[
  {model = GogSmallModel[n], graph, points, centered, spread},
  graph = Graph[
    Range[model["NodeCount"]],
    UndirectedEdge @@@ model["Edges"],
    GraphLayout -> If[
      model["NodeCount"] <= 17,
      "LayeredDigraphEmbedding",
      "SpringEmbedding"
    ]
  ];
  points = N[GraphEmbedding[graph]];
  centered = (# - Mean[points]) & /@ points;
  spread = (Max[Abs[#]] &) /@ Transpose[centered];
  spread = Replace[
    spread,
    value_ /; ! NumericQ[value] || value == 0 -> 1.,
    {1}
  ];
  ({1.72, 1.32} (#/spread)) & /@ centered
];

labPlotRange[coordinates_List, padding_: 0.28] :=
  ({Min[#] - padding, Max[#] + padding} &) /@ Transpose[coordinates];

GogClassAtlas[n_Integer: 4] := Module[
  {model = GogSmallModel[n], coordinates, support, carriers, columns},
  If[FailureQ[model], Return[model]];
  coordinates = labCoordinates[n];
  support = Graphics[
    {
      Directive[GrayLevel[0.72], AbsoluteThickness[2]],
      Line[coordinates[[#]]] & /@ model["Edges"],
      Table[
        {
          EdgeForm[Directive[$labNavy, AbsoluteThickness[1.2]]],
          FaceForm[White],
          Disk[coordinates[[index]], If[model["NodeCount"] <= 5, 0.19, 0.11]],
          Text[
            Style[
              labLabel[index],
              If[model["NodeCount"] <= 5, 10, 7],
              Bold,
              $labNavy,
              FontFamily -> "Helvetica"
            ],
            coordinates[[index]]
          ]
        },
        {index, model["NodeCount"]}
      ]
    },
    PlotRange -> labPlotRange[
      coordinates,
      If[model["NodeCount"] <= 5, 0.30, 0.20]
    ],
    PlotRangePadding -> None,
    ImageSize -> If[model["NodeCount"] <= 5, {560, 260}, {560, 410}],
    Background -> White
  ];
  carriers = Table[
    Column[
      {
        Style[labLabel[index], 10, Bold, $labNavy,
          FontFamily -> "Helvetica"],
        classCarrierGraph[
          n,
          index,
          If[model["NodeCount"] <= 5, {150, 120}, {105, 88}]
        ]
      },
      Alignment -> Center,
      Spacings -> 0.1
    ],
    {index, model["NodeCount"]}
  ];
  columns = Which[
    model["NodeCount"] <= 2, model["NodeCount"],
    model["NodeCount"] <= 5, 3,
    True, 4
  ];
  Column[
    {
      Style[
        "One-move connections between graph types",
        11,
        Bold,
        $labNavy,
        FontFamily -> "Helvetica"
      ],
      support,
      Style[
        "The vertices G1, G2, ... represent these cubic multigraphs:",
        10,
        $labMuted,
        FontFamily -> "Helvetica"
      ],
      Grid[
        Partition[carriers, columns, columns, {1, 1}, ""],
        Alignment -> Center,
        Spacings -> {0.55, 0.4}
      ]
    },
    Alignment -> Center,
    Spacings -> 0.45
  ]
];

classSupportGraphic[n_Integer, selected_Integer, setSelected_] := Module[
  {model = GogSmallModel[n], coordinates, radius},
  coordinates = labCoordinates[n];
  radius = Which[
    model["NodeCount"] <= 5, 0.18,
    model["NodeCount"] <= 17, 0.105,
    True, 0.028
  ];
  Graphics[
    {
      Directive[$labLine, AbsoluteThickness[1.8]],
      Line[coordinates[[#]]] & /@ model["Edges"],
      Table[
        With[{index = index, point = coordinates[[index]]},
          Tooltip[
            EventHandler[
              {
                EdgeForm[
                  Directive[
                    If[index === selected, $labOrange, $labNavy],
                    AbsoluteThickness[If[index === selected, 3, 1.3]]
                  ]
                ],
                FaceForm[If[index === selected, $labOrange, $labBlue]],
                Disk[point, radius],
                If[
                  model["NodeCount"] <= 17 || index === selected,
                  Text[
                    Style[
                      labLabel[index],
                      Which[
                        model["NodeCount"] <= 5, 9,
                        model["NodeCount"] <= 17, 6.5,
                        True, 5
                      ],
                      Bold,
                      White,
                      FontFamily -> "Helvetica"
                    ],
                    point
                  ],
                  Nothing
                ]
              },
              {"MouseClicked" :> setSelected[index]},
              PassEventsDown -> False
            ],
            labLabel[index] <> " — click to inspect its cubic multigraph"
          ]
        ],
        {index, model["NodeCount"]}
      ]
    },
    PlotRange -> labPlotRange[
      coordinates,
      If[model["NodeCount"] <= 5, 0.30, 0.20]
    ],
    PlotRangePadding -> None,
    ImageSize -> Which[
      model["NodeCount"] <= 2, {360, 150},
      model["NodeCount"] <= 5, {430, 230},
      model["NodeCount"] <= 17, {460, 350},
      True, {820, 580}
    ],
    Background -> White
  ]
];

Options[GogClassExplorer] = {"InitialSize" -> 4};

GogClassExplorer[OptionsPattern[]] := DynamicModule[
  {n = OptionValue["InitialSize"], selected = 1},
  Column[
    {
      Row[
        {
          Style["Number of vertices in the cubic graph:", 10,
            FontFamily -> "Helvetica"],
          Spacer[8],
          SetterBar[
            Dynamic[n, (n = #; selected = 1) &],
            {2 -> "2", 4 -> "4", 6 -> "6", 8 -> "8"}
          ]
        }
      ],
      Style[
        "Click any vertex in the graph of graphs; hover to see its label.",
        9,
        $labMuted,
        FontFamily -> "Helvetica"
      ],
      Dynamic[
        Grid[
          {{
            classSupportGraphic[n, selected, (selected = #) &],
            Column[
              {
                Style[
                  "Selected vertex: " <> labLabel[selected],
                  11,
                  Bold,
                  $labNavy,
                  FontFamily -> "Helvetica"
                ],
                classCarrierGraph[n, selected, {280, 220}],
                classSummary[n, selected]
              },
              Alignment -> Center,
              Spacings -> 0.35
            ]
          }},
          Alignment -> Center,
          Spacings -> {1.0, 0}
        ],
        TrackedSymbols :> {n, selected},
        SynchronousUpdating -> True
      ]
    },
    Alignment -> Center,
    Spacings -> 0.5
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
        If[! NameQ["GogFieldDynamics`GogSmallModel"],
          Needs["GogFieldDynamics`"]
        ];
      ],
      Null
    ]
  ],
  SynchronousInitialization -> True,
  SaveDefinitions -> False
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
    edgeLayer, trailLayer, activeLayer, nodeLayer, labelledIndices},
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
  baseRadius = Which[
    size <= 5, 0.21,
    size <= 17, 0.105,
    True, 0.028
  ];
  labelledIndices = If[
    size <= 17,
    Range[size],
    Union[
      {sampled},
      TakeLargestBy[Range[size], probability[[#]] &, Min[10, size]]
    ]
  ];

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
        radius = baseRadius,
        selected = index === sampled,
        textColor = If[
          N[probability[[index]]/maximum] > 0.34,
          White,
          $labNavy
        ]},
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
          If[
            MemberQ[labelledIndices, index],
            Text[
              Column[
                {
                  Style[
                    labLabel[index],
                    Which[size <= 5, 9, size <= 17, 6.5, True, 4.5],
                    Bold,
                    textColor,
                    FontFamily -> "Helvetica"
                  ],
                  If[
                    size <= 17,
                    Style[
                      ToString[NumberForm[N[mass], {3, 2}]],
                      If[size <= 5, 7, 5.5],
                      textColor,
                      FontFamily -> "Helvetica"
                    ],
                    Nothing
                  ]
                },
                Alignment -> Center,
                Spacings -> -0.1
              ],
              point
            ],
            Nothing
          ]
        },
        Grid[
          {
            {Style["class", Bold], labLabel[index]},
            {"exact mass", mass},
            {"holding probability", NumberForm[N[hold], {4, 3}]},
            {"stored graph data", Style[code, 8, FontFamily -> "Courier"]}
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
    PlotRange -> labPlotRange[coordinates, If[size <= 5, 0.34, 0.20]],
    PlotRangePadding -> None,
    ImageSize -> Which[
      size <= 5, {500, 260},
      size <= 17, {560, 400},
      True, {820, 600}
    ],
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

labFullPathRibbon[path_List] := Module[{starts, rows},
  starts = Range[1, Max[1, Length[path] - 1], 8];
  rows = Map[
    Function[start,
      With[
        {
          stop = Min[start + 8, Length[path]],
          labels = labLabel /@ Take[path, {start, Min[start + 8, Length[path]]}]
        },
        Row[
          {
            Style[
              "t = " <> ToString[start - 1] <> "\[Dash]" <>
                ToString[stop - 1] <> "   ",
              8,
              $labMuted,
              FontFamily -> "Helvetica"
            ],
            Row[
              Riffle[
                Style[#, 8, Bold, $labNavy,
                  FontFamily -> "Helvetica"] & /@ labels,
                Style["  \[Rule]  ", 9, Bold, $labOrange]
              ]
            ]
          }
        ]
      ]
    ],
    starts
  ];
  Column[rows, Alignment -> Left, Spacings -> 0.22]
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
    "all move outcomes retained, including repeated and stay-put outcomes",
    "equal weight for each distinct target; unused probability stays put"
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

Options[GogDiffusionSnapshot] = {"PathSteps" -> Automatic};

GogDiffusionSnapshot[
  n_Integer: 4,
  rule_String: "A",
  start_Integer: 1,
  step_Integer: 4,
  seed_Integer: 2026,
  OptionsPattern[]
] := Module[
  {trajectory, probability, path, picture, ruleName, probabilityTable,
    pathSteps, size, indices, tableRows, pictureAndTable},
  pathSteps = Replace[OptionValue["PathSteps"], Automatic -> step];
  If[
    ! IntegerQ[pathSteps] || pathSteps < step,
    Return[failure[
      "InvalidPathSteps",
      "PathSteps must be an integer at least as large as the diffusion time.",
      <|"Step" -> step, "PathSteps" -> pathSteps|>
    ]]
  ];
  trajectory = GogTrajectory[
    n,
    rule,
    start,
    pathSteps,
    seed,
    Method -> "Native"
  ];
  If[FailureQ[trajectory], Return[trajectory]];
  probability = GogDiffusionState[n, rule, start, step];
  path = trajectory["States"];
  picture = labGraph[n, rule, probability, path, pathSteps];
  ruleName = If[rule === "A", "Rule A", "Rule B"];
  size = Length[probability];
  If[
    size <= 10,
    tableRows = MapIndexed[
      {labLabel[First[#2]], #1, NumberForm[N[#1], {4, 3}]} &,
      probability
    ];
    probabilityTable = Grid[
      Prepend[
        tableRows,
        {
          Style["Graph", Bold],
          Style["Exact", Bold],
          Style["Decimal", Bold]
        }
      ],
      Alignment -> {{Left, Right, Right}},
      Dividers -> {None, {False, True, False}},
      Spacings -> {1.0, 0.45},
      BaseStyle -> {9, $labNavy, FontFamily -> "Helvetica"}
    ],
    indices = TakeLargestBy[
      Range[size],
      probability[[#]] &,
      Min[10, size]
    ];
    tableRows = {
      labLabel[#],
      NumberForm[N[probability[[#]]], {4, 3}]
    } & /@ indices;
    probabilityTable = Column[
      {
        Style[
          "Ten largest probabilities at t = " <> ToString[step],
          9,
          Bold,
          $labNavy,
          FontFamily -> "Helvetica"
        ],
        Grid[
          Prepend[
            tableRows,
            {Style["Graph", Bold], Style["Probability", Bold]}
          ],
          Alignment -> {{Left, Right}},
          Dividers -> {None, {False, True, False}},
          Spacings -> {1.2, 0.35},
          BaseStyle -> {8, $labNavy, FontFamily -> "Helvetica"}
        ],
        Style[
          "Total shown: " <>
            ToString[NumberForm[N[Total[probability[[indices]]]], {4, 3}]],
          8,
          $labMuted,
          FontFamily -> "Helvetica"
        ]
      },
      Alignment -> Left,
      Spacings -> 0.25
    ]
  ];
  pictureAndTable = If[
    size <= 17,
    Grid[
      {{picture, probabilityTable}},
      Alignment -> {{Center, Left}, Top},
      Spacings -> {1.0, 0}
    ],
    Column[
      {picture, probabilityTable},
      Alignment -> Center,
      Spacings -> 0.35
    ]
  ];
  Column[
    {
      Style[
        ruleName <> " after " <> ToString[step] <> " steps from " <>
          labLabel[start] <> " on the N = " <> ToString[n] <>
          " graph of graphs",
        11,
        Bold,
        $labNavy,
        FontFamily -> "Helvetica"
      ],
      pictureAndTable,
      Column[
        {
          Style[
            "Sample path: " <> ToString[pathSteps] <> " steps, seed " <>
              ToString[seed],
            9,
            Bold,
            $labNavy,
            FontFamily -> "Helvetica"],
          labFullPathRibbon[path]
        },
        Alignment -> Left,
        Spacings -> 0.2
      ],
      Style[
        "Blue encodes the exact rational distribution at t = " <>
          ToString[step] <> ". Orange marks the separate sampled path.",
        9,
        $labMuted,
        FontFamily -> "Helvetica"
      ]
    },
    Alignment -> Center,
    Spacings -> 0.35
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
                  "exact graph-type probabilities and one sampled path",
                  8,
                  $labMuted,
                  FontFamily -> "Helvetica"
                ]
              },
              Spacings -> 0.08
            ],
            Spacer[15],
            Framed[
              Style["INTERACTIVE", 7, Bold, White,
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
                  {2 -> "N=2", 4 -> "N=4", 6 -> "N=6", 8 -> "N=8"}
                ],
                labControlLabel["CHAIN"],
                SetterBar[
                  Dynamic[rule, (rule = #; step = 0; signature = None) &],
                  {"A" -> "Rule A", "B" -> "Rule B · stay-put steps"}
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
