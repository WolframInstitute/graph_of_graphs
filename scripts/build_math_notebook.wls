#!/usr/bin/env wolframscript

(* Build the concise executable companion notebook. *)

$requiredGogFieldDynamicsVersion = "0.2.0";
$minimumWolframVersion = 14.3;

fail[message_String] := (
  WriteString["stderr", "Companion notebook build failed: " <> message <> "\n"];
  Exit[1]
);

progress[message_String] := Print["Companion notebook build: " <> message];

scriptFile = If[
  StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[{Directory[], "scripts", "build_math_notebook.wls"}]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
notebookFile = FileNameJoin[
  {repositoryDirectory, "whitehead-field-dynamics.nb"}
];
visualsFile = FileNameJoin[
  {repositoryDirectory, "scripts", "notebook_visuals.wl"}
];
paperPacletDirectory = FileNameJoin[
  {repositoryDirectory, "Wolfram", "GogFieldDynamics"}
];

If[! FileExistsQ[visualsFile],
  fail["notebook source not found: " <> visualsFile]
];
If[! DirectoryQ[paperPacletDirectory],
  fail["local paclet not found: " <> paperPacletDirectory]
];
If[$VersionNumber < $minimumWolframVersion,
  fail["Wolfram Language 14.3 or newer is required; found " <> $Version]
];

Quiet @ Check[
  PacletDirectoryLoad[paperPacletDirectory],
  fail["the local GogFieldDynamics paclet directory could not be loaded"]
];
Quiet @ Check[
  Needs["GogFieldDynamics`"],
  fail["the local GogFieldDynamics context could not be loaded"]
];

paperPaclet = Quiet[Check[PacletObject["GogFieldDynamics"], $Failed]];
If[Head[paperPaclet] =!= PacletObject,
  fail["the GogFieldDynamics paclet could not be resolved"]
];
paperPacletVersion = paperPaclet["Version"];
If[paperPacletVersion =!= $requiredGogFieldDynamicsVersion,
  fail[
    "GogFieldDynamics " <> $requiredGogFieldDynamicsVersion <>
    " is required; found " <> ToString[paperPacletVersion]
  ]
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

progress["boxing the self-contained diffusion laboratory"];
diffusionExplorerBoxes = Quiet @ Check[
  ToBoxes[GogFieldDynamics`GogDiffusionExplorer[], StandardForm],
  $Failed
];
If[
  diffusionExplorerBoxes === $Failed ||
    ! AnyTrue[
      Cases[diffusionExplorerBoxes, _String, Infinity],
      StringContainsQ[#, "GRAPH-OF-GRAPHS DIFFUSION LAB"] &
    ],
  fail["the diffusion explorer could not be boxed"]
];

progress["loading the companion notebook source"];
visualsLoaded = Quiet[Check[Get[visualsFile], $Failed]];
If[
  visualsLoaded === $Failed ||
    ! NameQ["GogNotebookVisuals`BuildCompanionNotebook"],
  fail["the companion notebook constructor could not be loaded"]
];

progress["constructing the concise notebook"];
notebook = Quiet @ Check[
  GogNotebookVisuals`BuildCompanionNotebook[diffusionExplorerBoxes],
  $Failed
];
If[Head[notebook] =!= Notebook,
  fail["the companion constructor did not return a Notebook"]
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
missingVisualIDs = Select[requiredVisualIDs, FreeQ[notebook, #] &];
If[missingVisualIDs =!= {},
  fail[
    "required visual outputs are absent: " <>
      StringRiffle[missingVisualIDs, ", "]
  ]
];

cellCount = Count[notebook, _Cell, Infinity];
sectionCount = Count[notebook, Cell[_, "Section", ___], Infinity];
inputCount = Count[notebook, Cell[_, "Input", ___], Infinity];
outputCount = Count[notebook, Cell[_, "Output", ___], Infinity];
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

If[! Between[cellCount, {35, 80}],
  fail[
    "the companion should contain 35–80 cells, found " <>
      ToString[cellCount]
  ]
];
If[sectionCount =!= 7,
  fail["the companion should contain seven sections"]
];
If[inputCount < 6 || outputCount < 10,
  fail["the companion is missing executable or visual cells"]
];
If[theoremLikeCount =!= 0,
  fail["paper-style theorem/proof cells leaked into the companion"]
];

(* Seed stable top-level UUIDs, then normalize any UUIDs introduced by the
   front end.  Equal-length replacements preserve notebook cache offsets. *)
uuidFromSeed[seed_] := Module[{hex},
  hex = StringTake[
    IntegerString[Hash[{"gog-companion-notebook", seed}, "SHA256"], 16, 64],
    32
  ];
  StringRiffle[
    (StringTake[hex, #] &) /@ {
      {1, 8}, {9, 12}, {13, 16}, {17, 20}, {21, 32}
    },
    "-"
  ]
];

withExpressionUUID[expression_, uuid_String] := Append[
  DeleteCases[expression, HoldPattern[ExpressionUUID -> _], {1}],
  ExpressionUUID -> uuid
];

notebook = notebook /. Notebook[documentCells_List, options___] :>
  withExpressionUUID[
    Notebook[
      MapIndexed[
        withExpressionUUID[
          #1,
          uuidFromSeed[{"top-level-cell", First[#2]}]
        ] &,
        documentCells
      ],
      options
    ],
    uuidFromSeed["notebook-root"]
  ];

$uuidPattern = RegularExpression[
  "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-" <>
  "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
];

normalizeSerializedUUIDs[file_String] := Module[
  {input, bytes, serialized, existing, replacements, replacementAssociation,
    normalized, output},
  input = Quiet[Check[OpenRead[file, BinaryFormat -> True], $Failed]];
  If[Head[input] =!= InputStream,
    fail["could not reopen the serialized notebook"]
  ];
  bytes = Quiet[Check[BinaryReadList[input, "Byte"], $Failed]];
  Close[input];
  If[! ListQ[bytes], fail["could not read the serialized notebook bytes"]];
  serialized = FromCharacterCode[bytes, "UTF-8"];
  existing = DeleteDuplicates[StringCases[serialized, $uuidPattern]];
  If[existing === {}, fail["the serialized notebook contains no UUIDs"]];
  replacements = MapIndexed[#1 -> uuidFromSeed[First[#2]] &, existing];
  replacementAssociation = Association[replacements];
  normalized = StringReplace[
    serialized,
    uuid : $uuidPattern :> Lookup[replacementAssociation, uuid]
  ];
  output = Quiet[Check[OpenWrite[file, BinaryFormat -> True], $Failed]];
  If[Head[output] =!= OutputStream,
    fail["could not open the notebook for UUID normalization"]
  ];
  Quiet @ Check[
    BinaryWrite[output, ToCharacterCode[normalized, "UTF-8"], "Byte"],
    Close[output];
    fail["could not write the normalized notebook"]
  ];
  Close[output];
  Length[existing]
];

progress["saving through the Mathematica front end"];
saved = Quiet @ Check[
  UsingFrontEnd[
    saveObject = NotebookPut[notebook];
    NotebookSave[saveObject, notebookFile];
    NotebookClose[saveObject];
    notebookFile
  ],
  $Failed
];
If[saved =!= notebookFile || ! FileExistsQ[notebookFile],
  fail["could not save " <> notebookFile]
];

progress["normalizing serialized identifiers"];
deterministicUUIDCount = normalizeSerializedUUIDs[notebookFile];

progress["reopening the saved artifact"];
reopened = Quiet[Check[Get[notebookFile], $Failed]];
If[Head[reopened] =!= Notebook,
  fail["the saved file does not reopen as a Notebook expression"]
];
If[! FreeQ[reopened, "ComputationalCompanion"], Null,
  fail["the saved artifact lost its companion-edition metadata"]
];

Print[<|
  "Notebook" -> notebookFile,
  "WolframVersion" -> $Version,
  "GogFieldDynamicsVersion" -> paperPacletVersion,
  "Cells" -> cellCount,
  "Sections" -> sectionCount,
  "InputCells" -> inputCount,
  "OutputCells" -> outputCount,
  "NativeVisuals" -> Length[requiredVisualIDs],
  "PaperStyleCells" -> theoremLikeCount,
  "DeterministicUUIDs" -> deterministicUUIDCount,
  "NotebookSHA256" ->
    IntegerString[FileHash[notebookFile, "SHA256"], 16, 64]
|>];

Exit[0];
