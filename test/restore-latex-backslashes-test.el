;;; restore-latex-backslashes-test.el --- Tests for restore-latex-backslashes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
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

;; Run the suite with "make test" or with
;;
;;   emacs -Q --batch -L . -l test/restore-latex-backslashes-test.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'restore-latex-backslashes)

(defconst rlb-test-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory that holds this test file.")

(defun rlb-test-fixture (name)
  "Return the absolute file name of fixture NAME."
  (expand-file-name (concat "fixtures/" name) rlb-test-directory))

(defun rlb-test-read (file)
  "Return the contents of FILE as a string."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix))
      (insert-file-contents file))
    (buffer-string)))

(defun rlb-test-strip (string)
  "Return STRING with every backslash deleted."
  (replace-regexp-in-string "\\\\" "" string t t))

(defun rlb-test-unescape (string)
  "Return STRING after Python-style escape processing.
\\\\ becomes \\, and \\a \\b \\f \\n \\r \\t \\v become control
characters.  Other backslashes are kept, as Python keeps them."
  (replace-regexp-in-string
   "\\\\\\([\\\\abfnrtv]\\)"
   (lambda (match)
     (pcase (aref match 1)
       (?\\ "\\")
       (?a "\a") (?b "\b") (?f "\f") (?n "\n")
       (?r "\r") (?t "\t") (?v "\v")))
   string t t))

(defmacro rlb-test-with-defaults (&rest body)
  "Run BODY with every option of the package at its default value."
  (declare (indent 0) (debug t))
  `(let ((restore-latex-backslashes-rules
          (eval (car (get 'restore-latex-backslashes-rules 'standard-value))))
         (restore-latex-backslashes-row-ends 'single)
         (restore-latex-backslashes-verbose nil)
         (restore-latex-backslashes-backup-suffix ".orig"))
     ,@body))

(defun rlb (string)
  "Restore STRING with default settings."
  (rlb-test-with-defaults (restore-latex-backslashes-string string)))

(defmacro rlb-test-temp-dir (var &rest body)
  "Bind VAR to a fresh temporary directory while running BODY."
  (declare (indent 1) (debug t))
  `(let ((,var (make-temp-file "rlb-test-" t)))
     (unwind-protect (progn ,@body)
       (delete-directory ,var t))))

;;;; Environments and braced commands

(ert-deftest rlb-test-environments ()
  (should (equal (rlb "begin{document}\nend{document}")
                 "\\begin{document}\n\\end{document}"))
  (should (equal (rlb "the end of the story") "the end of the story")))

(ert-deftest rlb-test-braced-commands ()
  (should (equal (rlb "section{Intro}") "\\section{Intro}"))
  (should (equal (rlb "section*{Intro}") "\\section*{Intro}"))
  (should (equal (rlb "usepackage[margin=1in]{geometry}")
                 "\\usepackage[margin=1in]{geometry}"))
  (should (equal (rlb "See textbf{this} and emph{that}.")
                 "See \\textbf{this} and \\emph{that}."))
  (should (equal (rlb "Section~ref{sec:a}") "Section~\\ref{sec:a}")))

(ert-deftest rlb-test-braced-requires-argument ()
  (should (equal (rlb "In section 3 the title was long.")
                 "In section 3 the title was long."))
  (should (equal (rlb "a subsection{x}") "a \\subsection{x}"))
  (should (equal (rlb "mysection{x}") "mysection{x}")))

(ert-deftest rlb-test-nested-braced ()
  (should (equal (rlb "$frac{sqrt{a}}{b}$") "$\\frac{\\sqrt{a}}{b}$")))

;;;; Anywhere, line, and item rules

(ert-deftest rlb-test-anywhere ()
  (should (equal (rlb "noindent Text") "\\noindent Text"))
  (should (equal (rlb "width=0.5textwidth") "width=0.5\\textwidth"))
  (should (equal (rlb "maketitle") "\\maketitle")))

(ert-deftest rlb-test-line-commands ()
  (should (equal (rlb "  centering\n") "  \\centering\n"))
  (should (equal (rlb "The centering of the beam.")
                 "The centering of the beam."))
  (should (equal (rlb "appendix\nsection{A}") "\\appendix\n\\section{A}")))

(ert-deftest rlb-test-item-in-list ()
  (should (equal (rlb "begin{itemize}\n  item One\n  item[b] Two\nend{itemize}")
                 "\\begin{itemize}\n  \\item One\n  \\item[b] Two\n\\end{itemize}")))

(ert-deftest rlb-test-item-outside-list ()
  (should (equal (rlb "item number one is here") "item number one is here")))

(ert-deftest rlb-test-item-mid-line ()
  (should (equal (rlb "begin{enumerate}\nitem An item of note\nend{enumerate}")
                 "\\begin{enumerate}\n\\item An item of note\n\\end{enumerate}")))

;;;; Math

(ert-deftest rlb-test-inline-math ()
  (should (equal (rlb "$alpha + beta leq gamma$")
                 "$\\alpha + \\beta \\leq \\gamma$")))

(ert-deftest rlb-test-display-math ()
  (should (equal (rlb "$$sum_{i=1}^n x_i to infty$$")
                 "$$\\sum_{i=1}^n x_i \\to \\infty$$")))

(ert-deftest rlb-test-math-environment ()
  (should (equal (rlb "begin{equation}\nE = mc^2 times pi\nend{equation}")
                 "\\begin{equation}\nE = mc^2 \\times \\pi\n\\end{equation}")))

(ert-deftest rlb-test-prose-greek-untouched ()
  (should (equal (rlb "The alpha helix and beta sheet in times past.")
                 "The alpha helix and beta sheet in times past.")))

(ert-deftest rlb-test-math-text-arguments ()
  (should (equal (rlb "$x text{in the limit} to 0$")
                 "$x \\text{in the limit} \\to 0$")))

(ert-deftest rlb-test-math-subscript-exclusions ()
  (should (equal (rlb "$T_{max} in S$") "$T_{max} \\in S$"))
  (should (equal (rlb "$x_in$") "$x_in$"))
  (should (equal (rlb "$x_{alpha}$") "$x_{\\alpha}$")))

(ert-deftest rlb-test-currency-not-math ()
  (should (equal (rlb "It costs $5 in total and $10 to sum up.")
                 "It costs $5 in total and $10 to sum up.")))

(ert-deftest rlb-test-left-right ()
  (should (equal (rlb "$left( x right)$") "$\\left( x \\right)$")))

(ert-deftest rlb-test-existing-delimiters ()
  (should (equal (rlb "\\(alpha\\) and \\[beta\\]")
                 "\\(\\alpha\\) and \\[\\beta\\]")))

;;;; Special characters

(ert-deftest rlb-test-percent ()
  (should (equal (rlb "In 50% of cases") "In 50\\% of cases"))
  (should (equal (rlb "% a comment") "% a comment"))
  (should (equal (rlb "50\\% done") "50\\% done")))

(ert-deftest rlb-test-ampersand ()
  (should (equal (rlb "Smith & Jones") "Smith \\& Jones"))
  (should (equal (rlb "begin{tabular}{ll}\na & b\nend{tabular}")
                 "\\begin{tabular}{ll}\na & b\n\\end{tabular}"))
  (should (equal (rlb "a & b & c") "a & b & c"))
  (should (equal (rlb "a & b \\\\") "a & b \\\\")))

;;;; Row ends

(ert-deftest rlb-test-row-ends-single ()
  (should (equal (rlb "begin{tabular}{ll}\na & b \\\nc & d\nend{tabular}")
                 "\\begin{tabular}{ll}\na & b \\\\\nc & d\n\\end{tabular}")))

(ert-deftest rlb-test-row-ends-all ()
  (rlb-test-with-defaults
    (let ((restore-latex-backslashes-row-ends 'all))
      (should (equal (restore-latex-backslashes-string
                      "begin{tabular}{ll}\na & b\nc & d\nend{tabular}")
                     "\\begin{tabular}{ll}\na & b \\\\\nc & d\n\\end{tabular}")))))

(ert-deftest rlb-test-row-ends-off ()
  (rlb-test-with-defaults
    (let ((restore-latex-backslashes-row-ends nil))
      (should (equal (restore-latex-backslashes-string
                      "begin{tabular}{ll}\na & b \\\nend{tabular}")
                     "\\begin{tabular}{ll}\na & b \\\n\\end{tabular}")))))

;;;; Escape sequences

(ert-deftest rlb-test-escapes-control-characters ()
  (should (equal (rlb "\frac{1}{2}") "\\frac{1}{2}"))
  (should (equal (rlb "\begin{document}") "\\begin{document}"))
  (should (equal (rlb "$\alpha$") "$\\alpha$"))
  (should (equal (rlb "\vec{v}") "\\vec{v}"))
  (should (equal (rlb "\ref{x}") "\\ref{x}")))

(ert-deftest rlb-test-escapes-tab-and-newline ()
  (should (equal (rlb "\textbf{x}") "\\textbf{x}"))
  (should (equal (rlb "a\newline b") "a\\newline b"))
  (should (equal (rlb "$x \times y$") "$x \\times y$")))

(ert-deftest rlb-test-escapes-leave-real-whitespace ()
  (should (equal (rlb "\tindented text\nheading") "\tindented text\nheading"))
  (should (equal (rlb "see\neq. 3") "see\neq. 3"))
  (should (equal (rlb "\f\n") "\f\n")))

(ert-deftest rlb-test-escaped-fixture ()
  (let* ((original (rlb-test-read (rlb-test-fixture "escaped-sample.tex")))
         (damaged (rlb-test-unescape original)))
    (should-not (equal damaged original))
    (should (equal (rlb damaged) original))))

;;;; Protection

(ert-deftest rlb-test-verbatim-protected ()
  (should (equal (rlb "begin{verbatim}\nsection{x} alpha 50%\nend{verbatim}")
                 "\\begin{verbatim}\nsection{x} alpha 50%\n\\end{verbatim}")))

(ert-deftest rlb-test-inline-verb-protected ()
  (should (equal (rlb "\\verb|section{x}| section{y}")
                 "\\verb|section{x}| \\section{y}")))

(ert-deftest rlb-test-arguments-protected ()
  (should (equal (rlb "usepackage{parskip}") "\\usepackage{parskip}"))
  (should (equal (rlb "url{http://a.org/50%25&b}")
                 "\\url{http://a.org/50%25&b}"))
  (should (equal (rlb "label{eq:sum}") "\\label{eq:sum}")))

;;;; Engine behavior

(ert-deftest rlb-test-idempotent ()
  (let* ((stripped (rlb-test-strip (rlb-test-read (rlb-test-fixture "sample.tex"))))
         (once (rlb stripped)))
    (should (equal (rlb once) once))))

(ert-deftest rlb-test-already-correct-unchanged ()
  (rlb-test-with-defaults
    (let ((restore-latex-backslashes-row-ends 'all)
          (original (rlb-test-read (rlb-test-fixture "sample.tex"))))
      (should (equal (restore-latex-backslashes-string original) original)))))

(ert-deftest rlb-test-sample-round-trip ()
  (rlb-test-with-defaults
    (let* ((restore-latex-backslashes-row-ends 'all)
           (original (rlb-test-read (rlb-test-fixture "sample.tex")))
           (stripped (rlb-test-strip original)))
      (should (equal (restore-latex-backslashes-string stripped) original)))))

(ert-deftest rlb-test-rule-selection ()
  (rlb-test-with-defaults
    (let ((restore-latex-backslashes-rules '(braced)))
      (should (equal (restore-latex-backslashes-string "begin{x} section{y}")
                     "begin{x} \\section{y}")))))

(ert-deftest rlb-test-unknown-rule ()
  (rlb-test-with-defaults
    (let ((restore-latex-backslashes-rules '(no-such-rule)))
      (should-error (restore-latex-backslashes-string "x") :type 'user-error))))

(ert-deftest rlb-test-custom-command ()
  (rlb-test-with-defaults
    (let ((restore-latex-backslashes-braced-commands
           (cons "mymacro" restore-latex-backslashes-braced-commands)))
      (should (equal (restore-latex-backslashes-string "mymacro{x}")
                     "\\mymacro{x}")))))

(ert-deftest rlb-test-summary ()
  (should (equal (restore-latex-backslashes-summary '((braced . 0)))
                 "No backslashes needed restoring"))
  (should (equal (restore-latex-backslashes-summary '((braced . 1) (math . 0)))
                 "Restored 1 backslash (braced 1)"))
  (should (equal (restore-latex-backslashes-summary '((braced . 2) (math . 3)))
                 "Restored 5 backslashes (braced 2, math 3)")))

;;;; Interactive commands

(ert-deftest rlb-test-buffer-command-and-undo ()
  (rlb-test-with-defaults
    (with-temp-buffer
      (buffer-enable-undo)
      (insert "section{A}\n$alpha$\n")
      (undo-boundary)
      (let ((stats (restore-latex-backslashes-buffer)))
        (should (= (alist-get 'braced stats) 1))
        (should (= (alist-get 'math stats) 1)))
      (should (equal (buffer-string) "\\section{A}\n$\\alpha$\n"))
      ;; One undo step returns the original text.
      (undo-boundary)
      (let ((last-command nil)) (undo))
      (should (equal (buffer-string) "section{A}\n$alpha$\n")))))

(ert-deftest rlb-test-region-command ()
  (rlb-test-with-defaults
    (with-temp-buffer
      (insert "section{A}\nsection{B}\n")
      (restore-latex-backslashes-region (point-min) 12)
      (should (equal (buffer-string) "\\section{A}\nsection{B}\n")))))

(ert-deftest rlb-test-dwim-uses-region ()
  (rlb-test-with-defaults
    (with-temp-buffer
      (insert "section{A}\nsection{B}\n")
      (transient-mark-mode 1)
      (goto-char 12)
      (push-mark (point-max) t t)
      (restore-latex-backslashes)
      (should (equal (buffer-string) "section{A}\n\\section{B}\n")))))

(ert-deftest rlb-test-read-only-buffer ()
  (rlb-test-with-defaults
    (with-temp-buffer
      (insert "section{A}")
      (setq buffer-read-only t)
      (should-error (restore-latex-backslashes-buffer) :type 'buffer-read-only))))

(defun rlb-test-query (answers text)
  "Run query mode on TEXT, answering with the characters in ANSWERS."
  (rlb-test-with-defaults
    (with-temp-buffer
      (insert text)
      (let ((restore-latex-backslashes-query-function
             (lambda (_old _new _rule) (or (pop answers) ?n))))
        (restore-latex-backslashes-query))
      (buffer-string))))

(ert-deftest rlb-test-query-yes-no ()
  (should (equal (rlb-test-query (list ?y ?n ?y) "section{A} section{B} section{C}")
                 "\\section{A} section{B} \\section{C}")))

(ert-deftest rlb-test-query-all ()
  (should (equal (rlb-test-query (list ?n ?!) "section{A} section{B} $alpha$")
                 "section{A} \\section{B} $\\alpha$")))

(ert-deftest rlb-test-query-quit ()
  (should (equal (rlb-test-query (list ?y ?q) "section{A} section{B} $alpha$")
                 "\\section{A} section{B} $alpha$")))

(ert-deftest rlb-test-diff-command ()
  (rlb-test-with-defaults
    (with-temp-buffer
      (insert "section{A}\n")
      (let ((stats (restore-latex-backslashes-diff)))
        (should (= (restore-latex-backslashes--total stats) 1)))
      ;; The buffer itself is not modified.
      (should (equal (buffer-string) "section{A}\n"))
      (with-current-buffer "*restore-latex-backslashes diff*"
        (should (string-match-p "^\\+\\\\section{A}" (buffer-string)))))))

;;;; File commands

(ert-deftest rlb-test-file-in-place-with-backup ()
  (rlb-test-with-defaults
    (rlb-test-temp-dir dir
      (let ((file (expand-file-name "paper.tex" dir)))
        (with-temp-file file (insert "section{A}\n"))
        (restore-latex-backslashes-file file)
        (should (equal (rlb-test-read file) "\\section{A}\n"))
        (should (equal (rlb-test-read (concat file ".orig")) "section{A}\n"))))))

(ert-deftest rlb-test-file-no-backup ()
  (rlb-test-with-defaults
    (let ((restore-latex-backslashes-backup-suffix nil))
      (rlb-test-temp-dir dir
        (let ((file (expand-file-name "paper.tex" dir)))
          (with-temp-file file (insert "section{A}\n"))
          (restore-latex-backslashes-file file)
          (should-not (file-exists-p (concat file ".orig"))))))))

(ert-deftest rlb-test-file-unchanged-not-written ()
  (rlb-test-with-defaults
    (rlb-test-temp-dir dir
      (let ((file (expand-file-name "paper.tex" dir)))
        (with-temp-file file (insert "\\section{A}\n"))
        (restore-latex-backslashes-file file)
        (should-not (file-exists-p (concat file ".orig")))))))

(ert-deftest rlb-test-file-to-output ()
  (rlb-test-with-defaults
    (rlb-test-temp-dir dir
      (let ((file (expand-file-name "in.tex" dir))
            (out (expand-file-name "out.tex" dir)))
        (with-temp-file file (insert "section{A}\n"))
        (restore-latex-backslashes-file file out)
        (should (equal (rlb-test-read file) "section{A}\n"))
        (should (equal (rlb-test-read out) "\\section{A}\n"))
        (should-not (file-exists-p (concat file ".orig")))))))

(ert-deftest rlb-test-file-utf8 ()
  (rlb-test-with-defaults
    (rlb-test-temp-dir dir
      (let ((file (expand-file-name "utf.tex" dir)))
        (let ((coding-system-for-write 'utf-8))
          (with-temp-file file (insert "section{Ångström café}\n")))
        (restore-latex-backslashes-file file)
        (should (equal (rlb-test-read file) "\\section{Ångström café}\n"))))))

(ert-deftest rlb-test-file-refuses-modified-buffer ()
  (rlb-test-with-defaults
    (rlb-test-temp-dir dir
      (let ((file (expand-file-name "paper.tex" dir)))
        (with-temp-file file (insert "section{A}\n"))
        (let ((buf (find-file-noselect file)))
          (unwind-protect
              (progn
                (with-current-buffer buf (insert "x"))
                (should-error (restore-latex-backslashes-file file)
                              :type 'user-error))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))))))

(ert-deftest rlb-test-file-reverts-visiting-buffer ()
  (rlb-test-with-defaults
    (rlb-test-temp-dir dir
      (let ((file (expand-file-name "paper.tex" dir)))
        (with-temp-file file (insert "section{A}\n"))
        (let ((buf (find-file-noselect file)))
          (unwind-protect
              (progn
                (restore-latex-backslashes-file file)
                (with-current-buffer buf
                  (should (equal (buffer-string) "\\section{A}\n"))))
            (kill-buffer buf)))))))

(ert-deftest rlb-test-diff-file ()
  (rlb-test-with-defaults
    (rlb-test-temp-dir dir
      (let ((file (expand-file-name "paper.tex" dir)))
        (with-temp-file file (insert "section{A}\n"))
        (should (= 1 (restore-latex-backslashes--total
                      (restore-latex-backslashes-diff-file file))))
        (should (equal (rlb-test-read file) "section{A}\n"))))))

(ert-deftest rlb-test-batch ()
  (rlb-test-temp-dir dir
    (let ((file (expand-file-name "paper.tex" dir))
          (lib (locate-library "restore-latex-backslashes.el" t)))
      (with-temp-file file (insert "section{A}\n"))
      (let ((output
             (with-temp-buffer
               (list (call-process (expand-file-name invocation-name
                                                     invocation-directory)
                                   nil t nil "-Q" "--batch" "-l" lib
                                   "-f" "restore-latex-backslashes-batch"
                                   "--no-backup" file)
                     (buffer-string)))))
        (should (= (car output) 0))
        (should (string-match-p "Restored 1 backslash" (cadr output)))
        (should (equal (rlb-test-read file) "\\section{A}\n"))
        (should-not (file-exists-p (concat file ".orig")))))))

(provide 'restore-latex-backslashes-test)
;;; restore-latex-backslashes-test.el ends here
