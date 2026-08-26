#!/usr/bin/env wolframscript

(* Build the canonical MathNotebook artifact and fail on any fidelity loss. *)

$requiredMathNotebookVersion = "0.1.24";
$minimumWolframVersion = 14.3;

fail[message_String] := (
  WriteString["stderr", "MathNotebook build failed: " <> message <> "\n"];
  Exit[1]
);

scriptFile = If[StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[{Directory[], "scripts", "build_math_notebook.wls"}]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
sourceFile = FileNameJoin[{repositoryDirectory, "whitehead-field-dynamics.tex"}];
notebookFile = FileNameJoin[{repositoryDirectory, "whitehead-field-dynamics.nb"}];
visualsFile = FileNameJoin[{repositoryDirectory, "scripts", "notebook_visuals.wl"}];

If[! FileExistsQ[sourceFile], fail["source file not found: " <> sourceFile]];
If[! FileExistsQ[visualsFile], fail["visual layer not found: " <> visualsFile]];
If[$VersionNumber < $minimumWolframVersion,
  fail["Wolfram Language 14.3 or newer is required; found " <> $Version]
];

developmentPaclet = Environment["MATHNOTEBOOK_PACLET_DIR"];
If[StringQ[developmentPaclet] && developmentPaclet =!= "",
  If[! DirectoryQ[developmentPaclet],
    fail["MATHNOTEBOOK_PACLET_DIR is not a directory: " <> developmentPaclet]
  ];
  PacletDirectoryLoad[ExpandFileName[developmentPaclet]];
];

Quiet[
  Check[
    Needs["WolframInstitute`MathNotebook`"],
    fail[
      "MathNotebook is not installed. Follow the installation command in " <>
      "docs/notebook.rst."
    ]
  ]
];

mathNotebookPaclet = PacletObject["WolframInstitute/MathNotebook"];
If[Head[mathNotebookPaclet] =!= PacletObject,
  fail["the MathNotebook paclet could not be resolved"]
];
mathNotebookVersion = mathNotebookPaclet["Version"];
If[mathNotebookVersion =!= $requiredMathNotebookVersion,
  fail[
    "MathNotebook " <> $requiredMathNotebookVersion <>
    " is required for a reproducible build; found " <> ToString[mathNotebookVersion]
  ]
];

(* MathNotebook stores each formula's original TeX independently of the boxes
   used to display it. Expand this manuscript's private macros only for box
   construction, leaving SourceTeX—and therefore LaTeX export—untouched. *)
matchingClosingBrace[text_String, opening_Integer] := Module[
  {depth = 0, character},
  Do[
    character = StringTake[text, {index}];
    If[character === "{", depth++];
    If[character === "}",
      depth--;
      If[depth === 0, Return[index]]
    ],
    {index, opening, StringLength[text]}
  ];
  $Failed
];

expandUnaryMacro[
  text_String, name_String, opening_String, closing_String
] := Module[
  {token = "\\" <> name <> "{", position, start, openBrace, closeBrace, body},
  position = First[StringPosition[text, token, 1], Missing["NotFound"]];
  If[MissingQ[position], Return[text]];
  {start, openBrace} = position;
  closeBrace = matchingClosingBrace[text, openBrace];
  If[closeBrace === $Failed, Return[text]];
  body = StringTake[text, {openBrace + 1, closeBrace - 1}];
  StringTake[text, start - 1] <> opening <>
    expandUnaryMacro[body, name, opening, closing] <> closing <>
    expandUnaryMacro[StringDrop[text, closeBrace], name, opening, closing]
];

expandInnerProduct[text_String] := Module[
  {token = "\\ip{", position, start, firstOpen, firstClose, secondOpen,
    secondClose, firstBody, secondBody},
  position = First[StringPosition[text, token, 1], Missing["NotFound"]];
  If[MissingQ[position], Return[text]];
  {start, firstOpen} = position;
  firstClose = matchingClosingBrace[text, firstOpen];
  If[firstClose === $Failed, Return[text]];
  secondOpen = firstClose + 1;
  If[secondOpen > StringLength[text] ||
      StringTake[text, {secondOpen}] =!= "{", Return[text]];
  secondClose = matchingClosingBrace[text, secondOpen];
  If[secondClose === $Failed, Return[text]];
  firstBody = StringTake[text, {firstOpen + 1, firstClose - 1}];
  secondBody = StringTake[text, {secondOpen + 1, secondClose - 1}];
  StringTake[text, start - 1] <> "\\langle " <> firstBody <> "," <>
    secondBody <> "\\rangle" <> expandInnerProduct[StringDrop[text, secondClose]]
];

$simpleMacroExpansions = {
  RegularExpression["([0-9])\\\\,([0-9])"] -> "$1{,}$2",
  RegularExpression["\\\\Specsing(?![A-Za-z])"] ->
    "\\operatorname{Spec}_{\\mathrm{sing}}",
  RegularExpression["\\\\Spec(?![A-Za-z])"] -> "\\operatorname{Spec}",
  RegularExpression["\\\\source(?![A-Za-z])"] -> "\\operatorname{source}",
  RegularExpression["\\\\target(?![A-Za-z])"] -> "\\operatorname{target}",
  RegularExpression["\\\\rank(?![A-Za-z])"] -> "\\operatorname{rank}",
  RegularExpression["\\\\diam(?![A-Za-z])"] -> "\\operatorname{diam}",
  RegularExpression["\\\\Aut(?![A-Za-z])"] -> "\\operatorname{Aut}",
  RegularExpression["\\\\Pp(?![A-Za-z])"] -> "\\mathbb{P}",
  RegularExpression["\\\\one(?![A-Za-z])"] -> "\\mathbf{1}",
  RegularExpression["\\\\R(?![A-Za-z])"] -> "\\mathbb{R}",
  RegularExpression["\\\\E(?![A-Za-z])"] -> "\\mathbb{E}",
  RegularExpression["\\\\G(?![A-Za-z])"] -> "\\Gamma",
  RegularExpression["\\\\C(?![A-Za-z])"] -> "\\mathcal{C}",
  RegularExpression["\\\\F(?![A-Za-z])"] -> "\\mathcal{F}",
  RegularExpression["\\\\V(?![A-Za-z])"] -> "\\mathcal{V}",
  RegularExpression["\\\\A(?![A-Za-z])"] -> "\\mathcal{A}"
};

expandManuscriptTeX[tex_String] := StringReplace[
  expandUnaryMacro[expandInnerProduct[tex], "norm", "\\left\\|", "\\right\\|"],
  $simpleMacroExpansions
];

DownValues[gogOriginalTexToBoxes] =
  DownValues[WolframInstitute`MathNotebook`PackageScope`texToBoxes] /.
    HoldPattern[WolframInstitute`MathNotebook`PackageScope`texToBoxes] ->
      gogOriginalTexToBoxes;
Clear[WolframInstitute`MathNotebook`PackageScope`texToBoxes];
WolframInstitute`MathNotebook`PackageScope`texToBoxes[tex_String] :=
  gogOriginalTexToBoxes[expandManuscriptTeX[tex]];

(* ReadString preserves the terminal newline. Import[..., "Text"], used by the
   public file wrapper, normalizes it away. MathNotebook exposes latexToNotebook
   as its pure conversion core, so using it here makes the round trip byte-exact. *)
sourceStream = Quiet[
  Check[OpenRead[sourceFile, CharacterEncoding -> "UTF-8"], $Failed]
];
If[Head[sourceStream] =!= InputStream, fail["could not open " <> sourceFile]];
source = Quiet[Check[ReadString[sourceStream], $Failed]];
Close[sourceStream];
If[! StringQ[source], fail["could not read " <> sourceFile]];

notebook = Quiet[
  Check[
    WolframInstitute`MathNotebook`PackageScope`latexToNotebook[source],
    $Failed
  ]
];
If[Head[notebook] =!= Notebook, fail["the LaTeX importer did not return a Notebook"]];

commandArgument[text_String, command_String] := First[
  StringCases[
    text,
    ("\\" <> command <> "{") ~~ Shortest[value___] ~~ "}" :> value,
    1
  ],
  ""
];
suppressedFrontMatterCell[text_String, style_String] := Cell[
  text,
  style,
  TaggingRules -> <|"MathNotebook" -> <|"Suppressed" -> "True"|>|>
];
displayFrontMatter = DeleteCases[
  {
    suppressedFrontMatterCell[commandArgument[source, "title"], "Title"],
    suppressedFrontMatterCell[commandArgument[source, "author"], "Author"]
  },
  Cell["", _, ___]
];
notebook = notebook /. Notebook[documentCells_, options___] :>
  Notebook[Join[displayFrontMatter, documentCells], options];

(* thebibliography entries are source-oriented in MathNotebook 0.1.24: TeX
   accents and \url commands otherwise remain visible as literal markup.
   Give each Reference cell a readable display while storing its original
   cell-level LaTeX in BibliographyTeX, which the exporter emits verbatim. *)
$referenceTextRules = {
  "{\\L}" -> "Ł", "{\\l}" -> "ł", "\\L" -> "Ł", "\\l" -> "ł",
  "\\'A" -> "Á", "\\'E" -> "É", "\\'I" -> "Í", "\\'O" -> "Ó",
  "\\'U" -> "Ú", "\\'Y" -> "Ý", "\\'C" -> "Ć", "\\'N" -> "Ń",
  "\\'S" -> "Ś", "\\'Z" -> "Ź",
  "\\'a" -> "á", "\\'e" -> "é", "\\'i" -> "í", "\\'o" -> "ó",
  "\\'u" -> "ú", "\\'y" -> "ý", "\\'c" -> "ć", "\\'n" -> "ń",
  "\\'s" -> "ś", "\\'z" -> "ź",
  "--" -> "–", "~" -> FromCharacterCode[160]
};

normalizeReferenceText[text_String] := StringReplace[text, $referenceTextRules];
referenceURL[url_String] := ButtonBox[
  url,
  BaseStyle -> "URL",
  ButtonData -> {URL[url], None},
  ButtonNote -> url
];
referenceStringParts[text_String] := Replace[
  StringSplit[
    text,
    "\\url{" ~~ url : Except["}"] .. ~~ "}" :> referenceURL[url]
  ],
  part_String :> normalizeReferenceText[part],
  {1}
];

ClearAll[referenceDisplayPart];
referenceDisplayPart[text_String] := referenceStringParts[text];
referenceDisplayPart[StyleBox[text_String, options___]] :=
  {StyleBox[normalizeReferenceText[text], options]};
referenceDisplayPart[StyleBox[TextData[parts_], options___]] :=
  {StyleBox[
    TextData[Flatten[referenceDisplayPart /@ Flatten[{parts}]]],
    options
  ]};
referenceDisplayPart[part_] := {part};

referenceDisplayContent[text_String] := Replace[
  referenceStringParts[text],
  {{single_String} :> single, parts_List :> TextData[parts]}
];
referenceDisplayContent[TextData[parts_]] :=
  TextData[Flatten[referenceDisplayPart /@ Flatten[{parts}]]];
referenceDisplayContent[content_] := content;

cellToLaTeXFunction =
  Symbol["WolframInstitute`MathNotebook`Document`PackagePrivate`cellToLaTeX"];
displayReferenceCell[
  cell : Cell[content_, "Reference", options___]
] := Module[{originalLaTeX, displayed},
  originalLaTeX = cellToLaTeXFunction[cell];
  If[! StringQ[originalLaTeX], fail["could not preserve a bibliography entry"]];
  displayed = Cell[referenceDisplayContent[content], "Reference", options];
  WolframInstitute`MathNotebook`PackageScope`retagged[
    displayed,
    <|"BibliographyTeX" -> originalLaTeX|>
  ]
];
displayReferenceCell[cell_] := cell;

notebook = notebook /. Notebook[documentCells_, options___] :>
  Notebook[displayReferenceCell /@ documentCells, options];

(* MathNotebook deliberately preserves unsupported prose commands as literal
   text.  This manuscript uses a few of them for layout and code typography.
   Give those cells a clean notebook display while carrying their complete
   original TeX through the paclet's verbatim whole-cell export channel. *)
$proseDisplayRules = {
  RegularExpression["\\\\path\\{([^{}]*)\\}"] -> "$1",
  RegularExpression["\\\\texttt\\{([^{}]*)\\}"] -> "$1",
  RegularExpression["\\\\emph\\{([^{}]*)\\}"] -> "$1",
  "\\\\_" -> "_",
  "\\\\#" -> "#",
  "~" -> FromCharacterCode[160],
  "\n{\\small" ~~ EndOfString -> "",
  StartOfString ~~ "}\n" -> ""
};

cleanDisplayString[text_String] := StringReplace[text, $proseDisplayRules];

displayProseContent[text_String] := Module[{paragraph},
  paragraph = StringCases[
    text,
    StartOfString ~~ "\\paragraph{" ~~ title : Except["}"] .. ~~ "}\n" ~~
      body___ ~~ EndOfString :> {title, body},
    1
  ];
  If[
    paragraph === {},
    cleanDisplayString[text],
    TextData[{
      StyleBox[paragraph[[1, 1]], FontWeight -> "Bold"],
      "\n",
      cleanDisplayString[paragraph[[1, 2]]]
    }]
  ]
];
displayProseContent[TextData[parts_]] := TextData[
  Replace[parts, text_String :> cleanDisplayString[text], {1}]
];
displayProseContent[content_] := content;

displayProseCell[cell : Cell[content_, style_String, options___]] := Module[
  {displayedContent, originalLaTeX, displayed},
  displayedContent = displayProseContent[content];
  If[SameQ[displayedContent, content], Return[cell]];
  originalLaTeX = cellToLaTeXFunction[cell];
  If[! StringQ[originalLaTeX], fail["could not preserve cleaned prose source"]];
  displayed = Cell[displayedContent, style, options];
  WolframInstitute`MathNotebook`PackageScope`retagged[
    displayed,
    <|"BibliographyTeX" -> originalLaTeX|>
  ]
];
displayProseCell[cell_] := cell;

notebook = notebook /. Notebook[documentCells_, options___] :>
  Notebook[displayProseCell /@ documentCells, options];

(* Enrich the faithful article conversion with native, presentation-only
   Wolfram graphics.  Every added cell carries MathNotebook's Suppressed tag,
   so the canonical LaTeX export remains byte-exact. *)
visualsLoaded = Quiet[Check[Get[visualsFile], $Failed]];
If[visualsLoaded === $Failed ||
    ! NameQ["GogNotebookVisuals`EnrichNotebook"],
  fail["the notebook visual layer could not be loaded"]
];
notebook = Quiet[
  Check[GogNotebookVisuals`EnrichNotebook[notebook], $Failed]
];
If[Head[notebook] =!= Notebook,
  fail["the visual layer did not return a Notebook"]
];
requiredVisualIDs = {
  "GoGVisualAbstract", "GoGWhiteheadMove", "GoGConsensusSchedules",
  "GoGEnumerationGrowth"
};
requiredPresentationIDs = Join[
  {"GoGBanner", "GoGNavigation"},
  requiredVisualIDs
];
If[! AllTrue[requiredPresentationIDs, ! FreeQ[notebook, #] &],
  fail["one or more required notebook presentation elements are absent"]
];

(* MathNotebook and Export create fresh ExpressionUUID values on every build.
   The serialized .nb repeats those values in its cache outline, so normalize
   the unique UUIDs in first-occurrence order after export.  Equal-length
   replacements keep all cached byte offsets valid and make unchanged rebuilds
   byte-stable on the same Wolfram version. *)
uuidFromSeed[seed_] := Module[{hex},
  hex = StringTake[
    IntegerString[Hash[{"gog-math-notebook", seed}, "SHA256"], 16, 64],
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

(* A small number of long top-level cells can have their UUID string wrapped
   across physical .nb lines, outside the serialized regular-expression pass.
   Seed every top-level cell and the notebook itself before export so those
   wrapped values are deterministic too. *)
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
    normalized, output, normalizedUUIDs},
  input = Quiet[Check[OpenRead[file, BinaryFormat -> True], $Failed]];
  If[Head[input] =!= InputStream, fail["could not reopen the serialized notebook"]];
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
  normalizedUUIDs = DeleteDuplicates[StringCases[normalized, $uuidPattern]];
  If[
    Length[normalizedUUIDs] =!= Length[existing] ||
      ! DuplicateFreeQ[Last /@ replacements],
    fail["could not normalize the serialized notebook UUIDs"]
  ];
  output = Quiet[Check[OpenWrite[file, BinaryFormat -> True], $Failed]];
  If[Head[output] =!= OutputStream,
    fail["could not open the notebook for UUID normalization"]
  ];
  Quiet[Check[BinaryWrite[output, ToCharacterCode[normalized, "UTF-8"], "Byte"],
    Close[output]; fail["could not write the normalized notebook"]
  ]];
  Close[output];
  Length[existing]
];

roundTrip = Quiet[
  Check[WolframInstitute`MathNotebook`ExportLaTeXDocument[notebook], $Failed]
];
If[roundTrip =!= source,
  fail[
    "the in-memory LaTeX round trip differs (source " <>
    ToString[StringLength[source]] <> " characters, export " <>
    ToString[If[StringQ[roundTrip], StringLength[roundTrip], 0]] <> ")"
  ]
];

ClearAll[visibleStrings];
visibleStrings[text_String] := {text};
visibleStrings[TextData[parts_]] := Flatten[visibleStrings /@ Flatten[{parts}]];
visibleStrings[Cell[content_, ___]] := visibleStrings[content];
visibleStrings[StyleBox[content_, ___]] := visibleStrings[content];
visibleStrings[ButtonBox[content_, ___]] := visibleStrings[content];
visibleStrings[RowBox[parts_]] := Flatten[visibleStrings /@ Flatten[{parts}]];
visibleStrings[BoxData[_]] := {};
visibleStrings[_] := {};

cells = First[notebook];
styles = KeySort[Counts[Cases[cells, Cell[_, style_String, ___] :> style]]];
requiredStyles = {
  "Title", "Author", "Section", "Text", "DisplayFormula", "Theorem", "Proof",
  "Reference"
};
If[! AllTrue[requiredStyles, Lookup[styles, #, 0] > 0 &],
  fail["one or more required document styles are absent"]
];

visibleByCell = visibleStrings /@ cells;
unconvertedMath = Select[
  visibleByCell,
  AnyTrue[#, StringContainsQ[
      #,
      "$" | "\\(" | "\\[" | "\\begin{equation" | "\\begin{align" |
        "\\begin{gather" | "\\begin{multline"
    ] &] &
];
If[unconvertedMath =!= {},
  fail[ToString[Length[unconvertedMath]] <> " cells still contain visible raw math"]
];
rawProseMarkers = {"{\\small", "\\paragraph{", "\\path{", "\\texttt{"};
unconvertedProse = Select[
  visibleByCell,
  AnyTrue[#, StringContainsQ[#, Alternatives @@ rawProseMarkers] &] &
];
If[unconvertedProse =!= {},
  fail[
    ToString[Length[unconvertedProse]] <>
      " cells still contain visible unsupported prose commands"
  ]
];
If[! FreeQ[cells, text_String /; StringContainsQ[text, "$Failed"]],
  fail["the notebook contains a visible $Failed conversion artifact"]
];

saved = Quiet[Check[Export[notebookFile, notebook, "NB"], $Failed]];
If[saved =!= notebookFile || ! FileExistsQ[notebookFile],
  fail["could not save " <> notebookFile]
];
deterministicUUIDCount = normalizeSerializedUUIDs[notebookFile];

reopened = Quiet[Check[Get[notebookFile], $Failed]];
If[Head[reopened] =!= Notebook, fail["the saved file does not reopen as a Notebook expression"]];
savedRoundTrip = Quiet[
  Check[WolframInstitute`MathNotebook`ExportLaTeXDocument[reopened], $Failed]
];
If[savedRoundTrip =!= source,
  fail["the saved notebook no longer round-trips exactly to the LaTeX source"]
];

Print[<|
  "Notebook" -> notebookFile,
  "WolframVersion" -> $Version,
  "MathNotebookVersion" -> mathNotebookVersion,
  "Cells" -> Length[cells],
  "Styles" -> styles,
  "InlineMathCells" ->
    Count[cells, Cell[_BoxData, "InlineFormula", ___], Infinity],
  "DisplayMathCells" ->
    Count[cells, Cell[_BoxData, "DisplayFormula", ___]],
  "NotebookVisuals" -> Length[requiredVisualIDs],
  "Buttons" -> Count[cells, _ButtonBox, Infinity],
  "DeterministicUUIDs" -> deterministicUUIDCount,
  "NotebookSHA256" ->
    IntegerString[FileHash[notebookFile, "SHA256"], 16, 64],
  "ExactLaTeXRoundTrip" -> True
|>];

Exit[0];
