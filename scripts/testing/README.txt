Arena AI vs AI Test System
===========================

QUICK START
-----------
1. Double-click run_tests.bat in the arena folder (or run from Godot)
2. Set number of matches and seed
3. Click "Start Tests"
4. View results in the Output tab
5. Click "Charts" tab to see visualizations
6. Click "Replay" tab to watch match playback
7. Click "Export JSON" to save detailed results


BATCH FILES
-----------

run_tests.bat
  Opens the test app with a GUI window.
  Usage: run_tests.bat [options]

  Examples:
    run_tests.bat                          # Open UI with defaults
    run_tests.bat --matches=100 --auto     # Run 100 matches automatically
    run_tests.bat --seed=12345             # Use specific seed


run_tests_headless.bat
  Runs tests without any UI (console output only).
  Usage: run_tests_headless.bat [options]

  Options:
    --matches=N          Number of matches (default: 10)
    --seed=N             RNG seed for reproducibility (default: random)
    --p1=Champ1,Champ2   Specific champions for player 1
    --p2=Champ1,Champ2   Specific champions for player 2
    --full               Run all champion pair combinations
    --verbose            Show detailed output

  Examples:
    run_tests_headless.bat --matches=50
    run_tests_headless.bat --p1=Brute,Ranger --p2=Berserker,Shaman --matches=20
    run_tests_headless.bat --seed=12345 --matches=100


OUTPUT FILES
------------
Results are saved to: arena_godot/test_reports/

  report_[session_id].json     Full session report
  noop_analysis_[id].json      Cards that do nothing when cast


WHAT IT TESTS
-------------
- Card functionality: Detects "no-op" cards that cast but have no effect
- Champion balance: Win rates for each champion
- Card effectiveness: Which cards correlate with winning
- Pair synergies: Which champion pairs work well together


CHAMPIONS
---------
Brute, Ranger, Beast, Redeemer, Confessor, Barbarian,
Burglar, Berserker, Shaman, Illusionist, DarkWizard, Alchemist


TABS
----

Output Tab:
  Real-time log of test execution with color-coded messages.
  Shows match results, errors, and final summary.

Charts Tab:
  Visual analysis of test results:
  - Overview: Win/loss/draw pie chart, no-op cards bar chart
  - Champions: Win rate bar chart, detailed stats table
  - Cards: Most played cards, no-op analysis, usage patterns
  - Damage: Damage dealt/taken by champion

Replay Tab:
  Watch completed matches step-by-step:
  - Select any match from dropdown
  - Play/Pause, Step Forward/Back controls
  - Speed slider (0.25x to 4x)
  - Visual board with champion positions and HP
  - Action descriptions for each step


INTERPRETING RESULTS
--------------------

No-Op Cards:
  Cards with high no-op rates may have:
  - Targeting issues (no valid targets)
  - Conditional effects that rarely trigger
  - Bugs in effect processing

Champion Win Rates:
  - >55% = Potentially overpowered
  - <45% = Potentially underpowered
  - 45-55% = Balanced

Card Win Correlation:
  High win rate when played = Strong card
  Low win rate when played = Weak or situational card

Card Usage Analysis:
  - Never Played: Cards drawn but AI never chose to play
  - Low Usage (<30%): Cards rarely played when available
  - High Discard (>30%): Cards frequently discarded from hand

  These may indicate cards that:
  - Are too expensive for their effect
  - Have requirements that rarely align
  - Are outcompeted by better options
