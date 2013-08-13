#!/bin/sh

set -e

git submodule update --init

if ! [ -x menhir-bin/bin/menhir ]; then
  echo "Building menhir..."
  (cd menhir;
   # Fails on manual.pdf or something.
   make PREFIX=$(pwd)/../menhir-bin/ install || true)
fi

if ! [ -x merr/merr.native ]; then
  echo "Building merr..."
  (cd merr;
   ocamlbuild -use-ocamlfind merr/merr.native;
   ocamlbuild -use-ocamlfind merr/merr.native)
fi

echo "Building foundry..."
ocamlbuild -use-ocamlfind foundry.native