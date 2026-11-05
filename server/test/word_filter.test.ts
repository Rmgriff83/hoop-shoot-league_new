import { describe, expect, it } from "vitest";
import lists from "../../data/blocked_words.json";
import cases from "../../data/word_filter_cases.json";
import words from "../../data/handle_words.json";
import towns from "../../data/towns.json";
import { blockedWord, cleanTyping } from "../src/word_filter";
import { safeName, validName } from "../src/rules";
import { shownTown, validTown } from "../src/towns";

describe("word filter", () => {
  it("cleans typing to A-Z, 0-9 and single spaces", () => {
    expect(cleanTyping("brick  baron", 24)).toBe("BRICK BARON");
    expect(cleanTyping("  salt harbor ", 16)).toBe("SALT HARBOR ");
    expect(cleanTyping("'; DROP TABLE players; --", 24)).toBe("DROP TABLE PLAYERS "); // the trailing space stays while typing
    expect(cleanTyping("<script>alert(1)</script>", 24)).toBe("SCRIPTALERT1SCRIPT");
    expect(cleanTyping("na​me\n\ttab\u0000", 24)).toBe("NAMETAB");
    expect(cleanTyping("émilie 🏀 söder", 24)).toBe("MILIE SDER");
    expect(cleanTyping("a very long hometown name", 16)).toBe("A VERY LONG HOME");
  });
  it("agrees with the game on the shared verdict table", () => {
    for (const s of cases.blocked) expect(blockedWord(s), s).not.toBe("");
    for (const s of cases.allowed) expect(blockedWord(s), s).toBe("");
  });
  it("names the word it found", () => {
    expect(blockedWord("SH1T HEAD")).toBe("SHIT");
    expect(blockedWord("FU CK")).toBe("FUCK");
    expect(blockedWord("FUUUCK")).toBe("FUCK");
    expect(blockedWord("A SS")).toBe("ASS");
  });
  it("never refuses a rolled handle or a listed town", () => {
    for (const f of words.first) for (const s of words.second) expect(validName(`${f} ${s}`), `${f} ${s}`).toBe(true);
    for (const t of towns.towns) expect(validTown(t), t).toBe(true);
  });
  it("keeps the list tidy", () => {
    const all = [...lists.blocked, ...lists.whole];
    expect(new Set(all).size).toBe(all.length);
    for (const w of [...all, ...lists.allow]) expect(w, w).toMatch(/^[A-Z0-9]+$/);
    for (const w of lists.allow) expect(lists.blocked.some((b) => w.includes(b)), w).toBe(true);
  });
  it("applies to names and towns the same way", () => {
    expect(validName("FUCKER")).toBe(false);
    expect(validName("SH1T HEAD")).toBe(false);
    expect(validName("CLASS ACT")).toBe(true);
    expect(safeName("BRICK BARON")).toBe("BRICK BARON");
    expect(safeName("FUCK BARON")).toBe("PLAYER");
    expect(safeName("")).toBe("PLAYER");
    expect(validTown("FUCKVILLE")).toBe(false);
    expect(validTown("")).toBe(false);
    expect(shownTown("fuckville")).toBe("");
    expect(shownTown("salt  harbor!!")).toBe("SALT HARBOR");
  });
});
