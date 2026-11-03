# makefile
CRYSTAL ?= crystal
THREADS ?= 2

.PHONY: all help spec bench tables

all: help

help:               ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36mmake %-18s\033[0m \033[2;37m%s\033[0m\n", $$1, $$2}'

spec:               ## Run spec suite
	$(CRYSTAL) spec --threads $(THREADS)

bench:              ## Run bench suite
	@rm -f bench-suite
	$(CRYSTAL) build --release --no-debug --threads $(THREADS) bench/all.cr -o bench-suite
	./bench-suite
	@rm -f bench-suite

tables:             ## Regenerate data/tables.bin and spec/data from unicode.org (UCD=dir for a local mirror)
	$(CRYSTAL) run --threads $(THREADS) tools/gen_tables.cr -- $(UCD)
