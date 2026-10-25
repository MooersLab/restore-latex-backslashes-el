# Makefile for restore-latex-backslashes
#
# Targets:
#   make test      run the ERT suite against the source file
#   make compile   byte-compile with warnings treated as errors
#   make test-elc  run the ERT suite against the compiled file
#   make checkdoc  check docstrings and comments
#   make lint      run package-lint (needs package-lint on the load path)
#   make example   restore examples/stripped-example.tex to standard output
#   make all       compile, checkdoc, and test
#   make clean     delete compiled files and test leftovers

EMACS ?= emacs
BATCH  = $(EMACS) -Q --batch -L .
PKG    = restore-latex-backslashes
TESTS  = test/$(PKG)-test.el

# Point this at a checkout of https://github.com/purcell/package-lint
# when package-lint is not installed in your user directory.
PACKAGE_LINT_DIR ?=

.PHONY: all test test-elc compile checkdoc lint example clean

all: compile checkdoc test-elc

test:
	$(BATCH) -l $(PKG).el -l $(TESTS) -f ert-run-tests-batch-and-exit

compile: clean
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(PKG).el

test-elc: compile
	$(BATCH) -l $(PKG).elc -l $(TESTS) -f ert-run-tests-batch-and-exit

CHECKDOC_FORM = (let ((bad nil)) (require (quote checkdoc)) (advice-add (quote display-warning) :before (lambda (&rest _) (setq bad t))) (checkdoc-file "$(PKG).el") (kill-emacs (if bad 1 0)))

checkdoc:
	$(BATCH) --eval '$(CHECKDOC_FORM)'

lint:
	$(BATCH) $(if $(PACKAGE_LINT_DIR),-L $(PACKAGE_LINT_DIR),) --eval '(progn (package-initialize) (require (quote package-lint)))' -f package-lint-batch-and-exit $(PKG).el

EXAMPLE_FORM = (with-temp-buffer (insert-file-contents "examples/stripped-example.tex") (let ((restore-latex-backslashes-row-ends (quote all))) (restore-latex-backslashes-buffer)) (princ (buffer-string)))

example:
	$(BATCH) -l $(PKG).el --eval '$(EXAMPLE_FORM)'

clean:
	rm -f *.elc test/*.elc
