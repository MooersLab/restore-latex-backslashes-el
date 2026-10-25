;;; restore-latex-backslashes.el --- Restore backslashes stripped from LaTeX source -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Maintainer: Blaine Mooers <blaine-mooers@ou.edu>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tex, wp, convenience
;; URL: https://github.com/MooersLab/restore-latex-backslashes-el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; LaTeX source that passes through chat interfaces, web forms, PDF
;; extractors, spreadsheet cells, JSON serializers, or programming
;; language string literals often comes back damaged.  Two kinds of
;; damage are common.
;;
;; 1. The backslashes are simply deleted, so "\section{Results}"
;;    becomes "section{Results}" and "$\alpha + \beta$" becomes
;;    "$alpha + beta$".
;;
;; 2. The backslashes are interpreted as string escape sequences, so
;;    "\textbf" becomes a TAB followed by "extbf", "\frac" becomes a
;;    form feed followed by "rac", and "\begin" becomes a backspace
;;    followed by "egin".
;;
;; This package repairs both kinds of damage with a sequence of
;; conservative, context-aware rules.  Each rule knows the LaTeX
;; vocabulary that it is allowed to touch and the context in which a
;; bare word is safe to treat as a command.  Math symbols such as
;; "alpha" or "sum" are restored only inside math, list items are
;; restored only inside list environments, and verbatim material,
;; URLs, labels, and package names are never touched.
;;
;; Main entry points:
;;
;;   M-x restore-latex-backslashes          region if active, else buffer
;;   M-x restore-latex-backslashes-buffer   whole buffer
;;   M-x restore-latex-backslashes-region   active region
;;   M-x restore-latex-backslashes-query    confirm each change
;;   M-x restore-latex-backslashes-diff     preview the changes as a diff
;;   M-x restore-latex-backslashes-file     repair a .tex file on disk
;;   M-x restore-latex-backslashes-diff-file   preview a file repair
;;   M-x restore-latex-backslashes-dired    repair the marked files in Dired
;;
;; From the shell:
;;
;;   "emacs --batch -l restore-latex-backslashes.el
;;      -f restore-latex-backslashes-batch [--dry-run] [--no-backup] FILE..."
;;
;; From Lisp:
;;
;;   (restore-latex-backslashes-string "section{Intro}")
;;   => "\\section{Intro}"
;;
;; See README.md for a tutorial and doc/restore-latex-backslashes.org
;; for the reference manual.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defconst restore-latex-backslashes-version "0.1.0"
  "Version of the restore-latex-backslashes package.")

;;;; Customization

(defgroup restore-latex-backslashes nil
  "Restore backslashes that other programs stripped from LaTeX source."
  :group 'tex
  :prefix "restore-latex-backslashes-"
  :link '(url-link :tag "Homepage"
                   "https://github.com/MooersLab/restore-latex-backslashes-el"))

(defcustom restore-latex-backslashes-rules
  '(escapes environments braced anywhere line item math
            row-ends percent ampersand)
  "Rules that the restoration commands apply, in order.
Each element is a symbol naming one rule.

  `escapes'       Repair control characters left behind by string
                  escape processing, for example a TAB followed by
                  \"extbf\" becomes \"\\textbf\".
  `environments'  Restore \"begin{\" and \"end{\".
  `braced'        Restore known commands that are directly followed
                  by an argument, such as \"section{\" or \"frac{\".
  `anywhere'      Restore commands that are never English words,
                  such as \"noindent\" or \"textwidth\".
  `line'          Restore commands that stand alone on a line, such
                  as \"centering\" or \"appendix\".
  `item'          Restore \"item\" at the start of a line inside a
                  list environment.
  `math'          Restore math symbols such as \"alpha\" or \"sum\"
                  inside math.
  `row-ends'      Repair row terminators inside alignment
                  environments.  See `restore-latex-backslashes-row-ends'.
  `percent'       Escape a percent sign that follows a digit.
  `ampersand'     Escape an ampersand that is outside alignment
                  environments and math.

The order matters because later rules rely on the environments that
earlier rules restored."
  :type '(repeat (choice (const :tag "Escape sequences" escapes)
                         (const :tag "begin/end" environments)
                         (const :tag "Commands with arguments" braced)
                         (const :tag "Unambiguous commands" anywhere)
                         (const :tag "Commands alone on a line" line)
                         (const :tag "List items" item)
                         (const :tag "Math symbols" math)
                         (const :tag "Row ends" row-ends)
                         (const :tag "Percent after digit" percent)
                         (const :tag "Ampersand in text" ampersand)))
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-braced-commands
  '(;; Document structure
    "documentclass" "usepackage" "RequirePackage" "part" "chapter"
    "section" "subsection" "subsubsection" "paragraph" "subparagraph"
    "title" "author" "date" "thanks" "affil" "address" "email"
    "keywords" "caption" "captionof" "subcaption" "subfloat"
    "include" "includeonly" "input" "includegraphics" "graphicspath"
    "includepdf" "pagestyle" "thispagestyle" "pagenumbering"
    "geometry" "hypersetup" "today"
    ;; Cross references and citations
    "label" "ref" "eqref" "pageref" "autoref" "nameref" "cref" "Cref"
    "vref" "subref" "cite" "citep" "citet" "citealp" "citealt"
    "citeauthor" "citeyear" "parencite" "textcite" "autocite"
    "footcite" "nocite" "footnote" "footnotemark" "footnotetext"
    "marginpar" "bibliography" "bibliographystyle" "addbibresource"
    "bibitem" "url" "href" "path" "hyperref" "index"
    "gls" "Gls" "glspl" "acrshort" "acrlong" "acrfull" "ac" "acs" "acl"
    "newacronym" "newglossaryentry"
    ;; Text formatting
    "emph" "textbf" "textit" "texttt" "textrm" "textsf" "textsc"
    "textsl" "textup" "textmd" "textnormal" "textsuperscript"
    "textsubscript" "textcolor" "text" "underline" "uline" "sout" "hl"
    "fbox" "mbox" "makebox" "framebox" "parbox" "raisebox" "colorbox"
    "fcolorbox" "color" "definecolor" "centerline" "LaTeX" "TeX"
    "LaTeXe" "linespread" "fontsize" "setmainfont" "setsansfont"
    "setmonofont" "newfontfamily" "AA"
    ;; Definitions and lengths
    "newcommand" "renewcommand" "providecommand" "newenvironment"
    "renewenvironment" "DeclareMathOperator" "newtheorem" "setlength"
    "addtolength" "setcounter" "addtocounter" "stepcounter" "newcounter"
    "vspace" "hspace" "phantom" "hphantom" "vphantom"
    ;; Tables
    "multicolumn" "multirow" "cline" "cmidrule"
    ;; Code listings and graphics packages
    "lstinputlisting" "inputminted" "mintinline" "lstset"
    "usetikzlibrary" "tikzset" "pgfplotsset" "addplot"
    ;; Math with arguments
    "frac" "dfrac" "tfrac" "cfrac" "sqrt" "binom" "dbinom" "tbinom"
    "mathrm" "mathbf" "mathit" "mathsf" "mathtt" "mathcal" "mathbb"
    "mathfrak" "mathscr" "boldsymbol" "bm" "pmb" "operatorname"
    "overline" "underbrace" "overbrace" "hat" "widehat" "bar" "vec"
    "dot" "ddot" "tilde" "widetilde" "check" "breve" "acute" "grave"
    "stackrel" "overset" "underset" "substack" "boxed" "cancel"
    "xrightarrow" "xleftarrow" "overrightarrow" "pmod" "tag"
    "intertext" "smash" "mathop"
    ;; Units and chemistry
    "SI" "si" "num" "qty" "unit" "ang" "ce")
  "Commands restored when an argument directly follows the name.
A bare word from this list is restored only when it is immediately
followed by \"{\" or \"[\", optionally after a star.  For example
\"section*{\" becomes \"\\section*{\" but \"section 3\" is left
alone.  Add your own macros with `add-to-list'."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-anywhere-commands
  '("maketitle" "tableofcontents" "listoffigures" "listoftables"
    "noindent" "hline" "toprule" "midrule" "bottomrule" "addlinespace"
    "newpage" "clearpage" "cleardoublepage" "ldots" "cdots" "vdots"
    "ddots" "textwidth" "linewidth" "columnwidth" "textheight"
    "paperwidth" "paperheight" "baselineskip" "parindent" "parskip"
    "bigskip" "medskip" "smallskip" "vfill" "hfill" "dotfill"
    "hrulefill" "raggedright" "raggedleft" "printbibliography"
    "makeindex" "printindex" "frontmatter" "mainmatter" "backmatter"
    "bfseries" "itshape" "ttfamily" "sffamily" "rmfamily" "scshape"
    "mdseries" "upshape" "slshape" "normalfont" "footnotesize"
    "scriptsize" "normalsize" "textbackslash" "linenumbers"
    "doublespacing" "onehalfspacing" "singlespacing" "selectfont"
    "tightlist" "nolinebreak" "nopagebreak" "allowbreak" "textendash"
    "textemdash" "nonumber" "notag" "displaystyle" "infty" "leq" "geq"
    "neq" "rightarrow" "leftarrow" "Rightarrow" "Leftarrow"
    "leftrightarrow" "Leftrightarrow" "longrightarrow" "varepsilon"
    "vartheta" "varphi" "cdot")
  "Commands restored wherever they occur as a whole word.
Every entry must be a word that never appears in ordinary prose,
because the rule restores it in running text as well as in math."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-line-commands
  '("centering" "appendix" "newline" "par" "indent" "relax" "small"
    "large" "Large" "LARGE" "huge" "Huge" "tiny" "bigbreak" "endinput"
    "boldmath" "unboldmath" "protect" "linebreak" "pagebreak" "fussy"
    "sloppy")
  "Commands restored when they stand alone on a line.
These are commands whose names are also English words, so they are
restored only when nothing else shares the line."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-math-commands
  '(;; Greek letters
    "alpha" "beta" "gamma" "delta" "epsilon" "varepsilon" "zeta" "eta"
    "theta" "vartheta" "iota" "kappa" "lambda" "mu" "nu" "xi" "pi"
    "varpi" "rho" "varrho" "sigma" "varsigma" "tau" "upsilon" "phi"
    "varphi" "chi" "psi" "omega" "Gamma" "Delta" "Theta" "Lambda" "Xi"
    "Pi" "Sigma" "Upsilon" "Phi" "Psi" "Omega"
    ;; Large operators and named functions
    "sum" "prod" "coprod" "int" "iint" "iiint" "oint" "bigcup" "bigcap"
    "bigoplus" "bigotimes" "bigwedge" "bigvee" "lim" "limsup" "liminf"
    "sup" "inf" "max" "min" "arg" "det" "exp" "log" "ln" "lg" "sin"
    "cos" "tan" "cot" "sec" "csc" "arcsin" "arccos" "arctan" "sinh"
    "cosh" "tanh" "coth" "deg" "dim" "gcd" "hom" "ker" "Pr" "bmod"
    ;; Binary operators
    "pm" "mp" "times" "div" "cdot" "ast" "star" "circ" "bullet"
    "oplus" "ominus" "otimes" "oslash" "odot" "cup" "cap" "uplus"
    "setminus" "wedge" "vee" "land" "lor" "neg" "lnot" "diamond"
    ;; Relations
    "leq" "le" "geq" "ge" "neq" "ne" "leqslant" "geqslant" "lesssim"
    "gtrsim" "ll" "gg" "prec" "succ" "preceq" "succeq" "approx"
    "equiv" "sim" "simeq" "cong" "propto" "asymp" "doteq" "subset"
    "subseteq" "subsetneq" "supset" "supseteq" "in" "notin" "ni"
    "mid" "nmid" "parallel" "perp" "vdash" "models"
    ;; Arrows
    "to" "gets" "mapsto" "longmapsto" "rightarrow" "leftarrow"
    "Rightarrow" "Leftarrow" "leftrightarrow" "Leftrightarrow"
    "longrightarrow" "longleftarrow" "Longrightarrow" "Longleftarrow"
    "uparrow" "downarrow" "Uparrow" "Downarrow" "updownarrow"
    "nearrow" "searrow" "hookrightarrow" "rightleftharpoons"
    "leftrightharpoons" "implies" "iff"
    ;; Symbols
    "infty" "partial" "nabla" "prime" "hbar" "ell" "Re" "Im" "aleph"
    "forall" "exists" "nexists" "emptyset" "varnothing" "angle"
    "triangle" "square" "Box" "dagger" "ddagger" "colon"
    ;; Delimiters and sizing
    "left" "right" "middle" "big" "Big" "bigg" "Bigg" "bigl" "bigr"
    "Bigl" "Bigr" "langle" "rangle" "lfloor" "rfloor" "lceil" "rceil"
    "lvert" "rvert" "lVert" "rVert" "vert" "Vert" "backslash"
    ;; Dots, spacing, and style
    "ldots" "cdots" "vdots" "ddots" "dots" "quad" "qquad"
    "displaystyle" "textstyle" "scriptstyle" "limits" "nolimits"
    "nonumber" "notag")
  "Commands restored only inside math.
Math is $...$, $$...$$, \\(...\\), \\=\\[...\\], and the environments in
`restore-latex-backslashes-math-environments'.  Words inside the
arguments of `restore-latex-backslashes-math-text-commands' are
left alone."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-math-subscript-exclusions
  '("in" "out" "max" "min" "sup" "inf" "deg" "dim" "det" "log" "exp"
    "ln" "arg" "ker" "lim" "to" "ne" "le" "ge" "ni" "Re" "Im" "Pr")
  "Math words left alone when they directly follow \"_\" or \"^\".
Subscripts such as x_{in} or T_{max} are usually labels rather than
operators, so these words are skipped when they open a subscript or
superscript."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-math-text-commands
  '("text" "textrm" "textit" "textbf" "textsf" "texttt" "textnormal"
    "mbox" "hbox" "mathrm" "operatorname" "intertext" "label" "tag"
    "ref" "eqref" "SI" "si" "unit" "qty" "num" "ce")
  "Commands whose arguments are treated as text inside math.
The `math' rule does not touch words inside their first argument."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-math-environments
  '("equation" "equation*" "align" "align*" "alignat" "alignat*"
    "flalign" "flalign*" "gather" "gather*" "multline" "multline*"
    "eqnarray" "eqnarray*" "displaymath" "math" "split" "aligned"
    "gathered" "cases" "dmath" "dmath*")
  "Environments whose contents are math."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-alignment-environments
  '("tabular" "tabular*" "tabularx" "tabulary" "longtable" "array"
    "align" "align*" "alignat" "alignat*" "flalign" "flalign*"
    "eqnarray" "eqnarray*" "split" "aligned" "cases" "matrix" "pmatrix"
    "bmatrix" "Bmatrix" "vmatrix" "Vmatrix" "smallmatrix" "tblr"
    "xltabular" "supertabular")
  "Environments in which \"&\" is a column separator."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-list-environments
  '("itemize" "enumerate" "description" "compactitem" "compactenum"
    "inparaenum" "asparaenum" "checklist")
  "Environments in which a line that starts with \"item\" is an item."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-verbatim-environments
  '("verbatim" "verbatim*" "Verbatim" "BVerbatim" "LVerbatim"
    "lstlisting" "minted" "comment" "alltt" "filecontents"
    "filecontents*")
  "Environments whose contents are never modified, except by `escapes'."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-protected-argument-commands
  '("usepackage" "RequirePackage" "documentclass" "label" "ref" "eqref"
    "pageref" "autoref" "nameref" "cref" "Cref" "vref" "subref" "cite"
    "citep" "citet" "citealp" "citealt" "citeauthor" "citeyear"
    "parencite" "textcite" "autocite" "footcite" "nocite" "url" "href"
    "path" "input" "include" "includeonly" "includegraphics"
    "graphicspath" "bibliography" "bibliographystyle" "addbibresource"
    "begin" "end" "lstinputlisting" "inputminted" "usetikzlibrary"
    "pagestyle" "thispagestyle" "pagenumbering" "definecolor"
    "newtheorem" "newcounter" "setcounter" "addtocounter"
    "stepcounter" "bibitem")
  "Commands whose first brace argument is never modified.
These arguments hold file names, keys, labels, package names, and
URLs.  For example, \"\\usepackage{parskip}\" must not turn into
\"\\usepackage{\\parskip}\"."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-escape-stoplist
  '("he" "op" "ag" "an" "eq" "eg" "ie")
  "Word fragments that the `escapes' rule leaves alone after TAB or newline.
A TAB or a newline followed by the rest of a command name is treated
as a mangled \"\\t\" or \"\\n\" command.  For example, a TAB followed
by \"extbf\" becomes \"\\textbf\".  Fragments in this list look like
ordinary words at the start of a line, so they are skipped.
Fragments of one letter and fragments that are themselves command
names are always skipped."
  :type '(repeat string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-row-ends 'single
  "How the `row-ends' rule repairs row terminators.
The rule only looks at lines inside the environments in
`restore-latex-backslashes-alignment-environments'.

  nil      Do nothing.
  `single' Turn a lone \"\\\" at the end of a row into \"\\\\\".  This
           repairs text in which every \"\\\\\" was halved by escape
           processing.
  `all'    Also append \" \\\\\" to every row that contains \"&\" and
           has no terminator, except the last row of the environment.
           Use this for text in which every backslash was deleted."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "Repair lone backslash" single)
                 (const :tag "Repair and add missing terminators" all))
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-backup-suffix ".orig"
  "Suffix for the backup copy made before a file is repaired in place.
When nil, no backup copy is made."
  :type '(choice (const :tag "No backup" nil) string)
  :group 'restore-latex-backslashes)

(defcustom restore-latex-backslashes-verbose t
  "When non-nil, report a summary of the changes in the echo area."
  :type 'boolean
  :group 'restore-latex-backslashes)

(defface restore-latex-backslashes-query-face
  '((t :inherit query-replace))
  "Face that highlights the text under consideration during a query."
  :group 'restore-latex-backslashes)

(defvar restore-latex-backslashes-query-function
  #'restore-latex-backslashes--ask
  "Function that asks whether to apply one change in query mode.
It receives OLD, NEW, and RULE and returns one of the characters
?y, ?n, ?!, or ?q.  Tests rebind this variable.")

;;;; Small helpers

(defun restore-latex-backslashes--table (&rest lists)
  "Return a hash table whose keys are the strings in LISTS."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (list lists)
      (dolist (word list)
        (puthash word t table)))
    table))

(defun restore-latex-backslashes--escaped-p (pos)
  "Return non-nil when an odd number of backslashes precedes POS."
  (let ((count 0)
        (p pos))
    (while (and (> p (point-min)) (eq (char-before p) ?\\))
      (setq count (1+ count)
            p (1- p)))
    (= (% count 2) 1)))

(defun restore-latex-backslashes--in-ranges-p (pos ranges)
  "Return non-nil when POS lies inside one of RANGES.
Each range is a cons (BEG . END) that covers BEG up to but not
including END."
  (cl-some (lambda (range) (and (>= pos (car range)) (< pos (cdr range))))
           ranges))

(defun restore-latex-backslashes--word-start-ok-p (pos)
  "Return non-nil when a command name may start at POS.
The character before POS must not be a backslash, a letter, or
\"@\"."
  (let ((c (char-before pos)))
    (not (and c (or (eq c ?\\) (eq c ?@)
                    (and (<= ?a c) (<= c ?z))
                    (and (<= ?A c) (<= c ?Z)))))))

(defun restore-latex-backslashes--matching-brace (pos)
  "Return the position after the brace that closes the brace at POS.
Return nil when the brace is not closed."
  (save-excursion
    (goto-char (1+ pos))
    (let ((depth 1))
      (while (and (> depth 0) (re-search-forward "[{}]" nil t))
        (unless (restore-latex-backslashes--escaped-p (match-beginning 0))
          (if (eq (char-before) ?{)
              (setq depth (1+ depth))
            (setq depth (1- depth)))))
      (and (= depth 0) (point)))))

(defun restore-latex-backslashes--environment-ranges (names)
  "Return ranges (BEG . END) of the environments named in NAMES.
BEG is the start of \\begin{NAME} and END is the end of the matching
\\end{NAME}.  Nested environments of the same name are paired
correctly and unclosed environments are ignored."
  (let ((re (concat "\\\\\\(begin\\|end\\){\\(" (regexp-opt names) "\\)}"))
        (stack nil)
        (ranges nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward re nil t)
        (unless (restore-latex-backslashes--escaped-p (match-beginning 0))
          (let ((kind (match-string-no-properties 1))
                (name (match-string-no-properties 2)))
            (if (string= kind "begin")
                (push (cons name (match-beginning 0)) stack)
              (let ((open (assoc name stack)))
                (when open
                  (push (cons (cdr open) (match-end 0)) ranges)
                  (setq stack (delq open stack)))))))))
    ranges))

(defun restore-latex-backslashes--argument-ranges (commands)
  "Return ranges that cover the first brace argument of COMMANDS.
An optional [...] argument between the name and the brace is
allowed."
  (let ((re (concat "\\\\" (regexp-opt commands t)
                    "\\*?\\(?:\\[[^]\n]*\\]\\)?\\({\\)"))
        (ranges nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward re nil t)
        (let* ((open (match-beginning 2))
               (close (restore-latex-backslashes--matching-brace open)))
          (when close
            (push (cons open close) ranges)))))
    ranges))

(defun restore-latex-backslashes--inline-verb-ranges ()
  "Return ranges covering \\verb|...| and \\lstinline|...|."
  (let ((ranges nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              "\\\\\\(?:verb\\|lstinline\\)\\*?\\([^[:alpha:][:space:]*{]\\)"
              nil t)
        (let ((start (match-beginning 0))
              (delim (match-string-no-properties 1)))
          (when (search-forward delim (line-end-position) t)
            (push (cons start (point)) ranges)))))
    ranges))

(defun restore-latex-backslashes--verbatim-ranges ()
  "Return ranges of verbatim environments and inline verbatim."
  (append (restore-latex-backslashes--environment-ranges
           restore-latex-backslashes-verbatim-environments)
          (restore-latex-backslashes--inline-verb-ranges)))

(defun restore-latex-backslashes--protected-ranges ()
  "Return ranges that the word rules must not modify."
  (append (restore-latex-backslashes--verbatim-ranges)
          (restore-latex-backslashes--argument-ranges
           restore-latex-backslashes-protected-argument-commands)))

;;;; Math detection

(defun restore-latex-backslashes--find-display-close (from)
  "Return the position after the first unescaped \"$$\" after FROM."
  (save-excursion
    (goto-char from)
    (let ((found nil))
      (while (and (not found) (search-forward "$$" nil t))
        (unless (restore-latex-backslashes--escaped-p (- (point) 2))
          (setq found (point))))
      found)))

(defun restore-latex-backslashes--find-inline-close (start)
  "Return the position after the \"$\" that closes inline math at START.
The opening \"$\" must be followed by a non-space character.  The
closing \"$\" must follow a non-space character, must not be
followed by a digit, and must lie in the same paragraph.  These are
the rules that Pandoc uses, and they keep currency amounts such as
\"$5 and $10\" from being read as math."
  (let ((next (char-after (1+ start))))
    (when (and next (not (memq next '(?\s ?\t ?\n))))
      (save-excursion
        (let ((limit (save-excursion
                       (goto-char (1+ start))
                       (if (re-search-forward "\n[ \t]*\n" nil t)
                           (match-beginning 0)
                         (point-max))))
              (found nil)
              (stop nil))
          (goto-char (1+ start))
          (while (and (not found) (not stop) (search-forward "$" limit t))
            (let ((cand (1- (point))))
              (cond
               ((restore-latex-backslashes--escaped-p cand) nil)
               ((eq (char-after (1+ cand)) ?$) (setq stop t))
               ((memq (char-before cand) '(?\s ?\t ?\n)) nil)
               ((let ((after (char-after (1+ cand))))
                  (and after (<= ?0 after) (<= after ?9)))
                nil)
               (t (setq found (1+ cand))))))
          found)))))

(defun restore-latex-backslashes--dollar-ranges (protected)
  "Return ranges of $...$ and $$...$$ math outside PROTECTED ranges."
  (let ((ranges nil))
    (save-excursion
      (goto-char (point-min))
      (while (search-forward "$" nil t)
        (let ((start (1- (point))))
          (unless (or (restore-latex-backslashes--escaped-p start)
                      (restore-latex-backslashes--in-ranges-p start protected))
            (if (eq (char-after) ?$)
                (let ((close (restore-latex-backslashes--find-display-close
                              (1+ (point)))))
                  (if close
                      (progn (push (cons start close) ranges)
                             (goto-char close))
                    (forward-char 1)))
              (let ((close (restore-latex-backslashes--find-inline-close start)))
                (when close
                  (push (cons start close) ranges)
                  (goto-char close))))))))
    ranges))

(defun restore-latex-backslashes--delimited-ranges (open close)
  "Return ranges delimited by the literal strings OPEN and CLOSE."
  (let ((ranges nil))
    (save-excursion
      (goto-char (point-min))
      (while (search-forward open nil t)
        (let ((start (- (point) (length open)))
              (found nil))
          (unless (restore-latex-backslashes--escaped-p start)
            (while (and (not found) (search-forward close nil t))
              (unless (restore-latex-backslashes--escaped-p
                       (- (point) (length close)))
                (setq found (point))))
            (when found
              (push (cons start found) ranges))))))
    ranges))

(defun restore-latex-backslashes--math-ranges (protected)
  "Return ranges of math outside PROTECTED ranges."
  (append (restore-latex-backslashes--environment-ranges
           restore-latex-backslashes-math-environments)
          (restore-latex-backslashes--dollar-ranges protected)
          (restore-latex-backslashes--delimited-ranges "\\(" "\\)")
          (restore-latex-backslashes--delimited-ranges "\\[" "\\]")))

;;;; Rules
;;
;; Every rule works on the accessible part of the current buffer and
;; returns a list of edits.  An edit is a list (BEG END NEW RULE)
;; that replaces the text from BEG to END with NEW.  Rules do not
;; modify the buffer themselves.

(defun restore-latex-backslashes--scan-words (table rule pred)
  "Return edits that add a backslash to words found in TABLE.
RULE names the rule.  PRED is called with the start, end, and text
of each candidate word and must return non-nil to accept it."
  (let ((edits nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "[A-Za-z]+" nil t)
        (let ((beg (match-beginning 0))
              (end (match-end 0))
              (word (match-string-no-properties 0)))
          (when (and (gethash word table)
                     (restore-latex-backslashes--word-start-ok-p beg)
                     (funcall pred beg end word))
            (push (list beg end (concat "\\" word) rule) edits)))))
    edits))

(defconst restore-latex-backslashes--control-letters
  '((?\a . ?a) (?\b . ?b) (?\e . ?e) (?\f . ?f) (?\v . ?v) (?\r . ?r))
  "Control characters produced by escape processing and their letters.")

(defun restore-latex-backslashes--all-command-names ()
  "Return every command name that the package knows."
  (append '("begin" "end" "item")
          restore-latex-backslashes-braced-commands
          restore-latex-backslashes-anywhere-commands
          restore-latex-backslashes-line-commands
          restore-latex-backslashes-math-commands))

(defun restore-latex-backslashes--escape-table (letter)
  "Return a table of command name fragments that follow LETTER.
For LETTER ?t the table holds \"extbf\" for \"\\textbf\", and so on."
  (let* ((names (restore-latex-backslashes--all-command-names))
         (known (restore-latex-backslashes--table names))
         (table (make-hash-table :test #'equal)))
    (dolist (name names)
      (when (and (> (length name) 2) (eq (aref name 0) letter))
        (let ((rest (substring name 1)))
          (unless (or (gethash rest known)
                      (member rest restore-latex-backslashes-escape-stoplist))
            (puthash rest t table)))))
    table))

(defun restore-latex-backslashes--rule-escapes ()
  "Return edits that repair control characters left by escape processing."
  (let ((edits nil)
        (tab-table (restore-latex-backslashes--escape-table ?t))
        (newline-table (restore-latex-backslashes--escape-table ?n)))
    (save-excursion
      ;; BEL, BS, ESC, FF, VT, and CR never belong in LaTeX source,
      ;; so any of them followed by a letter is a lost backslash.
      (goto-char (point-min))
      (while (re-search-forward "[\a\b\e\f\v\r][A-Za-z]" nil t)
        (let* ((beg (match-beginning 0))
               (letter (cdr (assq (char-after beg)
                                  restore-latex-backslashes--control-letters))))
          (push (list beg (1+ beg) (string ?\\ letter) 'escapes) edits)
          (goto-char (1+ beg))))
      ;; TAB and newline are legitimate, so they count only when the
      ;; rest of a known command name follows them.
      (goto-char (point-min))
      (while (re-search-forward "[\t\n]\\([A-Za-z]+\\)" nil t)
        (let* ((beg (match-beginning 0))
               (tab (eq (char-after beg) ?\t))
               (word (match-string-no-properties 1)))
          (when (gethash word (if tab tab-table newline-table))
            (push (list beg (1+ beg) (if tab "\\t" "\\n") 'escapes) edits))
          (goto-char (match-beginning 1)))))
    edits))

(defun restore-latex-backslashes--rule-environments ()
  "Return edits that restore \"begin{\" and \"end{\"."
  (restore-latex-backslashes--scan-words
   (restore-latex-backslashes--table '("begin" "end"))
   'environments
   (lambda (_beg end _word) (eq (char-after end) ?{))))

(defun restore-latex-backslashes--followed-by-argument-p (pos)
  "Return non-nil if an argument begins at POS, perhaps after a star."
  (let ((c (char-after pos)))
    (or (memq c '(?{ ?\[))
        (and (eq c ?*) (memq (char-after (1+ pos)) '(?{ ?\[))))))

(defun restore-latex-backslashes--rule-braced ()
  "Return edits that restore commands directly followed by an argument."
  (let ((protected (restore-latex-backslashes--protected-ranges)))
    (restore-latex-backslashes--scan-words
     (restore-latex-backslashes--table restore-latex-backslashes-braced-commands)
     'braced
     (lambda (beg end _word)
       (and (restore-latex-backslashes--followed-by-argument-p end)
            (not (restore-latex-backslashes--in-ranges-p beg protected)))))))

(defun restore-latex-backslashes--rule-anywhere ()
  "Return edits that restore commands that are never English words."
  (let ((protected (restore-latex-backslashes--protected-ranges)))
    (restore-latex-backslashes--scan-words
     (restore-latex-backslashes--table restore-latex-backslashes-anywhere-commands)
     'anywhere
     (lambda (beg _end _word)
       (not (restore-latex-backslashes--in-ranges-p beg protected))))))

(defun restore-latex-backslashes--alone-on-line-p (beg end)
  "Return non-nil when only blanks surround BEG and END on their line."
  (and (save-excursion (goto-char beg) (skip-chars-backward " \t") (bolp))
       (save-excursion (goto-char end) (skip-chars-forward " \t") (eolp))))

(defun restore-latex-backslashes--rule-line ()
  "Return edits that restore commands that stand alone on a line."
  (let ((protected (restore-latex-backslashes--protected-ranges)))
    (restore-latex-backslashes--scan-words
     (restore-latex-backslashes--table restore-latex-backslashes-line-commands
                                       restore-latex-backslashes-anywhere-commands)
     'line
     (lambda (beg end _word)
       (and (restore-latex-backslashes--alone-on-line-p beg end)
            (not (restore-latex-backslashes--in-ranges-p beg protected)))))))

(defun restore-latex-backslashes--rule-item ()
  "Return edits that restore \"item\" at the start of a line in a list."
  (let ((protected (restore-latex-backslashes--protected-ranges))
        (lists (restore-latex-backslashes--environment-ranges
                restore-latex-backslashes-list-environments)))
    (when lists
      (restore-latex-backslashes--scan-words
       (restore-latex-backslashes--table '("item"))
       'item
       (lambda (beg end _word)
         (and (save-excursion (goto-char beg) (skip-chars-backward " \t") (bolp))
              (memq (char-after end) '(nil ?\s ?\t ?\n ?\[))
              (restore-latex-backslashes--in-ranges-p beg lists)
              (not (restore-latex-backslashes--in-ranges-p beg protected))))))))

(defun restore-latex-backslashes--after-script-p (pos)
  "Return non-nil when POS directly follows \"_\", \"^\", \"_{\", or \"^{\"."
  (let ((c (char-before pos)))
    (or (memq c '(?_ ?^))
        (and (eq c ?{) (memq (char-before (1- pos)) '(?_ ?^))))))

(defun restore-latex-backslashes--rule-math ()
  "Return edits that restore math symbols inside math."
  (let* ((protected (restore-latex-backslashes--protected-ranges))
         (math (restore-latex-backslashes--math-ranges protected))
         (text (restore-latex-backslashes--argument-ranges
                restore-latex-backslashes-math-text-commands))
         (excluded restore-latex-backslashes-math-subscript-exclusions))
    (when math
      (restore-latex-backslashes--scan-words
       (restore-latex-backslashes--table restore-latex-backslashes-math-commands)
       'math
       (lambda (beg _end word)
         (and (restore-latex-backslashes--in-ranges-p beg math)
              (not (restore-latex-backslashes--in-ranges-p beg protected))
              (not (restore-latex-backslashes--in-ranges-p beg text))
              (not (and (member word excluded)
                        (restore-latex-backslashes--after-script-p beg)))))))))

(defun restore-latex-backslashes--count-unescaped (char beg end)
  "Return the number of unescaped CHAR between BEG and END."
  (let ((count 0))
    (save-excursion
      (goto-char beg)
      (while (search-forward (string char) end t)
        (unless (restore-latex-backslashes--escaped-p (1- (point)))
          (setq count (1+ count)))))
    count))

(defun restore-latex-backslashes--next-line-ends-environment-p (limit)
  "Return non-nil when the next non-blank line before LIMIT is \\end{...}.
Also return non-nil when no such line exists."
  (save-excursion
    (forward-line 1)
    (while (and (< (point) limit) (looking-at-p "[ \t]*$"))
      (forward-line 1))
    (or (>= (point) limit) (looking-at-p "[ \t]*\\\\end{"))))

(defun restore-latex-backslashes--rule-row-ends ()
  "Return edits that repair row terminators in alignment environments."
  (when restore-latex-backslashes-row-ends
    (let ((protected (restore-latex-backslashes--protected-ranges))
          (edits nil)
          (seen (make-hash-table)))
      (save-excursion
        (dolist (range (restore-latex-backslashes--environment-ranges
                        restore-latex-backslashes-alignment-environments))
          (goto-char (car range))
          (forward-line 1)
          (while (< (point) (cdr range))
            (let* ((bol (point))
                   (eol (line-end-position))
                   (last (save-excursion (goto-char eol)
                                         (skip-chars-backward " \t" bol)
                                         (point))))
              (when (and (> last bol)
                         (not (gethash last seen))
                         (not (restore-latex-backslashes--in-ranges-p
                               bol protected))
                         (not (save-excursion (goto-char bol)
                                              (looking-at-p "[ \t]*\\\\end{"))))
                (cond
                 ;; A lone backslash that ends the row.
                 ((and (eq (char-before last) ?\\)
                       (not (eq (char-before (1- last)) ?\\)))
                  (puthash last t seen)
                  (push (list (1- last) last "\\\\" 'row-ends) edits))
                 ;; A row with columns that has lost its terminator.
                 ((and (eq restore-latex-backslashes-row-ends 'all)
                       (not (eq (char-before last) ?\\))
                       (not (eq (char-before last) ?%))
                       (> (restore-latex-backslashes--count-unescaped
                           ?& bol eol)
                          0)
                       (not (restore-latex-backslashes--next-line-ends-environment-p
                             (cdr range))))
                  (puthash last t seen)
                  (push (list (1- last) eol
                              (concat (string (char-before last)) " \\\\")
                              'row-ends)
                        edits))))
              (forward-line 1)))))
      edits)))

(defun restore-latex-backslashes--rule-percent ()
  "Return edits that escape a percent sign that follows a digit."
  (let ((protected (restore-latex-backslashes--protected-ranges))
        (edits nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "[0-9]\\(%\\)" nil t)
        (let ((pos (match-beginning 1)))
          (unless (restore-latex-backslashes--in-ranges-p pos protected)
            (push (list pos (1+ pos) "\\%" 'percent) edits)))))
    edits))

(defun restore-latex-backslashes--rule-ampersand ()
  "Return edits that escape an ampersand used in running text.
An ampersand is escaped only when it is outside alignment
environments and math, and when it is the only ampersand on a line
that does not end with \"\\\\\".  Lines with several ampersands look
like table rows and are left alone."
  (let* ((protected (restore-latex-backslashes--protected-ranges))
         (align (restore-latex-backslashes--environment-ranges
                 restore-latex-backslashes-alignment-environments))
         (math (restore-latex-backslashes--math-ranges protected))
         (edits nil))
    (save-excursion
      (goto-char (point-min))
      (while (search-forward "&" nil t)
        (let ((pos (1- (point))))
          (unless (or (restore-latex-backslashes--escaped-p pos)
                      (restore-latex-backslashes--in-ranges-p pos protected)
                      (restore-latex-backslashes--in-ranges-p pos align)
                      (restore-latex-backslashes--in-ranges-p pos math)
                      (/= 1 (restore-latex-backslashes--count-unescaped
                             ?& (line-beginning-position) (line-end-position)))
                      (save-excursion
                        (end-of-line)
                        (skip-chars-backward " \t")
                        (looking-back "\\\\\\\\" (line-beginning-position))))
            (push (list pos (1+ pos) "\\&" 'ampersand) edits)))))
    edits))

(defconst restore-latex-backslashes--rule-functions
  '((escapes . restore-latex-backslashes--rule-escapes)
    (environments . restore-latex-backslashes--rule-environments)
    (braced . restore-latex-backslashes--rule-braced)
    (anywhere . restore-latex-backslashes--rule-anywhere)
    (line . restore-latex-backslashes--rule-line)
    (item . restore-latex-backslashes--rule-item)
    (math . restore-latex-backslashes--rule-math)
    (row-ends . restore-latex-backslashes--rule-row-ends)
    (percent . restore-latex-backslashes--rule-percent)
    (ampersand . restore-latex-backslashes--rule-ampersand))
  "Map from rule names to the functions that compute their edits.")

;;;; Engine

(defun restore-latex-backslashes--clean-edits (edits)
  "Return EDITS sorted by position with overlapping edits removed."
  (let ((sorted (sort (copy-sequence edits)
                      (lambda (a b) (< (car a) (car b)))))
        (result nil)
        (last-end nil))
    (dolist (edit sorted)
      (when (or (null last-end) (>= (nth 0 edit) last-end))
        (push edit result)
        (setq last-end (nth 1 edit))))
    (nreverse result)))

(defun restore-latex-backslashes--replace (beg end new)
  "Replace the text from BEG to END with NEW."
  (goto-char beg)
  (delete-region beg end)
  (insert new))

(defun restore-latex-backslashes--apply-edits (edits)
  "Apply EDITS, which must be sorted and free of overlaps.
Return the number of edits applied."
  (dolist (edit (reverse edits))
    (restore-latex-backslashes--replace (nth 0 edit) (nth 1 edit) (nth 2 edit)))
  (length edits))

(defun restore-latex-backslashes--ask (old new rule)
  "Ask whether to replace OLD with NEW for RULE and return the answer."
  (read-char-choice
   (format "Restore %S to %S (%s)? [y]es [n]o [!]all [q]uit "
           old new rule)
   '(?y ?n ?! ?q ?\s ?\d)))

(defun restore-latex-backslashes--query-edits (edits state)
  "Ask about each of EDITS and apply the accepted ones.
STATE is a cons cell whose car becomes non-nil once the user answers
\"!\" and whose cdr becomes non-nil once the user answers \"q\".
Return the number of edits applied."
  (let ((markers (mapcar (lambda (edit)
                           (list (copy-marker (nth 0 edit))
                                 (copy-marker (nth 1 edit))
                                 (nth 2 edit) (nth 3 edit)))
                         edits))
        (count 0)
        (overlay nil))
    (unwind-protect
        (dolist (m markers)
          (unless (cdr state)
            (let* ((beg (marker-position (nth 0 m)))
                   (end (marker-position (nth 1 m)))
                   (answer
                    (if (car state)
                        ?!
                      (goto-char beg)
                      (setq overlay (make-overlay beg end))
                      (overlay-put overlay 'face
                                   'restore-latex-backslashes-query-face)
                      (prog1 (funcall restore-latex-backslashes-query-function
                                      (buffer-substring-no-properties beg end)
                                      (nth 2 m) (nth 3 m))
                        (delete-overlay overlay)
                        (setq overlay nil)))))
              (pcase answer
                (?! (setcar state t)
                    (restore-latex-backslashes--replace beg end (nth 2 m))
                    (setq count (1+ count)))
                ((or ?y ?\s)
                 (restore-latex-backslashes--replace beg end (nth 2 m))
                 (setq count (1+ count)))
                (?q (setcdr state t))
                (_ nil)))))
      (when overlay (delete-overlay overlay))
      (dolist (m markers)
        (set-marker (nth 0 m) nil)
        (set-marker (nth 1 m) nil)))
    count))

(defun restore-latex-backslashes--process (beg end &optional query)
  "Restore backslashes between BEG and END in the current buffer.
When QUERY is non-nil, ask before each change.  Return an alist
that maps each rule to the number of changes it made."
  (let ((case-fold-search nil)
        (state (cons nil nil))
        (stats nil))
    (save-excursion
      (save-restriction
        (narrow-to-region beg end)
        (dolist (rule restore-latex-backslashes-rules)
          (unless (cdr state)
            (let ((fn (alist-get rule restore-latex-backslashes--rule-functions)))
              (unless fn
                (user-error "Unknown rule in `restore-latex-backslashes-rules': %S"
                            rule))
              (let* ((edits (restore-latex-backslashes--clean-edits (funcall fn)))
                     (count (if query
                                (restore-latex-backslashes--query-edits edits state)
                              (restore-latex-backslashes--apply-edits edits))))
                (push (cons rule count) stats)))))))
    (nreverse stats)))

(defun restore-latex-backslashes--total (stats)
  "Return the sum of the counts in STATS."
  (apply #'+ (mapcar #'cdr stats)))

(defun restore-latex-backslashes-summary (stats)
  "Return a one-line description of STATS.
STATS is the alist that the restoration functions return."
  (let ((total (restore-latex-backslashes--total stats))
        (parts (delq nil (mapcar (lambda (s)
                                   (when (> (cdr s) 0)
                                     (format "%s %d" (car s) (cdr s))))
                                 stats))))
    (if (zerop total)
        "No backslashes needed restoring"
      (format "Restored %d backslash%s (%s)" total
              (if (= total 1) "" "es")
              (string-join parts ", ")))))

(defun restore-latex-backslashes--report (stats)
  "Show the summary of STATS when `restore-latex-backslashes-verbose' is set."
  (when restore-latex-backslashes-verbose
    (message "%s" (restore-latex-backslashes-summary stats)))
  stats)

(defun restore-latex-backslashes--run-undoably (beg end query)
  "Restore between BEG and END as one undoable change.
QUERY is passed to `restore-latex-backslashes--process'.  Return the
statistics alist."
  (barf-if-buffer-read-only)
  (let ((group (prepare-change-group))
        (done nil)
        (stats nil))
    (unwind-protect
        (progn
          (activate-change-group group)
          (setq stats (restore-latex-backslashes--process beg end query))
          (setq done t))
      (if done
          (progn (accept-change-group group)
                 (undo-amalgamate-change-group group))
        (cancel-change-group group)))
    stats))

;;;; Public API

;;;###autoload
(defun restore-latex-backslashes-string (string)
  "Return a copy of STRING with stripped LaTeX backslashes restored."
  (with-temp-buffer
    (insert string)
    (restore-latex-backslashes--process (point-min) (point-max))
    (buffer-string)))

;;;###autoload
(defun restore-latex-backslashes-region (beg end)
  "Restore stripped LaTeX backslashes between BEG and END.
Return an alist that maps each rule to its number of changes.  The
whole operation is a single undoable change."
  (interactive "r")
  (restore-latex-backslashes--report
   (restore-latex-backslashes--run-undoably beg end nil)))

;;;###autoload
(defun restore-latex-backslashes-buffer ()
  "Restore stripped LaTeX backslashes in the whole buffer.
Narrowing is respected.  Return an alist that maps each rule to its
number of changes."
  (interactive)
  (restore-latex-backslashes-region (point-min) (point-max)))

;;;###autoload
(defun restore-latex-backslashes ()
  "Restore stripped LaTeX backslashes in the region or the buffer.
When the region is active, repair only the region.  Otherwise repair
the accessible part of the buffer."
  (interactive)
  (if (use-region-p)
      (restore-latex-backslashes-region (region-beginning) (region-end))
    (restore-latex-backslashes-buffer)))

;;;###autoload
(defun restore-latex-backslashes-query ()
  "Restore stripped LaTeX backslashes, asking before each change.
Work on the region when it is active and on the buffer otherwise.
Answer y or SPC to accept a change, n or DEL to skip it, ! to
accept all remaining changes, and q to stop."
  (interactive)
  (let ((beg (if (use-region-p) (region-beginning) (point-min)))
        (end (if (use-region-p) (region-end) (point-max))))
    (deactivate-mark)
    (restore-latex-backslashes--report
     (restore-latex-backslashes--run-undoably beg end t))))

(defun restore-latex-backslashes--diff-buffers (old-buffer new-buffer stats)
  "Show a diff from OLD-BUFFER to NEW-BUFFER and report STATS."
  (require 'diff)
  (if (zerop (restore-latex-backslashes--total stats))
      (message "No backslashes needed restoring")
    (let ((out (get-buffer-create "*restore-latex-backslashes diff*")))
      (diff-no-select old-buffer new-buffer "-u" t out)
      (display-buffer out)
      (restore-latex-backslashes--report stats))))

;;;###autoload
(defun restore-latex-backslashes-diff ()
  "Display a diff of what restoration would do, without editing text.
The proposed edits are shown as a unified diff of the accessible part of the
current buffer.  Return the statistics alist."
  (interactive)
  (let ((text (buffer-substring-no-properties (point-min) (point-max)))
        (copy (generate-new-buffer " *restore-latex-backslashes copy*"))
        (original (generate-new-buffer " *restore-latex-backslashes original*"))
        (stats nil))
    (unwind-protect
        (progn
          (with-current-buffer original (insert text))
          (with-current-buffer copy
            (insert text)
            (setq stats (restore-latex-backslashes--process (point-min) (point-max))))
          (restore-latex-backslashes--diff-buffers original copy stats))
      (kill-buffer copy)
      (kill-buffer original))
    stats))

(defun restore-latex-backslashes--read-tex-file (prompt)
  "Read the name of an existing file with PROMPT."
  (let ((default (and buffer-file-name
                      (string-match-p "\\.tex\\'" buffer-file-name)
                      buffer-file-name)))
    (expand-file-name
     (read-file-name prompt nil default t
                     (and default (file-name-nondirectory default))))))

(defun restore-latex-backslashes--file-contents (file)
  "Return a cons (TEXT . CODING) with the contents of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (cons (buffer-string) last-coding-system-used)))

;;;###autoload
(defun restore-latex-backslashes-file (file &optional output-file)
  "Restore stripped LaTeX backslashes in FILE on disk.
When OUTPUT-FILE is nil, repair FILE in place.  Before an in-place
repair, copy FILE to FILE plus `restore-latex-backslashes-backup-suffix'
unless that option is nil.  When OUTPUT-FILE is non-nil, write the
repaired text there and leave FILE untouched.

Interactively, prompt for FILE.  With a prefix argument, also prompt
for OUTPUT-FILE.  If a buffer visits FILE and has unsaved changes,
signal an error rather than overwrite them.  A buffer that visits the
file and has no unsaved changes is reverted afterwards.  Return the
statistics alist."
  (interactive
   (let ((file (restore-latex-backslashes--read-tex-file
                "Restore backslashes in file: ")))
     (list file
           (when current-prefix-arg
             (expand-file-name
              (read-file-name "Write repaired text to: "
                              (file-name-directory file)))))))
  (setq file (expand-file-name file))
  (unless (file-readable-p file)
    (user-error "Cannot read %s" file))
  (let ((visiting (find-buffer-visiting file)))
    (when (and visiting (null output-file) (buffer-modified-p visiting))
      (user-error "Buffer %s has unsaved changes; save or revert it first"
                  (buffer-name visiting))))
  (let* ((contents (restore-latex-backslashes--file-contents file))
         (target (if output-file (expand-file-name output-file) file))
         (stats nil))
    (with-temp-buffer
      (insert (car contents))
      (setq stats (restore-latex-backslashes--process (point-min) (point-max)))
      (when (or output-file (> (restore-latex-backslashes--total stats) 0))
        (when (and (null output-file) restore-latex-backslashes-backup-suffix)
          (copy-file file (concat file restore-latex-backslashes-backup-suffix) t))
        (let ((coding-system-for-write (cdr contents)))
          (write-region (point-min) (point-max) target nil 'silent))))
    (let ((visiting (find-buffer-visiting target)))
      (when (and visiting (not (buffer-modified-p visiting)))
        (with-current-buffer visiting
          (revert-buffer t t t))))
    (restore-latex-backslashes--report stats)))

;;;###autoload
(defun restore-latex-backslashes-diff-file (file)
  "Display a diff of what restoration would do to FILE on disk.
FILE is not modified.  Return the statistics alist."
  (interactive
   (list (restore-latex-backslashes--read-tex-file
          "Preview restoration of file: ")))
  (let ((copy (generate-new-buffer " *restore-latex-backslashes copy*"))
        (stats nil))
    (unwind-protect
        (progn
          (with-current-buffer copy
            (insert (car (restore-latex-backslashes--file-contents file)))
            (setq stats (restore-latex-backslashes--process (point-min) (point-max))))
          (restore-latex-backslashes--diff-buffers (expand-file-name file) copy stats))
      (kill-buffer copy))
    stats))

(declare-function diff-no-select "diff")
(declare-function dired-get-marked-files "dired")
(declare-function dired-revert "dired")

;;;###autoload
(defun restore-latex-backslashes-dired ()
  "Restore stripped LaTeX backslashes in the files marked in Dired.
Each file is repaired in place, as by `restore-latex-backslashes-file'."
  (interactive)
  (require 'dired)
  (let ((files (dired-get-marked-files))
        (total 0))
    (let ((restore-latex-backslashes-verbose nil))
      (dolist (file files)
        (setq total (+ total (restore-latex-backslashes--total
                              (restore-latex-backslashes-file file))))))
    (when (derived-mode-p 'dired-mode)
      (dired-revert))
    (message "Restored %d backslash%s in %d file%s"
             total (if (= total 1) "" "es")
             (length files) (if (= (length files) 1) "" "s"))))

;;;###autoload
(defun restore-latex-backslashes-batch ()
  "Repair the files named on the command line, then exit Emacs.
Use this from the shell:

  `emacs --batch -l restore-latex-backslashes.el
     -f restore-latex-backslashes-batch [--dry-run] [--no-backup] FILE...'

With --dry-run, report the changes without writing any file.  With
--no-backup, do not make backup copies.  The exit status is 0 on
success and 1 when any file could not be processed."
  (unless noninteractive
    (user-error "`restore-latex-backslashes-batch' is for batch mode only"))
  (let ((args command-line-args-left)
        (dry-run nil)
        (files nil)
        (status 0)
        (restore-latex-backslashes-verbose nil)
        (restore-latex-backslashes-backup-suffix
         restore-latex-backslashes-backup-suffix))
    (setq command-line-args-left nil)
    (dolist (arg args)
      (cond ((string= arg "--dry-run") (setq dry-run t))
            ((string= arg "--no-backup")
             (setq restore-latex-backslashes-backup-suffix nil))
            (t (push arg files))))
    (dolist (file (nreverse files))
      (condition-case err
          (let ((stats
                 (if dry-run
                     (with-temp-buffer
                       (insert (car (restore-latex-backslashes--file-contents file)))
                       (restore-latex-backslashes--process (point-min) (point-max)))
                   (restore-latex-backslashes-file file))))
            (princ (format "%s: %s%s\n" file
                           (restore-latex-backslashes-summary stats)
                           (if dry-run " [dry run]" ""))))
        (error
         (setq status 1)
         (princ (format "%s: error: %s\n" file (error-message-string err))))))
    (kill-emacs status)))

(provide 'restore-latex-backslashes)
;;; restore-latex-backslashes.el ends here
