# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check real target-driver confirmation navigation without changing its choice."""

from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
NODE = shutil.which("node")
COMMON = ROOT / "tools/ui-automation/scenarios/ForgeBorosStudy.js"

HARNESS = r"""
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const scroll = {contentY:0, atYEnd:false};
let visible = false, revealOnWheel = true;
const clicks = [], wheels = [];
const session = {gameId:'game-1', promptId:33, promptMinSelections:0,
    boardTargetCandidates:() => { throw new Error('Do not replace an optional empty selection'); }};
const driver = {session, table:{interaction:{selectedCount:0, validTargets:true}},
    require:assert.ok, item:name => name === 'rulesPromptScroll' ? scroll : null,
    click:name => { clicks.push(name); return visible; }};
const context = vm.createContext({auditProbe:{wheel:(target, delta) => {
    assert.equal(target, scroll); wheels.push(delta); scroll.contentY += 127;
    if (revealOnWheel) visible = true;
    return true;
}}});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), context);
"""


@unittest.skipUnless(NODE, "JavaScript driver behavior checks require the optional Node tool runtime")
class ForgeTargetDriverTests(unittest.TestCase):
    def run_js(self, script):
        result = subprocess.run([NODE, "-e", HARNESS + script, str(COMMON)],
                                text=True, capture_output=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_visible_confirmation_keeps_normal_click_without_scrolling(self):
        self.run_js(r"""
visible = true;
context.chooseTarget(driver);
assert.deepEqual(clicks, ['rulesConfirmTargets']);
assert.deepEqual(wheels, []);
""")

    def test_optional_empty_selection_scrolls_then_clicks_visible_confirmation(self):
        self.run_js(r"""
context.chooseTarget(driver);
assert.deepEqual(wheels, [-360]);
assert.equal(scroll.contentY, 127);
context.chooseTarget(driver);
assert.deepEqual(clicks, ['rulesConfirmTargets', 'rulesConfirmTargets']);
assert.deepEqual(wheels, [-360]);
""")

    def test_unreachable_confirmation_fails_at_end_or_after_bounded_scrolls(self):
        self.run_js(r"""
scroll.atYEnd = true;
assert.throws(() => context.chooseTarget(driver), /Target confirmation/);
assert.deepEqual(wheels, []);
scroll.atYEnd = false;
revealOnWheel = false;
assert.throws(() => { for (let i=0; i<20; ++i) context.chooseTarget(driver); }, /Target confirmation/);
assert(wheels.length > 0 && wheels.length < 20);
session.promptId++;
context.chooseTarget(driver);
visible = true;
context.chooseTarget(driver);
""")


if __name__ == "__main__":
    unittest.main()
