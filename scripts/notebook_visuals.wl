(* ::Package:: *)

BeginPackage["GogNotebookVisuals`"];

EnrichNotebook::usage =
  "EnrichNotebook[notebook] adds source-suppressed navigation and native " <>
  "Wolfram visualizations to the generated MathNotebook article.";

BuildCompanionNotebook::usage =
  "BuildCompanionNotebook[diffusionBoxes] constructs the concise, visual " <>
  "Whitehead-field-dynamics companion notebook.";

Begin["`Private`"];

$navy = RGBColor[0.075, 0.13, 0.22];
$blue = RGBColor[0.00, 0.45, 0.70];
$sky = RGBColor[0.34, 0.71, 0.91];
$green = RGBColor[0.00, 0.62, 0.45];
$orange = RGBColor[0.90, 0.62, 0.00];
$vermillion = RGBColor[0.84, 0.37, 0.00];
$purple = RGBColor[0.80, 0.47, 0.65];
$muted = RGBColor[0.37, 0.42, 0.49];
$line = RGBColor[0.82, 0.85, 0.88];
$wash = RGBColor[0.965, 0.975, 0.985];

notebookTag[id_String] := <|
  "MathNotebook" -> <|"Suppressed" -> "True"|>,
  "GoGNotebook" -> <|"PresentationOnly" -> True, "ID" -> id|>
|>;

presentationCell[content_, style_String, id_String, options___] := Cell[
  content,
  style,
  TaggingRules -> notebookTag[id],
  CellTags -> {"GoGNotebookVisual", id},
  options,
  FontSlant -> Plain
];

graphicCell[expression_, id_String] := presentationCell[
  BoxData[ToBoxes[expression, TraditionalForm]],
  "Text",
  id,
  ShowCellBracket -> False,
  CellMargins -> {{16, 16}, {18, 8}},
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{12, 12}, {14, 14}},
  Background -> White,
  ShowStringCharacters -> False,
  TextAlignment -> Center
];

interactiveCellFromBoxes[boxes_, id_String] := presentationCell[
  BoxData[boxes],
  "Text",
  id,
  ShowCellBracket -> False,
  CellMargins -> {{8, 8}, {18, 8}},
  Background -> White,
  ShowStringCharacters -> False,
  TextAlignment -> Center
];

captionCell[_Integer, text_String, id_String] := presentationCell[
  TextData[{text}],
  "Caption",
  id,
  ShowCellBracket -> False,
  CellMargins -> {{84, 84}, {2, 18}},
  FontColor -> $muted
];

bannerCell[] := presentationCell[
  TextData[{
    StyleBox[
      "COMPUTATIONAL NOTEBOOK EDITION",
      FontFamily -> "Helvetica",
      FontWeight -> "Bold",
      FontTracking -> "Extended",
      FontColor -> $blue
    ],
    StyleBox["   •   ", FontColor -> $line],
    StyleBox[
      "native Mathematica visuals • exact finite models",
      FontFamily -> "Helvetica",
      FontColor -> $muted
    ]
  }],
  "Text",
  "GoGBanner",
  ShowCellBracket -> False,
  CellMargins -> {{64, 64}, {8, 14}},
  CellFrame -> {{0, 0}, {0, 1}},
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  TextAlignment -> Center,
  FontSize -> 10
];

navigationButton[label_String, title_String] := With[
  {target = title},
  ButtonBox[
    label,
    BaseStyle -> {
      "Hyperlink",
      FontFamily -> "Helvetica",
      FontWeight -> "Bold",
      FontColor -> $blue
    },
    ButtonFunction :> NotebookFind[
      InputNotebook[],
      target,
      All,
      CellStyle -> "Section"
    ],
    Evaluator -> Automatic,
    Method -> "Preemptive",
    ButtonNote -> "Jump to " <> title
  ]
];

navigationCell[] := presentationCell[
  TextData[Flatten[Riffle[
    navigationButton @@@ {
      {"OVERVIEW", "Introduction and contributions"},
      {"LOCAL MOVE", "Whitehead Moves and the Exact Random Rule"},
      {"PROJECTIONS", "Projection Calculus"},
      {"CONSENSUS", "Deterministic Consensus from Products of Projections"},
      {"MOVE GRAPHS", "Results for the three graphs of moves"},
      {"ENUMERATION", "Complete finite enumeration"},
      {"LEAN", "Lean Verification Boundary"},
      {"OPEN", "Open Problems"}
    },
    StyleBox["   •   ", FontColor -> $line]
  ]]],
  "Text",
  "GoGNavigation",
  ShowCellBracket -> False,
  CellMargins -> {{64, 64}, {6, 12}},
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{14, 14}, {8, 8}},
  Background -> $wash,
  TextAlignment -> Center,
  FontSize -> 9
];

carrierIcon[] := Module[
  {points, edges, values, colors},
  points = {{-0.8, 0.65}, {0.8, 0.65}, {-0.8, -0.65}, {0.8, -0.65}};
  edges = Subsets[Range[4], {2}];
  values = {"-1", "3", "0", "2"};
  colors = {$sky, $orange, $green, $purple};
  Graphics[
    {
      {Directive[$line, AbsoluteThickness[1.7]],
        Line[points[[#]]] & /@ edges},
      {Directive[$vermillion, AbsoluteThickness[4]], Line[points[[{1, 2}]]]},
      Table[
        {
          EdgeForm[Directive[White, AbsoluteThickness[2]]],
          colors[[index]],
          Disk[points[[index]], 0.19],
          Text[Style[values[[index]], 10, Bold, White], points[[index]]]
        },
        {index, 4}
      ]
    },
    PlotRange -> {{-1.15, 1.15}, {-0.95, 0.95}},
    ImageSize -> {76, 62},
    Background -> White
  ]
];

updateIcon[] := Column[
  {
    Row[{
      Style[
        Row[{Subscript[Style["f", Plain], Style["i", Plain]], ", ",
          Subscript[Style["f", Plain], Style["j", Plain]]}],
        9,
        $navy
      ],
      Style["  →  ", 11, Bold, $blue],
      Style[
        Row[{"m, m", "   ",
          Style["m = (", 8],
          Subscript[Style["f", Plain], Style["i", Plain]],
          Style[" + ", 8],
          Subscript[Style["f", Plain], Style["j", Plain]],
          Style[")/2", 8]}],
        9,
        $navy
      ]
    }],
    Graphics[
      {
        {$sky, Disk[{-0.55, 0}, 0.18]},
        {$orange, Disk[{0.55, 0}, 0.18]},
        {Directive[$vermillion, AbsoluteThickness[4]], Line[{{-0.36, 0}, {0.36, 0}}]},
        Text[Style["same mean", 10, Bold, $green], {0, -0.47}]
      },
      PlotRange -> {{-1, 1}, {-0.7, 0.45}},
      ImageSize -> {76, 52}
    ]
  },
  Alignment -> Center,
  Spacings -> 0.2
];

rewriteIcon[] := Graphics[
  {
    {Directive[$line, AbsoluteThickness[1.6]],
      Line[{{0.1, 0.8}, {0.72, 0.2}}],
      Line[{{0.1, -0.8}, {0.72, 0.2}}],
      Line[{{1.28, -0.2}, {1.9, 0.8}}],
      Line[{{1.28, -0.2}, {1.9, -0.8}}]},
    {Directive[$vermillion, AbsoluteThickness[4]], Line[{{0.72, 0.2}, {1.28, -0.2}}]},
    {$navy, Disk[{0.72, 0.2}, 0.11], Disk[{1.28, -0.2}, 0.11]},
    Text[Style["→", 18, Bold, $blue], {2.35, 0}],
    {Directive[$line, AbsoluteThickness[1.6]],
      Line[{{2.8, 0.8}, {3.55, 0.28}}],
      Line[{{4.3, 0.8}, {3.55, 0.28}}],
      Line[{{2.8, -0.8}, {3.55, -0.28}}],
      Line[{{4.3, -0.8}, {3.55, -0.28}}]},
    {Directive[$green, AbsoluteThickness[4]], Line[{{3.55, 0.28}, {3.55, -0.28}}]},
    {$navy, Disk[{3.55, 0.28}, 0.11], Disk[{3.55, -0.28}, 0.11]}
  },
  PlotRange -> {{-0.1, 4.5}, {-1, 1}},
  ImageSize -> {80, 55},
  Background -> White
];

baseChainIcon[] := Module[{nodes},
  nodes = {
    {{0, 0}, "[G]"}, {{0.8, 0.45}, "[H]"},
    {{1.6, 0.05}, "[K]"}, {{2.4, 0.55}, "[L]"}
  };
  Graphics[{
    {Directive[$line, AbsoluteThickness[2]],
      Line[{{0, 0}, {0.8, 0.45}, {1.6, 0.05}, {2.4, 0.55}}],
      BezierCurve[{{0.8, 0.45}, {1.4, 1.15}, {2.4, 0.55}}],
      BezierCurve[{{0, 0}, {0.8, -0.8}, {1.6, 0.05}}]},
      Table[
        {
          White,
          EdgeForm[Directive[$blue, AbsoluteThickness[2]]],
          Disk[nodes[[index, 1]], 0.22],
          Text[Style[nodes[[index, 2]], 9, Bold, $navy], nodes[[index, 1]]]
        },
        {index, Length[nodes]}
      ]
    },
    PlotRange -> {{-0.35, 2.75}, {-0.7, 1.05}},
    ImageSize -> {80, 55},
    Background -> White
  ]
];

flowCard[heading_String, body_, footer_String, color_] := Framed[
  Column[
    {
      Style[heading, 7.5, Bold, color, FontFamily -> "Helvetica"],
      body,
      Style[footer, 6.5, $muted, FontFamily -> "Helvetica", TextAlignment -> Center]
    },
    Alignment -> Center,
    Spacings -> 0.45
  ],
  Background -> White,
  FrameStyle -> Directive[Opacity[0.45], color, AbsoluteThickness[1.2]],
  FrameMargins -> {{5, 5}, {6, 6}},
  ImageSize -> {92, 125}
];

caseBadge[number_String, title_String, subtitle_String, color_] := Framed[
  Column[
    {
      Row[
        {
          Framed[
            Style[number, 10, Bold, White, FontFamily -> "Helvetica"],
            Background -> color,
            FrameStyle -> None,
            FrameMargins -> {{5, 5}, {2, 2}}
          ],
          Style[title, 6.5, Bold, $navy, FontFamily -> "Helvetica"]
        },
        Spacer[4]
      ],
      Style[subtitle, 6, $muted, FontFamily -> "Helvetica"]
    },
    Alignment -> Left,
    Spacings -> 0.2
  ],
  Background -> Blend[{White, color}, 0.08],
  FrameStyle -> Directive[Opacity[0.35], color],
  FrameMargins -> {{4, 4}, {4, 4}},
  ImageSize -> {100, 48}
];

visualAbstract[] := Framed[
  Column[
    {
      Style[
        "THE DYNAMICS AT A GLANCE",
        14,
        Bold,
        $navy,
        FontFamily -> "Helvetica"
      ],
      Grid[
        {{
          flowCard["1  CARRIER + FIELD", carrierIcon[],
            "a cubic multigraph with vertex data", $blue],
          Style["→", 20, Bold, $line],
          flowCard["2  PROJECT", updateIcon[],
            "average the selected endpoint pair", $vermillion],
          Style["→", 20, Bold, $line],
          flowCard["3  REWRITE", rewriteIcon[],
            "choose one of two resolutions", $green],
          Style["→", 20, Bold, $line],
          flowCard["4  QUOTIENT", baseChainIcon[],
            "move between isomorphism classes", $purple]
        }},
        Alignment -> Center,
        Spacings -> {0.12, 0}
      ],
      Style[
        "One local operation; four mathematical objects that must stay distinct",
        10,
        Plain,
        $muted,
        FontFamily -> "Helvetica"
      ],
      Grid[
        {{
          caseBadge["1", "field cocycle", "state (G,f)", $blue],
          caseBadge["2", "fixed-labelled", "four moves / edge", $vermillion],
          caseBadge["3", "multiplicity chain", "3N resolution slots", $green],
          caseBadge["4", "simple support", "fixed 3N clock", $purple]
        }},
        Spacings -> {0.18, 0},
        Alignment -> Center
      ]
    },
    Alignment -> Center,
    Spacings -> 0.9
  ],
  Background -> $wash,
  FrameStyle -> None,
  FrameMargins -> {{10, 10}, {12, 12}},
  ImageSize -> 480
];

$portCoordinates = <|
  "a" -> {-1.15, 0.75}, "b" -> {-1.15, -0.75},
  "c" -> {1.15, 0.75}, "d" -> {1.15, -0.75}
|>;
$portOffsets = <|
  "a" -> {-0.19, 0.16}, "b" -> {-0.19, -0.16},
  "c" -> {0.19, 0.16}, "d" -> {0.19, -0.16}
|>;

localStateGraphic[pairs_List, centers_List, centralColor_] := Graphics[
  {
    {Directive[$line, AbsoluteThickness[2]],
      Table[
        Line[{
          Lookup[$portCoordinates, pairs[[side, endpoint]]],
          centers[[side]]
        }],
        {side, 2}, {endpoint, 2}
      ]},
    {Directive[centralColor, AbsoluteThickness[5]], Line[centers]},
    Table[
      {
        White,
        EdgeForm[Directive[$muted, AbsoluteThickness[1.4]]],
        Disk[Lookup[$portCoordinates, label], 0.075],
        Text[
          Style[label, 10, Bold, $navy, FontFamily -> "Helvetica"],
          Lookup[$portCoordinates, label] + Lookup[$portOffsets, label]
        ]
      },
      {label, {"a", "b", "c", "d"}}
    ],
    {$navy, Disk[centers[[1]], 0.13], Disk[centers[[2]], 0.13]}
  },
  PlotRange -> {{-1.55, 1.55}, {-1.08, 1.08}},
  ImageSize -> {136, 95},
  Background -> White
];

movePanel[title_String, partition_String, graphic_, color_] := Framed[
  Column[
    {
      Style[title, 10, Bold, color, FontFamily -> "Helvetica"],
      graphic,
      Style[partition, 10, $muted, FontFamily -> "Helvetica"]
    },
    Alignment -> Center,
    Spacings -> 0.35
  ],
  Background -> White,
  FrameStyle -> Directive[Opacity[0.4], color],
  FrameMargins -> {{8, 8}, {7, 7}},
  ImageSize -> {160, 150}
];

whiteheadMoveFigure[] := Framed[
  Column[
    {
      Style[
        "ONE EDGE OBJECT, TWO COMPRESSED RESOLUTIONS",
        13,
        Bold,
        $navy,
        FontFamily -> "Helvetica"
      ],
      Grid[
        {{
          movePanel[
            "SELECTED CARRIER EDGE",
            "{a,b} | {c,d}",
            localStateGraphic[
              {{"a", "b"}, {"c", "d"}},
              {{-0.36, 0}, {0.36, 0}},
              $vermillion
            ],
            $vermillion
          ],
          Column[
            {
              Style["↗", 24, Bold, $blue],
              Style["collapse\nand\nre-expand", 9, $muted,
                FontFamily -> "Helvetica", TextAlignment -> Center],
              Style["↘", 24, Bold, $blue]
            },
            Alignment -> Center,
            Spacings -> 0.2
          ],
          Column[
            {
              movePanel[
                "RESOLUTION I",
                "{a,c} | {b,d}",
                localStateGraphic[
                  {{"a", "c"}, {"b", "d"}},
                  {{0, 0.34}, {0, -0.34}},
                  $green
                ],
                $green
              ],
              movePanel[
                "RESOLUTION II",
                "{a,d} | {b,c}",
                localStateGraphic[
                  {{"a", "d"}, {"b", "c"}},
                  {{-0.18, 0.18}, {0.18, -0.18}},
                  $purple
                ],
                $purple
              ]
            },
            Spacings -> 0.6
          ]
        }},
        Alignment -> Center,
        Spacings -> {0.8, 0}
      ],
      Style[
        "Rule A retains every resolution slot and its multiplicity.\n" <>
        "Rule B gives each distinct target probability 1/(3N); the rest stays put.",
        10,
        $muted,
        FontFamily -> "Helvetica",
        TextAlignment -> Center
      ]
    },
    Alignment -> Center,
    Spacings -> 0.8
  ],
  Background -> $wash,
  FrameStyle -> None,
  FrameMargins -> {{18, 18}, {14, 14}},
  ImageSize -> 480
];

k4Graphic[activeEdges_List, color_] := Module[
  {points, edges},
  points = {{-0.72, 0.72}, {0.72, 0.72}, {-0.72, -0.72}, {0.72, -0.72}};
  edges = Subsets[Range[4], {2}];
  Graphics[
    {
      {Directive[$line, AbsoluteThickness[1.5]], Line[points[[#]]] & /@ edges},
      {Directive[color, AbsoluteThickness[5]],
        Line[points[[#]]] & /@ activeEdges},
      Table[
        {
          White,
          EdgeForm[Directive[$navy, AbsoluteThickness[1.8]]],
          Disk[points[[index]], 0.15],
          Text[Style[ToString[index], 9, Bold, $navy], points[[index]]]
        },
        {index, 4}
      ]
    },
    PlotRange -> {{-1, 1}, {-1, 1}},
    ImageSize -> {65, 65},
    Background -> White
  ]
];

k4ScheduleGraphic[] := Row[
  {
    k4Graphic[{{1, 2}, {3, 4}}, $blue],
    Graphics[
      Text[Style["→", 16, Bold, $line], {0, 0}],
      PlotRange -> {{-0.5, 0.5}, {-0.5, 0.5}},
      ImageSize -> {18, 65},
      Background -> White
    ],
    k4Graphic[{{1, 3}, {2, 4}}, $orange]
  },
  Spacer[4]
];

cubeGraphic[] := Module[
  {bits, points, edges, coordinate},
  bits = Tuples[{0, 1}, 3];
  points = ({1.25 #[[1]] + 0.42 #[[3]],
      1.15 #[[2]] + 0.42 #[[3]]} &) /@ bits;
  edges = Select[
    Subsets[Range[8], {2}],
    Total[Abs[bits[[#[[1]]]] - bits[[#[[2]]]]]] === 1 &
  ];
  coordinate[edge_] := First @ FirstPosition[
    Abs[bits[[edge[[1]]]] - bits[[edge[[2]]]]],
    1
  ];
  Graphics[
    {
      Table[
        {
          Directive[
            {$blue, $orange, $green}[[coordinate[edge]]],
            AbsoluteThickness[3.5]
          ],
          Line[points[[edge]]]
        },
        {edge, edges}
      ],
      Table[
        {
          White,
          EdgeForm[Directive[$navy, AbsoluteThickness[1.5]]],
          Disk[points[[index]], 0.09]
        },
        {index, 8}
      ]
    },
    PlotRange -> {{-0.25, 1.95}, {-0.25, 1.85}},
    ImageSize -> {135, 118},
    Background -> White
  ]
];

legendSwatch[color_, text_String] := Row[
  {
    Graphics[{color, Rectangle[{0, 0}, {1, 0.25}]}, ImageSize -> {22, 8}],
    Style[text, 9, $muted, FontFamily -> "Helvetica"]
  },
  Spacer[5]
];

consensusFigure[] := Framed[
  Column[
    {
      Style[
        "FINITE KILLING WORDS ARE MATCHING SCHEDULES",
        13,
        Bold,
        $navy,
        FontFamily -> "Helvetica"
      ],
      Grid[
        {{
          Framed[
            Column[
              {
                Style["K4  •  two stages", 11, Bold, $navy,
                  FontFamily -> "Helvetica"],
                k4ScheduleGraphic[],
                Row[
                  {
                    legendSwatch[$blue, "{12,34}"],
                    legendSwatch[$orange, "{13,24}"]
                  },
                  Spacer[10]
                ],
                Style["equal blocks:  1 → 2 → 4",
                  10, Bold, $green, FontFamily -> "Helvetica"]
              },
              Alignment -> Center,
              Spacings -> 0.55
            ],
            Background -> White,
            FrameStyle -> Directive[$line],
            FrameMargins -> {{12, 12}, {10, 10}},
            ImageSize -> {195, 235}
          ],
          Framed[
            Column[
              {
                Style["Q3  •  three coordinate stages", 11, Bold, $navy,
                  FontFamily -> "Helvetica"],
                cubeGraphic[],
                Row[
                  {
                    legendSwatch[$blue, "coordinate 1"],
                    legendSwatch[$orange, "2"],
                    legendSwatch[$green, "3"]
                  },
                  Spacer[8]
                ],
                Style[
                  "equal blocks:  1 → 2 → 4 → 8",
                  10,
                  Bold,
                  $green,
                  FontFamily -> "Helvetica"
                ]
              },
              Alignment -> Center,
              Spacings -> 0.5
            ],
            Background -> White,
            FrameStyle -> Directive[$line],
            FrameMargins -> {{12, 12}, {10, 10}},
            ImageSize -> {195, 235}
          ]
        }},
        Spacings -> {0.8, 0},
        Alignment -> Center
      ],
      Style[
        "Each colored matching is a commuting block of pair projections; " <>
        "the complete schedule equals the consensus matrix J.",
        10,
        $muted,
        FontFamily -> "Helvetica"
      ]
    },
    Alignment -> Center,
    Spacings -> 0.85
  ],
  Background -> $wash,
  FrameStyle -> None,
  FrameMargins -> {{18, 18}, {14, 14}},
  ImageSize -> 480
];

enumerationFigure[] := Module[
  {nValues, classValues, slotValues, classLabels, xScale, yScale,
    classPoints, slotPoints, powers, xTicks},
  nValues = Range[2, 14, 2];
  classValues = {2, 5, 17, 71, 388, 2592, 21096};
  slotValues = {12, 60, 306, 1704, 11640, 93312, 886032};
  classLabels = {"2", "5", "17", "71", "388", "2,592", "21,096"};
  xScale[x_] := Rescale[x, {2, 14}, {1.15, 10.25}];
  yScale[y_] := Rescale[Log[10, y], {0, 6}, {0.85, 5.55}];
  classPoints = MapThread[{xScale[#1], yScale[#2]} &, {nValues, classValues}];
  slotPoints = MapThread[{xScale[#1], yScale[#2]} &, {nValues, slotValues}];
  powers = Range[0, 6];
  xTicks = MapThread[
    {Line[{{xScale[#1], 0.72}, {xScale[#1], 0.84}}],
      Text[Style[ToString[#1], 9, $muted], {xScale[#1], 0.48}]} &,
    {nValues}
  ];
  Graphics[
    {
      {White, Rectangle[{0, 0}, {11.4, 6.75}]},
      {Directive[$line, AbsoluteThickness[1]],
        Table[
          {
            Line[{{1.05, yScale[10^power]}, {10.45, yScale[10^power]}}],
            Text[
              Style[TraditionalForm[10^power], 8, $muted],
              {0.7, yScale[10^power]}
            ]
          },
          {power, powers}
        ]},
      {Directive[$navy, AbsoluteThickness[1.4]],
        Line[{{1.05, 0.84}, {10.45, 0.84}}],
        Line[{{1.05, 0.84}, {1.05, 5.65}}]},
      xTicks,
      {Directive[$blue, AbsoluteThickness[3]], Line[classPoints]},
      {$blue, PointSize[0.014], Point[classPoints]},
      {Directive[$orange, AbsoluteThickness[3]], Line[slotPoints]},
      {$orange, PointSize[0.014], Point[slotPoints]},
      MapThread[
        Text[
          Style[#2, 8, Bold, $blue, FontFamily -> "Helvetica"],
          #1 + {0, 0.24}
        ] &,
        {classPoints, classLabels}
      ],
      Text[
        Style["COMPLETE ENUMERATION GROWTH", 13, Bold, $navy,
          FontFamily -> "Helvetica"],
        {5.75, 6.4}
      ],
      Text[
        Style["carrier vertices N", 9, $muted, FontFamily -> "Helvetica"],
        {5.75, 0.15}
      ],
      Rotate[
        Text[
          Style["count (log10 scale)", 9, $muted,
            FontFamily -> "Helvetica"],
          {0.12, 3.25}
        ],
        Pi/2,
        {0.12, 3.25}
      ],
      Inset[
        Framed[
          Row[
            {
              legendSwatch[$blue, "unlabelled classes"],
              legendSwatch[$orange, "Rule-A slot records"]
            },
            Spacer[14]
          ],
          Background -> White,
          FrameStyle -> Directive[$line],
          FrameMargins -> {{8, 8}, {5, 5}}
        ],
        {4.2, 5.82}
      ],
      Inset[
        Framed[
          Column[
            {
              Style["N = 14", 10, Bold, $navy],
              Style["21,096 classes", 10, Bold, $blue],
              Style["886,032 slots", 10, Bold, $orange]
            },
            Alignment -> Left,
            Spacings -> 0.2
          ],
          Background -> Blend[{White, $orange}, 0.08],
          FrameStyle -> Directive[Opacity[0.35], $orange],
          FrameMargins -> {{9, 9}, {7, 7}}
        ],
        {8.5, 4.55}
      ]
    },
    PlotRange -> {{0, 11.4}, {0, 6.75}},
    ImageSize -> 470,
    Background -> White
  ]
];

styleCellQ[Cell[_, style_String, ___], target_String] := style === target;
styleCellQ[_, _] := False;

sectionCellQ[Cell[title_String, "Section", ___], target_String] :=
  title === target;
sectionCellQ[_, _] := False;

insertAfterFirst[cells_List, test_, additions_List] := Module[
  {position},
  position = SelectFirst[
    Range[Length[cells]],
    TrueQ[test[cells[[#]]]] &,
    Missing["NotFound"]
  ];
  If[
    MissingQ[position],
    cells,
    Join[Take[cells, position], additions, Drop[cells, position]]
  ]
];

enrichCells[inputCells_List, diffusionBoxes_] := Module[{cells},
  cells = inputCells;
  cells = insertAfterFirst[
    cells,
    (styleCellQ[#, "Author"] &),
    {bannerCell[]}
  ];
  cells = insertAfterFirst[
    cells,
    (styleCellQ[#, "Abstract"] &),
    {
      navigationCell[],
      graphicCell[visualAbstract[], "GoGVisualAbstract"],
      captionCell[
        1,
        "A notebook-only roadmap of the carrier, field update, local rewrite, " <>
        "and quotient dynamics.  The four numbered objects use different " <>
        "state spaces and transition conventions.",
        "GoGVisualAbstractCaption"
      ]
    }
  ];
  cells = insertAfterFirst[
    cells,
    (sectionCellQ[#, "Whitehead Moves and the Exact Random Rule"] &),
    {
      graphicCell[whiteheadMoveFigure[], "GoGWhiteheadMove"],
      captionCell[
        2,
        "The selected carrier edge determines four boundary half-edges.  The " <>
        "two alternative pairings are the two compressed Whitehead resolutions.",
        "GoGWhiteheadMoveCaption"
      ]
    }
  ];
  cells = insertAfterFirst[
    cells,
    (sectionCellQ[#, "Deterministic Consensus from Products of Projections"] &),
    {
      graphicCell[consensusFigure[], "GoGConsensusSchedules"],
      captionCell[
        3,
        "The exact finite-time consensus products used at N=4 and N=8.  Each color is " <>
        "one perfect matching, so equal-value blocks double at every stage.",
        "GoGConsensusSchedulesCaption"
      ]
    }
  ];
  cells = insertAfterFirst[
    cells,
    (sectionCellQ[#, "Results for the three graphs of moves"] &),
    {
      interactiveCellFromBoxes[
        diffusionBoxes,
        "GoGDiffusionLab"
      ],
      captionCell[
        4,
        "A playable exact diffusion on the complete N=2,4,6,8 unlabelled " <>
        "quotients.  Blue fill is probability mass; the orange ring and " <>
        "trail are one sampled path.  SetReplace repeats singleton-hypergraph " <>
        "rules by Rule-A slot multiplicity.  Rule B uses one rule per support " <>
        "neighbour and pads every class to a fixed 3N clock with self-rules.",
        "GoGDiffusionLabCaption"
      ]
    }
  ];
  cells = insertAfterFirst[
    cells,
    (sectionCellQ[#, "Complete finite enumeration"] &),
    {
      graphicCell[enumerationFigure[], "GoGEnumerationGrowth"],
      captionCell[
        5,
        "Complete unlabelled class and Rule-A slot counts through N=14.  The " <>
        "logarithmic axis makes the computational growth visible without " <>
        "turning finite evidence into an asymptotic claim.",
        "GoGEnumerationGrowthCaption"
      ]
    }
  ];
  cells
];

EnrichNotebook[notebook_Notebook] :=
  EnrichNotebook[
    notebook,
    ToBoxes[GogFieldDynamics`GogDiffusionExplorer[], StandardForm]
  ];

EnrichNotebook[
  Notebook[cells_List, options___],
  diffusionBoxes_
] := Notebook[enrichCells[cells, diffusionBoxes], options];

(* Concise companion notebook ------------------------------------------------ *)

companionTag[id_String] := <|
  "GoGNotebook" -> <|
    "Companion" -> True,
    "ID" -> id
  |>
|>;

companionCell[content_, style_String, id_String, options___] := Cell[
  content,
  style,
  TaggingRules -> companionTag[id],
  CellTags -> {"GoGCompanion", id},
  options,
  FontSlant -> Plain
];

companionText[text_String, id_String] := companionCell[
  text,
  "Text",
  id,
  FontSize -> 12,
  LineSpacing -> {1.15, 2}
];

companionCaption[text_String, id_String] := companionCell[
  text,
  "Caption",
  id,
  FontColor -> $muted,
  CellMargins -> {{72, 72}, {2, 18}},
  ShowCellBracket -> False
];

companionFigure[expression_, id_String] := companionCell[
  BoxData[ToBoxes[expression, StandardForm]],
  "Output",
  id,
  ShowCellBracket -> False,
  CellMargins -> {{24, 24}, {12, 8}},
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{12, 12}, {12, 12}},
  Background -> White,
  TextAlignment -> Center
];

companionDynamicCell[boxes_, id_String] := companionCell[
  BoxData[boxes],
  "Output",
  id,
  ShowCellBracket -> False,
  CellMargins -> {{12, 12}, {12, 8}},
  Background -> White,
  TextAlignment -> Center
];

companionCellHeading[text_String, id_String] := companionCell[
  TextData[{StyleBox["MATHEMATICA CELLS  ·  ", FontWeight -> "Bold",
    FontColor -> $blue], text}],
  "Text",
  id,
  ShowCellBracket -> False,
  CellMargins -> {{48, 48}, {10, 3}},
  TextAlignment -> Center,
  FontSize -> 10,
  FontColor -> $muted
];

SetAttributes[companionInputCell, HoldAllComplete];

(* Expressions written in this package are initially parsed in its private
   context.  Clean the finished boxes so displayed cells read like ordinary
   notebook code rather than an implementation trace.  Public paclet names
   remain explicitly qualified, which also makes those cells executable in a
   fresh kernel before Needs has changed the context path. *)
cleanCompanionBoxes[boxes_] := boxes /. text_String :> StringReplace[
  text,
  {
    "GogNotebookVisuals`Private`GogAvailableSizes" ->
      "GogFieldDynamics`GogAvailableSizes",
    "GogNotebookVisuals`Private`GogValidateSmallModels" ->
      "GogFieldDynamics`GogValidateSmallModels",
    "GogNotebookVisuals`Private`GogTransitionMatrix" ->
      "GogFieldDynamics`GogTransitionMatrix",
    "GogNotebookVisuals`Private`GogDiffusionState" ->
      "GogFieldDynamics`GogDiffusionState",
    "GogNotebookVisuals`Private`" -> ""
  }
];

companionInputCell[expression_, id_String] := companionCell[
  BoxData[cleanCompanionBoxes[ToBoxes[Defer[expression], StandardForm]]],
  "Input",
  id,
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{8, 8}, {7, 7}},
  Background -> $wash,
  FontSize -> 11
];

companionOutputCell[value_, id_String] := companionCell[
  BoxData[cleanCompanionBoxes[ToBoxes[value, StandardForm]]],
  "Output",
  id,
  CellFrame -> True,
  CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
  CellFrameMargins -> {{8, 8}, {7, 7}},
  Background -> Blend[{White, $orange}, 0.07],
  FontSize -> 11
];

SetAttributes[companionFormulaCell, HoldAllComplete];
companionFormulaCell[expression_, id_String] := companionCell[
  BoxData[cleanCompanionBoxes[ToBoxes[expression, TraditionalForm]]],
  "DisplayFormula",
  id,
  ShowCellBracket -> False,
  TextAlignment -> Center,
  FontSize -> 15
];

companionNavigationCell[] := Module[{items},
  items = {
    {"AT A GLANCE", "At a glance"},
    {"LOCAL MOVE", "Local move and energy"},
    {"CONSENSUS", "Finite-time consensus"},
    {"TRANSITIONS", "Transition probabilities"},
    {"DIFFUSION", "Diffusion laboratory"},
    {"ENUMERATION", "Finite enumeration"},
    {"SCOPE", "Scope and next steps"}
  };
  companionCell[
    TextData[Flatten[Riffle[
      Map[
        Function[item,
          With[{target = item[[2]]},
            ButtonBox[
              item[[1]],
              BaseStyle -> {"Hyperlink", FontFamily -> "Helvetica",
                FontWeight -> "Bold", FontColor -> $blue},
              ButtonFunction :> NotebookFind[
                InputNotebook[], target, All, CellStyle -> "Section"
              ],
              Evaluator -> Automatic,
              Method -> "Preemptive"
            ]
          ]
        ],
        items
      ],
      StyleBox["   •   ", FontColor -> $line]
    ]]],
    "Text",
    "GoGCompanionNavigation",
    ShowCellBracket -> False,
    CellFrame -> True,
    CellFrameStyle -> Directive[$line, AbsoluteThickness[1]],
    CellFrameMargins -> {{12, 12}, {8, 8}},
    Background -> $wash,
    TextAlignment -> Center,
    FontSize -> 8.5
  ]
];

pairValueGraphic[values_List, colors_List] := Graphics[
  {
    {Directive[$line, AbsoluteThickness[3]], Line[{{-0.65, 0}, {0.65, 0}}]},
    Table[
      {
        EdgeForm[Directive[White, AbsoluteThickness[2]]],
        colors[[index]],
        Disk[{{-0.65, 0}, {0.65, 0}}[[index]], 0.23],
        Text[
          Style[ToString[values[[index]]], 13, Bold, White,
            FontFamily -> "Helvetica"],
          {{-0.65, 0}, {0.65, 0}}[[index]]
        ]
      },
      {index, 2}
    ]
  },
  PlotRange -> {{-1, 1}, {-0.48, 0.48}},
  ImageSize -> {145, 72},
  Background -> White
];

varianceDropFigure[] := Framed[
  Column[
    {
      Style["ONE PAIR AVERAGE REMOVES THE ENTIRE LOCAL CONTRAST", 13,
        Bold, $navy, FontFamily -> "Helvetica"],
      Grid[
        {{
          Framed[
            Column[
              {
                Style["BEFORE", 9, Bold, $vermillion,
                  FontFamily -> "Helvetica"],
                pairValueGraphic[{-1, 3}, {$sky, $orange}],
                Style["pair mean = 1   •   contrast energy = 8", 9,
                  $muted, FontFamily -> "Helvetica"]
              },
              Alignment -> Center,
              Spacings -> 0.35
            ],
            Background -> White,
            FrameStyle -> Directive[$line],
            FrameMargins -> {{10, 10}, {8, 8}}
          ],
          Style["→", 24, Bold, $blue],
          Framed[
            Column[
              {
                Style["AFTER", 9, Bold, $green,
                  FontFamily -> "Helvetica"],
                pairValueGraphic[{1, 1}, {$green, $green}],
                Style["same mean   •   contrast energy = 0", 9,
                  $muted, FontFamily -> "Helvetica"]
              },
              Alignment -> Center,
              Spacings -> 0.35
            ],
            Background -> White,
            FrameStyle -> Directive[$line],
            FrameMargins -> {{10, 10}, {8, 8}}
          ]
        }},
        Alignment -> Center,
        Spacings -> {0.8, 0}
      ],
      Style[
        "exact loss = ((-1) - 3)^2 / 2 = 8",
        11,
        Bold,
        $blue,
        FontFamily -> "Helvetica"
      ]
    },
    Alignment -> Center,
    Spacings -> 0.8
  ],
  Background -> $wash,
  FrameStyle -> None,
  FrameMargins -> {{18, 18}, {14, 14}},
  ImageSize -> 500
];

transitionMatrixPlot[matrix_, title_String, subtitle_String] := Module[
  {ticks = MapIndexed[{First[#2], #1} &, "G" <> ToString[#] & /@ Range[5]]},
  Column[
    {
      Style[title, 11, Bold, $navy, FontFamily -> "Helvetica"],
      ArrayPlot[
        N[matrix],
        ColorFunction -> Function[value,
          Blend[{$wash, $sky, $blue}, Clip[value, {0, 1}]]
        ],
        ColorFunctionScaling -> False,
        PlotRange -> {0, 1},
        Mesh -> All,
        MeshStyle -> Directive[White, AbsoluteThickness[1]],
        Frame -> True,
        FrameTicks -> {{ticks, None}, {ticks, None}},
        FrameLabel -> {"target", "source"},
        ImageSize -> 190
      ],
      Style[subtitle, 8.5, $muted, FontFamily -> "Helvetica",
        TextAlignment -> Center]
    },
    Alignment -> Center,
    Spacings -> 0.35
  ]
];

transitionComparisonFigure[] := Module[{matrixA, matrixB},
  matrixA = GogFieldDynamics`GogTransitionMatrix[4, "A"];
  matrixB = GogFieldDynamics`GogTransitionMatrix[4, "B"];
  Framed[
    Column[
      {
        Style["THE SAME MOVES, DIFFERENT PROBABILITIES", 13, Bold, $navy,
          FontFamily -> "Helvetica"],
        Grid[
          {{
            transitionMatrixPlot[
              matrixA,
              "RULE A",
              "repeated outcomes retain extra weight\nnonuniform stationary law"
            ],
            transitionMatrixPlot[
              matrixB,
              "RULE B",
              "equal weight per distinct neighbour\nuniform stationary law"
            ]
          }},
          Alignment -> Center,
          Spacings -> {1.1, 0}
        ],
        Row[
          {
            Style["light", 8, $muted],
            Graphics[
              Table[
                {
                  Blend[{$wash, $sky, $blue}, k/14],
                  Rectangle[{k, 0}, {k + 1, 1}]
                },
                {k, 0, 14}
              ],
              PlotRange -> {{0, 15}, {0, 1}},
              ImagePadding -> 0,
              ImageSize -> {150, 9},
              AspectRatio -> 0.06
            ],
            Style["probability", 8, $muted],
            Style["dark", 8, $muted]
          },
          Spacer[6]
        ]
      },
      Alignment -> Center,
      Spacings -> 0.65
    ],
    Background -> White,
    FrameStyle -> Directive[$line],
    FrameMargins -> {{16, 16}, {12, 12}},
    ImageSize -> 500
  ]
];

companionPairAverage[n_Integer, {i_Integer, j_Integer}] := ReplacePart[
  IdentityMatrix[n],
  {
    {i, i} -> 1/2, {i, j} -> 1/2,
    {j, i} -> 1/2, {j, j} -> 1/2
  }
];

companionMatching[n_Integer, edges_List] :=
  Dot @@ (companionPairAverage[n, #] & /@ edges);

companionConsensusChecks[] := Module[{k4, q3},
  k4 = companionMatching[4, {{1, 3}, {2, 4}}] .
    companionMatching[4, {{1, 2}, {3, 4}}];
  q3 = companionMatching[8, {{1, 5}, {2, 6}, {3, 7}, {4, 8}}] .
    companionMatching[8, {{1, 3}, {2, 4}, {5, 7}, {6, 8}}] .
    companionMatching[8, {{1, 2}, {3, 4}, {5, 6}, {7, 8}}];
  {
    k4 === ConstantArray[1/4, {4, 4}],
    q3 === ConstantArray[1/8, {8, 8}]
  }
];

BuildCompanionNotebook[diffusionBoxes_] := Module[
  {pairLoss, validationSummary, clockChecks, diffusion, enumerationSummary,
    consensusChecks, cells},

  pairLoss = (x - y)^2/2;
  validationSummary = <|
    "AvailableSizes" -> GogFieldDynamics`GogAvailableSizes[],
    "ModelsValid" -> GogFieldDynamics`GogValidateSmallModels[]["Valid"]
  |>;
  clockChecks = With[
    {
      matrixA = GogFieldDynamics`GogTransitionMatrix[4, "A"],
      matrixB = GogFieldDynamics`GogTransitionMatrix[4, "B"]
    },
    <|
      "RuleASymmetric" -> SymmetricMatrixQ[matrixA],
      "RuleBSymmetric" -> SymmetricMatrixQ[matrixB],
      "RuleBUniformStationary" ->
        ConstantArray[1/5, 5] . matrixB === ConstantArray[1/5, 5]
    |>
  ];
  diffusion = GogFieldDynamics`GogDiffusionState[4, "A", 1, 4];
  enumerationSummary = Transpose[{
    Range[2, 14, 2],
    {2, 5, 17, 71, 388, 2592, 21096},
    {12, 60, 306, 1704, 11640, 93312, 886032}
  }];
  consensusChecks = companionConsensusChecks[];

  cells = {
    companionCell[
      "Whitehead Field Dynamics",
      "Title",
      "GoGCompanionTitle",
      TextAlignment -> Center,
      FontColor -> $navy
    ],
    companionCell[
      "A visual computational companion",
      "Subtitle",
      "GoGCompanionSubtitle",
      TextAlignment -> Center,
      FontColor -> $muted
    ],
    companionCell[
      "Alexander Kolpakov",
      "Author",
      "GoGCompanionAuthor",
      TextAlignment -> Center
    ],
    bannerCell[],
    companionNavigationCell[],
    companionText[
      "This notebook is a compact laboratory for the field update and the " <>
      "small exact graph-of-graphs models.  It favors executable cells, " <>
      "pictures, and one interactive experiment; proofs and asymptotic " <>
      "arguments remain in the LaTeX manuscript.",
      "GoGCompanionIntro"
    ],

    companionCell["At a glance", "Section", "GoGSectionOverview"],
    companionFigure[visualAbstract[], "GoGVisualAbstract"],
    companionCaption[
      "One local operation produces four related but inequivalent objects: " <>
      "the carrier field, a fixed-labelled move graph, the multiplicity " <>
      "chain, and the simple-support chain.",
      "GoGVisualAbstractCaption"
    ],

    companionCell[
      "Local move and energy",
      "Section",
      "GoGSectionLocalMove"
    ],
    companionText[
      "Select a non-loop carrier edge.  Its four exposed half-edges admit " <>
      "two compressed Whitehead resolutions.  Before the rewrite, the two " <>
      "endpoint values are replaced by their mean.",
      "GoGLocalMoveText"
    ],
    companionFigure[whiteheadMoveFigure[], "GoGWhiteheadMove"],
    companionCaption[
      "The local graph rewrite has two compressed resolutions; the field " <>
      "average is the same for either resolution.",
      "GoGWhiteheadMoveCaption"
    ],
    companionFigure[varianceDropFigure[], "GoGVarianceDrop"],
    companionFormulaCell[
      HoldForm[
        \[ScriptCapitalV][Subscript[A, i, j] f] ==
          \[ScriptCapitalV][f] -
            (Subscript[f, i] - Subscript[f, j])^2/2
      ],
      "GoGVarianceFormula"
    ],
    companionCaption[
      "Settlement permutations preserve sums and Euclidean norms, so this " <>
      "one-step identity survives passage to unlabelled representatives.",
      "GoGVarianceDropCaption"
    ],
    companionCellHeading["one-pair loss", "GoGPairLossHeading"],
    companionInputCell[
      FullSimplify[
        x^2 + y^2 - 2 ((x + y)/2)^2,
        Assumptions -> Element[{x, y}, Reals]
      ],
      "GoGPairLossInput"
    ],
    companionOutputCell[pairLoss, "GoGPairLossOutput"],

    companionCell[
      "Finite-time consensus",
      "Section",
      "GoGSectionConsensus"
    ],
    companionText[
      "Consensus means that every field coordinate equals the arithmetic " <>
      "mean of the initial field.  Finite-time consensus means that a finite " <>
      "product of pair-averaging matrices equals J_N.  Two matchings on K4 " <>
      "and three coordinate matchings on Q3 give explicit examples.",
      "GoGConsensusText"
    ],
    companionFigure[consensusFigure[], "GoGConsensusSchedules"],
    companionCaption[
      "The schedules double equal-value blocks at each stage: 1→2→4 on K4 " <>
      "and 1→2→4→8 on Q3.",
      "GoGConsensusSchedulesCaption"
    ],
    companionCellHeading["consensus products", "GoGConsensusHeading"],
    companionInputCell[
      pairAverage[n_, {i_, j_}] := ReplacePart[
        IdentityMatrix[n],
        {{i, i} -> 1/2, {i, j} -> 1/2,
          {j, i} -> 1/2, {j, j} -> 1/2}
      ];
      matching[n_, edges_] := Dot @@ (pairAverage[n, #] & /@ edges);
      k4 = matching[4, {{1, 3}, {2, 4}}] .
        matching[4, {{1, 2}, {3, 4}}];
      q3 = matching[8, {{1, 5}, {2, 6}, {3, 7}, {4, 8}}] .
        matching[8, {{1, 3}, {2, 4}, {5, 7}, {6, 8}}] .
        matching[8, {{1, 2}, {3, 4}, {5, 6}, {7, 8}}];
      {k4 === ConstantArray[1/4, {4, 4}],
        q3 === ConstantArray[1/8, {8, 8}]},
      "GoGConsensusInput"
    ],
    companionOutputCell[consensusChecks, "GoGConsensusOutput"],

    companionCell[
      "Transition probabilities",
      "Section",
      "GoGSectionClocks"
    ],
    companionText[
      "The bundled complete models have N=2,4,6,8.  Rule A keeps all 3N " <>
      "move outcomes and their multiplicities.  Rule B gives each distinct " <>
      "nonself target probability 1/(3N) and assigns the remaining " <>
      "probability to staying put.",
      "GoGClockText"
    ],
    companionCellHeading["load and validate", "GoGValidationHeading"],
    companionInputCell[
      PacletDirectoryLoad[
        FileNameJoin[{NotebookDirectory[], "Wolfram", "GogFieldDynamics"}]
      ];
      Needs["GogFieldDynamics`"];
      <|"AvailableSizes" -> GogAvailableSizes[],
        "ModelsValid" -> GogValidateSmallModels[]["Valid"]|>,
      "GoGValidationInput"
    ],
    companionOutputCell[validationSummary, "GoGValidationOutput"],
    companionFigure[transitionComparisonFigure[], "GoGTransitionComparison"],
    companionCaption[
      "Exact N=4 transition matrices shown as heat maps.  Rule A is not " <>
      "symmetric; Rule B is symmetric and has the uniform stationary law.",
      "GoGTransitionComparisonCaption"
    ],
    companionCellHeading["matrix checks", "GoGClockChecksHeading"],
    companionInputCell[
      pA = GogTransitionMatrix[4, "A"];
      pB = GogTransitionMatrix[4, "B"];
      <|"RuleASymmetric" -> SymmetricMatrixQ[pA],
        "RuleBSymmetric" -> SymmetricMatrixQ[pB],
        "RuleBUniformStationary" ->
          ConstantArray[1/5, 5] . pB === ConstantArray[1/5, 5]|>,
      "GoGClockChecksInput"
    ],
    companionOutputCell[clockChecks, "GoGClockChecksOutput"],

    companionCell[
      "Diffusion laboratory",
      "Section",
      "GoGSectionDiffusion"
    ],
    companionText[
      "Blue fill is the exact rational distribution after t graph-type steps.  " <>
      "The orange trail is one independently sampled path.  Change N, the " <>
      "rule, the starting graph type, or the seed and then play the time control.",
      "GoGDiffusionText"
    ],
    companionDynamicCell[diffusionBoxes, "GoGDiffusionLab"],
    companionCaption[
      "The distribution is matrix evolution, not a histogram of the sampled " <>
      "path.  SetReplace is an optional path engine; exact diffusion remains " <>
      "matrix based.",
      "GoGDiffusionLabCaption"
    ],
    companionCellHeading["default exact snapshot", "GoGDiffusionHeading"],
    companionInputCell[
      GogDiffusionState[4, "A", 1, 4],
      "GoGDiffusionInput"
    ],
    companionOutputCell[diffusion, "GoGDiffusionOutput"],

    companionCell[
      "Finite enumeration",
      "Section",
      "GoGSectionEnumeration"
    ],
    companionText[
      "Complete unlabelled enumeration grows rapidly.  The plot separates " <>
      "class counts from Rule-A slot records and uses a logarithmic vertical " <>
      "scale.  These are finite checks, not asymptotic evidence by themselves.",
      "GoGEnumerationText"
    ],
    companionFigure[enumerationFigure[], "GoGEnumerationGrowth"],
    companionCaption[
      "At N=14 the complete table contains 21,096 classes and 886,032 " <>
      "compressed Rule-A slot records.",
      "GoGEnumerationGrowthCaption"
    ],
    companionCellHeading["enumeration summary", "GoGEnumerationHeading"],
    companionInputCell[
      Transpose[{
        Range[2, 14, 2],
        {2, 5, 17, 71, 388, 2592, 21096},
        {12, 60, 306, 1704, 11640, 93312, 886032}
      }],
      "GoGEnumerationInput"
    ],
    companionOutputCell[enumerationSummary, "GoGEnumerationOutput"],

    companionCell[
      "Scope and next steps",
      "Section",
      "GoGSectionScope"
    ],
    companionText[
      "This companion deliberately omits theorem and proof text.  The full " <>
      "mathematical source is whitehead-field-dynamics.tex; the annotated " <>
      "cell transcript is whitehead-field-dynamics-computational-notes.tex; " <>
      "and docs/notebook.rst records the build and verification boundary.  " <>
      "The bundled quotient resource does not contain concrete carrier-edge " <>
      "choices or settlement maps, so it does not by itself define a " <>
      "pathwise transported-field cocycle.",
      "GoGScopeText"
    ]
  };

  Notebook[
    cells,
    WindowTitle -> "Whitehead Field Dynamics — Computational Companion",
    StyleDefinitions -> "Default.nb",
    TaggingRules -> <|
      "GoGNotebook" -> <|
        "Edition" -> "ComputationalCompanion",
        "SchemaVersion" -> 1,
        "Purpose" -> "Concise executable visual companion"
      |>
    |>,
    Saveable -> True,
    WindowSize -> {1040, 900},
    PrintingOptions -> {"PrintCellBrackets" -> False}
  ]
];

End[];
EndPackage[];
