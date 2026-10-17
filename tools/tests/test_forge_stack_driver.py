# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Execute the maintained test-player JS; no engine, network or GUI is launched."""

import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
NODE = shutil.which("node")
SOURCE = ROOT / "tools/ui-automation/scenarios/ForgeStackStudy.js"
FIXTURE = ROOT / "testdata/protocol/v1/rules-snapshot-stack-targets.json"

HARNESS = r"""
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const snapshot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).payload;
let now = 0, inputs = 0, accepted = true, mana = 4;
const records = [], captures = [], cards = {};
for (const object of snapshot.stack)
    cards[object.id] = {cardId:object.id, sourceId:object.sourceId,
        controllerSeat:object.controllerSeat, name:object.identity.name,
        rulesText:object.text, zone:'stack'};
cards.counterCard = {name:'Counterspell', zone:'hand'};
const session = {gameId:'test-game', turn:37, step:'declare_attackers', promptId:1,
    ids:['bolt'], stackObjectIds() { return this.ids; },
    cardForInspection(id) { return cards[id] || {}; }};
const driver = {session, availableMana() { return mana; },
    cardAction() { inputs++; return accepted; }, capture(name) { captures.push(name); }};
const option = {cardId:'counterCard', kind:'cast'};
const context = vm.createContext({Date:{now:() => now},
    ws:{roomSession:{seatIndex:1}}, auditProbe:{record:(name,value) => records.push({name,value})}});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), context, {filename:process.argv[1]});
function allowed(name='Counterspell') { return context.castAllowed(driver,name,option.cardId); }
function attempt() { return context.castCard(driver,option); }
"""


@unittest.skipUnless(NODE, "JavaScript driver behavior checks require the optional Node tool runtime")
class ForgeStackDriverTests(unittest.TestCase):
    def run_js(self, script):
        result = subprocess.run([NODE, "-e", HARNESS + script, str(SOURCE), str(FIXTURE)],
                                text=True, capture_output=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_visible_ability_is_excluded_but_protocol_spell_sources_remain_eligible(self):
        self.run_js(r"""
for (const id of ['bolt','trail','counter']) {
    session.ids = [id];
    context.ws.roomSession.seatIndex = 1 - cards[id].controllerSeat;
    for (const name of ['Counterspell','Negate','Cancel'])
        assert.equal(allowed(name),true,'An absent physical source is normal for a real spell projection');
}
context.ws.roomSession.seatIndex = 1;
cards.trigger = {sourceId:'permanent',controllerSeat:0,name:'Borderland Marauder',
    rulesText:'Borderland Marauder gets +2/+0 until end of turn.',zone:'stack'};
session.ids = ['trigger'];
for (const zone of ['battlefield','graveyard','exile','hand','command']) {
    cards.permanent = {zone};
    for (const name of ['Counterspell','Negate','Cancel']) assert.equal(allowed(name),false);
}
session.ids = ['bolt'];
cards['bolt-source'] = {zone:'stack'};
assert.equal(allowed(),true);
cards.bolt.controllerSeat = 1;
assert.equal(allowed(),false,'The test strategy does not counter its own spells');
cards.bolt.controllerSeat = 0;
cards.bolt.name = 'Wind Drake';
assert.equal(allowed('Negate'),false);
assert.equal(allowed('Counterspell'),true);
assert.equal(allowed('Cancel'),true);
assert.equal(allowed('Lightning Bolt'),true,'Non-counterspell strategy is untouched');
""")

    def test_unknown_stack_attempts_are_bounded_with_same_or_changed_prompt(self):
        for changing_prompt in (False, True):
            with self.subTest(changing_prompt=changing_prompt):
                self.run_js("const changingPrompt = " + json.dumps(changing_prompt) + r""";
for (let i=0; i<3; i++) {
    if (changingPrompt) session.promptId++;
    assert.equal(allowed(),true);
    assert.equal(attempt(),true);
    now += 200;
}
assert.equal(inputs,3);
assert.equal(allowed(),true,'Give delivered input one second to produce visible progress');
assert.equal(attempt(),false,'Do not send more input while waiting');
assert.equal(inputs,3);
now = 1000;
assert.equal(allowed(),false);
assert.equal(allowed(),false);
assert.equal(records.length,1);
assert.equal(records[0].value.reason,'no observable action progress');
assert.equal(records[0].value.attempts,3);
assert.deepEqual(captures,['counterspell-no-progress']);
""")

    def test_failed_input_and_new_observed_context_do_not_inherit_the_attempt_limit(self):
        self.run_js(r"""
accepted = false;
for (let i=0;i<4;i++) { assert.equal(allowed(),true); assert.equal(attempt(),false); }
accepted = true;
for (let i=0;i<3;i++) { assert.equal(allowed(),true); attempt(); }
now = 1000;
assert.equal(allowed(),false);
// A resolved/replaced stack object gives the same physical counterspell a
// fresh opportunity, including when a successful prior cast returned to hand.
cards.nextSpell = {...cards.bolt}; session.ids = ['nextSpell'];
assert.equal(allowed(),true); assert.equal(attempt(),true);
session.gameId = 'next-game';
assert.equal(allowed(),true); assert.equal(attempt(),true);
mana = 5;
assert.equal(allowed(),true); assert.equal(attempt(),true);
""")


if __name__ == "__main__":
    unittest.main()
