#!/usr/bin/env wolframscript

(* Open the committed companion in a real front end and verify that it stays
   concise, executable, visual, and printable. *)

fail[message_String] := (
  WriteString["stderr", "Companion notebook check failed: " <> message <> "\n"];
  Exit[1]
);

scriptFile = If[
  StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[{Directory[], "scripts", "check_math_notebook.wls"}]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
notebookFile = FileNameJoin[
  {repositoryDirectory, "whitehead-field-dynamics.nb"}
];
renderedPDF = FileNameJoin[
  {$TemporaryDirectory, "whitehead-field-dynamics-companion-check.pdf"}
];
paperPacletDirectory = FileNameJoin[
  {repositoryDirectory, "Wolfram", "GogFieldDynamics"}
];

If[! FileExistsQ[notebookFile],
  fail["notebook file not found: " <> notebookFile]
];
If[! DirectoryQ[paperPacletDirectory], fail["local paclet not found"]];

Quiet @ Check[
  PacletDirectoryLoad[paperPacletDirectory];
  Needs["GogFieldDynamics`"],
  fail["the local GogFieldDynamics paclet could not be loaded"]
];
smallModelValidation = Quiet @ Check[
  GogFieldDynamics`GogValidateSmallModels[],
  $Failed
];
If[
  ! AssociationQ[smallModelValidation] ||
    ! TrueQ[smallModelValidation["Valid"]],
  fail["the bundled small graph-of-graphs models failed validation"]
];

requiredVisualIDs = {
  "GoGVisualAbstract",
  "GoGWhiteheadMove",
  "GoGVarianceDrop",
  "GoGConsensusSchedules",
  "GoGTransitionComparison",
  "GoGDiffusionLab",
  "GoGEnumerationGrowth"
};

measurement = Quiet @ Check[
  UsingFrontEnd[
    notebookObject = NotebookOpen[notebookFile, Visible -> False];
    Pause[4];
    notebook = NotebookGet[notebookObject];
    styleDefinitions = CurrentValue[notebookObject, StyleDefinitions];
    pdf = Export[renderedPDF, notebookObject];
    NotebookClose[notebookObject];

    cells = Cases[notebook, _Cell, Infinity];
    textStrings = Cases[
      notebook,
      Cell[text_String, style : ("Text" | "Caption"), ___] :> text,
      Infinity
    ];
    theoremLikeCount = Count[
      notebook,
      Cell[_, style_String, ___] /;
        MemberQ[
          {"Theorem", "Proof", "Lemma", "Proposition", "Corollary",
            "Conjecture", "Reference"},
          style
        ],
      Infinity
    ];

    <|
      "NotebookHead" -> Head[notebook],
      "StyleDefinitions" -> styleDefinitions,
      "RenderedPDF" -> pdf,
      "RenderedPDFBytes" ->
        If[FileExistsQ[renderedPDF], FileByteCount[renderedPDF], 0],
      "Cells" -> Length[cells],
      "Sections" -> Count[notebook, Cell[_, "Section", ___], Infinity],
      "InputCells" -> Count[notebook, Cell[_, "Input", ___], Infinity],
      "OutputCells" -> Count[notebook, Cell[_, "Output", ___], Infinity],
      "NarrativeCharacters" -> Total[StringLength /@ textStrings],
      "PaperStyleCells" -> theoremLikeCount,
      "NativeVisuals" -> Count[
        requiredVisualIDs,
        id_ /; ! FreeQ[notebook, id]
      ],
      "CompanionMetadata" -> ! FreeQ[notebook, "ComputationalCompanion"],
      "DiffusionDefinitionsEmbedded" -> ! FreeQ[
        notebook,
        HoldPattern[GogFieldDynamics`Private`$smallModelCache]
      ],
      "SetReplaceVersion" -> GogFieldDynamics`GogSetReplaceVersion[]
    |>
  ],
  $Failed
];

If[! AssociationQ[measurement],
  fail["the Mathematica front end did not report"]
];
If[measurement["NotebookHead"] =!= Notebook,
  fail["the saved artifact did not open as a Notebook"]
];
If[
  ! StringContainsQ[
    ToString[measurement["StyleDefinitions"], InputForm],
    "Default.nb"
  ],
  fail["the built-in Default notebook stylesheet did not resolve"]
];
If[measurement["RenderedPDFBytes"] <= 0,
  fail["the front end did not render a PDF"]
];
If[! Between[measurement["Cells"], {35, 80}],
  fail["the notebook is no longer a concise companion"]
];
If[measurement["Sections"] =!= 7,
  fail["the notebook section map changed unexpectedly"]
];
If[measurement["InputCells"] < 6 || measurement["OutputCells"] < 10,
  fail["the notebook lost executable or output cells"]
];
If[measurement["NarrativeCharacters"] > 9000,
  fail["the notebook narrative grew too close to the full manuscript"]
];
If[measurement["PaperStyleCells"] =!= 0,
  fail["paper-style theorem/proof cells leaked into the companion"]
];
If[measurement["NativeVisuals"] =!= Length[requiredVisualIDs],
  fail["a required native visual is missing"]
];
If[! TrueQ[measurement["CompanionMetadata"]],
  fail["the artifact is not tagged as a computational companion"]
];
If[! TrueQ[measurement["DiffusionDefinitionsEmbedded"]],
  fail["the diffusion lab is missing its self-contained definitions"]
];

Print[measurement];
Exit[0];
