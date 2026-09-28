#!/usr/bin/env python3
"""Tests for scripts/check_claudemd.py on an invented repo laid out in a temp dir."""
import importlib.util
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "check_claudemd.py")


def load_module():
    spec = importlib.util.spec_from_file_location("check_claudemd", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def build_repo(root, with_codeowners=True):
    write(root, "CLAUDE.md", "\n".join([
        "# CLAUDE.md",
        "",
        "## Structure",
        "",
        "- `areas/`: the work itself. (scope: shared)",
        "- `areas/finance/`: money. (scope: jane-doe)",
        "- `areas/legal/`: contracts. (scope: sam-lee)",
        "- `areas/untracked/`: no CODEOWNERS line. (scope: shared)",
        "- `areas/ghost/`: no such operator. (scope: nobody)",
        "- `docs/`: untagged, never checked.",
        "",
        "## Rules",
        "",
        "- `areas/rules/`: outside Structure, never checked. (scope: sam-lee)",
        "",
    ]))
    write(root, "areas/finance/CLAUDE.md", "\n".join([
        "# finance",
        "",
        "```",
        "areas/finance/",
        "├── CLAUDE.md",
        "├── ledger.md",
        "├── missing.md",
        "└── [Client Name]/",
        "```",
        "",
        "See `../legal/` and `../nowhere/`. Skills: `skills/real`, `skills/ghost`,",
        "and `areas/<name>/CLAUDE.md` is a pattern, not a claim.",
        "",
    ]))
    write(root, "areas/finance/ledger.md", "ledger\n")
    write(root, "areas/legal/CLAUDE.md", "# legal\n")
    write(root, "skills/real/SKILL.md", "---\nname: real\n---\n")
    write(root, "operators/jane-doe.md", "---\nslug: jane-doe\ngit_names:\n  - Jane Doe\ngithub: jane-doe\n---\n")
    write(root, "operators/sam-lee.md", "---\nslug: sam-lee\ngit_names:\n  - Sam Lee\ngithub: @SamLee\n---\n")
    write(root, "operators/operator_template.md", "---\nslug: <slug>\ngithub: <github-username>\n---\n")
    if with_codeowners:
        write(root, ".github/CODEOWNERS", "\n".join([
            "# map",
            "/areas/           @jane-doe @sam-lee",
            "/areas/finance/   @jane-doe",
            "/areas/legal/     @jane-doe",
            "/areas/ghost/     @jane-doe",
            "",
        ]))


class CheckClaudemdTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_module()
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def findings(self, **kw):
        build_repo(self.root, **kw)
        return self.mod.scan(self.root)

    def claims(self, findings, check):
        return sorted(f["claim"] for f in findings if f["check"] == check)

    def test_dead_tree_leaf(self):
        f = self.findings()
        self.assertEqual(self.claims(f, "DEAD"), ["tree lists `missing.md`"])

    def test_skill_citation(self):
        f = self.findings()
        self.assertEqual(self.claims(f, "SKILL"), ["cites `skills/ghost`"])

    def test_cross_folder_path(self):
        f = self.findings()
        self.assertEqual(self.claims(f, "PATH"), ["cross-folder ref `../nowhere/`"])

    def test_scope_against_codeowners(self):
        f = self.findings()
        scope = {x["claim"]: (x["severity"], x["reality"]) for x in f if x["check"] == "SCOPE"}
        self.assertIn("`areas/legal` tagged (scope: sam-lee)", scope)
        self.assertEqual(scope["`areas/legal` tagged (scope: sam-lee)"][0], "error")
        self.assertIn("@jane-doe", scope["`areas/legal` tagged (scope: sam-lee)"][1])
        self.assertIn("`areas/untracked` tagged (scope: shared)", scope)
        self.assertEqual(scope["`areas/untracked` tagged (scope: shared)"][0], "info")
        self.assertIn("`areas/ghost` tagged (scope: nobody)", scope)
        self.assertEqual(scope["`areas/ghost` tagged (scope: nobody)"][0], "error")
        # Correct tags and untagged bullets raise nothing.
        self.assertNotIn("`areas` tagged (scope: shared)", scope)
        self.assertNotIn("`areas/finance` tagged (scope: jane-doe)", scope)
        self.assertFalse(any("docs" in c for c in scope))
        self.assertFalse(any("areas/rules" in c for c in scope))

    def test_no_codeowners_means_no_scope_check(self):
        f = self.findings(with_codeowners=False)
        self.assertEqual(self.claims(f, "SCOPE"), [])

    def test_every_finding_has_the_schema(self):
        for x in self.findings():
            self.assertEqual(set(x), {"file", "check", "severity", "claim", "reality"})
            self.assertIn(x["severity"], {"error", "info"})

    def test_strict_exit_code(self):
        build_repo(self.root)
        import subprocess
        rc = subprocess.run([sys.executable, SCRIPT, "--root", self.root, "--strict"], capture_output=True).returncode
        self.assertEqual(rc, 1)
        rc = subprocess.run([sys.executable, SCRIPT, "--root", self.root], capture_output=True).returncode
        self.assertEqual(rc, 0)

    def test_missing_root_is_an_execution_error_not_a_clean_scan(self):
        import subprocess
        missing = os.path.join(self.root, "does-not-exist")
        result = subprocess.run([sys.executable, SCRIPT, "--root", missing], capture_output=True)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
