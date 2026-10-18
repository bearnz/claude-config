# Conventional Commits — types, scopes, and worked examples

Contents:
1. [The grammar](#the-grammar)
2. [Choosing a type](#choosing-a-type)
3. [Choosing a scope](#choosing-a-scope)
4. [The subject line](#the-subject-line)
5. [The body](#the-body)
6. [Breaking changes](#breaking-changes)
7. [Footers](#footers)
8. [Worked examples](#worked-examples)
9. [Before and after](#before-and-after)

## The grammar

```
<type>(<scope>)<!>: <subject>
<blank line>
<body>
<blank line>
<footers>
```

Only `type` and `subject` are required. The `!` marks a breaking change. The
scope is optional but usually worth including — it is what makes a log
skimmable, because it lets a reader filter to the subsystem they care about.

## Choosing a type

The type answers "what kind of change is this?" from the point of view of
someone consuming the project, which is why `feat` and `fix` are the only two
that conventionally affect a version number.

| Type | Use when | Not when |
|---|---|---|
| `feat` | A user-visible capability that did not exist before | Refactoring that enables a future feature — that is `refactor` |
| `fix` | Behaviour was wrong and is now right | Behaviour was fine and is now different — that is `feat` or `refactor` |
| `perf` | Same behaviour, measurably faster or lighter | You believe it is faster but did not measure — that is `refactor` |
| `refactor` | Internal structure changed, behaviour did not | Any observable change slipped in — split it out |
| `docs` | Documentation, comments, README, doc-comments | Docs that ship as product content — that may be `feat` |
| `test` | Adding or correcting tests, no production code | The test change accompanies a fix — the fix's type wins |
| `build` | Build system, dependencies, packaging, lockfiles | CI configuration — that is `ci` |
| `ci` | Pipeline config, workflows, runners | Scripts developers run locally — that is `chore` or `build` |
| `style` | Formatting only: whitespace, semicolons, import order | Renaming things — that is `refactor` |
| `chore` | Housekeeping with no src or test change: ignore files, tooling config | Anything that fits a type above |
| `revert` | Undoing a previous commit; footer names it | A new fix that happens to restore old behaviour — that is `fix` |

Two rules resolve most of the hard calls:

**Pick the type that matches the change's effect on someone using the project,
not the effort that went into it.** A 600-line rewrite that leaves behaviour
identical is `refactor`, however much work it was.

**When a commit genuinely spans two types, that is usually the signal it should
be two commits.** If it must stay one, take the type highest in this order:
`fix` > `feat` > `perf` > `refactor` > everything else — a reader scanning for
risk needs the riskiest part surfaced.

## Choosing a scope

The scope names the part of the system that changed, in the vocabulary the repo
already uses. Derive it from the paths in the diff — a directory name, a module,
a package. `scripts/player/player_body.gd` and `scripts/player/view_hands.gd`
together give `player`; a change confined to `scripts/weapons/` gives `weapons`.

- Keep it lowercase and to one word where possible.
- Reuse scopes the repo has used before — check the recent subjects in the
  collector output. An inconsistent scope vocabulary is worse than none.
- If the change is genuinely repo-wide (a formatter run, a version bump), omit
  the scope rather than inventing `all` or `global`.
- If the change touches four unrelated scopes, that is the multi-commit signal
  again.

## The subject line

- Imperative mood: `add`, `fix`, `move`, `remove`. Not `added`, `adds`, `fixing`.
- No capital letter after the colon, no trailing period.
- Aim for 50 characters, hard-stop around 72 — `git log --oneline` and most
  hosting UIs truncate past that, and a truncated subject loses its verb's
  object, which is the only informative part.
- Say what the change does, not where it is. The scope already said where.
  `fix(auth): handle expired refresh tokens` beats
  `fix(auth): changes to token handling in auth.py`.

## The body

Separated from the subject by one blank line, wrapped at 72 columns (git does
not wrap for you, and unwrapped bodies read badly in every terminal tool).

Answer, in roughly this order, only the ones that apply:

1. **Why does this change exist?** The problem, the bug report, the constraint.
2. **What does it do about it?** The approach, and specifically any approach
   chosen over an obvious alternative — that is the reasoning most likely to be
   re-litigated later by someone who does not know it was considered.
3. **What are the consequences?** Behaviour changes, migrations required,
   performance effects, things a reviewer should look at hardest.
4. **What was deliberately left out?** A known gap stated in the commit is a
   decision; the same gap unstated is a bug someone will file.

Component bullets are useful on a large diff for navigation, but only for
changes a reader would otherwise have to hunt for. Never enumerate every file.

## Breaking changes

Two ways, and using both is conventional:

```
feat(api)!: return ISO-8601 timestamps from /events

BREAKING CHANGE: `created_at` was a Unix epoch integer and is now an
ISO-8601 string. Clients parsing it as a number will fail. Consumers
inside this repo were updated; external ones need a release note.
```

The `!` is what tooling reads at a glance; the `BREAKING CHANGE:` footer is what
tells a human what to actually do about it. A breaking change with no migration
note in the footer is not finished.

## Footers

`Key: value`, one per line, after a blank line. Common ones:

```
Refs: #142
Closes: #142
BREAKING CHANGE: <description>
Reverts: 7a25f33
Co-Authored-By: Human Name <email>
```

Only reference an issue number the user supplied or the branch name plainly
encodes (`feature/142-refresh-tokens`). Inventing plausible issue numbers
creates links to unrelated tickets.

`Co-Authored-By:` is for a **person** the user names. Never add one for Claude
or any assistant — see the attribution note in [SKILL.md](../SKILL.md#5-commit).

## Worked examples

**A feature with a design decision worth recording:**

```
feat(player): add third-person review camera

Nothing in first person can show a pose while it moves - the view
model hangs off the camera, and the body is off-screen below the
chin - so slides, dashes and mantles could only be judged from
captured stills, one frame at a time.

V (or the settings checkbox) swaps the active camera for a
SpringArm3D chase rig on the same pivot, offset up and over the
right shoulder so the carried weapon is not standing in front of
the lens.

Aim is deliberately untouched: shots and the interact ray still
leave the head down the pivot's forward direction, so the crosshair
is right about which way and wrong about where, by the parallax of
standing 2.5m back. This is a review tool rather than a game mode,
and is expected to be cut or earned before 1.0.

Refs: #31
```

**A fix where the cause is the whole story:**

```
fix(fx): reset interpolation after orienting tracers

Tracers were drawn as several beams fanning out of thin air behind
the shooter. CombatFX called reset_physics_interpolation() and then
look_at(), and turning a node after the reset re-arms exactly the
interpolation the reset cancelled - so a tracer pivoting about its
own centre swung its near end through an arc tens of metres wide on
its first frame.

_spawn() now takes a basis and applies it before the reset, making
the reset unconditionally the last thing done to the transform.

It was invisible in first person, where that arc falls off the sides
of the screen, which is why it survived so long.
```

**A small change that needs no body:**

```
fix(hud): clamp ammo counter at zero
```

**A chore, honestly labelled:**

```
chore: ignore Godot's .uid sidecars in dev scenes

They are regenerated on import and churn on every branch switch.
```

## Before and after

| Weak | Why it fails | Better |
|---|---|---|
| `update player.gd` | Names a file, not a change | `fix(player): keep soles on ground when crouching` |
| `fixes` | Fits every commit ever made | `fix(weapons): pay back cooldown overrun between shots` |
| `feat: various improvements to the enemy system` | No type discipline, no content | `perf(enemies): skip pathing for enemies outside the arena` |
| `refactor: changed the way we do things in the weapon controller and also fixed a bug with reloading` | Two commits wearing a trenchcoat | Split: `refactor(weapons): hoist hold pose to a static helper` and `fix(weapons): cancel reload on weapon swap` |
| `feat(player): added new dash` | Past tense, `new` says nothing | `feat(player): add air dash with a one-per-jump budget` |
