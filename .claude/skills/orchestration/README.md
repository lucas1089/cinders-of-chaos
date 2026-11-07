# Orchestrator

Core skill that defines how Claude operates as a conductor spawning worker agents.

## Source

Imported from: [cc-mirror/orchestration](https://github.com/numman-ali/cc-mirror/tree/649f42ad8943fd13cada0788109e05346ad5fd7d/src/skills/orchestration)

## Sync Targets

- **Production**: `production/orchestrator/`
- **Skills**: `.claude/skills/orchestrator/`

## Key Concepts

1. **Orchestrator vs Worker**: Claude decides its role based on context
2. **Parallel Agents**: Spawn multiple workers for parallel execution
3. **Task Management**: Use TaskCreate/TaskUpdate for dependency graphs
4. **Domain Guides**: Load relevant reference before decomposing tasks

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Core orchestrator behavior |
| `references/domains/` | Task-type-specific guides |
| `references/patterns.md` | Orchestration patterns |
| `references/tools.md` | Tool ownership details |
| `references/examples.md` | Workflow examples |
| `references/guide.md` | User-facing guide |

## Adaptation Notes

This skill needs adaptation for LeadGrow GTM context:
- [ ] Update domain references for GTM tasks (campaigns, lead processing, research)
- [ ] Add GTM-specific patterns
- [ ] Integrate with existing skills (enrich-leads, email-campaign, etc.)
