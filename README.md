[![Build Status](https://travis-ci.com/Raku/rakudoc.svg?branch=master)](https://travis-ci.com/Raku/rakudoc)

NAME
====

rakudoc - A tool for reading Raku documentation

SYNOPSIS
========

    rakudoc [-d|--doc-sources=<Directories>] [-D|--no-default-docs] <query>
    rakudoc -b|--build-index [-d|--doc-sources=<Directories>] [-D|--no-default-docs]
    rakudoc -V|--version
    rakudoc -h|--help <ARGUMENTS>

    <query>                           Example: 'Map', 'IO::Path.add', '.add'
    -d|--doc-sources=<Directories>    Additional directories to search for documentation
    -D|--no-default-docs              Use only directories in --doc / $RAKUDOC
    -b|--build-index                  Index all documents found in doc source directories

DESCRIPTION
===========

The `rakudoc` command displays Raku documentation for language features and installed modules.

ENVIRONMENT
===========

  * `RAKUDOC` — Comma-separated list of doc directories (e.g., `../doc/doc,./t/test-doc`); ignored if `--doc-sources` option is given

  * `RAKUDOC_DATA` — Path to directory where Rakudoc stores cache and index data

  * `RAKUDOC_PAGER` — Pager program (default: `$PAGER`)

LICENSE
=======

Rakudoc is Copyright (C) 2019–2021, by Joel Schüller, Tim Siegel and others.

It is free software; you can redistribute it and/or modify it under the terms of the [Artistic License 2.0](https://www.perlfoundation.org/artistic-license-20.html).

SAMPLE
======

Clone a copy of the Raku docs repo and index it.

```
$ cd ~/sandbox
$ git clone git@github.com:Raku/doc.git
$ zef install rakudoc
$ RAKUDOC=~/sandbox/doc/doc rakudoc -b
```

Now you can get documentation of types, methods, articles.

```
$ RAKUDOC=~/sandbox/doc/doc rakudoc -D Str          # TITLE class Str
$ RAKUDOC=~/sandbox/doc/doc rakudoc -D Match.target # Match's target method
$ RAKUDOC=~/sandbox/doc/doc rakudoc -D math         # Language/math article
```

Note that we are using the `doc` folder in the doc repo. 
