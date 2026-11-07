# Test-Driven Development Protocol

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   BUILD → TEST → VERIFY                                     │
│                                                             │
│   Never ship code without testing it.                       │
│   Tests prove the system works. Words don't.                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Testing Protocol

| When | Action |
|------|--------|
| After implementing | Run the code to verify it works |
| After modifying | Run existing tests + manual verification |
| Before marking complete | Demonstrate it works (output, screenshot, or test pass) |

## For Python Scripts

1. **Syntax check:** `python script.py --help` or import test
2. **Dry run:** Test with sample data if available
3. **Live test:** Run with real data (with user permission for API costs)

## For Batch Tools

1. Test with 1-3 records first (cheap validation)
2. Show output to user before full batch
3. Verify cost calculations match expected values

## What Counts as "Tested"

| ✅ Tested | ❌ Not Tested |
|-----------|---------------|
| Script runs without errors | "It should work" |
| Output matches expected format | "Syntax looks correct" |
| Edge cases handled | "I reviewed the code" |
| User sees proof of success | Assumptions without verification |

## Example Test Flow

```
1. Implement feature
2. Run --help to verify syntax
3. Test with 1-3 sample records
4. Show output to user
5. Mark as complete
```
