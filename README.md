# bartleby

> "I would prefer not to."

A scrivener for gopherspace. Bartleby walks a directory, reads
sidecar `.bcard` metadata, and writes a gopher menu tree under
`catalog/`. Not a blog engine. Not Jekyll for gopher. Your
gopherhole is a library, not a website, and bartleby is a
librarian, not a web developer.

`catalog/` is the only thing bartleby writes. The source tree is
read-only — delete `catalog/` and your library is exactly as you
wrote it.

**Status:** MVP under development.

## What it does

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

Point a gopher daemon at the library; share
`gopher://host:port/1/<selector>/catalog/` as the entry URL.

## Reference

### Classifications vs works

Every directory in your library is either a **classification** (a
subject grouping bartleby recurses into) or a **work** (an opaque
"directory-as-book" treated as a single catalog entry). The default
is classification. A directory becomes a work when you place a
sibling `.bcard` next to it:

- `recipes/` alone → classification.
- `recipes/` with a sibling `recipes.bcard` → work.

A file directly inside a classification is cataloged as its own work.
**Files and directories inside a work-directory are not separately
cataloged** — they are part of the work. Readers reach them via the
gopher daemon's natural directory listing once they click into the
work.

To give a classification custom metadata (title, description) without
promoting it to a work, put `classification: true` in the bcard:

    # recipes.bcard — classification metadata for recipes/
    title: Recipes
    description: Things with flour and heat.
    classification: true

### `.bcard` — sidecar metadata

YAML. Place next to the file or directory it describes, sharing the
name: `cheesecake.jpg.bcard` describes `cheesecake.jpg`;
`snickerdoodles.bcard` describes `snickerdoodles/`.

    title: Snickerdoodles
    created: 2026-04-20
    updated: 2026-04-21
    description: My grandmother's recipe.
    classification: false

Every field is optional. Defaults: `title` → filename or directory
name (verbatim); `created` → file mtime; `updated` → `created`;
`description` → first paragraph of the file for text works, empty
otherwise; `classification` → `false`.

### `bartleby.conf` — library configuration

YAML, one per library, at the library root:

    hostname: gopher.someodd.zip
    port: 70
    selector: /library
    recent_count: 10
    feed_count: 50
    text_preview_bytes: 4096

Only `hostname` is required. Everything else has the defaults shown.
The library's own title is the basename of the library directory —
the root is not metadata-special.

For deeper detail (warnings, UTF-8 semantics, catalog layout, atom
feed structure), see `bartleby-plan.md`.

## Usage

```
bartleby /path/to/library
```

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
