# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the maintained BO3 blocker driver against native selection outcomes."""

from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
NODE = shutil.which("node")
DRIVER = ROOT / "tools/ui-automation/scenarios/ForgeDuelMatch.qml"

HARNESS = r"""
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const qml = fs.readFileSync(process.argv[1], 'utf8');
function functionSource(name) {
    const start = qml.indexOf('    function ' + name + '(');
    if (start < 0) return '';
    const body = qml.indexOf('{', start);
    let depth = 1, end = body + 1;
    for (; depth && end < qml.length; ++end) {
        if (qml[end] === '{') ++depth;
        if (qml[end] === '}') --depth;
    }
    return qml.slice(start, end);
}
const start = qml.indexOf('        case "chooseBlockers": {');
const end = qml.indexOf('        case "chooseCombatDamageAssignment":', start);
const blockerCase = qml.slice(start, end);
const target = {responseId:'attacker', objectId:'card-attacker'};
const sources = ['one', 'two'].map(id => ({responseId:id, objectId:'card-' + id, validTargets:[target]}));
const assignments = {};
let acceptConfirmation = true, automaticAssignment = true, confirmations = 0;
const combat = {selectedSource:'', selectedTargets:id => assignments[id] || [],
    get links() { return sources.flatMap(source => (assignments[source.responseId] || [])
        .map(targetId => ({sourceId:source.responseId, targetId}))); }};
const session = {gameId:'game-1', promptId:117, promptKind:'chooseBlockers',
    promptCombat:{sourceItems:() => sources}};
const context = vm.createContext({extended:true, format:'modern', seat:2, blocks:0,
    countedBlockPrompts:{}, session, table:{combatInteraction:combat}, capturedCombat:false,
    commander:() => null, combatInputId:id => id, capture:() => {}, wheelToCard:() => {},
    require:assert.ok, auditProbe:{readShared:() => ({}), record:() => {}},
    click:name => {
        if (name === 'rulesConfirmCombat-blockers') {
            if (!acceptConfirmation) return false;
            ++confirmations; return true;
        }
        const source = sources.find(value => 'forgeCard-' + value.objectId === name);
        if (source) {
            if (automaticAssignment) assignments[source.responseId] = ['attacker'];
            else combat.selectedSource = source.responseId;
            return true;
        }
        if (name === 'forgeCard-card-attacker' && combat.selectedSource) {
            assignments[combat.selectedSource] = ['attacker']; combat.selectedSource = ''; return true;
        }
        return false;
    }});
vm.runInContext(functionSource('clickCombatSource') + '\n' + functionSource('confirmBlockers')
    + '\nfunction actBlockers() { switch (session.promptKind) {' + blockerCase + '} }', context);
"""


@unittest.skipUnless(NODE, "JavaScript driver behavior checks require the optional Node tool runtime")
class ForgeBlockDriverTests(unittest.TestCase):
    def run_js(self, script):
        result = subprocess.run([NODE, "-e", HARNESS + script, str(DRIVER)],
                                text=True, capture_output=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_automatic_unique_target_assignments_count_after_confirmation_once(self):
        self.run_js(r"""
context.actBlockers(); context.actBlockers();
assert.equal(combat.links.length, 2, 'Both native source clicks assigned their unique target');
context.actBlockers();
assert.equal(confirmations, 1);
assert.equal(context.blocks, 2, 'Count real blocker assignments without an extra attacker click');
context.actBlockers();
assert.equal(context.blocks, 2, 'A pending response must not count the same prompt twice');
""")

    def test_failed_confirmation_and_empty_assignments_do_not_inflate_coverage(self):
        self.run_js(r"""
context.actBlockers(); context.actBlockers();
acceptConfirmation = false;
context.actBlockers();
assert.equal(context.blocks, 0);
acceptConfirmation = true;
context.actBlockers();
assert.equal(context.blocks, 2);
session.gameId = 'game-2';
context.actBlockers();
assert.equal(context.blocks, 4, 'A new game may reuse the prompt number');
session.promptId++;
delete assignments.one; delete assignments.two;
context.extended = false;
context.actBlockers();
assert.equal(context.blocks, 4, 'Confirming no blockers is not blocking coverage');
""")

    def test_explicit_attacker_clicks_count_the_same_confirmed_assignments(self):
        self.run_js(r"""
automaticAssignment = false;
context.actBlockers(); context.actBlockers();
context.actBlockers(); context.actBlockers();
assert.equal(combat.links.length, 2);
assert.equal(context.blocks, 0, 'Selection clicks alone are not confirmed coverage');
context.actBlockers();
assert.equal(context.blocks, 2);
""")


if __name__ == "__main__":
    unittest.main()
