# Bartleby — A Scrivener for Gopherspace

> "I would prefer not to."

Bartleby walks a directory, reads sidecar `.bcard` metadata, and writes
a gopher menu tree under `catalog/`.

**`catalog/` is the only thing bartleby writes, modifies, or deletes.**
The source tree is read-only to bartleby. Nothing outside `catalog/`
is ever touched — not one byte, not one mtime. Delete `catalog/` and
your library is exactly as you wrote it.

This document is the MVP specification.

---

## Philosophy

Gopher was modeled on library information systems: a tree of menus,
not a stream of posts. Most gopherspace tools grow up imitating the
web — retrofitting blogs and feeds onto a medium that was never built
for them, abusing directories as pages, flattening hierarchies into
timelines because that is what the web trained us to expect. Phlogs
end up looking like blogs with a different first letter.

Bartleby asks a different question: what would sharing information
look like if gopher had won? If the web had never steamrolled
everything and information-browsing had stayed hierarchical? You
wouldn't have *posts*. You'd have a library — subjects on shelves,
works filed under classifications, a card catalog at the front door.
You'd browse by walking the stacks, not by scrolling a timeline.

Bartleby is that tool. Not a blog engine that speaks gopher. Not
Jekyll-for-gopher. A librarian, not a web developer.

- **Gopher-first.** Not web concepts ported over; the library
  metaphor is native to the medium.
- **I would prefer not to.** Bartleby prefers not to transform your
  files, not to add markup, not to be clever. He catalogs. That is
  the whole job.
- **Extremely opinionated.** One way to do things. Same input
  produces the same bytes.
- **`catalog/` is the only thing bartleby touches.** Source files are
  read-only to bartleby. Nothing is written, modified, or deleted
  outside `catalog/`. Delete that directory and the library is
  exactly as you wrote it — bartleby did nothing else.

---

## Vocabulary

Library terminology is used throughout — CLI flags, config keys,
error messages, doc prose, Haskell identifiers.

| Library term          | Bartleby concept                                    |
|-----------------------|-----------------------------------------------------|
| Library               | A directory of files cataloged by bartleby          |
| Catalog               | The generated `catalog/` directory                  |
| Classification        | A directory that groups works (like a subject)      |
| Work                  | A file or directory cataloged as a single item      |
| Card (`.bcard`)       | Sidecar metadata file describing a work or classification |
| Recent Accessions     | The "what's new" section in every catalog page      |
| Holdings              | The complete set of works in the library            |

---

## Source structure

Bartleby is invoked against a library directory containing
`bartleby.conf`. The library is any tree of files and directories.
Metadata is carried in **sidecar `.bcard` files**.

```
my-library/                              # the library root
  bartleby.conf                          # library configuration
  recipes.bcard                          # classification: true; titles recipes/ + description
  recipes/                               # a classification (described by sibling recipes.bcard above)
    cheesecake.jpg.bcard                 # describes cheesecake.jpg
    cheesecake.jpg                       # a work (file)
    snickerdoodles.bcard                 # describes snickerdoodles/
    snickerdoodles/                      # a work (directory — opaque to the catalog)
      photo.jpg
      recipe.txt
    desserts.bcard                       # classification: true; titles desserts/
    desserts/                            # a sub-classification
      cookies.txt                        # cataloged with auto-guessed metadata
  poetry/                                # a classification (no bcard — uses dirname)
    march-rain.txt.bcard                 # describes march-rain.txt
    march-rain.txt                       # a text work
```

Every `.bcard` sits in the **same directory** as the thing it
describes — never inside it. `recipes.bcard` is a sibling of
`recipes/`, not a child; `desserts.bcard` is a sibling of `desserts/`,
not a child.

### The single sidecar pattern

**One convention: `<name>.bcard` describes the sibling whose filename
is exactly `<name>`.** The sibling can be a file or a directory.

| Sidecar filename              | Describes                                |
|-------------------------------|------------------------------------------|
| `cheesecake.jpg.bcard`        | file `cheesecake.jpg`                    |
| `snickerdoodles.bcard`        | dir `snickerdoodles/` or file `snickerdoodles` |

A file and a directory with the same name cannot coexist as siblings
on POSIX filesystems, so the pattern is unambiguous by construction.

**Leading underscores are forbidden.** A file named `_foo.bcard` is a
parse-time warning; the card is skipped. The `_` prefix is reserved
for future conventions.

### Classification vs work

A directory is a **work** iff a sibling `<dirname>.bcard` exists and
`classification: true` is not set. Otherwise the directory is a
**classification**, and bartleby recurses into it. Within a
classification, a file is always a work; within a work-directory,
nothing is separately cataloged (the work is an opaque unit).

| Entry          | Sibling `.bcard`? | `classification:` in card?  | Result                                    |
|----------------|-------------------|-------------------------|-------------------------------------------|
| file           | no                | —                       | work (auto-guessed metadata)              |
| file           | yes               | absent / `false`        | work (from card)                          |
| file           | yes               | `true`                  | work; warn "`classification` ignored on file" |
| file           | yes, malformed    | —                       | work (auto-guessed); warn                 |
| directory      | no                | —                       | classification; recurse                   |
| directory      | yes               | absent / `false`        | work (gopher type `1`); do NOT recurse    |
| directory      | yes               | `true`                  | classification (with card metadata); recurse |
| directory      | yes, malformed    | —                       | classification; recurse; warn             |
| orphan `.bcard`| —                 | —                       | warn, skip                                |

A `.bcard` is a **correction**, not an opt-in. Bartleby catalogs every
file and directory it finds; auto-guessed metadata fills in when a
card is absent:

- `title` = filename with extension intact (or directory name, verbatim)
- `created` = `updated` = file mtime
- `description` = **first paragraph** of the file's content for text
  works (gopher type `0`); `""` for non-text works and classifications.
  See *Text previews and UTF-8-safe truncation* below.

The only source-tree content excluded from the catalog is filesystem-
hidden content (dotfiles) and orphan `.bcard` files whose target is
absent.

### Skipped during walk

- Anything whose filename starts with `.` (dotfile convention:
  `.git/`, `.DS_Store`, `.gophermap`)
- At library root: the literal `catalog/` and `catalog.tmp/`
  directories (bartleby's own output + staging). At deeper levels a
  classification named `catalog/` is permitted.
- The literal `bartleby.conf` at library root
- Symbolic links whose target is a directory (cycle protection);
  symlinks to files are followed

No bartleby-specific hiding convention. Everything not skipped gets
cataloged.

---

## `.bcard` — the metadata card

Format: YAML. Small, fixed schema.

```yaml
title:        Snickerdoodles
created:      2026-04-20
updated:      2026-04-21
description: |
  My grandmother's recipe,
  with a hint of nutmeg.
classification:   false
```

| Field         | Required            | Type           | Default                          |
|---------------|---------------------|----------------|----------------------------------|
| `title`       | yes (if card exists)| text           | —                                |
| `created`     | no                  | `YYYY-MM-DD`   | file mtime                       |
| `updated`     | no                  | `YYYY-MM-DD`   | `created`                        |
| `description` | no                  | text (multi-line OK) | first paragraph of file (text works) or `""` |
| `classification`  | no                  | bool (directories only) | `false`                 |

Unknown fields warn (e.g., `unknown field: tilte` — a likely typo of
`title`) but do not abort parse. Typo protection without rigidity.

**Cards are validated atomically.** Any single-field failure discards
the whole card; the target falls back to auto-guessed metadata. A
warning is recorded.

---

## `bartleby.conf` — the library configuration

Format: YAML. Same parser, same idioms.

```yaml
# Identity in gopherspace
hostname:     gopher.someodd.zip
port:         70
selector:     /library

# Catalog display tuning
recent_count:        10
feed_count:          50
text_preview_bytes:  4096
```

| Field                | Required | Default       | Notes                                 |
|----------------------|----------|---------------|---------------------------------------|
| `hostname`           | yes      | —             | No default. Bartleby refuses to guess.|
| `port`               | no       | 70            | 1–65535                               |
| `selector`           | no       | `/`           | Normalized: leading `/`, no trailing  |
| `recent_count`       | no       | 10            | Accessions per catalog gophermap      |
| `feed_count`         | no       | 50            | Entries per atom feed                 |
| `text_preview_bytes` | no       | 4096          | Upper bound for text-work content reads (used by atom `<content>` and the first-paragraph description fallback) |

The library's own title is the basename of the library directory,
just as any sub-classification's title is its directory name. The
root is not metadata-special.

---

## Output structure

Bartleby writes one directory: `<library>/catalog/`. Nothing outside.
The catalog mirrors the classification tree. Each classification gets
a `.gophermap` and a `feed.xml`.

```
my-library/
  catalog/                              # generated, safe to delete
    .gophermap                          # root catalog
    feed.xml                            # library-wide atom feed
    recipes/
      .gophermap
      feed.xml
      desserts/
        .gophermap
        feed.xml
    poetry/
      .gophermap
      feed.xml
```

### Hosting model

The gopher daemon is pointed at a gopherhole root; the library sits at
the configured `selector` inside it. The canonical entry URL is
`gopher://host:port/1<selector>/catalog/`. Bartleby's catalog is the
menu system; the library tree is the content.

Links inside gophermaps point *outward* in two forms:

- **Works** link to the work's real path at `<selector>/<path>`. The
  gopher daemon serves the file, or for directory-works shows its
  natural directory listing.
- **Classifications** link to their catalog page at
  `<selector>/catalog/<path>/`. Visitors always land on a
  bartleby-curated menu, never a raw daemon listing for a
  classification.

Selector composition: a work at relative path `<p>` is served at
`<config.selector>/<p>`; a classification at `<p>` is served at
`<config.selector>/catalog/<p>/`.

Visitors who land on `<selector>/` directly see whatever the daemon
shows for that directory — that is a daemon-configuration concern,
not bartleby's. Bartleby never writes `<library>/.gophermap` or any
other file outside `catalog/`.

---

## Gopher item type mapping

File extensions map to gopher item types (case-insensitive):

| Extensions                                              | Type |
|---------------------------------------------------------|------|
| `.txt .md .asc .org .rst .log .csv .yml .yaml .json .xml .ini .conf .py .hs .rb .js .c .h .cpp .sh` | `0` text |
| `.gif`                                                  | `g` GIF |
| `.jpg .jpeg .png .webp .bmp .svg`                       | `I` image |
| `.wav .mp3 .ogg .flac`                                  | `s` sound |
| `.html .htm`                                            | `h` HTML |
| anything else                                           | `9` binary |

Directory-works always render as type `1`. Generated `feed.xml` renders
as type `0` (it is text, plain XML, readable in a gopher client).

---

## Classification catalog layout

**One renderer for every classification — root and deep leaf use the
same function.** A classification's title is its directory name (for
the root, the library directory's basename). A sub-classification can
optionally override its title and description with a sibling `.bcard`
that sets `classification: true`.

Layout:

```
i
i  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
i   S P A C E D   T I T L E
i  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
i
i  Holdings: 42 works in 5 classifications (127.3 M)
i
i  <description line 1>
i  <description line 2>
i
i  Recent Accessions                            ← omit if total_recursive_works ≤ recent_count
i  -----------------
<top N recent works, each rendered as below>
i
i  Classifications                              ← omit if no sub-classifications
i  ---------------
1Desserts (12 works, updated 2026-04-20, 4.8 M)	<selector>/catalog/recipes/desserts/	<host>	<port>
i  Things with sugar.
...
i
i  Works                                        ← omit if no direct works
i  -----
1Snickerdoodles (2026-04-20, 4.3 M)	<selector>/recipes/snickerdoodles	<host>	<port>
i  My grandmother's recipe with a hint of nutmeg.
I Cheesecake (2026-04-18, 1.2 M)	<selector>/recipes/cheesecake.jpg	<host>	<port>
i  Classic New York style.  Makes one 9-inch springform.
i
0Atom feed	<selector>/catalog/recipes/feed.xml	<host>	<port>
```

### Description info lines

Every work in the "Recent Accessions" and "Works" sections — and every
sub-classification in the "Classifications" section — is followed by
one info line showing its description, truncated to 70 characters
(with `...` ellipsis if longer). The info line is **omitted** when the
description is empty. For works, the description is either the bcard
value or the first-paragraph fallback (text works only); for
sub-classifications, the description is whatever the child's
`classification: true` bcard set (or empty).

### The holdings summary line

Every classification header includes one `i`-line summarizing what is
cataloged beneath it:

- **Leaf** (no sub-classifications): `Holdings: N works (<size>)`
- **With subs**: `Holdings: N works in M classifications (<size>)`
- **Empty subtree**: `Holdings: none`

`N` (works) is **recursive** — every work anywhere in this
classification's subtree. `M` (classifications) is **direct only** —
the count of sub-classifications listed on this page; their own
sub-classifications are not counted. Size is the cumulative byte
count of every work (and every file inside a directory-work), across
the full subtree.

### Directory-work size exception

For a directory-work, `<size>` is the sum of all contained file sizes
(recursive). This is the single exception to the "opaque" rule —
bartleby walks into a work-directory to total its bytes but still
reads no bcards inside. Symlink policy matches the main walker: file
symlinks followed, directory symlinks not.

### Size formatting

1024-based. Bytes below 1024 display as `<N> B`; otherwise scale to
the largest unit ≤ the value and show one decimal with that unit
(K/M/G). Examples: `453 B`, `4.5 K`, `123.4 K`, `1.2 M`, `2.4 G`.
The `.` separator is the decimal point; no locale formatting.

### Ordering rules

- Works within a section: `updated` desc; path asc for ties
- Classifications: alphabetical (byte-order, locale-independent)
- Recent Accessions: `updated` desc across the entire subtree, capped
  at `recent_count`
- A sub-classification's displayed "updated" date is the max `updated`
  among its recursive works. Empty sub-classifications display
  `(0 works)` with no date or size parenthetical.

### Section-omission rules

- Skip Recent Accessions when `total_recursive_works ≤ recent_count`
  (the Works section already contains everything)
- Skip Classifications when there are none
- Skip Works when there are none directly in this classification

### Title rendering

Directory names are shown **verbatim** in catalog output. No
case-folding, no dash-to-space. `baking-notes/` displays as
`baking-notes`. If the user wants "Baking Notes" as a label, they name
the directory that way (spaces are legal) or set `classification: true`
with a `title:` field.

### Line formatting

All gophermap lines are produced via `Venusia.MenuBuilder`
(`text`, `directory`, `image`, `info`, `item`, etc.). Info lines use
`MenuBuilder.info` as-is (short form: `iMessage\t\t\t\r\n`). The
bartleby-written `.gophermap` is line-concatenated without the `.\r\n`
terminator — serving daemons emit that themselves.

**Escaping.** Gophermap lines are tab-separated on the wire — a stray
tab in a rendered title or description would corrupt the menu. In all
rendered text, tabs are replaced with two spaces. This applies to
bcard descriptions, auto-extracted first-paragraph descriptions, and
titles alike. Newlines in a multi-line description (classification
header) split across multiple `i` lines; in a single-line description
(per-entry info lines), newlines collapse to spaces. Filenames
containing a tab or newline are refused at catalog time with a warning.

---

## Atom feed layout

Every classification gets `feed.xml` containing all works in its
subtree, sorted `updated` desc, capped at `feed_count`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>gopher://host:port/1<selector>/catalog/<path>/</id>
  <title><classification title></title>
  <subtitle><classification description></subtitle>
  <updated><max-updated>T00:00:00Z</updated>
  <author><name><hostname></name></author>
  <link rel="self"      href="gopher://host:port/0<selector>/catalog/<path>/feed.xml"/>
  <link rel="alternate" href="gopher://host:port/1<selector>/catalog/<path>/"/>

  <entry>
    <id>gopher://host:port/<type><selector>/<work-path></id>
    <title><work title></title>
    <published><created>T00:00:00Z</published>
    <updated><updated>T00:00:00Z</updated>
    <link rel="alternate" length="<size-in-bytes>"
          href="gopher://host:port/<type><selector>/<work-path>"/>
    <summary type="text"><work description></summary>
    <content ...><!-- varies by kind, see below --></content>
  </entry>
</feed>
```

### `<content>` by work kind

| Kind                    | `<content>`                                                         |
|-------------------------|---------------------------------------------------------------------|
| Text file (type `0`)    | `type="text"`, the UTF-8-safe preview (see below), wrapped in CDATA |
| Image (type `I`, `g`)   | `type="html"`, CDATA-wrapped `<img src="gopher://..."/>` tag        |
| Directory-work (type `1`) | `type="text"`, description (or omitted if description empty)      |
| Audio / HTML / binary / other | omitted (summary carries metadata)                            |

### Feed-level rules

- Feed `<updated>` = max of included entries' `<updated>`. Empty
  feeds use `1970-01-01T00:00:00Z`. No wall-clock times anywhere.
- Feed `<id>` uses the `rel="alternate"` gopher URI (stable across
  runs).
- Entry `<id>` = the work's gopher URI. Renames produce new entries.

### Escaping

- Text content: standard XML escape of `& < > " '`.
- CDATA blocks: occurrences of `]]>` split via the trick
  `]]]]><![CDATA[>` to remain valid.

---

## Text previews and UTF-8-safe truncation

When bartleby reads a text work's content (for the atom `<content>`
preview and for the first-paragraph description fallback), it must
not split a UTF-8 codepoint at the byte limit. The rule:

1. Read up to `text_preview_bytes` bytes from the file.
2. Find the last complete UTF-8 codepoint boundary at or before the
   limit. Trim off any trailing partial codepoint.
3. Decode the remaining bytes as UTF-8. By construction, decode
   succeeds; the result is valid UTF-8, no longer than
   `text_preview_bytes` bytes.

From this single `Text` value, two things are derived:

- **Full preview** = the whole decoded `Text`. Used as atom `<content>`.
- **First paragraph** = prefix up to the first blank line (one or
  more consecutive line-endings; `\r\n` and `\n` both recognised).
  Leading blank lines are skipped before extraction. Used as the
  description fallback when the bcard does not supply one.

If the file is shorter than `text_preview_bytes`, both derivations
work on the full file content with no truncation concern.

On UTF-8 decode failure after step 2 (shouldn't happen — indicates a
corrupt file or non-UTF-8 encoding), the work is cataloged with an
empty description and no atom content preview, plus a warning.

---

## CLI

```
bartleby [PATH]

Arguments:
  PATH          Library directory containing bartleby.conf
                (default: current directory).

Options:
  --version     Print version and exit.
  --help        Print usage and exit.

Exit codes:
  0  Build succeeded (warnings, if any, printed to stderr).
  1  Fatal error (missing config, unwritable catalog, I/O failure).
```

No subcommands in MVP. `bartleby [PATH]` is the whole interface.

### Error messages

All errors in character:

```
bartleby: I would prefer not to catalog.
          'my-library/bartleby.conf' is absent.

bartleby: warning: 'recipes/cheesecake.jpg.bcard' has no sibling
          'cheesecake.jpg' — I would prefer not to catalog
          what is not there.

bartleby: warning: '_snickerdoodles.bcard' has a reserved filename
          — leading underscores are not allowed on catalog cards.
```

---

## Warnings

Non-fatal problems (dangling bcards, malformed YAML, nonsensical
fields, reserved filenames, tab/newline in filenames, UTF-8 decode
failures in text previews) print to stderr with the
`bartleby: warning:` prefix. The build continues; the affected entry
falls back to auto-guessed metadata or is skipped as appropriate.

---

## IO pipeline

```
1. Read bartleby.conf, walk the library tree (read bcards, stat
   files, UTF-8-safe-read each text work's preview — see the Text
   previews section)                                     (IO)
2. Build the Library model, render gophermaps and atom feeds
   from the sources just read                            (pure)
3. Write catalog.tmp/, then rm -rf catalog/ and rename
   catalog.tmp/ → catalog/ (two-step swap; brief window
   where catalog/ is absent)                             (IO)
```

Every run is a fresh rebuild. Nothing is persisted between runs
besides `catalog/` itself — no manifest, no hashes, no diff, no
incremental anything. If a run crashes mid-write, a stale
`catalog.tmp/` may remain; the next run blows it away before writing.

---

## Architecture

Bartleby's IO shell reads files, writes files, and swaps the catalog
into place. Everything between those boundaries is pure:
configuration and card parsing, tree-building, gophermap and atom
rendering. The pure core is fat and testable; the IO shell is thin.

**The root of the library is an ordinary classification.** Same type,
same data, same renderer, same atom feed. Its title is the library
directory's basename — the same rule every other classification uses
for itself. One gophermap rendering function handles every level; one
atom rendering function does the same. No root-special-case code, no
root-special-case data.

---

## Dependencies

```yaml
dependencies:
  - base
  - text
  - bytestring
  - containers
  - yaml                        # config + bcard parsing
  - aeson                       # yaml uses aeson internally
  - filepath
  - directory
  - time                        # Day for dates
  - Venusia                     # MenuBuilder: gophermap line formatting
```

Plus `liquidhaskell` at dev scope (see Testing).

Venusia is not on Hackage; pin in `stack.yaml` under `extra-deps`
with an explicit commit SHA. The CLI uses plain
`System.Environment.getArgs` — no `optparse-applicative`. Filesystem
operations use `directory` — no `unix`. No XML library; atom is
generated via Text concatenation with a small escape helper. No
hashing, no templating, no theming.

---

## Testing

QuickCheck properties cover the pure renderers and walker logic
(determinism, sort invariants, recent-count bounds, no path
traversal, classification-vs-work rules, auto-guess fallback,
UTF-8-safe truncation). A golden test runs a complete sample library
end-to-end and compares the catalog byte-exactly; any output change
fails the test and must be explicitly re-accepted.

**LiquidHaskell** is wired in on selected modules (scaffolded
"option B"): `Bartleby.Config` carries bounded refinements on numeric
fields (port 1–65535; non-negative `recent_count`, `feed_count`,
`text_preview_bytes`); `Bartleby.Walker` refines the selector type so
rendered paths cannot contain `..`; `Bartleby.Types` refines
`workSize`, `clsTotalSize`, and `clsTotalWorks` as non-negative.
Heavier refinement use is deferred to v2+.

---

## Deferred to v2+

- `bartleby audit` — report un-cataloged files
- `bartleby scaffold <target>` — stub a new bcard
- Per-work `author` override
- Tag / cross-reference support

---

## What v1 is NOT

- No transformation of your content (no word wrap, no markdown, no templates)
- No themes — one opinionated style
- No watch mode — re-run bartleby after edits
- No per-work gophermaps inside work-directories (daemon shows the
  directory; author a manual `.gophermap` if you want curation)
- No silent mutation — `catalog/` is rewritten atomically each run

These are not missing features. They are preferences.
