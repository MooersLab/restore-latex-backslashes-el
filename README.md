# restore-latex-backslashes
![Version](https://img.shields.io/static/v1?label=restore-latex-backslashes-el&message=0.1.0&color=brightcolor)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
![Emacs 27.1+](https://img.shields.io/badge/Emacs-27.1%2B-7F5AB6)

An Emacs package that puts back the backslashes that other programs strip
out of LaTeX source.

LaTeX that travels through chat windows, web forms, PDF text extractors,
spreadsheet cells, JSON serializers, or the string literals of a programming
language often comes back damaged.
This package repairs that damage in the current buffer, in a region, in a
`.tex` file on disk, in a batch of files marked in Dired, or from the shell.

## Contents

- [The problem](#the-problem)
- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Tutorial](#tutorial)
- [Command reference](#command-reference)
- [Customization](#customization)
- [How the rules work](#how-the-rules-work)
- [Limitations](#limitations)
- [Running the tests](#running-the-tests)
- [Submitting to MELPA](#submitting-to-melpa)
- [License](#license)

## The problem

Two kinds of damage are common.

**Deleted backslashes.**
The program simply removes every backslash.

| Original                     | After damage               |
|------------------------------|----------------------------|
| `\section{Results}`          | `section{Results}`         |
| `$\alpha + \beta \leq \pi$`  | `$alpha + beta leq pi$`    |
| `\item First point`          | `item First point`         |
| `80\% of trials`             | `80% of trials`            |
| `Smith \& Jones`             | `Smith & Jones`            |
| `a & b \\`                   | `a & b`                    |

**Interpreted backslashes.**
The program treats each backslash as the start of a string escape sequence,
as Python, C, and JavaScript do for ordinary string literals.
The letter after the backslash turns into an invisible control character.

| Original        | After damage                          |
|-----------------|---------------------------------------|
| `\textbf{x}`    | TAB followed by `extbf{x}`            |
| `\frac{1}{2}`   | form feed followed by `rac{1}{2}`     |
| `\begin{align}` | backspace followed by `egin{align}`   |
| `\alpha`        | bell character followed by `lpha`     |
| `\noindent`     | newline followed by `oindent`         |
| `a & b \\`      | `a & b \`                             |

Fixing either kind of damage by hand is slow and error prone because the
same word can be a command in one place and an ordinary English word in
another.
The word `alpha` is the command `\alpha` inside `$...$` but an ordinary word
in the phrase "alpha helix."
This package uses context to tell the two apart.

## Features

- Repairs both deleted and interpreted backslashes.
- Restores math symbols such as `alpha`, `sum`, and `leq` only inside math.
- Restores `item` only at the start of a line inside a list environment.
- Never touches verbatim environments, `\verb`, URLs, labels, citation keys,
  file names, or package names.
- Leaves currency such as `$5 and $10` alone by using the same rules for
  inline math that Pandoc uses.
- Escapes `%` after a digit and a lone `&` in running text.
- Repairs or adds the `\\` row terminators in tables and `align`
  environments.
- Previews every change as a unified diff before anything is modified.
- Offers a query mode that asks about each change, in the style of
  `query-replace`.
- Treats the whole repair as one undoable change.
- Is idempotent, so running it twice gives the same result as running it
  once.
- Works on the buffer, the region, a file on disk, the files marked in
  Dired, or files named on the command line.
- Offers a Lisp function that repairs a string.

## Installation

The package needs Emacs 27.1 or newer and has no other dependencies.

### From a local clone

```sh
git clone https://github.com/MooersLab/restore-latex-backslashes-el.git \
    ~/.emacs.d/site-lisp/restore-latex-backslashes-el
```

Add this to your init file.

```elisp
(add-to-list 'load-path "~/.emacs.d/site-lisp/restore-latex-backslashes-el")
(require 'restore-latex-backslashes)
```

### With use-package and a local clone

```elisp
(use-package restore-latex-backslashes
  :load-path "~/.emacs.d/site-lisp/restore-latex-backslashes-el"
  :commands (restore-latex-backslashes
             restore-latex-backslashes-buffer
             restore-latex-backslashes-region
             restore-latex-backslashes-query
             restore-latex-backslashes-diff
             restore-latex-backslashes-file
             restore-latex-backslashes-diff-file
             restore-latex-backslashes-dired))
```

### With use-package and package-vc (Emacs 30 and newer)

```elisp
(use-package restore-latex-backslashes
  :vc (:url "https://github.com/MooersLab/restore-latex-backslashes-el"
       :rev :newest))
```

### With straight.el

```elisp
(straight-use-package
 '(restore-latex-backslashes
   :type git :host github
   :repo "MooersLab/restore-latex-backslashes-el"))
```

### From MELPA

The package is not on MELPA yet.
Once it is accepted, `M-x package-install RET restore-latex-backslashes RET`
will install it.

### Suggested key bindings

The package defines no key bindings, as MELPA guidelines ask.
These bindings suit AUCTeX, the built-in `latex-mode`, and Org mode.

```elisp
(with-eval-after-load 'tex
  (define-key TeX-mode-map (kbd "C-c \\") #'restore-latex-backslashes)
  (define-key TeX-mode-map (kbd "C-c |")  #'restore-latex-backslashes-diff))

(with-eval-after-load 'tex-mode
  (define-key latex-mode-map (kbd "C-c \\") #'restore-latex-backslashes))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c \\") #'restore-latex-backslashes))
```

## Quick start

1. Open the damaged `.tex` file or paste the damaged text into a buffer.
2. Run `M-x restore-latex-backslashes-diff` to see what would change.
3. Run `M-x restore-latex-backslashes` to make the changes.
4. Press `C-/` once if you want everything back the way it was.

To repair a file without opening it, run `M-x restore-latex-backslashes-file`.

## Tutorial

The repository includes a damaged file at `examples/stripped-example.tex`.
Every backslash was deleted from it.
This tutorial walks through each way of repairing it.
Work on a copy so that you can repeat the steps.

```sh
cp examples/stripped-example.tex /tmp/damaged.tex
```

### Lesson 1. Look at the damage

Open `/tmp/damaged.tex` with `C-x C-f`.
Part of it looks like this.

```latex
section{Introduction}

noindent Our crystals diffracted to 1.8 AA{} resolution in 75% of the
trials.  We thank Smith & Jones for textbf{generous} help with the
emph{synchrotron} data collection described in Section~ref{sec:methods}.

The free energy is $Delta G = Delta H - T Delta S$ and the rate
constant obeys $k propto exp(-E_a / RT)$ when $T to infty$.
```

Three problems hide here in addition to the missing command backslashes.
The `75%` now starts a comment that hides the rest of the line from LaTeX.
The `&` in "Smith & Jones" now causes an error outside a table.
The table rows have lost their `\\` terminators.

### Lesson 2. Preview the repair

Run `M-x restore-latex-backslashes-diff`.
A window named `*restore-latex-backslashes diff*` opens and shows a unified
diff.
Lines that start with `-` are the damaged text and lines that start with `+`
are the repaired text.
Nothing in your buffer changes.
The echo area reports how many backslashes each rule would restore.

```
Restored 41 backslashes (environments 10, braced 12, anywhere 5, line 1,
item 2, math 9, percent 1, ampersand 1)
```

The diff buffer uses `diff-mode`, so `n` and `p` move between hunks and
`RET` jumps to the matching line of the file.
Press `q` to close the window.

### Lesson 3. Repair the whole buffer

Run `M-x restore-latex-backslashes`.
With no active region, the command repairs the whole buffer.
The same lines now read as follows.

```latex
\section{Introduction}

\noindent Our crystals diffracted to 1.8 \AA{} resolution in 75\% of the
trials.  We thank Smith \& Jones for \textbf{generous} help with the
\emph{synchrotron} data collection described in Section~\ref{sec:methods}.

The free energy is $\Delta G = \Delta H - T \Delta S$ and the rate
constant obeys $k \propto \exp(-E_a / RT)$ when $T \to \infty$.
```

Notice what stayed the same.
The word `resolution` was not touched, and neither was `sin` in a word such
as `since`.
The label `sec:methods` inside `\ref{...}` kept its exact spelling.

### Lesson 4. Undo in one step

Press `C-/` (or `C-x u`) once.
Every change disappears together because the package records the repair as
a single undoable change.
Press `C-/` again after `C-g` to redo it, or just run the command again.

### Lesson 5. Repair the table rows

Look at the table near the end of the buffer.

```latex
  begin{tabular}{lr}
    toprule
    Parameter & Value
    midrule
    Resolution & 1.8
    Completeness & 99.1
    bottomrule
  end{tabular}
```

The default repair restores `\toprule`, `\midrule`, and `\bottomrule`, but it
does not add the missing `\\`.
The default only repairs a row that ends in a single `\`, which is the
damage that escape processing causes.
Text that lost every backslash needs the stronger setting.
Undo the last repair, then evaluate this form with `M-:`.

```elisp
(setq restore-latex-backslashes-row-ends 'all)
```

Run `M-x restore-latex-backslashes` again.
Each row that contains `&` now ends with ` \\`, except the last row of an
environment.

```latex
  \begin{tabular}{lr}
    \toprule
    Parameter & Value \\
    \midrule
    Resolution & 1.8 \\
    Completeness & 99.1 \\
    \bottomrule
  \end{tabular}
```

The same setting repairs `align` and the other environments listed in
`restore-latex-backslashes-alignment-environments`.

### Lesson 6. Approve each change

Undo again and run `M-x restore-latex-backslashes-query`.
The package highlights each candidate and asks about it in the minibuffer.

```
Restore "section" to "\\section" (braced)? [y]es [n]o [!]all [q]uit
```

| Key           | Action                                        |
|---------------|-----------------------------------------------|
| `y` or `SPC`  | Make this change.                             |
| `n` or `DEL`  | Skip this change.                             |
| `!`           | Make this change and every remaining change.  |
| `q`           | Stop and keep the changes made so far.        |

Changes come grouped by rule, so you will first see every `\begin` and
`\end`, then every command with an argument, and so on.
The whole session is still one undoable change.

### Lesson 7. Repair only part of a buffer

Select a region with `C-SPC` and the motion keys, then run
`M-x restore-latex-backslashes`.
Only the region changes.
This is useful when you paste one damaged equation into an otherwise
healthy document.
The command `restore-latex-backslashes-region` does the same thing when you
call it from Lisp.

Rules that depend on context look only inside the region.
If you select the inside of an `itemize` environment without its
`\begin{itemize}` line, the `item` rule cannot know that it is inside a list.
Include the enclosing `begin{...}` and `end{...}` lines in the region to get
the full repair.

### Lesson 8. Repair a file on disk without opening it

Run `M-x restore-latex-backslashes-file` and choose `/tmp/damaged.tex`.
The package reads the file, repairs it, and writes it back.
Before it writes, it copies the original to `/tmp/damaged.tex.orig`.

- With a prefix argument (`C-u M-x restore-latex-backslashes-file`), the
  command also asks for an output file and leaves the original alone.
- If a buffer already visits the file and has unsaved changes, the command
  stops with an error rather than discard your edits.
- If a buffer visits the file and has no unsaved changes, the buffer is
  reverted so that it shows the repaired text.
- If nothing needs repair, the file and its time stamp stay untouched and no
  backup is made.
- The file keeps its original coding system, so UTF-8 text such as
  `Ångström` survives.

To preview a file without changing it, run
`M-x restore-latex-backslashes-diff-file`.

### Lesson 9. Repair many files from Dired

Open the folder in Dired with `C-x d`.
Mark the damaged files with `m`, or mark every `.tex` file with
`% m \.tex$ RET`.
Run `M-x restore-latex-backslashes-dired`.
Each marked file is repaired in place with a backup, and the echo area
reports the total.

### Lesson 10. Repair files from the shell

The batch entry point lets you repair files from a terminal, a Makefile, or
a script without starting an interactive Emacs.

```sh
emacs --batch -l /path/to/restore-latex-backslashes.el \
      -f restore-latex-backslashes-batch chapter1.tex chapter2.tex
```

The command prints one line per file.

```
chapter1.tex: Restored 212 backslashes (environments 40, braced 118, ...)
chapter2.tex: No backslashes needed restoring
```

Two flags change its behavior.

| Flag          | Effect                                             |
|---------------|----------------------------------------------------|
| `--dry-run`   | Report what would change but write nothing.        |
| `--no-backup` | Do not make `.orig` copies.                        |

The exit status is 0 when every file was processed and 1 when any file
failed, which makes the command safe to use in scripts.
Use `--eval` before `-f` to set options, for example
`--eval "(setq restore-latex-backslashes-row-ends 'all)"`.

### Lesson 11. Repair text mangled by escape processing

This kind of damage is common when LaTeX passes through a Python, C, or
JavaScript string literal without a raw-string prefix.
Run this Python snippet to make a damaged file.

```python
s = "\textbf{Result} is $\frac{\alpha}{\beta}$\noindent next\n"
open("/tmp/escaped.tex", "w").write(s)
```

Open `/tmp/escaped.tex` in Emacs.
Emacs shows the control characters with caret notation, so the text looks
like this.

```
	extbf{Result} is $^Lrac{^Glpha}{^Heta}$
oindent next
```

Run `M-x restore-latex-backslashes`.
The text becomes the following.

```latex
\textbf{Result} is $\frac{\alpha}{\beta}$\noindent next
```

The bell, backspace, escape, form feed, vertical tab, and carriage return
characters never belong in LaTeX, so any of them followed by a letter is
repaired.
A TAB or a newline is legitimate, so the package repairs it only when the
rest of a known command name follows it, as in TAB plus `extbf` or newline
plus `oindent`.
A real indentation TAB in front of ordinary text stays as it is.

### Lesson 12. Teach the package your own macros

Suppose your documents use a custom macro `\resid{...}` for residue numbers,
the `\degree` symbol from the gensymb package, and a custom list environment
named `steps`.
Add each name to the matching list.

```elisp
(with-eval-after-load 'restore-latex-backslashes
  (add-to-list 'restore-latex-backslashes-braced-commands "resid")
  (add-to-list 'restore-latex-backslashes-math-commands "degree")
  (add-to-list 'restore-latex-backslashes-list-environments "steps"))
```

Now `resid{G34}` becomes `\resid{G34}`, `degree` becomes `\degree` inside
math, and `item` is restored inside a custom `steps` list.
You can also browse every option with
`M-x customize-group RET restore-latex-backslashes RET`.

### Lesson 13. Turn rules off

The option `restore-latex-backslashes-rules` lists the rules in the order
that they run.
Remove a rule to turn it off.
For example, this setting keeps every rule except the `&` rule.

```elisp
(setq restore-latex-backslashes-rules
      (remq 'ampersand restore-latex-backslashes-rules))
```

### Lesson 14. Call the package from Lisp

The function `restore-latex-backslashes-string` takes a string and returns
the repaired string.
It is handy in your own commands, in Org Babel blocks, and in hooks.

```elisp
(restore-latex-backslashes-string "section{Intro} with $alpha$")
;; => "\\section{Intro} with $\\alpha$"
```

This command repairs whatever LaTeX is on the kill ring and inserts it at
point.

```elisp
(defun my-yank-repaired-latex ()
  "Insert the most recent kill after restoring its LaTeX backslashes."
  (interactive)
  (insert (restore-latex-backslashes-string (current-kill 0))))
```

The interactive commands also return an alist that maps each rule to its
number of changes, such as `((escapes . 0) (environments . 4) ...)`.
Pass that alist to `restore-latex-backslashes-summary` for a one-line report.

## Command reference

| Command | What it does |
|---------|--------------|
| `restore-latex-backslashes` | Repair the region when it is active and the buffer otherwise. |
| `restore-latex-backslashes-buffer` | Repair the accessible part of the buffer. |
| `restore-latex-backslashes-region` | Repair the text between two positions. |
| `restore-latex-backslashes-query` | Ask before each change. |
| `restore-latex-backslashes-diff` | Show the changes as a diff without making them. |
| `restore-latex-backslashes-file` | Repair a file on disk, with a backup. With `C-u`, write to another file. |
| `restore-latex-backslashes-diff-file` | Show the changes to a file on disk as a diff. |
| `restore-latex-backslashes-dired` | Repair every file marked in Dired. |
| `restore-latex-backslashes-batch` | Entry point for `emacs --batch`. |
| `restore-latex-backslashes-string` | Lisp function that returns a repaired copy of a string. |
| `restore-latex-backslashes-summary` | Lisp function that formats the statistics alist. |

## Customization

Run `M-x customize-group RET restore-latex-backslashes RET` to see every
option with its documentation.

| Option | Default | Purpose |
|--------|---------|---------|
| `restore-latex-backslashes-rules` | all ten rules | Which rules run, and in what order. |
| `restore-latex-backslashes-row-ends` | `single` | `nil`, `single` (repair a lone `\`), or `all` (also add missing `\\`). |
| `restore-latex-backslashes-backup-suffix` | `".orig"` | Suffix for backups of repaired files, or `nil` for none. |
| `restore-latex-backslashes-verbose` | `t` | Report a summary in the echo area. |
| `restore-latex-backslashes-braced-commands` | about 200 names | Commands restored when `{` or `[` follows them. |
| `restore-latex-backslashes-anywhere-commands` | about 80 names | Commands that are never English words. |
| `restore-latex-backslashes-line-commands` | about 20 names | Commands restored only when alone on a line. |
| `restore-latex-backslashes-math-commands` | about 220 names | Symbols restored only inside math. |
| `restore-latex-backslashes-math-subscript-exclusions` | `in`, `max`, `min`, and others | Math words skipped right after `_` or `^`. |
| `restore-latex-backslashes-math-text-commands` | `text`, `mathrm`, and others | Commands whose arguments are text inside math. |
| `restore-latex-backslashes-math-environments` | `equation`, `align`, and others | Environments that hold math. |
| `restore-latex-backslashes-alignment-environments` | `tabular`, `align`, and others | Environments where `&` separates columns. |
| `restore-latex-backslashes-list-environments` | `itemize`, `enumerate`, `description`, and others | Environments where `item` starts a line. |
| `restore-latex-backslashes-verbatim-environments` | `verbatim`, `lstlisting`, `minted`, and others | Environments that are never modified. |
| `restore-latex-backslashes-protected-argument-commands` | `usepackage`, `label`, `ref`, `cite`, `url`, and others | Commands whose first argument is never modified. |
| `restore-latex-backslashes-escape-stoplist` | `he`, `op`, `ag`, `an`, `eq`, `eg`, `ie` | Fragments that a TAB or newline may legitimately precede. |

## How the rules work

The package runs ten rules in order.
Each rule finds candidate changes, and then all of that rule's changes are
applied before the next rule starts.
The order matters because later rules depend on the environments that
earlier rules restored.
For example, the `math` rule can only find `\begin{equation}` after the
`environments` rule has restored it.

| Order | Rule | What it restores | Where |
|-------|------|------------------|-------|
| 1 | `escapes` | Control characters left by escape processing | Everywhere |
| 2 | `environments` | `begin{` and `end{` | Everywhere |
| 3 | `braced` | `section{`, `frac{`, `includegraphics[`, and so on | Outside protected text |
| 4 | `anywhere` | `noindent`, `textwidth`, `hline`, and so on | Outside protected text |
| 5 | `line` | `centering`, `appendix`, `small`, and so on | Only when alone on a line |
| 6 | `item` | `item` | Start of a line inside a list environment |
| 7 | `math` | `alpha`, `sum`, `leq`, `to`, `left`, and so on | Inside math only |
| 8 | `row-ends` | `\\` at the end of table and `align` rows | Inside alignment environments |
| 9 | `percent` | `%` after a digit becomes `\%` | Outside protected text |
| 10 | `ampersand` | A lone `&` in running text becomes `\&` | Outside tables and math |

Several safeguards keep the rules from damaging good text.

- A word is a candidate only when it is a whole word, so `sin` inside
  `since` is never a candidate.
- A word that already has a backslash is skipped, which makes the package
  idempotent and safe on documents that are only partly damaged.
- Protected text is skipped by every rule after `environments`.
  Protected text includes verbatim environments, `\verb|...|`,
  `\lstinline|...|`, and the first argument of `\usepackage`, `\label`,
  `\ref`, `\cite`, `\url`, `\href`, `\includegraphics`, `\input`, and
  similar commands.
  This keeps `\usepackage{parskip}` from turning into
  `\usepackage{\parskip}`.
- Inside math, the arguments of `\text{...}`, `\mathrm{...}`, `\label{...}`,
  and similar commands are skipped, so `\text{for all x in S}` stays as it is.
- Inside math, words such as `in`, `max`, and `min` are skipped right after
  `_` or `^`, so `T_{max}` and `x_{in}` keep their meaning.
- Inline math follows Pandoc's rules.
  The opening `$` must be followed by a non-space character and the closing
  `$` must follow a non-space character and must not be followed by a digit.
  This keeps `$5 in total and $10` from being read as math.
- A line that holds two or more `&` characters looks like a table row, so
  the `ampersand` rule leaves it alone even outside a table environment.

## Limitations

Some damage cannot be undone without more information than the damaged text
contains.

- **Bracketed math delimiters.**
  `\(x\)` and `\[x\]` become `(x)` and `[x]` once the backslash is gone, and
  these look exactly like ordinary parentheses and brackets.
  The package restores math inside `\(...\)` and `\[...\]` only when those
  delimiters survived.
- **Symbol commands.**
  Commands made of one punctuation character, such as `\,`, `\;`, `\!`,
  `\{`, `\}`, `\_`, `\#`, `\$`, `\'`, and `` \` ``, become indistinguishable
  from ordinary punctuation.
- **English words used as commands outside math.**
  `\today`, `\item` outside a list, `\centering` in the middle of a line, and
  similar commands are not restored when they share a line with other text
  because they look like prose.
- **Percent signs after letters.**
  Only `%` after a digit is escaped, because `%` after a letter or a space is
  more often a real comment.
- **Short escape fragments.**
  The `escapes` rule needs at least two letters after a TAB or a newline, so
  `\to`, `\nu`, and `\ni` are not repaired from TAB or newline damage.
  They are still repaired by the `math` rule when they appear inside math
  after deletion damage.
- **Unknown macros.**
  Commands that are not in any list are not restored.
  Add your own macros as shown in Lesson 12.

Always review the diff from `restore-latex-backslashes-diff` and compile the
document afterward.
LaTeX error messages point straight at anything that the package missed.

## Running the tests

The tests use ERT, which ships with Emacs.

```sh
make test        # run the suite against the source file
make compile     # byte-compile with warnings treated as errors
make test-elc    # run the suite against the compiled file
make checkdoc    # check docstrings
make lint        # run package-lint, if it is installed
make all         # compile, checkdoc, and test-elc
make example     # print the repaired tutorial example
```

Set `EMACS` to test with a different Emacs, for example
`make test EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`.
If package-lint lives in a checkout rather than in your package directory,
pass its location with `make lint PACKAGE_LINT_DIR=~/src/package-lint`.

The suite has 54 tests.
They cover each rule, the safeguards, idempotency, a full round trip of the
fixture `test/fixtures/sample.tex` after every backslash is deleted, a full
round trip of `test/fixtures/escaped-sample.tex` after Python-style escape
processing, undo, query mode, the diff preview, and the file, backup,
coding-system, and batch behavior.

## Repository layout

```
restore-latex-backslashes.el        the package
README.org                          this tutorial in Org format
README.md                           the same tutorial in Markdown
test/restore-latex-backslashes-test.el
test/fixtures/sample.tex            healthy LaTeX for the round-trip test
test/fixtures/escaped-sample.tex    healthy LaTeX for the escape test
examples/stripped-example.tex       damaged file used in the tutorial
doc/restore-latex-backslashes.org   reference manual in Org format
Makefile
CHANGELOG.md
LICENSE                             GNU GPL version 3
.github/workflows/test.yml          continuous integration
```

## Submitting to MELPA

The package header, the GPL-3.0-or-later license, the autoload cookies, and
the clean checkdoc and package-lint results follow the MELPA guidelines.
When the repository is public, submit this recipe as
`recipes/restore-latex-backslashes` in a pull request to
<https://github.com/melpa/melpa>.

```elisp
(restore-latex-backslashes
 :fetcher github
 :repo "MooersLab/restore-latex-backslashes-el"
 :files ("restore-latex-backslashes.el"))
```

## License

Copyright (C) 2026 Blaine Mooers.

This program is free software.
You can redistribute it and modify it under the terms of the GNU General
Public License as published by the Free Software Foundation, either version
3 of the License or (at your option) any later version.
See [LICENSE](LICENSE) for the full text.

## Author

Blaine Mooers, Department of Biochemistry and Physiology, University of
Oklahoma Health Campus.
Email blaine-mooers@ou.edu.
