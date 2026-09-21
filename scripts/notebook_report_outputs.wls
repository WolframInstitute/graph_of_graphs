#!/usr/bin/env wolframscript

(*
  Deterministic text transcript for
  whitehead-field-dynamics-computational-notes.tex.

  Run from any directory with

    /path/to/WolframKernel -noinit -noprompt -script \
      scripts/notebook_report_outputs.wls
*)

$HistoryLength = 0;

fail[message_String] := (
  WriteString[$Output, "notebook report output failed: ", message, "\n"];
  Exit[1]
);

write[label_String, value_] := WriteString[
  $Output,
  "\n(* ", label, " *)\n",
  ToString[value, InputForm],
  "\n"
];

scriptFile = If[
  StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[{Directory[], "scripts", "notebook_report_outputs.wls"}]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
pacletDirectory = FileNameJoin[
  {repositoryDirectory, "Wolfram", "GogFieldDynamics"}
];

If[! DirectoryQ[pacletDirectory], fail["the local paclet directory is missing"]];

Quiet @ Check[
  PacletDirectoryLoad[pacletDirectory],
  fail["the local paclet could not be loaded"]
];
Quiet @ Check[
  Needs["GogFieldDynamics`"],
  fail["the GogFieldDynamics context could not be loaded"]
];

pairAverage[n_Integer, {i_Integer, j_Integer}] := ReplacePart[
  IdentityMatrix[n],
  {
    {i, i} -> 1/2,
    {i, j} -> 1/2,
    {j, i} -> 1/2,
    {j, j} -> 1/2
  }
];

matching[n_Integer, edges_List] := Dot @@ (pairAverage[n, #] & /@ edges);

sizes = GogFieldDynamics`GogAvailableSizes[];
If[FailureQ[sizes], fail["the bundled model sizes could not be read"]];

summary = Table[
  With[
    {model = GogFieldDynamics`GogSmallModel[n]},
    {
      n,
      model["NodeCount"],
      model["EdgeCount"],
      model["RuleASlotCount"]
    }
  ],
  {n, sizes}
];

validation = GogFieldDynamics`GogValidateSmallModels[];
validationSummary = {
  validation["Valid"],
  AssociationMap[validation["Models", #]["Valid"] &, sizes]
};

countsA = GogFieldDynamics`GogTransitionCounts[4, "A"];
matrixA = GogFieldDynamics`GogTransitionMatrix[4, "A"];
stationaryA = First[
  NullSpace[Transpose[matrixA] - IdentityMatrix[Length[matrixA]]]
];
stationaryA = stationaryA/Total[stationaryA];

matrixB = GogFieldDynamics`GogTransitionMatrix[4, "B"];
uniformB = ConstantArray[1/Length[matrixB], Length[matrixB]];

diffusionA = GogFieldDynamics`GogDiffusionState[4, "A", 1, 4];
diffusionB = GogFieldDynamics`GogDiffusionState[4, "B", 1, 4];
trajectoryA = GogFieldDynamics`GogRandomTrajectory[4, "A", 1, 12, 2026];

k4Word =
  matching[4, {{1, 3}, {2, 4}}] .
  matching[4, {{1, 2}, {3, 4}}];

q3Word =
  matching[8, {{1, 5}, {2, 6}, {3, 7}, {4, 8}}] .
  matching[8, {{1, 3}, {2, 4}, {5, 7}, {6, 8}}] .
  matching[8, {{1, 2}, {3, 4}, {5, 6}, {7, 8}}];

write["Wolfram version", $Version];
write["bundled carrier sizes", sizes];
write["{N, classes, support edges, Rule-A slots}", summary];
write["small-model validation", validationSummary];

write[
  "one-pair loss",
  FullSimplify[
    x^2 + y^2 - 2 ((x + y)/2)^2,
    Assumptions -> Element[{x, y}, Reals]
  ]
];
write[
  "projection checks for A_13 in dimension 4",
  With[
    {average = pairAverage[4, {1, 3}], one = ConstantArray[1, 4]},
    {
      SymmetricMatrixQ[average],
      average . average === average,
      average . one === one
    }
  ]
];

write["N=4 Rule-A integer counts", countsA];
write["N=4 Rule-A row sums", Total /@ countsA];
write["N=4 Rule-A transition matrix", matrixA];
write["N=4 Rule-A stationary distribution", stationaryA];

write["N=4 fixed-clock Rule-B transition matrix", matrixB];
write[
  "Rule-B symmetry and uniform stationarity",
  {SymmetricMatrixQ[matrixB], uniformB . matrixB}
];
write[
  "N=2 fixed-clock Rule B and its jump chain",
  {
    GogFieldDynamics`GogTransitionMatrix[2, "B"],
    GogFieldDynamics`GogTransitionMatrix[2, "BJump"]
  }
];

write["N=4 Rule-A exact diffusion at t=4", diffusionA];
write["N=4 Rule-A decimal diffusion at t=4", N[diffusionA, 6]];
write["N=4 Rule-B exact diffusion at t=4", diffusionB];
write["N=4 Rule-B decimal diffusion at t=4", N[diffusionB, 6]];
write["N=4 Rule-A native path, seed 2026", trajectoryA];

write[
  "finite-consensus checks for K4 and Q3",
  {
    k4Word === ConstantArray[1/4, {4, 4}],
    q3Word === ConstantArray[1/8, {8, 8}]
  }
];
write["K4 consensus product", k4Word];

Exit[0];
