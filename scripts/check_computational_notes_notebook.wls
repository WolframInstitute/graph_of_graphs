#!/usr/bin/env wolframscript

(* Verify that the computational notebook is readable and that every visible
   input cell evaluates in order in a fresh kernel. *)

fail[message_String] := (
  WriteString[
    "stderr",
    "Computational-notes notebook check failed: " <> message <> "\n"
  ];
  Exit[1]
);

scriptFile = If[
  StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[
    {Directory[], "scripts", "check_computational_notes_notebook.wls"}
  ]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
notebookFile = FileNameJoin[
  {repositoryDirectory, "whitehead-field-dynamics-computational-notes.nb"}
];

If[! FileExistsQ[notebookFile],
  fail["notebook file not found: " <> notebookFile]
];
SetDirectory[repositoryDirectory];

notebook = Quiet[Check[Get[notebookFile], $Failed]];
If[Head[notebook] =!= Notebook,
  fail["the committed file is not a readable Notebook expression"]
];

inputBoxes = Cases[
  notebook,
  Cell[BoxData[boxes_], "Input", ___] :> boxes,
  Infinity
];
If[Length[inputBoxes] =!= 19,
  fail["expected 19 executable input cells, found " <>
    ToString[Length[inputBoxes]]]
];

(* This checker runs in a fresh -noinit kernel.  The first notebook cell must
   load the local package; later cells are parsed and evaluated one at a time. *)
evaluationResults = MapIndexed[
  Function[{boxes, position},
    result = Quiet[Check[ToExpression[boxes, StandardForm], $Failed]];
    If[result === $Failed,
      fail["evaluation failed at input cell " <> ToString[First[position]]]
    ];
    result
  ],
  inputBoxes
];

setupResult = First[evaluationResults];
If[
  ! AssociationQ[setupResult] ||
    setupResult["GogFieldDynamicsVersion"] =!= "0.2.0" ||
    ! TrueQ[setupResult["PackageLoaded"]],
  fail["the visible setup cell did not load the expected local package"]
];

notebookChecks = <|
  "AvailableSizes" -> (GogAvailableSizes[] === {2, 4, 6, 8}),
  "ModelsValidate" -> TrueQ[GogValidateSmallModels[]["Valid"]],
  "PairLoss" -> (
    FullSimplify[
      x^2 + y^2 - 2 ((x + y)/2)^2,
      Assumptions -> Element[{x, y}, Reals]
    ] === (x - y)^2/2
  ),
  "Projection" -> And @@ {
    SymmetricMatrixQ[a],
    a . a === a,
    a . ConstantArray[1, 4] === ConstantArray[1, 4]
  },
  "RuleARowSums" ->
    (Total /@ countsA === ConstantArray[12, 5]),
  "RuleBUniform" ->
    (SymmetricMatrixQ[pB] &&
      ConstantArray[1/5, 5] . pB === ConstantArray[1/5, 5]),
  "RuleBGap" ->
    (FullSimplify[1 - eigenvaluesB[[2]]] === (3 - Sqrt[5])/24),
  "DiffusionMass" -> (Total[p4A] === 1 && Total[p4B] === 1),
  "SeededTrajectory" ->
    (samplePath ===
      {1, 28, 24, 29, 29, 9, 54, 9, 54, 54, 34, 54, 25, 54,
       52, 20, 27, 20, 61, 61, 71, 69, 63, 63, 61, 61, 63, 36,
       37, 66, 37, 49, 64, 64, 64, 64, 64, 49, 49, 49, 45, 26,
       26, 26, 58, 51, 53, 55, 48}),
  "FiniteConsensus" ->
    (k4Product === ConstantArray[1/4, {4, 4}] &&
      q3Product === ConstantArray[1/8, {8, 8}])
|>;
If[! AllTrue[Values[notebookChecks], TrueQ],
  fail["the mathematical checks did not all pass"]
];

requiredIDs = {
  "setupInput",
  "pair-lossInput",
  "averaging-matrixInput",
  "resource-summaryInput",
  "validationInput",
  "class-atlasInput",
  "class-explorerInput",
  "rule-a-countsInput",
  "rule-a-stationaryInput",
  "rule-b-matrixInput",
  "symmetry-stationarityInput",
  "rule-b-spectrumInput",
  "b-versus-jumpInput",
  "diffusion-aInput",
  "diffusion-bInput",
  "diffusion-pictureInput",
  "seeded-pathInput",
  "matching-productsInput",
  "k4-productInput"
};
missingIDs = Select[requiredIDs, FreeQ[notebook, #] &];
If[missingIDs =!= {},
  fail["missing executable cell identifiers: " <>
    StringRiffle[missingIDs, ", "]]
];

atlasResult = evaluationResults[[2]];
inspectorResult = evaluationResults[[3]];
diffusionPictureResult = evaluationResults[[16]];
diffusionPictureText = ToString[diffusionPictureResult, InputForm];
If[
  ! MatchQ[atlasResult, _Column] ||
    Count[atlasResult, _Graph, Infinity] =!= 5 ||
    ! AllTrue[Cases[atlasResult, _Graph, Infinity], EdgeCount[#] === 6 &],
  fail["the N=4 graph-of-graphs atlas is missing its five carrier drawings"]
];
If[
  ! MatchQ[inspectorResult, _DynamicModule] ||
    ! StringContainsQ[
      ToString[inspectorResult, InputForm],
      "classSupportGraphic"
    ],
  fail["the click-to-inspect graph-of-graphs output is missing"]
];
clickableVertexCounts = Table[
  Count[
    ToExpression[
      "GogFieldDynamics`Private`classSupportGraphic[" <>
        ToString[n] <> ",1,Identity]",
      InputForm
    ],
    _EventHandler,
    Infinity
  ],
  {n, GogAvailableSizes[]}
];
If[clickableVertexCounts =!= {2, 5, 17, 71},
  fail["the class inspector does not expose every bundled GoG vertex"]
];
carrierEdgeCounts = Table[
  Union @ Table[
    EdgeCount @ ToExpression[
      "GogFieldDynamics`Private`classCarrierGraph[" <>
        ToString[n] <> "," <> ToString[index] <> "]",
      InputForm
    ],
    {index, GogSmallModel[n]["NodeCount"]}
  ],
  {n, GogAvailableSizes[]}
];
If[carrierEdgeCounts =!= {{3}, {6}, {9}, {12}},
  fail["a class-inspector drawing does not represent a cubic multigraph"]
];
mediumLayoutCoordinates = ToExpression[
  "GogFieldDynamics" <> FromCharacterCode[96] <> "Private" <>
    FromCharacterCode[96] <> "labCoordinates[6]"
];
mediumLayoutSeparation = Min[
  EuclideanDistance @@@ Subsets[mediumLayoutCoordinates, {2}]
];
mediumLayoutSpan =
  (Max[#] - Min[#] &) /@ Transpose[mediumLayoutCoordinates];
If[
  mediumLayoutSeparation <= 0.30 || mediumLayoutSpan[[2]] <= 2.2,
  fail["the 17-vertex graph-of-graphs layout is still too crowded"]
];
largeLayoutCoordinates = ToExpression[
  "GogFieldDynamics" <> FromCharacterCode[96] <> "Private" <>
    FromCharacterCode[96] <> "labCoordinates[8]"
];
largeLayoutSeparation = Min[
  EuclideanDistance @@@ Subsets[largeLayoutCoordinates, {2}]
];
largeLayoutSpan =
  (Max[#] - Min[#] &) /@ Transpose[largeLayoutCoordinates];
If[
  largeLayoutSeparation <= 0.07 || Min[largeLayoutSpan] <= 2.2,
  fail["the 71-vertex graph-of-graphs layout is still too crowded"]
];
If[
  ! MatchQ[diffusionPictureResult, _Column] ||
    ! StringContainsQ[
      diffusionPictureText,
      "Blue encodes the exact rational distribution at t = 12."
    ] ||
    ! StringContainsQ[
      diffusionPictureText,
      "Sample path: 48 steps, seed 273"
    ] ||
    Count[diffusionPictureResult, _Disk, Infinity] < 71 ||
    Count[diffusionPictureResult, _Grid, Infinity] < 1,
  fail["the exact-distribution and sampled-path picture is missing"]
];

If[
  ! FreeQ[notebook, "EXECUTABLE MINI-NOTEBOOK"] ||
    ! FreeQ[notebook, "MATHEMATICA CELLS"] ||
    ! FreeQ[notebook, "NATIVE WOLFRAM LAB"] ||
    ! FreeQ[notebook, "EXACT DIFFUSION"] ||
    ! FreeQ[notebook, "Interpretation limits"] ||
    ! FreeQ[notebook, "Reproduction and self-test"] ||
    ! FreeQ[notebook, "AllTestsPassed"],
  fail["deprecated product-style notebook labels are still present"]
];

displayFormulaBoxes = Cases[
  notebook,
  Cell[BoxData[boxes_], "DisplayFormula", ___] :> boxes,
  Infinity
];
displayFormulaText = ToString[displayFormulaBoxes, InputForm];
If[
  AnyTrue[
    {"ConstantArray", "IdentityMatrix", "MatrixForm", "&&"},
    StringContainsQ[displayFormulaText, #] &
  ],
  fail["a displayed equation still contains programming syntax"]
];

styleDefinitions = Replace[
  notebook,
  Notebook[_, options___] :> (StyleDefinitions /. {options})
];
narrativeStrings = Cases[
  notebook,
  Cell[text_String, style : ("Text" | "Caption" | "Item" |
      "ItemNumbered"), ___] :> text,
  Infinity
];
measurement = <|
  "NotebookHead" -> Head[notebook],
  "StyleDefinitions" -> styleDefinitions,
  "Cells" -> Count[notebook, _Cell, Infinity],
  "Sections" -> Count[notebook, Cell[_, "Section", ___], Infinity],
  "InputCells" -> Count[notebook, Cell[_, "Input", ___], Infinity],
  "OutputCells" -> Count[notebook, Cell[_, "Output", ___], Infinity],
  "NarrativeCharacters" -> Total[StringLength /@ narrativeStrings],
  "ClassAtlasGraphs" -> Count[atlasResult, _Graph, Infinity],
  "ClickableVertices" -> clickableVertexCounts,
  "CarrierEdgeCounts" -> carrierEdgeCounts,
  "MediumLayoutMinimumSeparation" -> mediumLayoutSeparation,
  "MediumLayoutSpan" -> mediumLayoutSpan,
  "LargeLayoutMinimumSeparation" -> largeLayoutSeparation,
  "LargeLayoutSpan" -> largeLayoutSpan,
  "DiffusionPicture" -> True,
  "SourceMetadata" ->
    ! FreeQ[notebook, "whitehead-field-dynamics-computational-notes.tex"],
  "EditionMetadata" -> ! FreeQ[notebook, "ComputationalNotes"]
|>;

If[! AssociationQ[measurement],
  fail["the notebook measurement pass did not return an association"]
];
If[measurement["NotebookHead"] =!= Notebook,
  fail["the saved artifact did not reopen as a Notebook"]
];
If[
  ! StringContainsQ[
    ToString[measurement["StyleDefinitions"], InputForm],
    "Default.nb"
  ],
  fail["the built-in Default.nb stylesheet did not resolve"]
];
If[measurement["Sections"] =!= 9,
  fail["expected 9 report sections"]
];
If[measurement["InputCells"] =!= 19 || measurement["OutputCells"] < 19,
  fail["the executable cell pairs changed unexpectedly"]
];
If[! Between[measurement["NarrativeCharacters"], {4500, 11000}],
  fail["the notebook no longer resembles the mini-report narrative"]
];
If[
  ! TrueQ[measurement["SourceMetadata"]] ||
    ! TrueQ[measurement["EditionMetadata"]],
  fail["source or edition metadata is missing"]
];

serialized = FromCharacterCode[
  BinaryReadList[notebookFile, "Byte"],
  "UTF-8"
];
If[StringContainsQ[serialized, "build_computational_notes_notebook`Private`"],
  fail["a private builder context leaked into visible notebook boxes"]
];

Print @ Join[
  measurement,
  <|
    "SequentialEvaluation" -> True,
    "ChecksPassed" -> AllTrue[Values[notebookChecks], TrueQ],
    "NotebookSHA256" -> FileHash[notebookFile, "SHA256", "HexString"]
  |>
];

Exit[0];
