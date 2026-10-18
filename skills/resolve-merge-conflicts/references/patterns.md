# Recurring conflict shapes

Look up the file class here rather than reasoning from first principles each
time — these are the conflicts that appear in nearly every merge, and most of
them have one correct answer.

- [Derived files: never hand-merge](#derived-files-never-hand-merge)
- [Ordered and unordered lists](#ordered-and-unordered-lists)
- [Changelogs and release notes](#changelogs-and-release-notes)
- [Whitespace, line endings and formatter passes](#whitespace-line-endings-and-formatter-passes)
- [Renames, moves and delete/modify](#renames-moves-and-deletemodify)
- [Serialised scene, editor and project files](#serialised-scene-editor-and-project-files)
- [Version numbers, migrations and other allocated identifiers](#version-numbers-migrations-and-other-allocated-identifiers)
- [The clean merge that does not build](#the-clean-merge-that-does-not-build)

## Derived files: never hand-merge

A derived file is not content — it is a function of content that happens to be
committed. Merging one by hand produces a file that corresponds to no input, and
it will disagree with its source in a way nothing checks until much later.

The move is always the same: get the *source* merged first, take either side of
the derived file to clear the conflict, then regenerate and stage the result.

| File | Regenerate with |
| --- | --- |
| `package-lock.json`, `npm-shrinkwrap.json` | `npm install` (after merging `package.json`) |
| `yarn.lock` | `yarn install` |
| `pnpm-lock.yaml` | `pnpm install` |
| `poetry.lock` | `poetry lock --no-update` |
| `Cargo.lock` | `cargo build` or `cargo generate-lockfile` |
| `Gemfile.lock` | `bundle install` |
| `go.sum` | `go mod tidy` |
| `composer.lock` | `composer update --lock` |
| `*.uid`, `.import`, `.godot/` (Godot) | reimport: `godot --headless --import` |
| Compiled CSS/JS bundles, minified assets | the project's build command |
| Snapshot tests (`__snapshots__`, `.snap`) | the test runner's update flag, **after** confirming the new output is right |

Two cautions. Regenerating a lockfile with a bare `install` can quietly bump
transitive dependencies beyond what either branch intended — prefer the variant
that only resolves what the manifest requires, and check the resulting diff is
about the merge and not about the world moving on. And snapshots are the one
entry in the table that is not purely derived: an updated snapshot can encode a
regression, so read the change rather than accepting it.

## Ordered and unordered lists

Both sides adding entries to a list is the single most common conflict and
usually the most mechanical. What decides the resolution is whether position
carries meaning.

**Order is not meaningful** — imports, exports, dependency blocks, test case
lists, enum members that are never serialised by index, independent `case`
branches, CSS rules that do not overlap, `.gitignore` lines. Take the union,
remove duplicates, and re-sort into whatever convention the file already follows
rather than leaving our block followed by theirs. Interleaving properly is what
makes the next merge of the same file clean.

**Order is meaningful** — middleware chains, route tables where an earlier
pattern shadows a later one, CSS with real cascade overlap, migration lists,
initialisation sequences, enum members with persisted numeric values, and
anything with an explicit comment about ordering. The union is still probably
right, but *where* each entry goes is a judgement call. Ask, and say what
depends on the ordering.

An enum whose values are written to disk or sent over a wire is worth calling
out specially: appending to it is safe, and inserting into the middle
renumbers everything after it and invalidates existing data.

## Changelogs and release notes

Both sides added an entry at the top of the file. This is a union, always — no
entry is a replacement for another. Merge both under the correct headings,
preserve the existing chronology, and do not sort entries by author or branch.
If both sides opened a new "Unreleased" section, fold them into one.

The one thing to check: an entry that names a version number that is now wrong
because the other side released. Fix the heading, not the entries.

## Whitespace, line endings and formatter passes

When a conflict looks enormous but the two sides read the same, one side ran a
formatter or the file changed line endings. Confirm it before doing anything
manual:

```bash
git diff --ignore-all-space <base> HEAD -- <path>
git diff --ignore-all-space <base> MERGE_HEAD -- <path>
```

If one of those is nearly empty, that side is the formatting pass. The
resolution is to take the *formatted* file and re-apply the other side's real
change on top of it — so the merge keeps the reformat rather than partially
undoing it. `git merge -Xignore-all-space` can do this wholesale for a merge
dominated by whitespace, but it will also swallow meaningful indentation changes
in languages where indentation is syntax (Python, YAML), so check the result
rather than trusting the flag.

CRLF/LF conflicts across a whole file usually mean the repo needs a
`.gitattributes` entry. Fix the merge now; mention the underlying cause rather
than fixing it in the merge commit.

## Renames, moves and delete/modify

`git status` reports these as `DU` (deleted by us, modified by them), `UD`
(modified by us, deleted by them), or `AA` (both added). Git shows a rename as a
delete plus an add when the content changed enough, so a "deleted" file is
frequently a moved one.

Before deciding, find out whether the file actually moved:

```bash
git log --follow --oneline -- <path>
git diff --find-renames --name-status <base> MERGE_HEAD
```

- **They moved it, we edited it.** Apply our edit to the file at its new path,
  then remove the old path (`git rm <old>`). The common failure is resolving the
  delete by keeping our version, which restores the file at the old location and
  leaves two copies in the tree.
- **They deleted it, we edited it.** A judgement call — ask. The deletion might
  postdate our edit and supersede it, or our edit might be a fix the deleting
  branch never saw.
- **Both added the same path** (`AA`). Two independent implementations. Do not
  concatenate them; present both and ask which one survives, or whether one
  needs features from the other.

After any rename resolution, grep the repository for references to the old path
— imports, config, docs, CI files. Git renames the file and nothing else.

## Serialised scene, editor and project files

Godot `.tscn`/`.tres`, Unity `.prefab`/`.unity`, Xcode `.pbxproj`, Jupyter
`.ipynb`, and similar formats are text but are not source: they carry generated
ids, node ordering, and references between sections. A textually merged one can
be structurally invalid in ways that only show up when the tool opens it.

Small, well-separated edits (two different properties on two different nodes)
merge fine. Anything touching the same node, ids, or the file's header does not.
When in doubt, take one side whole and redo the other side's change in the
editor — that is faster than debugging a corrupted scene, and it is the answer
the tool's own documentation gives.

Always open the resolved file in the tool, or load it headlessly, before
committing. For a Godot project this is `godot --headless --import` plus any
smoke test the repo has.

## Version numbers, migrations and other allocated identifiers

Both branches bumped `version` to the same next number, or both added a
migration numbered `0042`, or both took the same port/id from a shared pool.
Text-wise this is a two-line conflict; semantically both sides allocated the
same slot and one of them has to move.

The resolution is not to pick a side — it is to renumber the loser and update
everything that refers to it. For migrations that means renaming the file and
fixing its `down_revision`/parent pointer; sequences with a dependency chain
break silently otherwise. This is worth confirming with the user, since it
changes a file neither branch conflicted on.

## The clean merge that does not build

Not a conflict at all, and the reason step 5 of the skill exists. Both diffs
applied cleanly and the combination is broken. The shapes to look for, using
the "touched by both sides" list from the collector script:

- One side renamed or deleted a symbol; the other added a caller of it.
- One side changed a function signature; the other added a call using the old
  one.
- One side moved a file; the other added an import from the old path.
- One side changed a config key, constant or string id; the other added a reader
  of the old name.
- One side added a required field; the other added a constructor that omits it.

A fast sweep: take the symbols each side added or removed, and grep for them in
the files the *other* side touched.

```bash
git diff <base> MERGE_HEAD --name-only | xargs git grep -n '<symbol we renamed>' --
```

Building or running the tests catches most of this in one step, which is why
that is the check that matters rather than an extra one.
