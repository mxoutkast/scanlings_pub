import "dotenv/config";
import Fastify from "fastify";
import multipart from "@fastify/multipart";
import { z } from "zod";
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";

type MvpCatalog = {
  version: number;
  mvp: {
    allowed_archetypes: string[];
    elements: string[];
    archetypes: Record<string, { silhouette_ids: string[]; allowed_passives?: string[]; allowed_cues?: string[] }>;
  };
};

function loadMvpCatalog(): MvpCatalog {
  // backend/src/index.ts -> backend -> scanlings
  const p = path.join(__dirname, "..", "..", "MVP_CATALOG.json");
  const raw = fs.readFileSync(p, "utf8");
  return JSON.parse(raw) as MvpCatalog;
}

const MVP_CATALOG = loadMvpCatalog();

// Short silhouette descriptions (from SILHOUETTES_AND_PASSIVES.md) to help both Gemini selection and Decart conditioning.
const SILHOUETTE_DESCS: Record<string, string> = {
  bulwark_golem_01: "squat boulder body, big fists",
  bulwark_golem_02: "barrel torso, shield slab arm",
  bulwark_golem_03: "turtle-golem shell, low stance",

  pouncer_01: "catlike crouch, blade tail",
  pouncer_02: "bat-imp, wing cloak",
  pouncer_03: "fox sprite, dagger ears",

  zoner_wisp_01: "floating orb + ribbon arms",
  zoner_wisp_02: "lantern wisp, dangling tassels",
  zoner_wisp_03: "cloud jelly, drifting tendrils",

  sprout_medic_01: "sprout kid, leaf cape",
  sprout_medic_02: "potion bud, bottle belly",
  sprout_medic_03: "mushroom nurse, cap hat",

  cannon_critter_01: "chubby raccoon with arm-cannon",
  cannon_critter_02: "penguin blaster, chest turret",
  cannon_critter_03: "snail tank, shell cannon",

  hex_scholar_01: "owl mage, scroll wings",
  hex_scholar_02: "witch doll, big sleeves",
  hex_scholar_03: "book imp, page cape",

  storm_skater_01: "slick lizard, fin shoes",
  storm_skater_02: "sparrow skater, wing blades",
  storm_skater_03: "electric eel, hover tail",

  forge_pup_01: "metal puppy, big jaw",
  forge_pup_02: "boar cub, rivet hide",
  forge_pup_03: "bearlet, furnace belly",
};

function slugifyTemplateId(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function templatePathForArchetype(archetype: string): string {
  const slug = slugifyTemplateId(archetype);
  const candidate = path.join(process.cwd(), "templates", `archetype_${slug}.png`);
  if (fs.existsSync(candidate)) return candidate;
  return path.join(process.cwd(), "templates", "vinyl_template_default.png");
}

function templatePathForSilhouette(params: { silhouetteId?: string; archetype: string }): string {
  if (params.silhouetteId) {
    const cand = path.join(process.cwd(), "templates", `silhouette_${params.silhouetteId}.png`);
    if (fs.existsSync(cand)) return cand;
  }
  return templatePathForArchetype(params.archetype);
}

function loadTemplateFile(p: string): Buffer {
  const b = fs.readFileSync(p);

  // Fast path: looks like a real PNG header
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
    return b;
  }

  // If the file was accidentally saved as base64 text or data URL, decode it.
  const utf8 = b.toString("utf8").trim();
  const trimmed = utf8.replace(/^\uFEFF/, "").trim();

  const dataUrlMatch = trimmed.match(/^data:image\/(png|jpeg);base64,(.+)$/i);
  let base64Str: string | null = null;
  if (dataUrlMatch) {
    base64Str = dataUrlMatch[2];
  } else {
    // Heuristic: detect UTF-16LE text (lots of NUL bytes)
    let nulCount = 0;
    for (let i = 0; i < Math.min(256, b.length); i++) if (b[i] === 0) nulCount++;
    const text = nulCount > 16 ? b.toString("utf16le").trim() : trimmed;
    const head = text.slice(0, 16);
    if (head.startsWith("iVBOR") || head.startsWith("/9j/") || head.startsWith("UEsDB")) {
      base64Str = text;
    }
  }

  if (base64Str) {
    const s = base64Str.replace(/\s+/g, "");
    if (/^[A-Za-z0-9+/=]+$/.test(s) && s.length > 64) {
      return Buffer.from(s, "base64");
    }
  }

  return b;
}

const PORT = parseInt(process.env.PORT || "8787", 10);
const HOST = process.env.HOST || "127.0.0.1";
const REQUIRE_DEVICE_ID = (process.env.REQUIRE_DEVICE_ID || "false").toLowerCase() === "true";

const DECART_API_KEY = process.env.DECART_API_KEY || "";
const DECART_BASE_URL = process.env.DECART_BASE_URL || "https://api.decart.ai";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY || "";
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-2.5-flash-lite";

const app = Fastify({ logger: true });

// Minimal CORS for local dev (Godot desktop/editor).
app.addHook("onSend", async (_req, reply, payload) => {
  reply.header("Access-Control-Allow-Origin", "*");
  reply.header("Access-Control-Allow-Headers", "Content-Type, X-Device-Id");
  reply.header("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  return payload;
});

app.options("/*", async (_req, reply) => {
  reply.code(204).send();
});

app.get("/health", async () => ({ ok: true }));

const UnitRef = z.object({
  local_id: z.string().min(1),
  archetype: z.string().min(1),
  element: z.string().min(1),
  rarity: z.string().min(1),
});

const LadderBattleReq = z.object({
  my_team: z.array(UnitRef).min(3).max(5),
  opponent_team: z.array(UnitRef).min(3).max(5),
});

type UnitIn = z.infer<typeof UnitRef>;

type Role = "tank" | "support" | "dps" | "control";

type MoveKind = "damage" | "heal" | "shield" | "control";

type Targeting = "frontline" | "backline_random" | "enemy_lowest_hp" | "ally_lowest_hp" | "self";

type MoveDef = {
  move_id: string;
  name: string;
  cue: string;
  kind: MoveKind;
  base: number;
  targeting: Targeting;
};

type ArchetypeKit = {
  archetype: string;
  role: Role;
  hp_max: number;
  moves: [MoveDef, MoveDef];
};

type CreatureStats = {
  hp: number;
  atk: number;
  def: number;
  spd: number;
};

const KITS: Record<string, ArchetypeKit> = {
  "Bulwark Golem": {
    archetype: "Bulwark Golem",
    role: "tank",
    hp_max: 160,
    moves: [
      { move_id: "stonewall_slam", name: "Stonewall Slam", cue: "CUE_CHARGE_SHAKE", kind: "damage", base: 14, targeting: "frontline" },
      { move_id: "guard_up", name: "Guard Up", cue: "CUE_RING_PULSE", kind: "shield", base: 10, targeting: "self" },
    ],
  },
  "Forge Pup": {
    archetype: "Forge Pup",
    role: "tank",
    hp_max: 150,
    moves: [
      { move_id: "spark_bite", name: "Spark Bite", cue: "CUE_TWO_BEAT", kind: "damage", base: 15, targeting: "frontline" },
      { move_id: "heat_guard", name: "Heat Guard", cue: "CUE_RING_PULSE", kind: "shield", base: 9, targeting: "ally_lowest_hp" },
    ],
  },
  "Sprout Medic": {
    archetype: "Sprout Medic",
    role: "support",
    hp_max: 120,
    moves: [
      { move_id: "green_patch", name: "Green Patch", cue: "CUE_RING_PULSE", kind: "heal", base: 16, targeting: "ally_lowest_hp" },
      { move_id: "seed_shield", name: "Seed Shield", cue: "CUE_TARGET_MARK", kind: "shield", base: 10, targeting: "ally_lowest_hp" },
    ],
  },
  "Hex Scholar": {
    archetype: "Hex Scholar",
    role: "support",
    hp_max: 115,
    moves: [
      { move_id: "sigil_mend", name: "Sigil Mend", cue: "CUE_RING_PULSE", kind: "heal", base: 14, targeting: "ally_lowest_hp" },
      { move_id: "ward_rune", name: "Ward Rune", cue: "CUE_TARGET_MARK", kind: "shield", base: 11, targeting: "ally_lowest_hp" },
    ],
  },
  "Cannon Critter": {
    archetype: "Cannon Critter",
    role: "dps",
    hp_max: 100,
    moves: [
      { move_id: "scoop_n_fling", name: "Scoop 'n Fling", cue: "CUE_TWO_BEAT", kind: "damage", base: 22, targeting: "frontline" },
      { move_id: "cutlery_clatter", name: "Cutlery Clatter", cue: "CUE_TARGET_MARK", kind: "damage", base: 18, targeting: "frontline" },
    ],
  },
  Pouncer: {
    archetype: "Pouncer",
    role: "dps",
    hp_max: 105,
    moves: [
      { move_id: "pounce", name: "Pounce", cue: "CUE_CHARGE_SHAKE", kind: "damage", base: 21, targeting: "backline_random" },
      { move_id: "backflip_kick", name: "Backflip Kick", cue: "CUE_TWO_BEAT", kind: "damage", base: 19, targeting: "frontline" },
    ],
  },
  "Zoner Wisp": {
    archetype: "Zoner Wisp",
    role: "control",
    hp_max: 112,
    moves: [
      { move_id: "zone_burst", name: "Zone Burst", cue: "CUE_TARGET_MARK", kind: "control", base: 16, targeting: "frontline" },
      { move_id: "slow_field", name: "Slow Field", cue: "CUE_RING_PULSE", kind: "control", base: 0, targeting: "frontline" },
    ],
  },
  "Storm Skater": {
    archetype: "Storm Skater",
    role: "control",
    hp_max: 110,
    moves: [
      { move_id: "static_dash", name: "Static Dash", cue: "CUE_TWO_BEAT", kind: "damage", base: 17, targeting: "frontline" },
      { move_id: "arc_jam", name: "Arc Jam", cue: "CUE_TARGET_MARK", kind: "control", base: 0, targeting: "frontline" },
    ],
  },
};

function rarityMult(rarity: string): number {
  switch (rarity) {
    case "Rare":
      return 1.08;
    case "Epic":
      return 1.16;
    case "Legendary":
      return 1.25;
    default:
      return 1.0;
  }
}

function baseStatsForArchetype(archetype: string): { atk: number; def: number; spd: number } {
  // MVP baseline stats (Common). These will be scaled by rarity.
  switch (archetype) {
    case "Bulwark Golem":
      return { atk: 12, def: 16, spd: 8 };
    case "Cannon Critter":
      return { atk: 18, def: 10, spd: 12 };
    case "Sprout Medic":
      return { atk: 10, def: 14, spd: 11 };
    case "Zoner Wisp":
      return { atk: 12, def: 12, spd: 14 };
    case "Pouncer":
      return { atk: 17, def: 9, spd: 16 };
    case "Forge Pup":
      return { atk: 16, def: 12, spd: 11 };
    case "Hex Scholar":
      return { atk: 12, def: 12, spd: 12 };
    case "Storm Skater":
      return { atk: 13, def: 10, spd: 18 };
    default:
      return { atk: 14, def: 12, spd: 12 };
  }
}

function statsForCreature(params: { archetype: string; rarity: string }): CreatureStats {
  const kit = kitFor(params.archetype);
  const m = rarityMult(params.rarity);
  const base = baseStatsForArchetype(params.archetype);
  return {
    hp: Math.max(1, Math.round(kit.hp_max * m)),
    atk: Math.max(1, Math.round(base.atk * m)),
    def: Math.max(1, Math.round(base.def * m)),
    spd: Math.max(1, Math.round(base.spd * m)),
  };
}

function kitFor(archetype: string): ArchetypeKit {
  return KITS[archetype] ?? {
    archetype,
    role: "dps",
    hp_max: 100,
    moves: [
      { move_id: "slam", name: "Slam", cue: "CUE_CHARGE_SHAKE", kind: "damage", base: 18, targeting: "frontline" },
      { move_id: "jab", name: "Jab", cue: "CUE_TWO_BEAT", kind: "damage", base: 16, targeting: "frontline" },
    ],
  };
}

function roleForArchetype(archetype: string): Role {
  return kitFor(archetype).role;
}

function makeBattleResult(params: {
  my_team: UnitIn[];
  opponent_team: UnitIn[];
  seed: number;
}) {
  const { my_team, opponent_team, seed } = params;

  // Phase 1.5: kit-aware sim (archetype kits w/ move_id + cue + intent)

  const N = my_team.length;

  const roleOf = (side: "me" | "opp", idx0: number): Role => {
    const u = side === "me" ? my_team[idx0] : opponent_team[idx0];
    return roleForArchetype(u.archetype);
  };

  const me_hp_max = Array.from({ length: N }, (_, i) => kitFor(my_team[i].archetype).hp_max);
  const opp_hp_max = Array.from({ length: N }, (_, i) => kitFor(opponent_team[i].archetype).hp_max);
  const me_hp = me_hp_max.slice();
  const opp_hp = opp_hp_max.slice();
  const me_shield = Array.from({ length: N }, () => 0);
  const opp_shield = Array.from({ length: N }, () => 0);

  const firstAlive = (hp: number[]) => hp.findIndex((x) => x > 0);
  const firstAliveIn = (hp: number[], indices: number[]) => {
    for (const i of indices) {
      if (i >= 0 && i < hp.length && hp[i] > 0) return i;
    }
    return -1;
  };
  const lowestAlive = (hp: number[]) => {
    let best = -1;
    let bestHp = Infinity;
    for (let i = 0; i < hp.length; i++) {
      if (hp[i] > 0 && hp[i] < bestHp) {
        best = i;
        bestHp = hp[i];
      }
    }
    return best;
  };

  const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

  // Simple deterministic RNG (xorshift32)
  let rng = (seed >>> 0) || 1;
  const rand01 = () => {
    rng ^= rng << 13;
    rng ^= rng >>> 17;
    rng ^= rng << 5;
    return (rng >>> 0) / 0xffffffff;
  };

  const units = {
    me: Array.from({ length: N }, (_, i) => ({
      ref: `me_${i + 1}`,
      local_id: my_team[i].local_id,
      archetype: my_team[i].archetype,
      element: my_team[i].element,
      rarity: my_team[i].rarity,
      role: roleOf("me", i),
      hp_max: me_hp_max[i],
    })),
    opp: Array.from({ length: N }, (_, i) => ({
      ref: `opp_${i + 1}`,
      local_id: opponent_team[i].local_id,
      archetype: opponent_team[i].archetype,
      element: opponent_team[i].element,
      rarity: opponent_team[i].rarity,
      role: roleOf("opp", i),
      hp_max: opp_hp_max[i],
    })),
  };

  const turns: any[] = [];

  // status state (MVP): jam applies to target for 1 action
  const me_jam: number[] = Array.from({ length: N }, () => 0);
  const opp_jam: number[] = Array.from({ length: N }, () => 0);

  const SOFT_CAP = 20;
  const HARD_CAP = 60;

  for (let t = 1; t <= HARD_CAP; t++) {
    // stop if a side is fully KO
    if (me_hp.every((x) => x <= 0) || opp_hp.every((x) => x <= 0)) break;

    const meTurn = t % 2 === 1;
    const side = meTurn ? "me" : "opp";

    const atkHp = meTurn ? me_hp : opp_hp;
    const defHp = meTurn ? opp_hp : me_hp;

    // Pick an alive actor. Start from round-robin slot, then advance until we find alive.
    let actor_i = ((t - 1) % N) | 0;
    let guard = 0;
    while (guard < N && atkHp[actor_i] <= 0) {
      actor_i = (actor_i + 1) % N;
      guard++;
    }
    if (guard >= N) {
      // No alive actors on this side.
      break;
    }

    const actor_ref = `${side}_${actor_i + 1}`;
    const actor_role = roleOf(side, actor_i);

    // If jammed, 20% chance to misfire (consume jam on attempt)
    const jamArr = meTurn ? me_jam : opp_jam;
    let misfire = false;
    if (jamArr[actor_i] > 0) {
      jamArr[actor_i] = Math.max(0, jamArr[actor_i] - 1);
      if (rand01() < 0.2) misfire = true;
    }

    const actorKit = kitFor((meTurn ? my_team : opponent_team)[actor_i].archetype);
    const move = actorKit.moves[(t + actor_i) % 2];

    if (misfire) {
      const sh = meTurn ? me_shield : opp_shield;
      turns.push({
        turn: t,
        actor: actor_ref,
        target: actor_ref,
        move_id: move.move_id,
        move_name: move.name,
        cue: move.cue,
        hit: false,
        misfire: true,
        damage: 0,
        healing: 0,
        shield_delta: 0,
        absorbed: 0,
        target_hp: (meTurn ? me_hp : opp_hp)[actor_i],
        target_shield: sh[actor_i],
        ko: false,
        status_applied: [],
        status_consumed: ["jam"],
        jam_remaining_by_ref: {
          ...Object.fromEntries(me_jam.map((v, i) => [`me_${i + 1}`, v])),
          ...Object.fromEntries(opp_jam.map((v, i) => [`opp_${i + 1}`, v])),
        },
      });
      continue;
    }

    if (move.kind === "heal") {
      const hp = meTurn ? me_hp : opp_hp;
      const hpMax = meTurn ? me_hp_max : opp_hp_max;
      const target_i = move.targeting === "self" ? actor_i : lowestAlive(hp);
      if (target_i === -1) continue;

      const before = hp[target_i];
      const variance = Math.floor(rand01() * 5); // 0-4
      const healDamp = t > SOFT_CAP ? Math.max(0, 1 - 0.08 * (t - SOFT_CAP)) : 1;
      const healing = Math.max(1, Math.floor((move.base + variance) * healDamp));
      hp[target_i] = clamp(hp[target_i] + healing, 0, hpMax[target_i]);
      const after = hp[target_i];

      turns.push({
        turn: t,
        actor: actor_ref,
        target: `${side}_${target_i + 1}`,
        move_id: move.move_id,
        move_name: move.name,
        cue: move.cue,
        hit: true,
        damage: 0,
        healing: after - before,
        shield: 0,
        target_hp: after,
        ko: false,
        status_applied: [],
        status_consumed: [],
        jam_remaining_by_ref: {
          ...Object.fromEntries(me_jam.map((v, i) => [`me_${i + 1}`, v])),
          ...Object.fromEntries(opp_jam.map((v, i) => [`opp_${i + 1}`, v])),
        },
      });
      continue;
    }

    if (move.kind === "shield") {
      const hp = meTurn ? me_hp : opp_hp;
      const sh = meTurn ? me_shield : opp_shield;
      const target_i = move.targeting === "self" ? actor_i : lowestAlive(hp);
      if (target_i === -1) continue;

      const beforeSh = sh[target_i];
      const variance = Math.floor(rand01() * 4); // 0-3
      const healDamp = t > SOFT_CAP ? Math.max(0, 1 - 0.08 * (t - SOFT_CAP)) : 1;
      const shieldAmt = Math.max(1, Math.floor((move.base + variance) * healDamp));

      // Cap shields (MVP): 40 or 30% of hp_max, whichever is higher.
      const cap = Math.max(40, Math.floor((meTurn ? me_hp_max : opp_hp_max)[target_i] * 0.3));
      sh[target_i] = clamp(sh[target_i] + shieldAmt, 0, cap);
      const afterSh = sh[target_i];

      turns.push({
        turn: t,
        actor: actor_ref,
        target: `${side}_${target_i + 1}`,
        move_id: move.move_id,
        move_name: move.name,
        cue: move.cue,
        hit: true,
        damage: 0,
        healing: 0,
        shield_delta: afterSh - beforeSh,
        absorbed: 0,
        target_hp: hp[target_i],
        target_shield: afterSh,
        ko: false,
        status_applied: ["shield"],
        status_consumed: [],
        jam_remaining_by_ref: {
          ...Object.fromEntries(me_jam.map((v, i) => [`me_${i + 1}`, v])),
          ...Object.fromEntries(opp_jam.map((v, i) => [`opp_${i + 1}`, v])),
        },
      });
      continue;
    }

    // Formation: slots 0-1 frontline, 2+ backline.
    const frontline = [0, 1].filter((i) => i < N);
    const backline = [2, 3, 4].filter((i) => i < N);

    let target_i = -1;
    if (move.targeting === "backline_random") {
      const aliveBack = backline.filter((i) => defHp[i] > 0);
      if (aliveBack.length > 0) {
        target_i = aliveBack[Math.floor(rand01() * aliveBack.length)];
      }
    }

    // Default targeting: frontline first
    if (target_i === -1) {
      target_i = firstAliveIn(defHp, frontline);
      if (target_i === -1) target_i = firstAliveIn(defHp, backline);
    }

    if (target_i === -1) continue;

    const before = defHp[target_i];

    // Intercept: if a backliner would be hit and defender has an alive tank, tank may intercept.
    const defSide: "me" | "opp" = meTurn ? "opp" : "me";
    const defTeam = defSide === "me" ? my_team : opponent_team;
    let intercepted = false;
    let target_original: number | null = null;
    if (target_i >= 2) {
      const tank_i = [0, 1].find((i) => i < N && defHp[i] > 0 && roleForArchetype(defTeam[i].archetype) === "tank");
      if (tank_i !== undefined && rand01() < 0.45) {
        intercepted = true;
        target_original = target_i;
        target_i = tank_i;
      }
    }

    const variance = Math.floor(rand01() * 7); // 0-6
    const crit = rand01() < 0.1;
    const ramp = t > SOFT_CAP ? 1 + 0.12 * (t - SOFT_CAP) : 1;

    const roleMult = actor_role === "tank" ? 0.75 : actor_role === "support" ? 0.6 : actor_role === "control" ? 0.8 : 1.0;
    const damage = Math.max(1, Math.floor((move.base + variance) * roleMult * (crit ? 1.5 : 1.0) * ramp));

    const defShield = meTurn ? opp_shield : me_shield;
    const beforeSh = defShield[target_i];
    const absorbed = Math.min(beforeSh, damage);
    defShield[target_i] = beforeSh - absorbed;
    const dmgToHp = damage - absorbed;

    defHp[target_i] = Math.max(0, defHp[target_i] - dmgToHp);
    const after = defHp[target_i];
    const ko = before > 0 && after === 0;

    const targetRef = `${meTurn ? "opp" : "me"}_${target_i + 1}`;
    const targetOriginalRef = target_original === null ? null : `${meTurn ? "opp" : "me"}_${target_original + 1}`;
    const statuses: string[] = [];
    // Control can apply JAM (1 action) to the target.
    if (actor_role === "control" && rand01() < 0.35) {
      statuses.push("jam");
      const jamTarget = meTurn ? me_jam : opp_jam; // attacking side's jam array is for its own units; we need defender
      // Correct: apply to defender
      if (meTurn) {
        me_jam[target_i] = 0; // noop for clarity
        opp_jam[target_i] = 1;
      } else {
        opp_jam[target_i] = 0;
        me_jam[target_i] = 1;
      }
    }

    turns.push({
      turn: t,
      actor: actor_ref,
      target: targetRef,
      target_original: targetOriginalRef,
      intercepted,
      move_id: move.move_id,
      move_name: move.name,
      cue: move.cue,
      targeting: move.targeting,
      hit: true,
      damage,
      healing: 0,
      shield_delta: 0 - absorbed,
      absorbed,
      target_hp: after,
      target_shield: defShield[target_i],
      ko,
      status_applied: statuses,
      status_consumed: [],
      jam_remaining_by_ref: {
        ...Object.fromEntries(me_jam.map((v, i) => [`me_${i + 1}`, v])),
        ...Object.fromEntries(opp_jam.map((v, i) => [`opp_${i + 1}`, v])),
      },
    });
  }

  // Determine winner by wipeout.
  const meAlive = me_hp.some((x) => x > 0);
  const oppAlive = opp_hp.some((x) => x > 0);
  const winner = meAlive && !oppAlive ? "me" : !meAlive && oppAlive ? "opp" : meAlive ? "me" : "opp";

  const end_turn = turns.length > 0 ? turns[turns.length - 1].turn : 0;

  return {
    battle_id: `b_${seed}_${Date.now()}`,
    winner,
    winner_reason: end_turn >= HARD_CAP ? "sudden_death_hard_cap" : "wipeout",
    end_turn,
    rating_delta: winner === "me" ? { me: 12, opp: -12 } : { me: -12, opp: 12 },
    essence_reward: winner === "me" ? 20 : 10,
    seed,
    units,
    initial_hp: {
      me: me_hp_max,
      opp: opp_hp_max,
    },
    turn_log: turns,
  };
}

async function callGeminiVisionSpec(params: {
  imageBytes: Buffer;
  imageMimeType: string;
}): Promise<{
  name: string;
  archetype: string;
  silhouette_id: string;
  silhouette_desc: string;
  element: string;
  rarity: string;
  palette_hex: string[];
  texture_notes: string;
  move_name_overrides: string[];
  essence: string;
  flavor_text: string;
}> {
  if (!GEMINI_API_KEY) throw new Error("missing_gemini_api_key");

  const allowedArchetypes = MVP_CATALOG.mvp.allowed_archetypes.filter((a) => Object.prototype.hasOwnProperty.call(KITS, a));
  const allowedElements = MVP_CATALOG.mvp.elements;
  const allowedRarities = ["Common", "Rare", "Epic", "Legendary"];

  const silhouetteCatalog: Record<string, string[]> = Object.fromEntries(
    allowedArchetypes.map((a) => [a, MVP_CATALOG.mvp.archetypes[a]?.silhouette_ids ?? []]),
  );

  const allSilhouettes = allowedArchetypes.flatMap((a) => silhouetteCatalog[a] ?? []);

  const silhouetteOptionsText = allowedArchetypes
    .map((arch) => {
      const ids = silhouetteCatalog[arch] ?? [];
      const lines = ids.map((id) => `- ${id}: ${SILHOUETTE_DESCS[id] ?? "(no desc)"}`);
      return [`${arch} silhouettes:`, ...lines].join("\n");
    })
    .join("\n\n");

  const schemaHint = {
    name: "string (short, playful, original; not a generic object label)",
    archetype: allowedArchetypes,
    silhouette_id: allSilhouettes,
    element: allowedElements,
    rarity: allowedRarities,
    palette_hex: ["#RRGGBB"],
    texture_notes: "string (<= 24 words) describing materials/textures/colors seen",
    move_name_overrides: ["string"],
    essence: "string",
    flavor_text: "string",
  };

  const prompt = [
    "You are classifying a real-world object photo into a Scanlings creature.",
    "Return ONLY valid JSON with keys: name, archetype, silhouette_id, element, rarity, palette_hex, texture_notes, move_name_overrides, essence, flavor_text.",
    "Name rules: invent a playful, character-like proper name (1-3 words). Do NOT use generic object labels like 'coffee mug', 'chair', 'bottle', 'phone'.",
    "Avoid brand names. Avoid real copyrighted character names.",
    "palette_hex must be 3-5 hex colors in the form #RRGGBB, extracted from the photo (dominant colors).",
    "texture_notes should describe material/texture cues from the photo (e.g. glossy plastic, brushed metal, fabric, wood grain).",
    "move_name_overrides must be an array of exactly 2 short move names that fit the photo/theme. These are cosmetic only.",
    "essence must be a short theme statement (8-16 words) describing what the object/photo IS and its vibe/context (e.g. 'old CRT television, retro tech, cozy living room nostalgia').",
    "flavor_text must be 1-2 short sentences describing the NEWLY CREATED Scanling creature (not the real photo). Reference archetype/element/silhouette vibe and optionally echo the essence.",
    "Do not reference real brands or copyrighted character names.",
    "Pick archetype ONLY from the allowed list.",
    "Pick silhouette_id ONLY from the 3 silhouettes that belong to that archetype.",
    "Use the silhouette descriptions below to choose the closest matching silhouette.",
    "Silhouette options:",
    silhouetteOptionsText,
    "Pick element ONLY from the allowed list.",
    "Pick rarity ONLY from the allowed list.",
    "If uncertain, choose the closest archetype and default rarity Common.",
    "Do not include markdown or extra text.",
    "Allowed schema hint:",
    JSON.stringify(schemaHint),
  ].join("\n");

  const body: any = {
    contents: [
      {
        role: "user",
        parts: [
          { text: prompt },
          {
            inlineData: {
              mimeType: params.imageMimeType,
              data: params.imageBytes.toString("base64"),
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      responseMimeType: "application/json",
    },
  };

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(GEMINI_MODEL)}:generateContent?key=${encodeURIComponent(GEMINI_API_KEY)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`gemini_failed_${res.status}: ${txt.slice(0, 200)}`);
  }

  const json: any = await res.json();
  const text = json?.candidates?.[0]?.content?.parts?.map((p: any) => p.text).filter(Boolean).join("") ?? "";
  if (!text) throw new Error("gemini_no_text");

  let raw = String(text).trim();
  if (raw.startsWith("```")) raw = raw.replace(/^```[a-zA-Z]*\s*/m, "").replace(/```\s*$/m, "").trim();

  // Sometimes providers still return extra prose; try to extract first {...} block.
  const m = raw.match(/\{[\s\S]*\}/);
  if (m) raw = m[0];

  let parsed: any;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`gemini_bad_json: ${raw.slice(0, 200)}`);
  }

  const clampTo = (v: any, allowed: string[], fallback: string) => (allowed.includes(String(v)) ? String(v) : fallback);

  const archetype = clampTo(parsed.archetype, allowedArchetypes, "Cannon Critter");
  const element = clampTo(parsed.element, allowedElements, "Water");
  const rarity = clampTo(parsed.rarity, allowedRarities, "Common");
  const rawName = typeof parsed.name === "string" ? parsed.name.trim() : "";
  const genericLabels = new Set([
    "coffee mug",
    "mug",
    "cup",
    "bottle",
    "chair",
    "table",
    "phone",
    "keyboard",
    "mouse",
    "remote",
    "tv",
    "television",
    "lamp",
  ]);
  const isGeneric = (n: string) => {
    const k = n.toLowerCase().replace(/[^a-z0-9\s]/g, "").trim();
    return genericLabels.has(k) || k.split(/\s+/).length >= 3 && genericLabels.has(k.split(/\s+/).slice(-2).join(" "));
  };

  const name = rawName && !isGeneric(rawName) ? rawName.slice(0, 28) : archetype;

  const allowedSilsForArch = silhouetteCatalog[archetype] ?? [];
  let silhouette_id = typeof parsed.silhouette_id === "string" ? parsed.silhouette_id.trim() : "";
  if (!allowedSilsForArch.includes(silhouette_id)) {
    // fallback: pick first silhouette for the archetype
    silhouette_id = allowedSilsForArch[0] ?? "";
  }

  const palIn = Array.isArray(parsed.palette_hex) ? parsed.palette_hex : [];
  const palette_hex = palIn
    .map((x: any) => String(x).trim())
    .filter((x: string) => /^#[0-9a-fA-F]{6}$/.test(x))
    .slice(0, 5);

  const texture_notes = typeof parsed.texture_notes === "string" ? parsed.texture_notes.trim().slice(0, 160) : "";

  const mnos = Array.isArray(parsed.move_name_overrides) ? parsed.move_name_overrides : [];
  const move_name_overrides = mnos
    .map((x: any) => String(x).trim())
    .filter((x: string) => x.length > 0)
    .slice(0, 2);

  const essence = typeof parsed.essence === "string" ? parsed.essence.trim().slice(0, 140) : "";
  const flavor_text = typeof parsed.flavor_text === "string" ? parsed.flavor_text.trim().slice(0, 220) : "";

  const silhouette_desc = SILHOUETTE_DESCS[silhouette_id] ?? "";

  return { name, archetype, silhouette_id, silhouette_desc, element, rarity, palette_hex, texture_notes, move_name_overrides, essence, flavor_text };
}

async function callLucyProI2I(params: {
  prompt: string;
  templateBytes: Buffer;
  templateFilename: string;
  templateContentType: string;
  seed?: number;
  resolution?: "720p" | "480p";
}): Promise<Buffer> {

  if (!DECART_API_KEY) throw new Error("missing_decart_api_key");

  const form = new FormData();
  form.append("prompt", params.prompt);
  form.append(
    "data",
    new Blob([params.templateBytes], { type: params.templateContentType }),
    params.templateFilename,
  );
  if (params.seed !== undefined) form.append("seed", String(params.seed >>> 0));
  form.append("resolution", params.resolution ?? "720p");
  form.append("enhance_prompt", "false");

  const res = await fetch(`${DECART_BASE_URL}/v1/generate/lucy-pro-i2i`, {
    method: "POST",
    headers: {
      "X-API-KEY": DECART_API_KEY,
    },
    body: form as any,
  });

  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`lucy_i2i_failed_${res.status}: ${txt.slice(0, 200)}`);
  }

  const ab = await res.arrayBuffer();
  return Buffer.from(ab);
}

app.post("/v1/scan", async (req, reply) => {
  // MVP: accept multipart upload and return Sacred 8 creature + art.
  // For now the *photo* isn't used; we generate art from a fixed template via Lucy i2i.

  const file = await req.file();
  if (!file) return reply.code(400).send({ error: "missing_image" });
  const photoBytes = await file.toBuffer();

  // Stage 1: Vision -> structured spec (archetype + silhouette_id + palette/texture + essence)
  let spec: { name: string; archetype: string; silhouette_id: string; silhouette_desc: string; element: string; rarity: string; palette_hex: string[]; texture_notes: string; move_name_overrides: string[]; essence: string; flavor_text: string };
  if (GEMINI_API_KEY) {
    try {
      spec = await callGeminiVisionSpec({ imageBytes: photoBytes, imageMimeType: file.mimetype || "image/jpeg" });
    } catch (e) {
      app.log.warn({ err: e }, "gemini_vision_failed_fallback");
      const archetypes = Object.keys(KITS);
      const pick = archetypes[Math.floor(Math.random() * archetypes.length)];
      spec = { name: pick, archetype: pick, silhouette_id: "", silhouette_desc: "", element: "Water", rarity: "Common", palette_hex: [], texture_notes: "", move_name_overrides: [], essence: "", flavor_text: "" };
    }
  } else {
    const archetypes = Object.keys(KITS);
    const pick = archetypes[Math.floor(Math.random() * archetypes.length)];
    spec = { name: pick, archetype: pick, silhouette_id: "", silhouette_desc: "", element: "Water", rarity: "Common", palette_hex: [], texture_notes: "", move_name_overrides: [], essence: "", flavor_text: "" };
  }

  const kit = kitFor(spec.archetype);
  const stats = statsForCreature({ archetype: kit.archetype, rarity: spec.rarity });

  const artHash = `art_${Date.now()}`;

  let pngBytes: Buffer;
  let templatePath: string = "";
  let templateBytes: Buffer | null = null;
  let bgc: { r: number; g: number; b: number } = { r: 235, g: 240, b: 248 };

  if (DECART_API_KEY) {
    templatePath = templatePathForSilhouette({ silhouetteId: spec.silhouette_id, archetype: kit.archetype });
    app.log.info({ archetype: kit.archetype, silhouette_id: spec.silhouette_id, templatePath }, "template_selected");
    templateBytes = loadTemplateFile(templatePath);

    // Validate template is a supported image
    try {
      await sharp(templateBytes!, { failOn: "none" }).metadata();
    } catch (e) {
      return reply.code(400).send({
        error: "template_invalid",
        detail: "vinyl_template_default.png is not a supported image format (must be a real PNG/JPG or base64/data URL of one).",
      });
    }

    // Guardrail: Decart returns 413 if payload is too large. Keep template small.
    // If you want a high-res template, use a compressed JPG instead.
    const maxTemplateBytes = 2 * 1024 * 1024; // 2MB
    if (templateBytes!.byteLength > maxTemplateBytes) {
      return reply.code(400).send({
        error: "template_too_large",
        detail: `${path.basename(templatePath)} is ${templateBytes!.byteLength} bytes; keep under ${maxTemplateBytes} bytes (try 480p or JPG).`,
      });
    }

    const essenceHint = spec.essence ? `Overall essence/theme (must be obvious in the design): ${spec.essence}.` : "";
    const silhouetteHint = spec.silhouette_id ? `Silhouette: ${spec.silhouette_id}${spec.silhouette_desc ? " (" + spec.silhouette_desc + ")" : ""}. Outer contour should match the silhouette closely.` : "";

    const prompt = [
      "Semi-real stylized PBR 3D game character render (digital), front view, Supercell-like readability.",
      "Look: clean shapes, crisp silhouette, stylized proportions, but with physically-based rendering materials and believable light response.",
      "PBR materials: painted metal, leather, cloth, stone/wood as appropriate; subtle roughness variation; clear material separation; avoid hyperreal micro-surface detail.",
      "Lighting: bright high-contrast game lighting with strong key + rim light; crisp shadows; no gloom, no fog, no cinematic film look.",
      "Not photoreal: NOT product photography, NOT real-world lens artifacts.",
      essenceHint,
      silhouetteHint,
      "Use the input image only as a silhouette/shape guide; invent surface detail and color within the silhouette.",
      `Archetype: ${kit.archetype}.`,
      `Element theme: ${spec.element}.`,
      `Rarity vibe: ${spec.rarity}.`,
      spec.palette_hex.length ? `Color palette (from photo): ${spec.palette_hex.join(", ")}.` : "",
      spec.texture_notes ? `Texture/material notes (from photo): ${spec.texture_notes}.` : "",
      "Palette adherence is mandatory: use ONLY the provided palette colors as dominant hues. Neutrals (black/white/gray) are allowed.",
      "Do NOT introduce strong new hues (especially bright blue, yellow, red) unless they are present in the palette list.",
      "High contrast must come from lighting/value contrast and clean shading, not by changing hue away from the palette.",
      "Add archetype-appropriate accessories and sculpt details (straps, plates, charms, vents, runes) but keep it readable and game-like.",
      "Background: bright solid or soft gradient, no clutter.",
      "No text, no logos, no watermark, no signature.",
    ].join(" ");

    // Composite: inject photo texture/colors inside the silhouette to guide i2i.
    // We infer a mask from the template alpha if present; otherwise from luminance threshold.
    const tpl = sharp(templateBytes!, { failOn: "none" }).ensureAlpha();
    const meta = await tpl.metadata();
    const w = meta.width ?? 0;
    const h = meta.height ?? 0;
    if (w <= 0 || h <= 0) throw new Error("bad_template_dimensions");

    // Build a robust mask: prefer alpha, but if alpha is fully opaque, derive mask from luminance.
    const alphaRaw = await tpl.extractChannel("alpha").raw().toBuffer({ resolveWithObject: true });
    const alphaBuf: Buffer = alphaRaw.data;
    const alphaPng: Buffer = await tpl.extractChannel("alpha").png().toBuffer();
    let alphaMin = 255;
    let alphaMax = 0;
    for (let i = 0; i < alphaBuf.length; i++) {
      const v = alphaBuf[i];
      if (v < alphaMin) alphaMin = v;
      if (v > alphaMax) alphaMax = v;
    }

    let maskPng: Buffer;
    if (alphaMin === 255 && alphaMax === 255) {
      // No useful alpha; threshold luminance from RGB.
      maskPng = await sharp(templateBytes, { failOn: "none" })
        .resize(w, h)
        .grayscale()
        .threshold(200)
        .png()
        .toBuffer();
    } else {
      // Use encoded alpha image, not raw bytes.
      maskPng = alphaPng;
    }

    const photo = sharp(photoBytes, { failOn: "none" }).resize(w, h, { fit: "cover" }).blur(1.2);
    const photoBuf = await photo.toBuffer();

    // Apply mask to photo (keep only silhouette region)
    const photoMasked = await sharp(photoBuf, { failOn: "none" })
      .ensureAlpha()
      .joinChannel(maskPng)
      .png()
      .toBuffer();

    // Blend masked photo onto template at low opacity
    const guide = await sharp(templateBytes!, { failOn: "none" })
      .ensureAlpha()
      .composite([{ input: photoMasked, blend: "over", opacity: 0.35 }])
      .png()
      .toBuffer();

    pngBytes = await callLucyProI2I({
      prompt,
      templateBytes: guide,
      templateFilename: "guide.png",
      templateContentType: "image/png",
      resolution: "720p",
    });
  } else {
    // fallback placeholder (base64 png)
    const pngB64 =
      "iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAAACXBIWXMAAAsSAAALEgHS3X78AAABT0lEQVR4nO3RQQEAAAgDINc/9Ck4QkQ0mGk4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPgWQy4AAa7mHj0AAAAASUVORK5CYII=";
    pngBytes = Buffer.from(pngB64, "base64");
  }

  // Crop to square 720x720 for card art.
  // Lucy outputs portrait; we center-crop and then resize to 720.
  let outPng: Buffer = pngBytes;
  try {
    const img = sharp(pngBytes, { failOn: "none" });
    const meta2 = await img.metadata();
    const w2 = meta2.width ?? 0;
    const h2 = meta2.height ?? 0;
    if (w2 > 0 && h2 > 0) {
      const side = Math.min(w2, h2);
      const left = Math.floor((w2 - side) / 2);
      const top = Math.floor((h2 - side) / 2);
      outPng = await img.extract({ left, top, width: side, height: side }).resize(720, 720).png().toBuffer();
    }

    // Enforce silhouette after generation by applying the template-derived mask.
    // Prefer template alpha; if alpha is fully opaque, derive a mask from luminance.
    const tplBytes2 = templateBytes ?? Buffer.alloc(0);
    const tpl2 = sharp(tplBytes2, { failOn: "none" }).ensureAlpha().resize(720, 720);

    const alphaRaw2 = await tpl2.extractChannel("alpha").raw().toBuffer({ resolveWithObject: true });
    const alphaBuf2: Buffer = alphaRaw2.data;
    let aMin = 255;
    let aMax = 0;
    for (let i = 0; i < alphaBuf2.length; i++) {
      const v = alphaBuf2[i];
      if (v < aMin) aMin = v;
      if (v > aMax) aMax = v;
    }

    let mask720Png: Buffer;
    let maskSource: "alpha" | "luma" = "alpha";
    if (aMin === 255 && aMax === 255) {
      maskSource = "luma";
      // No useful alpha; derive mask from luminance.
      // Try both polarities (light-on-dark vs dark-on-light) and pick the one that yields a non-trivial mask.
      const base = sharp(tplBytes2, { failOn: "none" }).resize(720, 720).grayscale();
      const m1 = await base.clone().threshold(200).png().toBuffer();
      const s1 = await sharp(m1, { failOn: "none" }).stats();
      const mean1 = s1.channels[0]?.mean ?? 0;

      const m2 = await base.clone().negate().threshold(200).png().toBuffer();
      const s2 = await sharp(m2, { failOn: "none" }).stats();
      const mean2 = s2.channels[0]?.mean ?? 0;

      // Heuristic: prefer masks that are neither almost-all-black nor almost-all-white.
      const score = (m: number) => Math.min(m, 255 - m);
      mask720Png = score(mean2) > score(mean1) ? m2 : m1;
    } else {
      mask720Png = await tpl2.extractChannel("alpha").png().toBuffer();
    }

    const maskStats = await sharp(mask720Png, { failOn: "none" }).stats();
    app.log.info(
      {
        template_file: path.basename(templatePath),
        maskSource,
        mask_mean: maskStats.channels[0]?.mean,
        mask_min: maskStats.channels[0]?.min,
        mask_max: maskStats.channels[0]?.max,
      },
      "mask_stats",
    );

    // Apply silhouette mask to character, then composite onto an opaque square background.
    const maskedChar = await sharp(outPng, { failOn: "none" }).ensureAlpha().joinChannel(mask720Png).png().toBuffer();

    // Background: solid color derived from template silhouette mask + tinted by rarity.
    // Outside-silhouette area becomes the background; the character sits on top.
    const rarityBg: Record<string, { r: number; g: number; b: number }> = {
      Common: { r: 225, g: 230, b: 236 },
      Rare: { r: 190, g: 220, b: 255 },
      Epic: { r: 210, g: 190, b: 255 },
      Legendary: { r: 255, g: 230, b: 170 },
    };
    bgc = rarityBg[spec.rarity] ?? rarityBg.Common;

    const bg = await sharp({
      create: {
        width: 720,
        height: 720,
        channels: 4,
        background: { ...bgc, alpha: 1 },
      },
    })
      .png()
      .toBuffer();

    // Ensure outside-silhouette is solid even if Lucy returned background artifacts.
    // Since maskedChar has 0 alpha outside silhouette, compositing it over bg produces a clean silhouette cut.
    outPng = await sharp(bg, { failOn: "none" })
      .composite([{ input: maskedChar, blend: "over" }])
      .flatten({ background: bgc })
      .png()
      .toBuffer();
  } catch (e) {
    app.log.warn({ err: e }, "square_crop_failed");
  }

  const moveNames = spec.move_name_overrides.length === 2 ? spec.move_name_overrides : kit.moves.map((m) => m.name);

  return reply.send({
    creature: {
      local_id: `scan_${Date.now()}`,
      name: spec.name,
      archetype: kit.archetype,
      element: spec.element,
      rarity: spec.rarity,
      silhouette_id: spec.silhouette_id,
      silhouette_desc: spec.silhouette_desc,
      // Vision context (used for lore + stronger downstream conditioning)
      essence: spec.essence,
      flavor_text: spec.flavor_text,
      palette_hex: spec.palette_hex,
      texture_notes: spec.texture_notes,
      stats,
      moves: kit.moves.map((m, i) => ({ move_id: m.move_id, name: moveNames[i] ?? m.name, cue: m.cue })),
    },
    art: {
      art_b64_png: outPng.toString("base64"),
      art_hash: artHash,
      provider: DECART_API_KEY ? "decart_lucy_pro_i2i" : "placeholder",
      format: "png",
      size: "720x720",
      template_file: path.basename(templatePath),
      bg_rgb: bgc,
    },
  });
});

app.post("/v1/ladder/battle", async (req, reply) => {
  if (REQUIRE_DEVICE_ID) {
    const did = req.headers["x-device-id"];
    if (!did || (Array.isArray(did) ? did[0] : did).toString().trim() === "") {
      return reply.code(400).send({ error: "missing_x_device_id" });
    }
  }

  const parsed = LadderBattleReq.safeParse(req.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: "invalid_body", details: parsed.error.flatten() });
  }

  const { my_team, opponent_team } = parsed.data;
  if (my_team.length !== opponent_team.length) {
    return reply.code(400).send({ error: "team_size_mismatch" });
  }

  const seed = Math.floor(Math.random() * 1_000_000_000);
  const result = makeBattleResult({ my_team, opponent_team, seed });
  return reply.send(result);
});

async function main() {
  // Multipart support (for /v1/scan)
  await app.register(multipart, {
    limits: { fileSize: 10 * 1024 * 1024 },
  });

  await app.listen({ port: PORT, host: HOST });
}

main().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
