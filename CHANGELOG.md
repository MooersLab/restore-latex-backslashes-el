# Changelog

All notable changes to this project are recorded in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-25

### Added

- Ten restoration rules (`escapes`, `environments`, `braced`, `anywhere`,
  `line`, `item`, `math`, `row-ends`, `percent`, and `ampersand`).
- Repair of control characters left by string escape processing.
- Context detection for math (Pandoc-style `$...$`, `$$...$$`, `\(...\)`,
  `\[...\]`, and math environments) and for list and alignment environments.
- Protection for verbatim environments, inline verbatim, and the arguments
  of package, label, citation, URL, and file commands.
- Commands `restore-latex-backslashes`, `restore-latex-backslashes-buffer`,
  `restore-latex-backslashes-region`, `restore-latex-backslashes-query`,
  `restore-latex-backslashes-diff`, `restore-latex-backslashes-file`,
  `restore-latex-backslashes-diff-file`, `restore-latex-backslashes-dired`,
  and `restore-latex-backslashes-batch`.
- Lisp functions `restore-latex-backslashes-string` and
  `restore-latex-backslashes-summary`.
- ERT suite with 54 tests, a Makefile, a README tutorial, and an Org
  reference manual.
