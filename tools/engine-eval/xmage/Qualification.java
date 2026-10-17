// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import com.google.gson.GsonBuilder;
import org.junit.runner.JUnitCore;
import org.junit.runner.Request;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** The runner records observations; the shared evaluator owns semantic verdicts. */
public final class Qualification {
    static final Map<String, Object> observations = new LinkedHashMap<>();

    public static void observe(String key, Object value) {
        observations.put(key, value);
        System.out.println("OBSERVE " + key + "=" + value);
    }

    public static void main(String[] args) throws Exception {
        Map<String, String> cases = new LinkedHashMap<>();
        cases.put("opening", "org.hexproof.eval.HumanCases#openingKeepSeven");
        cases.put("land_priority", "org.hexproof.eval.DuelCases#landPriority");
        cases.put("bolt_player", "org.hexproof.eval.DuelCases#boltPlayer");
        cases.put("bolt_creature", "org.hexproof.eval.DuelCases#boltCreature");
        cases.put("counterspell", "org.hexproof.eval.DuelCases#counterspell");
        cases.put("etb_draw", "org.hexproof.eval.DuelCases#etbDraw");
        cases.put("blocked_combat", "org.hexproof.eval.DuelCases#blockedCombat");
        cases.put("hidden_views", "org.hexproof.eval.DuelCases#hiddenViews");
        cases.put("four_player_departure", "org.hexproof.eval.FourCases#departure");
        cases.put("adventure", "org.hexproof.eval.MechanicCases#adventure");
        cases.put("modal_dfc", "org.hexproof.eval.MechanicCases#modalDfc");
        cases.put("replacement", "org.hexproof.eval.MechanicCases#replacement");
        cases.put("copy", "org.hexproof.eval.MechanicCases#copy");
        cases.put("tokens", "org.hexproof.eval.MechanicCases#tokens");
        cases.put("morph", "org.hexproof.eval.MechanicCases#morph");
        cases.put("commander_tax", "org.hexproof.eval.CommanderCases#tax");
        cases.put("commander_damage", "org.hexproof.eval.CommanderCases#damage");
        cases.put("prepare_cast", "org.hexproof.eval.PrepareCases#cast");
        cases.put("prepare_source_leaves", "org.hexproof.eval.PrepareCases#sourceLeaves");
        List<Map<String, Object>> output = new ArrayList<>();
        List<String> selected = args.length > 1
                ? Arrays.asList(Arrays.copyOfRange(args, 1, args.length))
                : new ArrayList<>(cases.keySet());
        for (String caseId : selected) {
            String target = cases.get(caseId);
            if (target == null) throw new IllegalArgumentException("Unknown case " + caseId);
            String[] parts = target.split("#");
            observations.clear();
            System.out.println("CASE_BEGIN " + caseId);
            Result result = new JUnitCore().run(Request.method(Class.forName(parts[0]), parts[1]));
            Map<String, Object> record = new LinkedHashMap<>();
            record.put("case_id", caseId);
            record.put("junit_success", result.wasSuccessful());
            record.put("junit_run_count", result.getRunCount());
            record.put("junit_ignored_count", result.getIgnoreCount());
            record.put("observations", new LinkedHashMap<>(observations));
            List<Map<String, Object>> failures = new ArrayList<>();
            for (Failure failure : result.getFailures()) {
                Map<String, Object> detail = new LinkedHashMap<>();
                detail.put("message", failure.getMessage());
                detail.put("exception", failure.getException().getClass().getName());
                detail.put("trace", failure.getTrace());
                failures.add(detail);
                System.out.println(failure.getTrace());
            }
            record.put("failures", failures);
            output.add(record);
            Files.write(Paths.get(args[0]), new GsonBuilder().setPrettyPrinting().create()
                    .toJson(output).getBytes(StandardCharsets.UTF_8));
            System.out.println("CASE_END " + caseId + " junit_success=" + result.wasSuccessful());
        }
    }
}
