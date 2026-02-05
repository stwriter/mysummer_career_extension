# MySummer Career - XP Progression Analysis

## Current Level Requirements

| Level | Chapter Name | Required XP | XP Needed from Previous |
|-------|--------------|-------------|------------------------|
| 0 | Prologue | 0 | - |
| 1 | Chapter 1 - Among Friends | 300 | 300 |
| 2 | Chapter 2 - Low Underground | 800 | 500 |
| 3 | Chapter 3 - Regional Rallies | 1500 | 700 |
| 4 | Chapter 4 - High Underground | 2500 | 1000 |
| 5 | Chapter 5 - Official Rallies | 4000 | 1500 |
| 6 | Chapter 6 - The Big One | 6000 | 2000 |

## Street Race Distribution by Level

### Prologue (Level 0) - Street Racing Begins
**Races**: 001-STREET, 002-STREET, 003-STREET
**Total XP** (if all Gold): 200 + 200 + 220 = **620 XP**
**Progress**: ✓ Exceeds 300 XP needed for Level 1 (surplus: 320 XP)

### Chapter 1 (Level 1) - Racing Among Friends
**Races**: 004-STREET, 005-STREET, 006-STREET
**Total XP** (if all Gold): 250 + 250 + 280 = **780 XP**
**Cumulative**: 1400 XP
**Progress**: ✓ Exceeds 800 XP needed for Level 2 (surplus: 600 XP)

### Chapter 2 (Level 2) - Low Underground
**Races**: 007-STREET, 008-STREET
**Total XP** (if all Gold): 300 + 320 = **620 XP**
**Cumulative**: 2020 XP
**Progress**: ✓ Exceeds 1500 XP needed for Level 3 (surplus: 520 XP)

### Chapter 3 (Level 3) - Regional Rallies
**Races**: Rally content (to be added)
**Total XP**: TBD
**Cumulative**: 2020 XP + rally XP
**Progress**: ⚠️ Need ~480 XP to reach 2500 for Level 4

### Chapter 4 (Level 4) - High Underground
**Races**: 009-STREET, 010-STREET
**Total XP** (if all Gold): 350 + 400 = **750 XP**
**Cumulative**: 2770 XP (assuming only street races)
**Progress**: ⚠️ Need Chapter 3 content + contacts to reach 4000 for Level 5

### Chapter 5 (Level 5) - Official Rallies
**Races**: Circuit/Rally content (to be added)
**Total XP**: TBD
**Progress**: ⚠️ Need circuit/rally content to reach 6000 for Level 6

### Chapter 6 (Level 6) - The Big One
**Races**: Final race (to be added)

## XP Rewards per Race (Gold Only)

| Race | XP | Level Required | Chapter |
|------|----|----|---------|
| 001-STREET | 200 | 0 | Prologue |
| 002-STREET | 200 | 0 | Prologue |
| 003-STREET | 220 | 0 | Prologue |
| 004-STREET | 250 | 1 | Chapter 1 |
| 005-STREET | 250 | 1 | Chapter 1 |
| 006-STREET | 280 | 1 | Chapter 1 |
| 007-STREET | 300 | 2 | Chapter 2 |
| 008-STREET | 320 | 2 | Chapter 2 |
| 009-STREET | 350 | 4 | Chapter 4 |
| 010-STREET | 400 | 4 | Chapter 4 |

## Contact Missions (Planned)

Based on user design: **3 races + 1 contact mission = advance to next level**

Recommended XP for contact missions:
- **Prologue Contact**: 50-100 XP (storytelling, already have enough from races)
- **Chapter 1 Contact**: 50-100 XP (meet Ghost)
- **Chapter 2 Contact**: 100-150 XP (underground introduction)
- **Chapter 3 Contacts**: Rally-related missions (to be designed)
- **Chapter 4 Contact**: 150-200 XP (Shadow network)
- **Chapter 5 Contacts**: Circuit-related missions (to be designed)

## Analysis

### ✓ Working Well
1. **Prologue → Chapter 1**: 3 races provide more than enough XP (620 vs 300 needed)
2. **Chapter 1 → Chapter 2**: 3 races provide adequate XP (780 vs 500 needed)
3. **Chapter 2 → Chapter 3**: 2 races + surplus provide enough XP (620 + surplus vs 700 needed)

### ⚠️ Needs Additional Content
1. **Chapter 3**: Rally races and missions needed to bridge gap to Level 4
2. **Chapter 4 → Chapter 5**: Significant XP gap (1230 XP needed) - requires Chapter 3 content + contacts
3. **Chapter 5 → Chapter 6**: Major content needed (2000+ XP) - circuit/rally missions

### Recommendations

1. **Keep current street race XP values** - They provide good progression for early game
2. **Add contact missions** for each chapter:
   - Provide 50-200 XP each
   - Tell story and introduce characters
   - Fill XP gaps between levels
3. **Add rally content** for Chapter 3:
   - 2-3 rally races
   - 1-2 contact missions
   - Total ~500-700 XP
4. **Add circuit/rally content** for Chapter 5:
   - 3-4 circuit races
   - 1-2 contact missions
   - Total ~1500-2000 XP
5. **Add The Big One** for Chapter 6:
   - Final championship race
   - High XP reward (500-1000 XP)

## Implementation Status

- [x] Branch level gating implemented for all street races
- [x] Races distributed according to chapter themes
- [x] XP rewards analyzed and validated
- [ ] Contact missions to be created
- [ ] Rally content for Chapter 3 to be added
- [ ] Circuit content for Chapter 5 to be added
- [ ] The Big One race for Chapter 6 to be added

## Notes

- Players who don't win Gold on every race will have tighter progression
- XP surplus in early chapters provides buffer for learning curve
- Later chapters require diverse content (not just street racing) to maintain narrative interest
- Current implementation allows Chapters 0-2 to be fully playable
- Chapters 3-6 need additional content to be completable
