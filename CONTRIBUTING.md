# Contributing to ActionHud

Thank you for your interest in contributing to ActionHud! We welcome contributions from developers and agents alike.

## Philosophy
ActionHud is designed to be **lightweight**, **performant**, and **single-purpose**.
- **No Libraries**: We avoid embedding libraries like Ace3 or Libs unless absolutely critical.
- **Event-Driven**: We avoid `OnUpdate` loops. Code should react to WoW API events.
- **Native Look**: We aim for deep integration with the default WoW UI aesthetic and systems.

## Workflow
1.  Fork the repository.
2.  Create a feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes.
4.  Push to the branch.
5.  Open a Pull Request.

## Agent Guidelines
If you are an AI agent modifying this codebase:
- **Consult `AGENTS.md`**: This file contains architectural decisions and context.
- **Respect Granularity**: Update functions are split (`UpdateAction`, `UpdateCooldown`, `UpdateState`). Do not merge them back into a monolith.
- **Performance First**: Always verify `Update` loops are efficient.

## Bug Reports
Please include:
- A description of the issue.
- Any Lua errors (captured via BugSack/BugGrabber).
- Steps to reproduce.
- `/actionhud` debug output if relevant.
