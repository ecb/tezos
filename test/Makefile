
TESTS :=  data-encoding store context state basic basic.sh

all: test

INCLUDES = $(patsubst %, -I %, $(SOURCE_DIRECTORIES) lib)
OCAMLFLAGS = \
  -g -safe-string -w -40 \
  ${INCLUDES} \
  $(patsubst %, -package %, $(PACKAGES)) \
  ${EXTRA_OCAMLFLAGS}

SOURCE_DIRECTORIES := \
  lib \
$(addprefix ../src/, \
  minutils \
  utils \
  compiler \
  node/db \
  node/net \
  node/updater \
  node/shell \
  proto \
)

PACKAGES := \
  base64 \
  calendar \
  cohttp.lwt \
  compiler-libs.optcomp \
  config-file \
  cstruct \
  dynlink \
  ezjsonm \
  git \
  irmin.unix \
  lwt \
  lwt.unix \
  ocplib-endian \
  ocplib-ocamlres \
  ocplib-json-typed.bson \
  ocplib-resto.directory \
  sodium \
  unix \
  kaputt \

ifeq ($(strip ${COVERAGE}),yes)
PACKAGES += bisect_ppx.runtime
endif

############################################################################
## External packages

NODELIB := \
  ../src/minutils.cmxa ../src/utils.cmxa \
  ../src/compiler.cmxa ../src/node.cmxa
CLIENTLIB := ../src/client.cmxa \
  $(patsubst ../src/client/embedded/%/, \
	     ../src/proto/client_embedded_proto_%.cmxa, \
             $(shell ls -d ../src/client/embedded/*/)) \
  $(patsubst ../src/client/embedded/%/, \
             ../src/client/embedded/client_%.cmx, \
	     $(shell ls -d ../src/client/embedded/*/))

${NODELIB} ${CLIENTLIB}:
	${MAKE} -C ../src $@

.PHONY: build-test run-test test
build-test: ${addprefix build-test-,${TESTS}} test-p2p
run-test:
	@$(patsubst %,${MAKE} run-test-% ; , ${TESTS}) \
	  echo && echo "Success" && echo
test:
	@${MAKE} --no-print-directory build-test
	@${MAKE} --no-print-directory run-test

############################################################################
## Store test program

.PHONY:build-test-store run-test-store
build-test-store: test-store
run-test-store:
	./test-store

TEST_STORE_INTFS =

TEST_STORE_IMPLS = \
  lib/assert.ml \
  lib/test.ml \
  test_store.ml

${TEST_STORE_IMPLS:.ml=.cmx}: ${NODELIB}
test-store: ${NODELIB} ${TEST_STORE_IMPLS:.ml=.cmx}
	ocamlfind ocamlopt -linkall -linkpkg ${OCAMLFLAGS} -o $@ $^

clean::
	rm -f test-store


############################################################################
## Context test program

.PHONY:build-test-context run-test-context
build-test-context: test-context
run-test-context:
	./test-context

TEST_CONTEXT_INTFS =

TEST_CONTEXT_IMPLS = \
  lib/assert.ml \
  lib/test.ml \
  test_context.ml

${TEST_CONTEXT_IMPLS:.ml=.cmx}: ${NODELIB}
test-context: ${NODELIB} ${TEST_CONTEXT_IMPLS:.ml=.cmx}
	ocamlfind ocamlopt -linkall -linkpkg ${OCAMLFLAGS} -o $@ $^

clean::
	rm -f test-context


############################################################################
## State test program

.PHONY:build-test-state run-test-state
build-test-state: test-state
run-test-state:
	./test-state

TEST_STATE_INTFS =

TEST_STATE_IMPLS = \
  lib/assert.ml \
  lib/test.ml \
  test_state.ml

${TEST_STATE_IMPLS:.ml=.cmx}: ${NODELIB}
test-state: ${NODELIB} ../src/proto/embedded_proto_demo.cmxa ${TEST_STATE_IMPLS:.ml=.cmx}
	ocamlfind ocamlopt -linkall -linkpkg ${OCAMLFLAGS} -o $@ $^

clean::
	rm -f test-state


############################################################################
## Basic-client-functionality test program

.PHONY:build-test-basic.sh run-test-basic.sh
build-test-basic.sh:
run-test-basic.sh:
	./test-basic.sh

.PHONY:build-test-basic run-test-basic
build-test-basic: test-basic
run-test-basic:
	./test-basic

TEST_BASIC_INTFS =

TEST_BASIC_IMPLS = \
  lib/assert.ml \
  lib/test.ml \
  test_basic.ml

test-basic \
${TEST_BASIC_IMPLS:.ml=.cmx}: \
  SOURCE_DIRECTORIES+=../src/client ../src/client/embedded/

${TEST_BASIC_IMPLS:.ml=.cmx}: ${NODELIB} ${CLIENTLIB}
test-basic: ${NODELIB} ${CLIENTLIB} ${TEST_BASIC_IMPLS:.ml=.cmx}
	ocamlfind ocamlopt -linkall -linkpkg ${OCAMLFLAGS} -o $@ $^

clean::
	rm -f test-basic

############################################################################
## p2p test program

TEST_P2P_INTFS =

TEST_P2P_IMPLS = \
  test_p2p.ml

${TEST_BASIC_IMPLS:.ml=.cmx}: ${NODELIB}
test-p2p: ${NODELIB} ${TEST_P2P_IMPLS:.ml=.cmx}
	ocamlfind ocamlopt -linkall -linkpkg ${OCAMLFLAGS} -o $@ $^

clean::
	rm -f test-p2p

############################################################################
## data encoding test program

.PHONY:build-test-data-encoding run-test-data-encoding
build-test-data-encoding: test-data-encoding
run-test-data-encoding:
	./test-data-encoding

TEST_DATA_ENCODING_INTFS =

TEST_DATA_ENCODING_IMPLS = \
  lib/assert.ml \
  lib/test.ml \
  test_data_encoding.ml

${TEST_DATA_ENCODING_IMPLS:.ml=.cmx}: ${NODELIB}
test-data-encoding: ${NODELIB} ${TEST_DATA_ENCODING_IMPLS:.ml=.cmx}
	ocamlfind ocamlopt -linkall -linkpkg ${OCAMLFLAGS} -o $@ $^

clean::
	rm -f test-data-encoding

COVERAGESRCDIR= \
  -I ../src \
  -I ../src/client \
  -I ../src/client/embedded \
  -I ../src/client/embedded/bootstrap \
  -I ../src/client/embedded/bootstrap/mining \
  -I ../src/compiler \
  -I ../src/node \
  -I ../src/node/db \
  -I ../src/node/updater \
  -I ../src/node/net \
  -I ../src/node/shell \
  -I ../src/proto \
  -I ../src/proto/bootstrap \
  -I ../src/proto/demo \
  -I ../src/minutils \
  -I ../src/utils

bisect:
	bisect-ppx-report $(COVERAGESRCDIR) \
          -ignore-missing-files -html reports bisect*.out

############################################################################
## Generic rules

test.cmx: test.cmi

%.cmx: %.ml
	ocamlfind ocamlopt ${OCAMLFLAGS} -c $<

%.cmo: %.ml
	ocamlfind ocamlc ${OCAMLFLAGS} -c $<

%.cmi: %.mli
	ocamlfind ocamlc ${OCAMLFLAGS} -c $<

clean::
	-rm -f *.cm* lib/*.cm* *.out *.o

-include .depend
.depend: $(wildcard *.ml *.mli lib/*.ml lib/*.mli)
	ocamldep -I lib $^ > .depend

clean::
	-rm .depend
