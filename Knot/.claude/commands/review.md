Review all staged git changes for errors, then commit.

## Steps

1. Run `git diff --cached` to see all staged changes. If nothing is staged, tell me and stop.
2. Carefully review every line of the diff for:
   - Bugs, logic errors, or incorrect behavior
   - Missing imports or undefined references
   - Typos in code or strings
   - Security issues (hardcoded secrets, injection vulnerabilities)
   - Syntax errors or compilation issues
3. If any issues are found:
   - Fix ALL issues across all affected files
   - Re-stage the fixed files with `git add <specific files>`
   - Run `git diff --cached` again to verify the final state
4. Write a commit message and commit:
   - Title line: concise summary of what changed
   - Blank line, then multiple paragraphs describing what was changed and why
   - Use past tense, be specific about files and features
   - Do NOT include step numbers or Co-Authored-By lines
   - Commit with `git commit`
5. Run `git status` to confirm the commit succeeded.
