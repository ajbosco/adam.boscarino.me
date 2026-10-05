# Agent notes

## Cleaning up

Claude and Codex clean up after themselves. Once work is merged and deployed (or abandoned), remove its git worktrees (`git worktree remove`, then `git worktree prune`), delete scratch build folders (extra DerivedData paths, scratch `.build` folders, screenshot dumps), keep only the newest `.xcarchive` per app, and delete any simulators created for the task. Stop anything you started in the background. Never remove something another running session is still using, and save uncommitted changes as a patch before removing a worktree that has them.
