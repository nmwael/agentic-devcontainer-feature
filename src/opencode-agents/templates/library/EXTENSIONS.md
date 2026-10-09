# Library Extensions Guide

This guide documents how consumers can add their own books to the library and the opt-out mechanics.

## Extending the Library

Consumers can add books by dropping files into the workspace `library/<role>/` tree (the same convention agents already read) and registering them in `library/README.md`'s consumer section.

The payload ships a `library/EXTENSIONS.md` guide documenting this, and the shipped register is never overwritten once the consumer edits it (no-clobber).

## Opt-Out Mechanics

The shipped library payload is only `library/skills/`, `library/release-it.mini.md`, and `library/EXTENSIONS.md` — no per-role books ship with the feature. `WITH_LIBRARY=false` drops even the `skills/` copy, leaving just the extension docs + empty register; the rest of the agentic setup (AGENTS contract, agents, opencode fragment) is unaffected and functional.

## No-Clobber Guarantee

Scaffold writes ONLY files on its shipped-file MANIFEST; consumer books and consumer-edited register entries survive, even across `OVERWRITE=true` refreshes.