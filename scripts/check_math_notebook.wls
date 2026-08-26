#!/usr/bin/env wolframscript

(* Open the committed notebook in a real front end and verify its presentation
   layer without writing generated files into the repository. *)

fail[message_String] := (
  WriteString["stderr", "MathNotebook check failed: " <> message <> "\n"];
  Exit[1]
);

scriptFile = If[StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[{Directory[], "scripts", "check_math_notebook.wls"}]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
sourceFile = FileNameJoin[{repositoryDirectory, "whitehead-field-dynamics.tex"}];
notebookFile = FileNameJoin[{repositoryDirectory, "whitehead-field-dynamics.nb"}];
renderedPDF = FileNameJoin[{$TemporaryDirectory, "whitehead-field-dynamics-notebook-check.pdf"}];

If[! FileExistsQ[sourceFile], fail["source file not found: " <> sourceFile]];
If[! FileExistsQ[notebookFile], fail["notebook file not found: " <> notebookFile]];

Quiet[
  Check[
    Needs["WolframInstitute`MathNotebook`"],
    fail["MathNotebook is not installed"]
  ]
];

sourceStream = Quiet[
  Check[OpenRead[sourceFile, CharacterEncoding -> "UTF-8"], $Failed]
];
If[Head[sourceStream] =!= InputStream, fail["could not open the LaTeX source"]];
source = Quiet[Check[ReadString[sourceStream], $Failed]];
Close[sourceStream];
If[! StringQ[source], fail["could not read the LaTeX source"]];

measurement = Quiet[
  Check[
    UsingFrontEnd[
      notebookObject = NotebookOpen[notebookFile, Visible -> False];
      notebook = NotebookGet[notebookObject];
      styleDefinitions = CurrentValue[notebookObject, StyleDefinitions];
      textFontSize = CurrentValue[
        notebookObject,
        {StyleDefinitions, "Text", FontSize}
      ];
      pdf = Export[renderedPDF, notebookObject];
      NotebookClose[notebookObject];
      <|
        "NotebookHead" -> Head[notebook],
        "StyleDefinitions" -> styleDefinitions,
        "TextFontSize" -> textFontSize,
        "RenderedPDF" -> pdf,
        "RenderedPDFBytes" ->
          If[FileExistsQ[renderedPDF], FileByteCount[renderedPDF], 0],
        "PresentationElements" -> Count[
          {
            "GoGBanner", "GoGNavigation", "GoGVisualAbstract",
            "GoGWhiteheadMove", "GoGConsensusSchedules",
            "GoGEnumerationGrowth"
          },
          id_ /; ! FreeQ[notebook, id]
        ],
        "ExactLaTeXRoundTrip" ->
          (WolframInstitute`MathNotebook`ExportLaTeXDocument[notebook] === source)
      |>
    ],
    $Failed
  ]
];

If[! AssociationQ[measurement], fail["the Mathematica front end did not report"]];
If[measurement["NotebookHead"] =!= Notebook,
  fail["the saved artifact did not open as a Notebook"]
];
If[! StringContainsQ[
    ToString[measurement["StyleDefinitions"], InputForm],
    "PlainArticle.nb"
  ],
  fail["the MathNotebook PlainArticle stylesheet did not resolve"]
];
If[measurement["RenderedPDFBytes"] <= 0,
  fail["the front end did not render a PDF"]
];
If[measurement["PresentationElements"] =!= 6,
  fail["front-end normalization lost a required presentation element"]
];
If[! TrueQ[measurement["ExactLaTeXRoundTrip"]],
  fail["front-end normalization changed the LaTeX round trip"]
];

Print[measurement];
Exit[0];
