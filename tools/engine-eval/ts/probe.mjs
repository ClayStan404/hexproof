// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
// Independent qualification. Upstream sources and archived results remain untouched.
import { readFileSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const [checkoutArg, outputArg, cardsZipArg] = process.argv.slice(2);
if (!checkoutArg || !outputArg || !cardsZipArg) throw Error('Usage: node probe.mjs CHECKOUT NEW_OUTPUT_JSON PINNED_FORGE_CARDS_ZIP');
const checkout = resolve(checkoutArg), output = resolve(outputArg);
if (existsSync(output) || existsSync(output+'.evidence.json')) throw Error('Refusing to overwrite prior evidence');
const revision = 'e5f64769168b2a1ce20fb63d32e5684a85f13594';
if (execFileSync('git', ['-C', checkout, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim() !== revision)
    throw Error('Unexpected upstream revision');
if (execFileSync('git',['-C',checkout,'diff','HEAD','--','packages'],{encoding:'utf8'}).trim())
    throw Error('Upstream package sources have tracked modifications');
const load = p => import(pathToFileURL(resolve(checkout, p)).href);
const C = await load('packages/core/dist/index.mjs');
const G = await load('packages/game/dist/index.mjs');
const {parseCard} = await load('packages/cards/dist/index.mjs');
const suite = JSON.parse(readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), '../scenarios.json')));
const result = {schemaVersion:1, suiteVersion:suite.suiteVersion, candidate:'mtg-forge-ts',
    source:{url:'https://github.com/Baldugar/mtg-forge-ts', revision, patches:[],
        bundleSha256:Object.fromEntries(['core','game','cards'].map(name=>[name,createHash('sha256').update(readFileSync(resolve(checkout,`packages/${name}/dist/index.mjs`))).digest('hex')]))}, cases:[],
    notes:[
        'Qualification only; no performance claims or timings.',
        'Direct card/zone fixtures; exported cast/action/resolve/SBA components, except opening uses runGame.',
        'Basic-land intrinsic mana is expressed as equivalent AB$ Mana text in fixture definitions. No outcomes are manually changed.',
        'Component passes do not establish a functioning complete external human driver.',
    ], supplemental:[]};
const cardArchive=resolve(cardsZipArg),archiveFiles={
    'Raise the Alarm':'r/raise_the_alarm.txt','Rest in Peace':'r/rest_in_peace.txt','Clone':'c/clone.txt',
    'Giant Growth':'g/giant_growth.txt','Lovestruck Beast':'l/lovestruck_beast_hearts_desire.txt',
    'Bala Ged Recovery':'b/bala_ged_recovery_bala_ged_sanctuary.txt','Willbender':'w/willbender.txt',
    'Doom Blade':'d/doom_blade.txt','Emeritus of Truce':'e/emeritus_of_truce_swords_to_plowshares.txt',
    'Goblin Glasswright':'g/goblin_glasswright_craft_with_pride.txt','Time Ebb':'t/time_ebb.txt','Myr Mindservant':'m/myr_mindservant.txt',
};
result.source.cardFixtureArchive={path:cardArchive,forgeRevision:'143a6b556ac365cea97929ffcebb48eed03ecde8',
    sha256:createHash('sha256').update(readFileSync(cardArchive)).digest('hex'),entries:archiveFiles};
const scripts = {
    'Lightning Bolt':'Name:Lightning Bolt\nManaCost:R\nTypes:Instant\nA:SP$ DealDamage | Cost$ R | NumDmg$ 3 | ValidTgts$ Any | SpellDescription$ CARDNAME deals 3 damage to any target.',
    'Counterspell':'Name:Counterspell\nManaCost:U U\nTypes:Instant\nA:SP$ Counter | Cost$ U U | ValidTgts$ Spell | TgtPrompt$ Select target spell | SpellDescription$ Counter target spell.',
    'Grizzly Bears':'Name:Grizzly Bears\nManaCost:1 G\nTypes:Creature Bear\nPT:2/2',
    'Elvish Visionary':'Name:Elvish Visionary\nManaCost:1 G\nTypes:Creature Elf Shaman\nPT:1/1\nT:Mode$ ChangesZone | Origin$ Any | Destination$ Battlefield | ValidCard$ Card.Self | Execute$ TrigDraw | TriggerDescription$ When CARDNAME enters, draw a card.\nSVar:TrigDraw:DB$ Draw | Defined$ You | NumCards$ 1',
    'Isamaru, Hound of Konda':'Name:Isamaru, Hound of Konda\nManaCost:W\nTypes:Legendary Creature Dog\nPT:2/2',
};
for(const [name,entry] of Object.entries(archiveFiles))scripts[name]=execFileSync('unzip',['-p',cardArchive,entry],{encoding:'utf8'});
for (const [name,color] of [['Plains','W'],['Mountain','R'],['Forest','G'],['Island','U'],['Swamp','B']])
    scripts[name]=`Name:${name}\nManaCost:no cost\nTypes:Basic Land ${name}\nA:AB$ Mana | Cost$ T | Produced$ ${color} | Amount$ 1`;
const rules={formatId:'casual',startingLife:20,startingHandSize:7,mulliganRule:'london',firstPlayerSkipsDraw:true,
    ruleOverrides:[],playerCount:{min:2,max:4},poisonCountersToLose:10,playForAnte:false,manaBurn:false,appliedVariants:[]};
function mint(g,name,seat,zone){
    const id=g.newEntityId(),definition=parseCard(scripts[name],`${name}.txt`);
    const paper={name,edition:'EVAL',collectorNumber:String(id),language:'en',foil:false,flags:C.DEFAULT_PAPER_CARD_FLAGS,definition};
    if(definition.faces?.length){
        const alternate=scripts[name].match(/^AlternateMode:(.+)$/m)?.[1];
        const key=alternate==='Adventure'?'adventure':'back';
        paper.faces={front:{name:definition.name},[key]:{name:definition.faces[0].name}};
        if(alternate==='Modal')paper.isModalDfc=true;
    }
    const card=new G.Card(id,paper,C.mkPlayerSeat(seat),C.mkPlayerSeat(seat),zone);
    g.cards.set(id,card);g.players[seat].zones.get(zone).add(id);
    card.activateAbilitiesFromDefinition();card.activateTriggersFromDefinition(g);
    card.activateReplacementsFromDefinition(g);card.activateKeywordsFromDefinition(g);card.activateStaticsFromDefinition(g);
    return card;
}
function game(count=2,librarySize=30,commander=false){
    const g=new G.Game({lobbyPlayers:Array.from({length:count},(_,i)=>({id:`p${i}`,name:`P${i}`,controllerKind:'human'})),
        rules:{...rules,...(commander?{formatId:'commander',startingLife:40}:{})},
        meta:{engineVersion:G.GAME_VERSION,forgeSha:'independent-evaluation',cardDataSyncedAt:'2026-09-09',crVersion:'2026-08-07',seed:'42'},rng:new C.SeededRng(42n)});
    for(const p of g.players){
        for(const [type,Klass] of [[C.ZoneType.Library,G.Library],[C.ZoneType.Hand,G.Hand],[C.ZoneType.Battlefield,G.Battlefield],[C.ZoneType.Graveyard,G.Graveyard],[C.ZoneType.Command,G.CommandZone]])
            p.zones.set(type,new Klass(type,p.seat));
        p.manaPool=new G.ManaPool();
        for(let i=0;i<librarySize;i++)mint(g,'Plains',p.seat,C.ZoneType.Library);
    }
    g.turn=1;g.phase=C.PhaseStep.Main1;return g;
}
function drain(gen,decide){
    const controller=new G.RandomLegalController(new C.SeededRng(9n));
    const events=[],decisions=[];let step=gen.next(),n=0;
    while(!step.done){
        if(++n>10000)throw Error('Generator step limit');
        const y=step.value;
        if(y.kind==='decision'){
            decisions.push(y.request);
            const response=decide?.(y.request) ?? (y.request.kind==='priority'?{kind:'priority',action:{kind:'pass'}}:controller.decide(y.request));
            step=gen.next(response);
        } else {if(y.kind==='event')events.push(y.event);step=gen.next();}
    }
    return {events,decisions,value:step.value};
}
function mana(g,lands){
    for(const land of lands){
        drain(g.action.activateAbility(land.id,0,land.controllerSeat));
        const item=g.sharedZones.stack.top();
        if(!item)throw Error('Mana ability activation produced no stack item');
        drain(G.resolveStackItem(g,item));
    }
}
function cast(g,card,targets,lands=[],choose,proposal={}){
    const trace=[];
    const casted=drain(g.castPipeline.run({castingPlayer:card.controllerSeat,sourceCardId:card.id,originZone:card.zone,asSpecialAction:false,...proposal}),req=>{
        trace.push({requestKind:req.kind,face:card.face,characteristics:chars(g,card)});
        const picked=choose?.(req);if(picked)return picked;
        if(req.kind==='chooseCastTargets')return {kind:req.kind,targets};
        if(req.kind==='activateManaAbilities'){mana(g,lands);return {kind:req.kind,done:true};}
    });
    return {...casted,trace};
}
function summary(g){return {life:g.players.map(p=>p.life),players:g.players.map(p=>p.seat),hasLost:g.players.map(p=>p.hasLost),terminal:g.isTerminal(),terminalState:g.terminalState,
    zones:g.players.map(p=>Object.fromEntries([...p.zones].map(([type,z])=>[type,z.toArray().map(id=>g.cards.get(id)?.paperCard.name)]))),
    stack:g.sharedZones.stack.toArray().map(i=>({id:i.id,name:g.cards.get(i.sourceCardId)?.paperCard.name,kind:i.kind,targets:i.targets}))};}
function record(id,body){
    const row={id,status:'UNVERIFIED',layer:'engine',reason:'',setup:'Direct scenario fixture; engine methods execute actions.',assertionsPassed:0,assertionsFailed:0,observed:{},evidence:[basename(output)+'.evidence.json']};
    try {body(row);}catch(error){row.status='UNVERIFIED';row.layer='fixture';row.reason=`Probe exception requiring triage: ${error}`;row.observed.exception=error.stack;}
    result.cases.push(row);console.log(`${id}: ${row.status} ${row.reason}`);
}
function checks(row,assertions){
    row.observed.assertions=assertions;row.assertionsPassed=assertions.filter(a=>a.pass).length;row.assertionsFailed=assertions.filter(a=>!a.pass).length;
    row.status=row.assertionsFailed?'FAIL':'PASS';row.reason=row.assertionsFailed?'Exported engine component violated the frozen expected behavior.':'All frozen assertions passed through the disclosed engine component path.';
}
const chars=(g,c)=>{const p=g.layerEngine.computeCharacteristics(c.id);return {name:p.name,power:p.power,toughness:p.toughness,types:[...p.types],subtypes:[...p.subtypes],colors:Object.values(C.Color).filter(color=>p.colors.has(color)),abilities:p.abilities,manaCost:p.manaCost??null};};
const lands=(g,seat,names)=>names.map(name=>mint(g,name,seat,C.ZoneType.Battlefield));
function finish(g){
    const events=[],decisions=[];
    for(let i=0;i<50;i++){
        const priority=drain(G.runPriorityWindow(g));events.push(...priority.events);decisions.push(...priority.decisions);
        const item=g.sharedZones.stack.top();if(!item)return {events,decisions};
        const r=drain(G.resolveStackItem(g,item));events.push(...r.events);decisions.push(...r.decisions);
    }throw Error('Resolution loop exceeded bound');
}
function commanderGame(){
    const g=game(4,30,true),commanders=[];
    for(let seat=0;seat<4;seat++){const c=mint(g,'Isamaru, Hound of Konda',seat,C.ZoneType.Command);c.isCommander=true;g.flags.commandersOwnedByPlayer.set(seat,[c.id]);g.flags.commanderCastCount.set(c.id,0);commanders.push(c);}
    return {g,commanders};
}
function nativeView(g,viewer){
    const seat=viewer===null?99:viewer;
    if(viewer===null&&g.players.some(p=>p.seat===seat))throw Error('Reserved spectator seat collides');
    const data={turn:g.turn,phase:g.phase,activePlayer:g.activePlayer,
        players:g.players.map(p=>({seat:p.seat,life:p.life,zones:Object.fromEntries([...p.zones].map(([t,z])=>[t,z.toArray()]))})),
        cards:Object.fromEntries([...g.cards].map(([id,c])=>[id,{id,name:c.paperCard.name,zone:c.zone,tapped:c.tapped,faceDown:c.faceDown.kind!=='none',counters:{}}])),
        stack:g.sharedZones.stack.toArray().map(s=>s.sourceCardId)};
    return C.makeGameView(data,C.mkPlayerSeat(seat));
}
record('opening',row=>{
    const g=game(2,60),decks=Object.fromEntries(g.players.map(p=>[p.seat,p.zones.get(C.ZoneType.Library).toArray()]));
    // setupGame owns initial library seeding; card registry entries already exist.
    for(const p of g.players)for(const id of decks[p.seat])p.zones.get(C.ZoneType.Library).remove(id);
    g.startingPlayer=C.mkPlayerSeat(0);
    const gen=G.runGame(g,{decks}),decisions=[],events=[];let step=gen.next(),n=0,found=false;
    const controller=new G.RandomLegalController(new C.SeededRng(9n));
    while(!step.done){
        if(++n>10000)throw Error('Opening step limit');const y=step.value;
        if(y.kind==='decision'){
            decisions.push(y.request);
            if(y.request.kind==='priority' && g.phase===C.PhaseStep.Main1){found=true;break;}
            step=gen.next(y.request.kind==='priority'?{kind:'priority',action:{kind:'pass'}}:controller.decide(y.request));
        } else {if(y.kind==='event')events.push(y.event);step=gen.next();}
    }
    row.observed={state:summary(g),decisions,events};
    checks(row,[{name:'both hands seven',pass:g.players.every(p=>p.zones.get(C.ZoneType.Hand).size===7)},
        {name:'both libraries 53',pass:g.players.every(p=>p.zones.get(C.ZoneType.Library).size===53)},
        {name:'first draw skipped',pass:!events.some(e=>e.kind==='CardDrawn' && e.turn===1 && e.phase===C.PhaseStep.Draw)},
        {name:'player zero main decision',pass:found&&decisions.at(-1).playerSeat===0}]);gen.return();
});
record('land_priority',row=>{
    const g=game(),first=mint(g,'Plains',0,C.ZoneType.Hand),second=mint(g,'Plains',0,C.ZoneType.Hand);
    const request=drain(G.runPriorityWindow(g)).decisions.at(-1),before=JSON.stringify(summary(g));
    const pending={actor:request.playerSeat,id:1};
    function answer(actor,id,action){
        if(actor!==pending.actor||id!==pending.id||!request.legalActions.some(a=>JSON.stringify(a)===JSON.stringify(action)))return false;
        pending.id++;drain(g.action.playLand(action.cardId,actor));return true;
    }
    const action=request.legalActions.find(a=>a.kind==='playLand'&&a.cardId===first.id);
    const wrong=!answer(1,1,action)&&before===JSON.stringify(summary(g));
    const stale=!answer(0,0,action)&&before===JSON.stringify(summary(g));
    const accepted=answer(0,1,action),afterFirst=summary(g),legalSecond=G.enumerateLegalActions(g,0);
    const secondUnavailable=!legalSecond.some(a=>a.kind==='playLand'&&a.cardId===second.id);
    row.observed={nativeRequest:request,afterFirst,after:summary(g),legalSecond,hostActorGuard:{wrong,stale,accepted}};
    checks(row,[{name:'one Plains moved',pass:accepted&&first.zone===C.ZoneType.Battlefield&&second.zone===C.ZoneType.Hand},
        {name:'second land unavailable without mutation',pass:secondUnavailable&&JSON.stringify(afterFirst)===JSON.stringify(summary(g))},
        {name:'wrong actor cannot spend decision',pass:wrong&&stale}]);
    row.layer='adapter';row.reason+=' Host routes native runPriorityWindow legal actions to playLand and adds pending actor/id validation; not native authentication or a full phase driver.';
});
for(const creature of [false,true])record(creature?'bolt_creature':'bolt_player',row=>{
    const g=game(),bolt=mint(g,'Lightning Bolt',0,C.ZoneType.Hand),land=mint(g,'Mountain',0,C.ZoneType.Battlefield);
    const bears=creature?mint(g,'Grizzly Bears',1,C.ZoneType.Battlefield):null;
    const c=cast(g,bolt,[bears?{kind:'card',id:bears.id}:{kind:'player',seat:1}],[land]);
    const before=summary(g);before.boltCardZone=bolt.zone;if(!c.value)throw Error('Bolt cast returned null');
    const r=drain(G.resolveStackItem(g,c.value)),s=drain(g.sbaEngine.sweep());
    row.observed={before,after:summary(g),mountainTapped:land.tapped,events:[...c.events,...r.events,...s.events],decisions:c.decisions};
    checks(row,creature?[
        {name:'both graveyards',pass:bolt.zone===C.ZoneType.Graveyard&&bears.zone===C.ZoneType.Graveyard},
        {name:'defender life 20',pass:g.players[1].life===20},
        {name:'no bears battlefield',pass:!g.players[1].zones.get(C.ZoneType.Battlefield).toArray().includes(bears.id)},
    ]:[{name:'stack before damage',pass:before.life[1]===20&&before.stack.some(i=>i.name==='Lightning Bolt')&&before.boltCardZone===C.ZoneType.Stack},
        {name:'life 17',pass:g.players[1].life===17},
        {name:'graveyard and tap',pass:bolt.zone===C.ZoneType.Graveyard&&land.tapped}]);
});
record('counterspell',row=>{
    const g=game(),bolt=mint(g,'Lightning Bolt',0,C.ZoneType.Hand),mountain=mint(g,'Mountain',0,C.ZoneType.Battlefield),
        counter=mint(g,'Counterspell',1,C.ZoneType.Hand),islands=[mint(g,'Island',1,C.ZoneType.Battlefield),mint(g,'Island',1,C.ZoneType.Battlefield)];
    const b=cast(g,bolt,[{kind:'player',seat:1}],[mountain]);if(!b.value)throw Error('Bolt did not cast');
    const c=cast(g,counter,[{kind:'card',id:bolt.id}],islands);const before=summary(g);
    if(!c.value){row.observed={before,boltCardZone:bolt.zone,decisions:c.decisions,events:c.events};row.status='FAIL';row.reason='CastPipeline leaves Bolt card in Hand while creating its stack item; valid Spell target enumeration is empty and Counterspell targeting Bolt is rejected. No source-card zone correction is injected.';row.assertionsPassed=0;row.assertionsFailed=1;return;}
    const events=drain(G.resolveStackItem(g,c.value)).events;
    if(g.sharedZones.stack.top())events.push(...drain(G.resolveStackItem(g,g.sharedZones.stack.top())).events);
    row.observed={before,after:summary(g),events,decisions:c.decisions};
    checks(row,[{name:'counter above bolt',pass:before.stack.at(-1)?.name==='Counterspell'&&before.stack.some(i=>i.name==='Lightning Bolt')},
        {name:'no damage',pass:g.players.every(p=>p.life===20)},
        {name:'both graveyards and empty stack',pass:bolt.zone===C.ZoneType.Graveyard&&counter.zone===C.ZoneType.Graveyard&&g.sharedZones.stack.size===0}]);
    row.notes=['The fixture explicitly routes the responding seat into CastPipeline; PhaseHandler does not provide that opponent priority window.'];
});
record('etb_draw',row=>{
    const g=game(),v=mint(g,'Elvish Visionary',0,C.ZoneType.Hand),lands=[mint(g,'Forest',0,C.ZoneType.Battlefield),mint(g,'Plains',0,C.ZoneType.Battlefield)];
    const c=cast(g,v,[],lands);if(!c.value)throw Error('Visionary did not cast');
    const events=drain(G.resolveStackItem(g,c.value)).events;
    const creatureResolved=summary(g);events.push(...drain(G.runPriorityWindow(g)).events);
    const triggerStack=summary(g);
    if(g.sharedZones.stack.top())events.push(...drain(G.resolveStackItem(g,g.sharedZones.stack.top())).events);
    row.observed={creatureResolved,triggerStack,after:summary(g),events};
    checks(row,[{name:'visionary battlefield',pass:v.zone===C.ZoneType.Battlefield},
        {name:'one card drawn',pass:g.players[0].zones.get(C.ZoneType.Library).size===29&&g.players[0].zones.get(C.ZoneType.Hand).size===1},
        {name:'trigger stacked after creature',pass:creatureResolved.stack.length===0&&triggerStack.stack.some(i=>i.kind==='triggeredAbility')}]);
});
record('blocked_combat',row=>{
    const g=game(),a=mint(g,'Grizzly Bears',0,C.ZoneType.Battlefield),b=mint(g,'Grizzly Bears',1,C.ZoneType.Battlefield),handler=new G.CombatHandler(g);
    for(const phase of [C.PhaseStep.BeginCombat,C.PhaseStep.DeclareAttackers]){g.phase=phase;drain(new G.PhaseHandler(g).runStep(phase));}
    handler.declareAttackers([{attackerId:a.id,defender:{kind:'player',seat:1}}]);
    g.phase=C.PhaseStep.DeclareBlockers;handler.declareBlockers([{blockerId:b.id,attackerIds:[a.id]}]);
    handler.setBlockerOrder(a.id,[b.id]);g.phase=C.PhaseStep.CombatDamage;
    const damage=drain(handler.runCombatDamage()),sba=drain(g.sbaEngine.sweep());row.observed={after:summary(g),events:[...damage.events,...sba.events]};
    checks(row,[{name:'both dead',pass:a.zone!==C.ZoneType.Battlefield&&b.zone!==C.ZoneType.Battlefield},
        {name:'life unchanged',pass:g.players.every(p=>p.life===20)},
        {name:'owners graveyards',pass:g.players[0].zones.get(C.ZoneType.Graveyard).toArray().includes(a.id)&&g.players[1].zones.get(C.ZoneType.Graveyard).toArray().includes(b.id)}]);
    row.notes=['The fixture schedules combat declarations explicitly; PhaseHandler lacks integrated attack/block decisions.'];
});
record('hidden_views',row=>{
    const g=game();mint(g,'Lightning Bolt',0,C.ZoneType.Hand);mint(g,'Counterspell',1,C.ZoneType.Hand);mint(g,'Grizzly Bears',1,C.ZoneType.Battlefield);
    for(const p of g.players){const library=p.zones.get(C.ZoneType.Library),old=library.toArray()[0];library.remove(old);g.cards.delete(old);mint(g,p.seat===0?'Elvish Visionary':'Isamaru, Hound of Konda',p.seat,C.ZoneType.Library);}
    const owner=nativeView(g,0),opponent=nativeView(g,1),spectator=nativeView(g,null);
    row.observed={owner,opponent,spectator};
    checks(row,[{name:'own hand visible',pass:owner.players[0].zones.Hand.cards[0].name==='Lightning Bolt'},
        {name:'other secrets private',pass:!JSON.stringify(opponent).includes('Lightning Bolt')&&!JSON.stringify(owner).includes('Counterspell')&&!JSON.stringify(spectator).includes('Lightning Bolt')&&!JSON.stringify(spectator).includes('Counterspell')},
        {name:'library identity/order private',pass:[owner,opponent,spectator].every(v=>v.players.every(p=>p.zones.Library.kind==='hidden'&&p.zones.Library.count===30))},
        {name:'public card and counts',pass:[owner,opponent,spectator].every(v=>v.players[1].zones.Battlefield.cards[0].name==='Grizzly Bears')}]);
    const bears=[...g.cards.values()].find(c=>c.paperCard.name==='Grizzly Bears'),ebb=mint(g,'Time Ebb',0,C.ZoneType.Hand),ebbMana=lands(g,0,['Island','Plains','Plains']);
    const casted=cast(g,ebb,[{kind:'card',id:bears.id}],ebbMana);if(!casted.value)throw Error('Time Ebb did not cast');drain(G.resolveStackItem(g,casted.value));
    const before=g.players[1].zones.get(C.ZoneType.Library).toArray(),myr=mint(g,'Myr Mindservant',1,C.ZoneType.Battlefield),myrMana=lands(g,1,['Plains','Plains']);
    mana(g,myrMana);let myrAttempt;
    try{const activated=drain(g.action.activateAbility(myr.id,0,1)),item=g.sharedZones.stack.top();if(!item)throw Error('Myr activation produced no stack item');drain(G.resolveStackItem(g,item));myrAttempt={status:'PASS',events:activated.events};}
    catch(error){myrAttempt={status:'FAIL',layer:'engine',reason:String(error),cardScript:scripts['Myr Mindservant'],note:'Supplemental original-card activation failure, not one of the frozen hidden-view assertions'};}
    // The frozen privacy case does not require a particular shuffle card.
    // Exercise the existing native shuffle component independently; do not
    // repair the unsupported printed "2 T" cost or claim a paid Myr activation.
    const shuffled=drain(g.action.shuffle(1));
    const after=g.players[1].zones.get(C.ZoneType.Library).toArray(),views=[nativeView(g,0),nativeView(g,1),nativeView(g,null)];
    const supplemental=[{name:'real Time Ebb puts known Bears in library',pass:before.includes(bears.id)&&bears.zone===C.ZoneType.Library},
        {name:'native shuffle changes ordered known-card library',pass:JSON.stringify(before)!==JSON.stringify(after)&&after.includes(bears.id)},
        {name:'post-shuffle libraries expose counts not stable IDs',pass:views.every(v=>v.players.every(p=>p.zones.Library.kind==='hidden'&&!('cards' in p.zones.Library)&&!('ids' in p.zones.Library)))}];
    row.observed={...row.observed,myrAttempt,postShuffle:{path:'Actual Time Ebb followed by native GameAction.shuffle component; not a successful paid Myr activation',knownPublicId:bears.id,oracleBefore:before,oracleAfter:after,views,events:shuffled.events,assertions:supplemental},hostSpectatorConvention:'Adapter validates reserved nonparticipant seat 99 and maps spectator null to it before actual makeGameView; no native dedicated spectator API claimed'};
    checks(row,[...row.observed.assertions,...supplemental]);row.layer='adapter';row.reason+=' Actual native makeGameView plus tested snapshot conversion and explicit reserved-seat spectator convention; not production transport certification.';
});
record('four_player_departure',row=>{
    const g=game(4),bears=mint(g,'Grizzly Bears',2,C.ZoneType.Battlefield);
    const gen=new G.PhaseHandler(g).runStep(C.PhaseStep.Main1);let s=gen.next();while(!s.done&&s.value.kind!=='decision')s=gen.next();
    row.observed={pending:s.value?.request,before:summary(g)};
    const loss=drain(g.action.gameLoss(2,{reason:'concede'})),sba=drain(g.sbaEngine.sweep()),afterFirst=summary(g);
    s=gen.next({kind:'priority',action:{kind:'pass'}});while(!s.done)s=gen.next();
    for(const seat of [1,3]){drain(g.action.gameLoss(seat,{reason:'concede'}));drain(g.sbaEngine.sweep());}
    row.observed={...row.observed,afterFirst,after:summary(g),concedeEvents:loss.events,sbaEvents:sba.events,pendingCompleted:s.done,bearsStillRegistered:g.cards.has(bears.id)};
    checks(row,[{name:'seat two departure leaves three without terminal',pass:afterFirst.hasLost.filter(Boolean).length===1&&!afterFirst.terminal},
        {name:'departing Bears leaves all zones and registry',pass:!g.cards.has(bears.id)&&g.players.every(p=>[...p.zones.values()].every(z=>!z.toArray().includes(bears.id)))},
        {name:'player zero pending decision completes',pass:s.done},
        {name:'zero wins only after all opponents leave',pass:g.isTerminal()&&g.terminalState?.outcome?.winner===0}]);
    row.reason='Native out-of-turn GameAction.gameLoss(concede) emits PlayerLost but does not update liveness or invoke cleanup; SBA does not consume that event. Default PhaseHandler concede separately ends the whole four-player game. Host repair is supplemental, not this canonical result.';
    const nativeDriver=game(4),supplement=drain(new G.PhaseHandler(nativeDriver).runStep(C.PhaseStep.Main1),()=>({kind:'priority',action:{kind:'concede'}}));
    result.supplemental.push({id:'active_player_concede_four',notCanonical:'Conceding seat is 0 rather than canonical seat 2; default native driver defect.',after:summary(nativeDriver),events:supplement.events});
    const host=game(4),publicBears=mint(host,'Grizzly Bears',2,C.ZoneType.Battlefield),land=mint(host,'Plains',0,C.ZoneType.Hand);
    const pending=drain(G.runPriorityWindow(host)).decisions.at(-1),hostEvents=[];
    function hostConcede(seat){hostEvents.push(...drain(host.action.gameLoss(seat,{reason:'concede'})).events);host.sbaEngine.markPlayerLost(seat,'concede');hostEvents.push(...drain(G.removePlayerFromGame(host,seat)).events);}
    hostConcede(2);const hostFirst=summary(host),removed=!host.cards.has(publicBears.id)&&host.players.every(p=>[...p.zones.values()].every(z=>!z.toArray().includes(publicBears.id)));
    drain(host.action.playLand(land.id,pending.playerSeat));hostConcede(1);hostConcede(3);
    const hostAssertions=[{name:'three remain without ending',pass:hostFirst.hasLost.filter(Boolean).length===1&&!hostFirst.terminal},
        {name:'owned object leaves all zones',pass:removed},{name:'remaining native decision action executes',pass:land.zone===C.ZoneType.Battlefield},
        {name:'zero is sole winner',pass:host.isTerminal()&&host.terminalState?.outcome?.winner===0}];
    result.supplemental.push({id:'four_player_departure_host_adaptation',status:hostAssertions.every(a=>a.pass)?'PASS':'FAIL',layer:'adapter',notCanonical:'Host coordinates existing GameAction.gameLoss, private compiled SbaEngine.markPlayerLost, and exported removePlayerFromGame. This bypasses the incomplete business entrypoint and is not production/native driver qualification.',assertions:hostAssertions,pending,afterFirst:hostFirst,after:summary(host),events:hostEvents});
});
{
    const empty=()=>Object.fromEntries(Object.values(C.ZoneType).map(z=>[z,[]]));
    const opponentZones=empty();opponentZones.Battlefield=[2];
    const data={turn:1,phase:C.PhaseStep.Main1,activePlayer:0,
        players:[{seat:0,life:20,zones:empty()},{seat:1,life:20,zones:opponentZones}],
        cards:{1:{id:1,name:'Willbender',zone:C.ZoneType.Stack,tapped:false,faceDown:true,counters:{}},
            2:{id:2,name:'Willbender',zone:C.ZoneType.Battlefield,tapped:false,faceDown:true,counters:{}}},stack:[1]};
    const opponentView=C.makeGameView(data,C.mkPlayerSeat(0));
    result.supplemental.push({id:'facedown_view_projection',notCanonical:'Projection fixture only; no morph cast/turn-face-up action. Not a pass/fail for canonical morph.',
        opponentView,stackLeaksName:JSON.stringify(opponentView.stack).includes('Willbender'),
        battlefieldLeaksName:JSON.stringify(opponentView.players[1].zones.Battlefield).includes('Willbender')});
}
record('commander_tax',row=>{
    const {g,commanders}=commanderGame(),c=commanders[0],plains=lands(g,0,['Plains','Plains','Plains','Plains']),black=lands(g,1,['Swamp','Plains']);
    const initial=summary(g),first=cast(g,c,[],[plains[0]]);row.observed={initial,firstCastDecisions:first.decisions,firstResult:summary(g)};
    if(!first.value){checks(row,[{name:'first command-zone cast succeeds with W',pass:false}]);return;}
    drain(G.resolveStackItem(g,first.value));
    const doom=mint(g,'Doom Blade',1,C.ZoneType.Hand),destroy=cast(g,doom,[{kind:'card',id:c.id}],black);
    if(!destroy.value)throw Error('Doom Blade fixture cast did not succeed');
    const killed=drain(G.resolveStackItem(g,destroy.value)),returned=drain(g.sbaEngine.sweep());
    const afterReturn=summary(g),optional=returned.decisions.some(d=>d.kind.includes('commander')||JSON.stringify(d).includes('Command'));
    const second=cast(g,c,[],[plains[1]]),insufficientRejected=!second.value;
    if(second.value)drain(G.resolveStackItem(g,second.value));
    row.observed={...row.observed,afterReturn,returnDecisions:returned.decisions,destructionEvents:killed.events,secondCastDecisions:second.decisions,secondSucceededWithOnlyW:!!second.value,after:summary(g),castCount:g.flags.commanderCastCount.get(c.id)};
    checks(row,[{name:'four at forty and command-zone commanders',pass:initial.life.every(n=>n===40)&&commanders.length===4},
        {name:'optional command return offered',pass:optional},
        {name:'second cast needs two generic tax',pass:insufficientRejected}]);
    row.observed.unexecuted=['Correct 2W recast cannot be credited: the preceding W-only attempt already illegally succeeded in this run.'];
    row.notes=['Component command-zone casts deliberately attempted despite the incomplete native action menu; no tax/cast-count or return-decision behavior is supplied by the host.'];
});
record('commander_damage',row=>{
    const {g,commanders}=commanderGame(),c=commanders[0];
    drain(g.action.moveTo(c.id,C.ZoneType.Battlefield,{toSeat:0,cause:'initialFixture'}));
    g.flags.commanderDamage.set(c.id,new Map([[1,19]]));
    const handler=new G.CombatHandler(g);g.phase=C.PhaseStep.DeclareAttackers;
    handler.declareAttackers([{attackerId:c.id,defender:{kind:'player',seat:1}}]);
    g.phase=C.PhaseStep.DeclareBlockers;handler.declareBlockers([]);g.phase=C.PhaseStep.CombatDamage;
    const combat=drain(handler.runCombatDamage()),sba=drain(g.sbaEngine.sweep());
    const continuation=drain(G.runPriorityWindow(g)),land=mint(g,'Plains',0,C.ZoneType.Hand);
    g.phase=C.PhaseStep.Main2;const decision=drain(G.runPriorityWindow(g));drain(g.action.playLand(land.id,0));
    const fresh=commanderGame(),nc=fresh.commanders[0];drain(fresh.g.action.moveTo(nc.id,C.ZoneType.Battlefield,{toSeat:0,cause:'initialFixture'}));
    const noncombat=drain(fresh.g.action.damage(nc.id,'player',1,2,false));drain(fresh.g.sbaEngine.sweep());
    row.observed={afterCombat:summary(g),combatEvents:combat.events,sbaEvents:sba.events,recordedCommanderDamage:g.flags.commanderDamage.get(c.id)?.get(1),continuationDecisions:[...continuation.decisions,...decision.decisions],continuationLand:land.zone,noncombat:{state:summary(fresh.g),events:noncombat.events,counter:fresh.g.flags.commanderDamage.get(nc.id)?.get(1)??0}};
    checks(row,[{name:'defender loses after actual two combat damage at positive life',pass:g.players[1].life===38&&g.players[1].hasLost===true},
        {name:'remaining players receive and complete a decision',pass:!g.isTerminal()&&decision.decisions.some(d=>d.kind==='priority')&&land.zone===C.ZoneType.Battlefield},
        {name:'actual noncombat damage not recorded as commander combat damage',pass:fresh.g.players[1].life===38&&(fresh.g.flags.commanderDamage.get(nc.id)?.get(1)??0)===0}]);
});
record('tokens',row=>{
    const g=game(),spell=mint(g,'Raise the Alarm',0,C.ZoneType.Hand),manaLands=lands(g,0,['Plains','Plains']);
    const casted=cast(g,spell,[],manaLands);if(!casted.value)throw Error('Token spell not cast');
    const resolved=drain(G.resolveStackItem(g,casted.value)),sba=drain(g.sbaEngine.sweep());
    const tokens=[...g.cards.values()].filter(c=>c.isToken&&c.zone===C.ZoneType.Battlefield),tokenChars=tokens.map(c=>chars(g,c));
    row.observed={after:summary(g),tokens:tokenChars,events:[...resolved.events,...sba.events],decisions:casted.decisions};
    checks(row,[{name:'two controlled white 1/1 Soldier tokens',pass:tokens.length===2&&tokens.every(c=>c.controllerSeat===0&&g.layerEngine.computeCharacteristics(c.id).colors.has(C.Color.White))&&tokenChars.every(c=>c.power===1&&c.toughness===1&&c.subtypes.includes('Soldier'))},
        {name:'Raise the Alarm in graveyard',pass:spell.zone===C.ZoneType.Graveyard},
        {name:'no token consumed from hand or library',pass:g.players[0].zones.get(C.ZoneType.Library).size===30&&g.players[0].zones.get(C.ZoneType.Hand).size===0}]);
});
record('replacement',row=>{
    const g=game();mint(g,'Rest in Peace',0,C.ZoneType.Battlefield);const bears=mint(g,'Grizzly Bears',1,C.ZoneType.Battlefield),bolt=mint(g,'Lightning Bolt',0,C.ZoneType.Hand),mountain=mint(g,'Mountain',0,C.ZoneType.Battlefield);
    const casted=cast(g,bolt,[{kind:'card',id:bears.id}],[mountain]);if(!casted.value)throw Error('Bolt not cast');
    const r=drain(G.resolveStackItem(g,casted.value)),s=drain(g.sbaEngine.sweep());
    row.observed={after:summary(g),boltZone:bolt.zone,bearsZone:bears.zone,events:[...r.events,...s.events]};
    checks(row,[{name:'Bears exiled',pass:bears.zone===C.ZoneType.Exile},{name:'Bolt exiled',pass:bolt.zone===C.ZoneType.Exile},
        {name:'both graveyards empty',pass:g.players.every(p=>p.zones.get(C.ZoneType.Graveyard).size===0)}]);
});
record('copy',row=>{
    const g=game(),bears=mint(g,'Grizzly Bears',1,C.ZoneType.Battlefield),growth=mint(g,'Giant Growth',0,C.ZoneType.Hand),clone=mint(g,'Clone',0,C.ZoneType.Hand),sources=lands(g,0,['Forest','Island','Plains','Plains','Plains']);
    const pump=cast(g,growth,[{kind:'card',id:bears.id}],[sources[0]]);if(!pump.value)throw Error('Growth not cast');drain(G.resolveStackItem(g,pump.value));
    const grown=chars(g,bears),casted=cast(g,clone,[],sources.slice(1));if(!casted.value)throw Error('Clone not cast');
    const r=drain(G.resolveStackItem(g,casted.value)),rest=finish(g);
    row.observed={grown,original:chars(g,bears),clone:chars(g,clone),after:summary(g),decisions:[...casted.decisions,...r.decisions,...rest.decisions],events:[...pump.events,...r.events,...rest.events]};
    checks(row,[{name:'Clone enters as Bears copy',pass:clone.zone===C.ZoneType.Battlefield&&chars(g,clone).name==='Grizzly Bears'},
        {name:'copy excludes temporary growth',pass:chars(g,clone).power===2&&chars(g,clone).toughness===2},
        {name:'original actually remains 5/5',pass:grown.power===5&&grown.toughness===5&&chars(g,bears).power===5&&chars(g,bears).toughness===5}]);
});
record('adventure',row=>{
    const g=game(),card=mint(g,'Lovestruck Beast',0,C.ZoneType.Hand),sources=lands(g,0,['Forest','Forest','Plains','Plains']);
    const casted=cast(g,card,[],[sources[0]],req=>req.kind==='chooseFace'?{kind:'chooseFace',face:'adventure'}:undefined);
    row.observed={castDecisions:casted.decisions,castTrace:casted.trace,afterCast:summary(g),faceAfterPipeline:card.face,characteristicsAfterPipeline:chars(g,card)};
    if(!casted.value){checks(row,[{name:'Adventure cast succeeds for G',pass:false}]);return;}
    const r=drain(G.resolveStackItem(g,casted.value));const exiled=card.zone===C.ZoneType.Exile,tokens=[...g.cards.values()].filter(c=>c.isToken&&c.zone===C.ZoneType.Battlefield);
    const recast=exiled?cast(g,card,[],sources.slice(1),req=>req.kind==='chooseFace'?{kind:'chooseFace',face:'front'}:undefined,{altCostKey:'Adventure'}):null;
    if(recast?.value)drain(G.resolveStackItem(g,recast.value));
    row.observed={...row.observed,events:r.events,adventureSide:card.adventureSide,exiledAfterAdventure:exiled,tokens:tokens.map(c=>chars(g,c)),recastDecisions:recast?.decisions,after:summary(g)};
    checks(row,[{name:'one white 1/1 Human',pass:tokens.length===1&&chars(g,tokens[0]).power===1&&chars(g,tokens[0]).toughness===1&&chars(g,tokens[0]).subtypes.includes('Human')&&g.layerEngine.computeCharacteristics(tokens[0].id).colors.has(C.Color.White)},
        {name:'card exiled after Adventure',pass:exiled},
        {name:'same creature cast from exile as 5/5',pass:!!recast?.value&&card.zone===C.ZoneType.Battlefield&&chars(g,card).power===5&&chars(g,card).toughness===5}]);
});
record('modal_dfc',row=>{
    const g=game(),card=mint(g,'Bala Ged Recovery',0,C.ZoneType.Hand),before=summary(g);
    const offered=G.enumerateLegalActions(g,0),probe=cast(g,card,[],[],req=>req.kind==='chooseFace'?{kind:'chooseFace',face:'back'}:undefined,{asSpecialAction:true});
    const afterFace=chars(g,card),offeredAfter=G.enumerateLegalActions(g,0);
    row.observed={before,offered,faceDecision:probe.decisions,castTrace:probe.trace,faceAfterPipeline:card.face,characteristicsAfterPipeline:afterFace,offeredAfter,after:summary(g),castResult:!!probe.value};
    const landAction=offeredAfter.find(a=>a.kind==='playLand'&&a.cardId===card.id);
    if(landAction)drain(g.action.playLand(card.id,0));
    checks(row,[{name:'Sanctuary entered tapped as land without sorcery cast',pass:card.zone===C.ZoneType.Battlefield&&card.tapped&&chars(g,card).types.includes(C.CardType.Land)&&g.sharedZones.stack.size===0},
        {name:'no sorcery effect occurred',pass:g.players[0].zones.get(C.ZoneType.Graveyard).size===0&&g.sharedZones.stack.size===0}]);
    row.observed.unexecuted=['Untap and green mana activation depend on the absent land-face play.'];
    row.reason='Native back-face choice ran in the real cast pipeline, but no land action became available and no land entered. The pipeline abort restores the default face; separate in-flight trace is preserved. No expected land state injected; untap/mana continuation cannot execute.';
});
record('morph',row=>{
    const g=game(),card=mint(g,'Willbender',0,C.ZoneType.Hand),sources=lands(g,0,['Plains','Plains','Plains','Island','Plains']);
    const options=G.altCostRegistry.available(card,g).map(c=>c.handlerKey),hasMorph=G.altCostRegistry.has('Morph');
    const casted=cast(g,card,[],sources.slice(0,3),undefined,{altCostKey:'Morph'});
    row.observed={options,hasRegisteredMorphAltCost:hasMorph,keyword:card.morphCost,castDecisions:casted.decisions,castReturned:!!casted.value,afterCast:summary(g),faceDown:card.faceDown};
    if(casted.value)drain(G.resolveStackItem(g,casted.value));
    checks(row,[{name:'real paid three-mana face-down spell',pass:!!casted.value&&card.faceDown.kind!=='none'}]);
    row.reason='Exact parsed Willbender keyword exists, but no Morph alternative-cost handler is registered and requesting Morph through the real cast pipeline does not create a face-down spell. No manual faceDown mutation is credited.';
});
const extensions=JSON.parse(readFileSync(resolve(dirname(fileURLToPath(import.meta.url)),'../extensions.json'))),extensionRows=[];
for(const remove of [false,true]){
    record(remove?'prepare_source_leaves':'prepare_cast',row=>{
        const g=game(),goblin=mint(g,'Goblin Glasswright',0,C.ZoneType.Hand),sources=lands(g,0,['Mountain','Mountain','Mountain']);
        const options=G.enumerateLegalActions(g,0),casted=cast(g,goblin,[],sources.slice(0,2));
        if(!casted.value)throw Error('Goblin Glasswright fixture cast failed');
        const resolved=drain(G.resolveStackItem(g,casted.value)),rest=finish(g),copies=[...g.cards.values()].filter(c=>c.zone===C.ZoneType.Exile&&c.paperCard.name==='Craft with Pride');
        const prepared={state:summary(g),creature:chars(g,goblin),prepared:goblin.prepared??goblin.isPrepared??null,copyIds:copies.map(c=>c.id),actions:G.enumerateLegalActions(g,0)};
        row.observed={options,castDecisions:casted.decisions,afterCreature:prepared,events:[...resolved.events,...rest.events],fixtureArchiveEntry:archiveFiles['Goblin Glasswright']};
        if(remove){
            const bolt=mint(g,'Lightning Bolt',1,C.ZoneType.Hand),mountain=mint(g,'Mountain',1,C.ZoneType.Battlefield),shot=cast(g,bolt,[{kind:'card',id:goblin.id}],[mountain]);
            if(!shot.value)throw Error('Responder Bolt failed in Prepare removal fixture');
            const damage=drain(G.resolveStackItem(g,shot.value)),sba=drain(g.sbaEngine.sweep());
            row.observed.removal={state:summary(g),events:[...damage.events,...sba.events],sourceZone:goblin.zone};
            checks(row,[{name:'creature and associated prepared copy existed',pass:prepared.creature.power===2&&prepared.creature.toughness===2&&copies.length===1&&prepared.prepared===true},
                {name:'actual Bolt destroys creature',pass:goblin.zone===C.ZoneType.Graveyard&&damage.events.some(e=>e.kind==='DamageDealt')}]);
            row.observed.unexecuted=['Uncast associated copy cleanup is not credited because the native engine never created that copy.'];
        }else{
            checks(row,[{name:'alternative sorcery not directly castable from hand',pass:options.every(a=>a.kind!=='castSpell'||g.cards.get(a.cardId)?.paperCard.name!=='Craft with Pride')},
                {name:'creature enters prepared with exactly one associated copy',pass:goblin.zone===C.ZoneType.Battlefield&&prepared.creature.power===2&&prepared.creature.toughness===2&&copies.length===1&&prepared.prepared===true}]);
            row.observed.unexecuted=['Prepared sorcery casting and Treasure/copy lifetime assertions cannot execute because no associated prepared copy exists.'];
        }
        row.reason='Real original Goblin Glasswright cast resolves as 2/2, but the native engine does not execute its ETB Prepare replacement or create its associated Craft with Pride copy. No substitute AlterAttribute implementation or expected state is injected.';
    });
    const row=result.cases.pop();extensionRows.push(row);result.supplemental.push({...row,extensionSuite:extensions.suiteVersion});
}
for(const def of suite.cases)if(!result.cases.some(c=>c.id===def.id))result.cases.push({id:def.id,status:'UNVERIFIED',layer:'fixture',reason:'No exact shared fixture implemented in this qualification round.',setup:'Not executed.',assertionsPassed:0,assertionsFailed:0,observed:{},evidence:[]});
mkdirSync(dirname(output),{recursive:true});
writeFileSync(output+'.probe.mjs',readFileSync(fileURLToPath(import.meta.url)));
writeFileSync(output+'.card-scripts.json',JSON.stringify(scripts,null,2)+'\n');
writeFileSync(output+'.command.json',JSON.stringify({argv:process.argv,node:process.version,cwd:process.cwd(),source:checkout,cardsZip:cardArchive},null,2)+'\n');
writeFileSync(output+'.extensions.json',JSON.stringify({schemaVersion:1,suiteVersion:extensions.suiteVersion,candidate:result.candidate,source:result.source,cases:extensionRows},null,2)+'\n');
writeFileSync(output+'.evidence.json',JSON.stringify({source:result.source,observations:result.cases.map(c=>({id:c.id,observed:c.observed})),supplemental:result.supplemental},null,2)+'\n');
writeFileSync(output,JSON.stringify(result,null,2)+'\n');
console.log(output);
process.exitCode=result.cases.some(c=>c.status==='UNVERIFIED'||c.status==='BLOCKED')?2:result.cases.some(c=>c.status==='FAIL')?1:0;
