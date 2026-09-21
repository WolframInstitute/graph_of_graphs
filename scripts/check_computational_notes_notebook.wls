#!/usr/bin/env wolframscript

(* Verify that the executable computational-notes mini-notebook opens,
   renders, and evaluates from its setup cell through its final self-test. *)

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
renderedPDF = FileNameJoin[
  {$TemporaryDirectory, "whitehead-field-dynamics-computational-notes-check.pdf"}
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
If[Length[inputBoxes] =!= 16,
  fail["expected 16 executable input cells, found " <>
    ToString[Length[inputBoxes]]]
];

(* This checker runs in a fresh -noinit kernel.  The first notebook cell must
   load the local paclet; later cells are parsed and evaluated one at a time. *)
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
selfTestResult = Last[evaluationResults];
If[
  ! AssociationQ[setupResult] ||
    setupResult["GogFieldDynamicsVersion"] =!= "0.2.0" ||
    ! TrueQ[setupResult["PacletLoaded"]],
  fail["the visible setup cell did not load the expected local paclet"]
];
If[
  ! AssociationQ[selfTestResult] ||
    ! TrueQ[selfTestResult["AllTestsPassed"]] ||
    ! AllTrue[Values[selfTestResult["Checks"]], TrueQ],
  fail["the visible final self-test did not pass"]
];

requiredIDs = {
  "setupInput",
  "pair-lossInput",
  "averaging-matrixInput",
  "resource-summaryInput",
  "validationInput",
  "rule-a-countsInput",
  "rule-a-stationaryInput",
  "fixed-clock-bInput",
  "symmetry-stationarityInput",
  "b-versus-jumpInput",
  "diffusion-aInput",
  "diffusion-bInput",
  "seeded-pathInput",
  "matching-productsInput",
  "k4-productInput",
  "self-testInput"
};
missingIDs = Select[requiredIDs, FreeQ[notebook, #] &];
If[missingIDs =!= {},
  fail["missing executable cell identifiers: " <>
    StringRiffle[missingIDs, ", "]]
];

measurement = Quiet @ Check[
  UsingFrontEnd[
    notebookObject = NotebookOpen[notebookFile, Visible -> False];
    Pause[3];
    openedNotebook = NotebookGet[notebookObject];
    styleDefinitions = CurrentValue[notebookObject, StyleDefinitions];
    pdf = Export[renderedPDF, notebookObject];
    NotebookClose[notebookObject];

    narrativeStrings = Cases[
      openedNotebook,
      Cell[text_String, style : ("Text" | "Caption" | "Item" |
          "ItemNumbered"), ___] :> text,
      Infinity
    ];

    <|
      "NotebookHead" -> Head[openedNotebook],
      "StyleDefinitions" -> styleDefinitions,
      "RenderedPDF" -> pdf,
      "RenderedPDFBytes" ->
        If[FileExistsQ[renderedPDF], FileByteCount[renderedPDF], 0],
      "Cells" -> Count[openedNotebook, _Cell, Infinity],
      "Sections" ->
        Count[openedNotebook, Cell[_, "Section", ___], Infinity],
      "InputCells" ->
        Count[openedNotebook, Cell[_, "Input", ___], Infinity],
      "OutputCells" ->
        Count[openedNotebook, Cell[_, "Output", ___], Infinity],
      "NarrativeCharacters" -> Total[StringLength /@ narrativeStrings],
      "SourceMetadata" ->
        ! FreeQ[
          openedNotebook,
          "whitehead-field-dynamics-computational-notes.tex"
        ],
      "SelfTestMetadata" ->
        ! FreeQ[openedNotebook, "ExecutableMiniNotebook"]
    |>
  ],
  $Failed
];

If[! AssociationQ[measurement],
  fail["the Mathematica front end did not return notebook measurements"]
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
If[measurement["RenderedPDFBytes"] <= 0,
  fail["the front end did not render a nonempty PDF"]
];
If[measurement["Sections"] =!= 11,
  fail["expected 11 report sections"]
];
If[measurement["InputCells"] =!= 16 || measurement["OutputCells"] < 16,
  fail["the executable cell pairs changed unexpectedly"]
];
If[! Between[measurement["NarrativeCharacters"], {7000, 18000}],
  fail["the notebook no longer resembles the mini-report narrative"]
];
If[
  ! TrueQ[measurement["SourceMetadata"]] ||
    ! TrueQ[measurement["SelfTestMetadata"]],
  fail["source or self-test metadata is missing"]
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
    "AllTestsPassed" -> selfTestResult["AllTestsPassed"],
    "NotebookSHA256" -> FileHash[notebookFile, "SHA256", "HexString"]
  |>
];

Exit[0];
