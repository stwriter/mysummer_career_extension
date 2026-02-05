@echo off
REM Update race missions with branch level requirements
REM Distribution based on chapter themes from skill progression

echo Updating race missions with branch level gating...

REM Prologue (Level 0) - Races 001, 002, 003
for %%r in (001 002 003) do (
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:0,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET-REPEAT/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:0,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
)

REM Chapter 1 (Level 1) - Races 004, 005, 006
for %%r in (004 005 006) do (
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:1,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET-REPEAT/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:1,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
)

REM Chapter 2 (Level 2) - Races 007, 008
for %%r in (007 008) do (
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:2,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET-REPEAT/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:2,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
)

REM Chapter 3 (Level 3) - Rally content (not street races)

REM Chapter 4 (Level 4) - Races 009, 010
for %%r in (009 010) do (
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:4,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
  node -e "const fs=require('fs');const p='gameplay/missions/west_coast_usa/aiRace/%%r-STREET-REPEAT/info.json';const d=JSON.parse(fs.readFileSync(p,'utf8'));d.startCondition={branchId:'mysummer-streetracing',level:4,type:'branchLevel'};d.visibleCondition={type:'automatic'};fs.writeFileSync(p,JSON.stringify(d,null,2));"
)

REM Chapter 5 (Level 5) - Circuit/Rally content (not street races)
REM Chapter 6 (Level 6) - The Big One (to be added)

echo Done! All races updated with branch level requirements.
echo.
echo Distribution (based on chapter themes):
echo   Prologue (Level 0): Races 001-003  [Street Racing begins]
echo   Chapter 1 (Level 1): Races 004-006  [Racing Among Friends]
echo   Chapter 2 (Level 2): Races 007-008  [Low Underground]
echo   Chapter 3 (Level 3): Rally content  [Regional Rallies - to be added]
echo   Chapter 4 (Level 4): Races 009-010  [High Underground]
echo   Chapter 5 (Level 5): Circuit content  [Official Rallies - to be added]
echo   Chapter 6 (Level 6): The Big One  [Final race - to be added]
pause
