# bartleby

> "I would prefer not to."

A scrivener for gopherspace. Bartleby walks a directory, reads
sidecar `.bcard` metadata, and writes a gopher menu tree under
`catalog/`. Not a blog engine. Not Jekyll for gopher. Your
gopherhole is a library, not a website, and bartleby is a
librarian, not a web developer.

**Status:** MVP under development. The full specification lives in
[`bartleby-plan.md`](./bartleby-plan.md).

## What it does

Gopher was modeled on library information systems — a tree of
menus, not a stream of posts. Bartleby takes that seriously.
Collections are the primary axis. Directories are classifications.
Files (and directories with sidecar `.bcard` metadata) are works.
Walk the stacks, don't scroll a timeline.

Given a library directory:

```
my-library/
  bartleby.conf
  recipes.bcard            # optional metadata for recipes/
  recipes/
    cheesecake.jpg
    cheesecake.jpg.bcard   # optional metadata for cheesecake.jpg
    march-rain.txt.bcard
    march-rain.txt
  poetry/
    ...
```

bartleby emits `catalog/` alongside it:

```
my-library/
  catalog/                  # everything bartleby generates lives here
    .gophermap              # the root card catalog
    feed.xml                # atom feed of the whole library
    recipes/
      .gophermap
      feed.xml
    poetry/
      .gophermap
      feed.xml
```

`catalog/` is the **only** thing bartleby writes. Your source tree
is never touched. Delete `catalog/` and the library is exactly as
you wrote it.

## Usage

```
bartleby /path/to/library
```

Point a gopher daemon at the library; share
`gopher://host:port/1/<selector>/catalog/` as the entry URL.

## Build from source

Requires [Stack](https://docs.haskellstack.org/).

```
stack build
stack test
stack install
```

First build pulls in [Venusia](https://github.com/someodd/venusia)
(the gopher library that handles menu formatting), pinned to a
specific commit in `stack.yaml`.

## License

GPL-3.0-or-later. See [LICENSE](./LICENSE).
