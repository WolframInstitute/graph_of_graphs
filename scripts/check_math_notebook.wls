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
paperPacletDirectory = FileNameJoin[
  {repositoryDirectory, "Wolfram", "GogFieldDynamics"}
];

If[! FileExistsQ[sourceFile], fail["source file not found: " <> sourceFile]];
If[! FileExistsQ[notebookFile], fail["notebook file not found: " <> notebookFile]];
If[! DirectoryQ[paperPacletDirectory], fail["paper paclet not found"]];

Quiet[
  Check[
    PacletDirectoryLoad[paperPacletDirectory];
    Needs["GogFieldDynamics`"],
    fail["the local GogFieldDynamics paclet could not be loaded"]
  ]
];
smallModelValidation = Quiet[
  Check[GogFieldDynamics`GogValidateSmallModels[], $Failed]
];
If[
  ! AssociationQ[smallModelValidation] ||
    ! TrueQ[smallModelValidation["Valid"]],
  fail["the bundled small graph-of-graphs models failed validation"]
];

If[Quiet[Check[PacletFind["WolframInstitute/MathNotebook"], {}]] === {},
  mathNotebookRepository = FileNameJoin[
    {$UserBaseDirectory, "Paclets", "Repository"}
  ];
  mathNotebookCandidates = If[
    DirectoryQ[mathNotebookRepository],
    Select[
      FileNames[
        "WolframInstitute__MathNotebook-*",
        mathNotebookRepository
      ],
      DirectoryQ
    ],
    {}
  ];
  Scan[
    Function[path, Quiet[Check[PacletDirectoryLoad[path], Null]]],
    mathNotebookCandidates
  ];
];

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
      Pause[6];
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
            "GoGDiffusionLab", "GoGEnumerationGrowth"
          },
          id_ /; ! FreeQ[notebook, id]
        ],
        "DiffusionDefinitionsEmbedded" ->
          (! FreeQ[
            notebook,
            HoldPattern[GogFieldDynamics`Private`$smallModelCache]
          ]),
        "SetReplaceVersion" -> GogFieldDynamics`GogSetReplaceVersion[],
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
If[measurement["PresentationElements"] =!= 7,
  fail["front-end normalization lost a required presentation element"]
];
If[! TrueQ[measurement["DiffusionDefinitionsEmbedded"]],
  fail["the diffusion lab is missing its self-contained definitions"]
];
If[! TrueQ[measurement["ExactLaTeXRoundTrip"]],
  fail["front-end normalization changed the LaTeX round trip"]
];

Print[measurement];
Exit[0];
