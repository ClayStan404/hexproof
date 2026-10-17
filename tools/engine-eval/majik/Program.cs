// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

using System.Text.Json;
using Majik.Bot;
using Majik.Core.Api;
using Majik.Core.CardData;
using Majik.Core.Cards;
using Majik.Core.Random;

// Supplemental actual catalog/bot gameplay, not a common human policy or a
// qualification of all seventeen fixtures. No fallback vanilla cards.
if (args.Length != 3)
    throw new ArgumentException("workloads.json workload-id new-output-directory");
var output = Path.GetFullPath(args[2]);
Directory.CreateDirectory(output);
if (File.Exists(Path.Combine(output, "events.jsonl")))
    throw new InvalidOperationException("Refusing to overwrite evidence");
var payload = File.ReadAllText(args[0]);
File.WriteAllText(Path.Combine(output, "workloads.json"), payload);
using var document = JsonDocument.Parse(payload);
var spec = document.RootElement.GetProperty("workloads").EnumerateArray()
    .Single(w => w.GetProperty("id").GetString() == args[1]);
var specs = spec.GetProperty("players").EnumerateArray().ToArray();
if (specs.Length != 2 || spec.GetProperty("variant").GetString() != "Constructed")
    throw new NotSupportedException("The actual GameFacade factory has exactly Alice and Bob; this probe does not invent four-player hosting");
var repo = new EmbeddedCardRepository();
IReadOnlyList<ICard> Deck(JsonElement player) => player.GetProperty("cards").EnumerateArray()
    .SelectMany(card => Enumerable.Range(0, card.GetProperty("count").GetInt32())
        .Select(_ => DeckCardShellBuilder.Build(repo.GetByName(card.GetProperty("name").GetString()!)
            ?? throw new InvalidOperationException("Named reference card absent from actual catalog: " + card))))
    .ToList();
using var facade = GameFacade.Create("Reference seat 0", "Reference seat 1", Deck(specs[0]), Deck(specs[1]), cardRepo: repo);
using var trace = new StreamWriter(Path.Combine(output, "events.jsonl"));
var gate = new object();
int eventCount = 0;
var eventTypes = new Dictionary<string, int>();
using var subscription = facade.Subscribe(e => {
    lock (gate) {
        trace.WriteLine(JsonSerializer.Serialize(e));
        eventCount++;
        eventTypes[e.Type] = eventTypes.GetValueOrDefault(e.Type) + 1;
    }
});
var initial = facade.GetState();
if (initial.Players.Any(p => p.Life != spec.GetProperty("startingLife").GetInt32()))
    throw new InvalidOperationException("Wrong actual initial life");
if (initial.Players.Count != 2 || initial.Players.Select(p => p.Id).Distinct().Count() != 2)
    throw new InvalidOperationException("Wrong actual registered players");
for (int seat = 0; seat < 2; seat++) {
    var expected = specs[seat].GetProperty("cards").EnumerateArray().Sum(c => c.GetProperty("count").GetInt32());
    if (initial.Players[seat].Library.Cards.Count != expected || initial.Players[seat].Hand.Cards.Count != 0)
        throw new InvalidOperationException("Wrong actual deck size before opening draw");
}
facade.ReplaceAliceAgent(new BotPlayerAgent(facade.Alice, new BotConfig("Burn", RandomSeed: 1)));
facade.ReplaceBobAgent(new BotPlayerAgent(facade.Bob, new BotConfig("Burn", RandomSeed: 2)));
using var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(90));
try {
    await facade.StartFullGameAsync(firstPlayerSlot: spec.GetProperty("startingPlayer").GetInt32(),
        maxTurns: 200, ct: cancel.Token, rng: new GameRandom(spec.GetProperty("seed").GetInt32()));
    var ended = await facade.FullGameTask!;
    var final = facade.GetState();
    bool natural = ended.Winner is not null && final.Players.Count == 2 &&
        final.Players.Select(p => p.Id).ToHashSet().SetEquals(initial.Players.Select(p => p.Id)) &&
        final.Players.Single(p => p.Id == ended.Winner.Id).Life > 0 &&
        !final.Players.Single(p => p.Id == ended.Winner.Id).HasLost &&
        final.Players.Where(p => p.Id != ended.Winner.Id).All(p => p.HasLost) &&
        new[] { "LibraryShuffledEvent", "OpeningHandCheckEvent", "SpellCastEvent",
            "StackObjectResolvedEvent", "PlayerLostEvent" }
            .All(kind => eventTypes.GetValueOrDefault(kind) > 0) &&
        (eventTypes.GetValueOrDefault("DamageDealtEvent") > 0 ||
            eventTypes.GetValueOrDefault("CombatDamageDealtEvent") > 0);
    var result = new { status = natural ? "PASS" : "FAIL", workload = args[1],
        scope = "Supplemental actual-catalog native heuristic bots; not common external human policy",
        naturalCompletion = natural, turns = ended.TurnsPlayed, winner = ended.Winner?.Id,
        eventCount, eventTypes, initial, final, observerViewAbsent = facade.GetStateFor(Guid.Empty) is null };
    File.WriteAllText(Path.Combine(output, "result.json"), JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    Console.WriteLine(JsonSerializer.Serialize(result));
    return natural ? 0 : 1;
} catch (Exception error) {
    File.WriteAllText(Path.Combine(output, "failure.txt"), error.ToString());
    throw;
}
