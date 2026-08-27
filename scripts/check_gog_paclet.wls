#!/usr/bin/env wolframscript

fail[message_String] := (
  WriteString["stderr", "GogFieldDynamics check failed: " <> message <> "\n"];
  Exit[1]
);

scriptFile = If[StringQ[$InputFileName] && $InputFileName =!= "",
  ExpandFileName[$InputFileName],
  FileNameJoin[{Directory[], "scripts", "check_gog_paclet.wls"}]
];
repositoryDirectory = DirectoryName[DirectoryName[scriptFile]];
pacletDirectory = FileNameJoin[
  {repositoryDirectory, "Wolfram", "GogFieldDynamics"}
];
testFile = FileNameJoin[
  {pacletDirectory, "Tests", "Dynamics.wlt"}
];

If[! DirectoryQ[pacletDirectory], fail["paclet directory not found"]];
If[! FileExistsQ[testFile], fail["test file not found"]];

Quiet[Check[PacletDirectoryLoad[pacletDirectory], fail["could not load paclet directory"]]];
Quiet[Check[Needs["GogFieldDynamics`"], fail["could not load paclet context"]]];

If[
  ! TrueQ[GogFieldDynamics`GogSetReplaceAvailableQ[]],
  fail["SetReplace is not installed; the integration test is required here"]
];

report = Quiet[Check[TestReport[testFile], $Failed]];
If[Head[report] =!= TestReportObject, fail["TestReport did not return a report"]];
If[! TrueQ[report["ReportSucceeded"]],
  Print[report["ResultsByOutcome"]];
  fail["one or more paclet tests failed"]
];

testCount = Length[report["Results"]];

Print[<|
  "Paclet" -> "GogFieldDynamics 0.1.0",
  "SmallModels" -> GogFieldDynamics`GogAvailableSizes[],
  "SetReplaceVersion" -> GogFieldDynamics`GogSetReplaceVersion[],
  "TestsRun" -> testCount,
  "TestsSucceeded" -> testCount
|>];

Exit[0];
