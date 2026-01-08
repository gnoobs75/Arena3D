# Response Card Workflows

This document describes the expected workflow for each response card trigger type.

---

## TRIGGER: beforeDamage

**When it fires:** After attacker declares attack/spell, BEFORE damage is calculated and applied.

**Who responds:** The player whose champion is being targeted (defender).

**After responses resolve:** Re-validate the attack:
- Target moved out of range? → Attack MISSES (consumed, no damage)
- Target died? → Attack consumed, no effect
- Target has negateDamage buff? → Damage negated
- Target has damageReduction buff? → Damage reduced
- Target still valid? → Execute attack normally

---

### Oblivious (Brute) - Cost 0
```
SCENARIO: Enemy attacks Brute for 5 damage

1. Enemy declares attack on Brute
2. [beforeDamage] Response window opens for Brute's player
3. Player plays Oblivious
4. Effect: Brute gains "damageReduction" buff (reduce to 1)
5. Player passes priority
6. Stack resolves → Oblivious effect applied
7. Attack executes → 5 damage reduced to 1 damage
8. Brute takes 1 damage
9. Attacker's turn continues
```

---

### Quick Instincts (Beast) - Cost 0
```
SCENARIO: Enemy attacks Beast

1. Enemy declares attack on Beast
2. [beforeDamage] Response window opens for Beast's player
3. Player plays Quick Instincts
4. Effect: +2 movement, immediate movement phase
5. Beast moves 2+ tiles away (out of melee range)
6. Player passes priority
7. Stack resolves → Beast moved
8. Attack re-validates → Beast out of range
9. Attack MISSES (consumed, no damage)
10. Attacker's turn continues
```

---

### Bear Tank (Beast) - Cost 1
```
SCENARIO: Enemy attacks Ranger (Beast's ally is nearby)

1. Enemy declares attack on Ranger
2. [beforeDamage] Response window opens for Ranger's player
3. Player plays Bear Tank (targeting Ranger)
4. Effect: Beast moves adjacent to Ranger, takes 1 damage instead
5. Player passes priority
6. Stack resolves:
   - Beast moves adjacent to Ranger
   - Beast takes 1 damage
   - Original attack is REDIRECTED to Beast (or cancelled?)
7. Ranger takes no damage
8. Attacker's turn continues

NOTE: Need to clarify - does the original attack still hit Beast, or is it fully prevented?
```

---

### Power Shield (Redeemer) - Cost 0
```
SCENARIO: Enemy attacks ally for 4 damage

1. Enemy declares attack on ally
2. [beforeDamage] Response window opens
3. Player plays Power Shield (targeting ally)
4. Effect: Ally gains "shield" buff (prevents 2 damage)
5. Player passes priority
6. Stack resolves → Shield applied
7. Attack executes → 4 damage, 2 blocked by shield
8. Ally takes 2 damage
9. Attacker's turn continues
```

---

### Self-Hate (Confessor) - Cost 2
```
SCENARIO: Enemy attacks Confessor for 3 damage

1. Enemy declares attack on Confessor
2. [beforeDamage] Response window opens
3. Player plays Self-Hate
4. Effect: Confessor gains "redirectDamage" buff
5. Player passes priority
6. Stack resolves → Buff applied
7. Attack executes → Damage REDIRECTED to attacker
8. Attacker takes 3 damage instead
9. Confessor takes 0 damage
10. Attacker's turn continues
```

---

### Dodge (Barbarian) - Cost 1
```
SCENARIO: Enemy attacks Barbarian

1. Enemy declares attack on Barbarian
2. [beforeDamage] Response window opens
3. Player plays Dodge
4. Effect: Immediate movement phase
5. Barbarian moves out of range
6. Player passes priority
7. Stack resolves → Barbarian moved
8. Attack re-validates → Barbarian out of range
9. Attack MISSES
10. Attacker's turn continues
```

---

### Vanish (Burglar) - Cost 2
```
SCENARIO: Enemy attacks Burglar

1. Enemy declares attack on Burglar
2. [beforeDamage] Response window opens
3. Player plays Vanish
4. Effect: Move to safe position (no enemy can target)
5. Player passes priority
6. Stack resolves → Burglar teleports to safe tile
7. Attack re-validates → Burglar out of range
8. Attack MISSES
9. Attacker's turn continues
```

---

### Now You See Me (Illusionist) - Cost 0
```
SCENARIO: Enemy attacks Illusionist

1. Enemy declares attack on Illusionist
2. [beforeDamage] Response window opens
3. Player plays Now You See Me
4. Effect: 50% chance to negate damage
5. Player passes priority
6. Stack resolves → Roll dice
   - WIN (50%): Illusionist gains "negateDamage" buff
   - LOSE (50%): No effect, card wasted
7. Attack executes:
   - If negateDamage: 0 damage dealt
   - If no buff: Full damage dealt
8. Attacker's turn continues
```

---

### Unlimited Chances (Illusionist) - Cost 0
```
SCENARIO: Enemy attacks Illusionist

1. Enemy declares attack on Illusionist
2. [beforeDamage] Response window opens
3. Player plays Unlimited Chances
4. Effect: 50% chance to negate + return card to hand
5. Player passes priority
6. Stack resolves → Roll dice
   - WIN: negateDamage buff + card returns to hand
   - LOSE: No effect, card goes to discard
7. Attack executes accordingly
8. Attacker's turn continues
```

---

### Smoke Bomb (Alchemist) - Cost 2
```
SCENARIO: Ranger attacks Burglar (Burglar + Alchemist on same team)

1. Ranger declares attack on Burglar
2. [beforeDamage] Response window opens for Burglar's player
3. Player plays Smoke Bomb
4. Effect: ALL friendlies get immediate movement phase
5. Burglar moves out of Ranger's range
6. Alchemist also moves (bonus repositioning)
7. Player passes priority
8. Stack resolves → Both champions moved
9. Attack re-validates → Burglar out of range
10. Attack MISSES
11. Ranger's turn continues (can still move, cast other cards)
```

---

## TRIGGER: afterDamage

**When it fires:** AFTER damage has been dealt and applied.

**Who responds:** The player whose champion took damage.

---

### Tantrum (Brute) - Cost 1
```
SCENARIO: Enemy dealt 3 damage to Brute

1. Damage is dealt → Brute takes 3 damage
2. [afterDamage] Response window opens
3. Player plays Tantrum
4. Effect: Deal 2 damage back to attacker
5. Player passes priority
6. Stack resolves → Attacker takes 2 damage
7. Attacker's turn continues
```

---

### Spell Punish (Berserker) - Cost 1
```
SCENARIO: Enemy spell dealt damage to Berserker

1. Spell damage dealt → Berserker takes damage
2. [afterDamage] Response window opens (only if spell damage)
3. Player plays Spell Punish
4. Effect: Berserker moves adjacent to spell caster
5. Player passes priority
6. Stack resolves → Berserker now adjacent to caster
7. Caster's turn continues (Berserker is now in melee range!)
```

---

## TRIGGER: onMove

**When it fires:** When a champion moves (after movement completes).

**Who responds:** The opponent of the moving champion.

---

### Bear Trap (Ranger) - Cost 1
```
SCENARIO: Enemy moves into melee range (1 tile) of Ranger

1. Enemy champion moves
2. Final position is adjacent to Ranger
3. [onMove] Response window opens for Ranger's player
4. Player plays Bear Trap
5. Effect: Deal 2 damage to the enemy who moved
6. Player passes priority
7. Stack resolves → Enemy takes 2 damage
8. Enemy's movement is complete
9. Enemy's turn continues
```

---

### Pit of Despair (Dark Wizard) - Cost 0
```
SCENARIO: Enemy moves into melee range of Dark Wizard

1. Enemy champion moves toward Dark Wizard
2. Would end adjacent to Dark Wizard
3. [onMove] Response window opens
4. Player plays Pit of Despair
5. Effect:
   - Create pits around Dark Wizard (adjacent tiles become pits)
   - Enemy loses remaining movement
6. Player passes priority
7. Stack resolves:
   - Pits created (until end of turn)
   - Enemy cannot move further this turn
8. Enemy stuck, possibly standing on/near pit
9. Enemy's turn continues (but can't move)
```

---

## TRIGGER: onHeal

**When it fires:** When a champion is about to be healed.

**Who responds:** The opponent (Bloodthirsty triggers when enemy heals).

---

### Bloodthirsty (Berserker) - Cost 1
```
SCENARIO: Enemy champion is being healed

1. Enemy plays heal card/effect on their champion
2. [onHeal] Response window opens for Berserker's player
3. Player plays Bloodthirsty
4. Effect: Deal 2 damage to the enemy being healed
5. Player passes priority
6. Stack resolves → Enemy takes 2 damage
7. Original heal then applies
8. Net effect: Enemy healed X, but also took 2 damage
```

---

## TRIGGER: onDraw

**When it fires:** When a player draws extra cards (beyond normal turn draw).

**Who responds:** The opponent.

---

### Hypocrite (Confessor) - Cost 1
```
SCENARIO: Enemy plays card that draws 2 extra cards

1. Enemy plays draw effect
2. [onDraw] Response window opens for Confessor's player
3. Player plays Hypocrite
4. Effect: Draw same number of cards as opponent drew
5. Player passes priority
6. Stack resolves → Player draws 2 cards
7. Both players now have extra cards
```

---

## TRIGGER: onCast

**When it fires:** When a card is cast (before effects resolve).

**Who responds:** Either player (Confuse can redirect spells).

---

### Confuse (Illusionist) - Cost 2
```
SCENARIO: Enemy casts damaging spell at Illusionist

1. Enemy casts spell targeting Illusionist
2. [onCast] Response window opens
3. Player plays Confuse
4. Effect: Redirect spell to different target
5. Player selects new target (e.g., enemy's own champion)
6. Player passes priority
7. Stack resolves → Spell target changed
8. Original spell now hits the new target
9. Enemy's turn continues
```

---

## TRIGGER: endTurn

**When it fires:** At the end of a player's turn.

**Who responds:** The player whose turn is ending.

---

### Nature's Wrath (Beast) - Cost 0
```
SCENARIO: Beast took damage this turn, opponent's turn is ending

1. Opponent ends their turn
2. [endTurn] Response window opens for Beast's player
3. Condition check: Did Beast take damage this turn? YES
4. Player plays Nature's Wrath
5. Effect: Deal 2 damage to random enemy
6. Player passes priority
7. Stack resolves → Random enemy takes 2 damage
8. Turn fully ends, next player begins
```

---

## Implementation Notes

### Response Stack Rules
1. Responses resolve in LIFO order (last played resolves first)
2. After a response is PLAYED (not resolved), priority passes to opponent
3. Opponent can play their own response (counter-response)
4. This can chain back and forth until both players pass consecutively
5. When both players pass consecutively, entire stack resolves top-to-bottom
6. After stack resolves, original action re-validates and executes (or fails)

### Counter-Response Example
```
1. Ranger attacks Burglar
2. [beforeDamage] → Burglar's player has priority
3. Burglar plays Smoke Bomb → Stack: [Smoke Bomb]
4. Priority passes to Ranger's player
5. Ranger's player could play a response here (if they have one)
6. Ranger's player passes → consecutive_passes = 1
7. Priority passes to Burglar's player
8. Burglar's player passes → consecutive_passes = 2
9. Stack resolves: Smoke Bomb effect executes
10. Attack re-validates → Burglar out of range → MISS
```

### Attack Miss Conditions (after beforeDamage responses)
- Target moved out of range
- Target died during response window
- Target has full damage negation (negateDamage buff)

### Consuming Actions
- Even if attack misses, the attacker's attack for the turn is consumed
- The attacker can still move and cast cards after a missed attack
