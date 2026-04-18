{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/pre-commit-lint.sh"
          },
          {
            "type": "command",
            "command": "bash .claude/hooks/terraform-safety.sh"
          }
        ]
      }
    ]
  }
}
