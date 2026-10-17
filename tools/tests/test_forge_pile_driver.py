# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check test-player pile navigation through the actual JS and QML action helper."""

from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
NODE = shutil.which("node")
COMMON = ROOT / "tools/ui-automation/scenarios/ForgeBorosStudy.js"
DRIVER = ROOT / "tools/ui-automation/scenarios/ForgeDuelMatch.qml"

HARNESS = r"""
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const common = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1],'utf8'),common);
const qml = fs.readFileSync(process.argv[2],'utf8');
const action = qml.slice(qml.indexOf('    function cardAction(option) {'),
    qml.indexOf('    function availableMana() {'));
const member = {cardId:'card-86',stackIndex:0,stackSize:2,stackFront:false,fanned:false};
const front = {cardId:'card-88',stackIndex:0,stackSize:2,stackFront:true,fanned:false};
const lane = {visible:true,zone:'battlefield',category:'land',visibleCards:[member,front],scrollArea:{}};
const board = {name:'forgeCard-card-86'}, frontBoard = {name:'forgeCard-card-88'};
let badgeVisible = true;
const clicks = [], wheels = [];
function item(name) {
    if (name === 'forgeCard-card-86' && (member.fanned || member.stackFront || member.stackSize===1)) return board;
    if (name === 'forgeCard-card-88') return frontBoard;
    return null;
}
function click(name) {
    if (name !== 'forgeCardStackCount-card-88' || !badgeVisible) return false;
    clicks.push(name); member.fanned = true; front.fanned = true;
    return true;
}
const table = {presentation:{children:[lane]},cardActionPicker:{opened:false},interaction:{zoneActions:[]}};
const driver = {table,click,require:assert.ok,wheelToCard:(id,hand)=>wheels.push({id,hand})};
const context = vm.createContext({BorosStudy:common,driver,table,item,click,progress:0,
    require:assert.ok,auditProbe:{click:target=>{clicks.push(target.name);return true;}},
    session:{promptId:283},navigationRetries:{},
    wheelToCard:(id,hand)=>{wheels.push({id,hand});return false;}});
vm.runInContext(action,context);
const option = {kind:'activateAbility',cardId:'card-86',responseId:'action:18'};
"""


@unittest.skipUnless(NODE, "JavaScript driver behavior checks require the optional Node tool runtime")
class ForgePileDriverTests(unittest.TestCase):
    def run_js(self, script):
        result = subprocess.run([NODE, "-e", HARNESS + script, str(COMMON), str(DRIVER)],
                                text=True, capture_output=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_covered_action_opens_pile_then_activates_original_physical_member(self):
        self.run_js(r"""
assert.equal(context.cardAction(option),false,'Opening a pile is not submitting the requested action');
assert.deepEqual(clicks,['forgeCardStackCount-card-88']);
assert.deepEqual(wheels,[],'The covered card is already in the viewport');
assert.equal(context.cardAction(option),true);
assert.deepEqual(clicks,['forgeCardStackCount-card-88','forgeCard-card-86']);
assert.equal(option.cardId,'card-86');
""")

    def test_offscreen_badge_navigates_front_before_exposing_original_card(self):
        self.run_js(r"""
badgeVisible = false;
assert.equal(context.cardAction(option),false);
assert.deepEqual(clicks,[]);
assert.deepEqual(wheels,[{id:'card-88',hand:false}]);
badgeVisible = true;
assert.equal(context.cardAction(option),false);
assert.equal(context.cardAction(option),true);
assert.deepEqual(clicks,['forgeCardStackCount-card-88','forgeCard-card-86']);
""")

    def test_front_open_fan_and_single_card_keep_normal_action_route(self):
        self.run_js(r"""
assert.equal(context.cardAction({...option,cardId:'card-88'}),true);
assert.deepEqual(clicks,['forgeCard-card-88']);
assert.equal(common.exposeActionCard(driver,'missing'),false);
member.fanned = true;
assert.equal(common.exposeActionCard(driver,'card-86'),false);
assert.equal(context.cardAction(option),true);
member.fanned = false; member.stackSize = 1;
assert.equal(common.exposeActionCard(driver,'card-86'),false);
assert.equal(context.cardAction(option),true);
assert.deepEqual(clicks,['forgeCard-card-88','forgeCard-card-86','forgeCard-card-86']);
assert.deepEqual(wheels,[]);
""")


if __name__ == "__main__":
    unittest.main()
