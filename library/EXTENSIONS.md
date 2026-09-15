# Library Extensions Guide

This guide documents how consumers can add their own books to the library and the opt-out mechanics.

## Extending the Library

Consumers can add books by dropping files into the workspace `library/<role>/` tree (the same convention agents already read) and registering them in `library/README.md`'s consumer section.

The payload ships a `library/EXTENSIONS.md` guide documenting this, and the shipped register is never overwritten once the consumer edits it (no-clobber).

## Opt-Out Mechanics

`WITH_LIBRARY=false` installs NO shipped library books (zero redistribution/attribution surface), leaving only the extension docs + empty register; the rest of the agentic setup (AGENTS contract, agents, skills, opencode fragment) is unaffected and functional.

## No-Clobber Guarantee

Scaffold writes ONLY files on its shipped-file MANIFEST; consumer books and consumer-edited register entries survive, even across `OVERWRITE=true` refreshes.