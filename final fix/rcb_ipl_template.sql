/* =====================================================================
   RCB IPL STRATEGY — STUDENT ANSWER TEMPLATE
   ===================================================================== */

USE ipl;

/* =====================================================================
   QUERY OPTIMIZATION METHODOLOGY & APPROACH (LEVEL 10)
   =====================================================================
   1. Early Dataset Pruning: Filters matches, seasons, and teams early via CTEs
      prior to scanning and joining high-volume tables (e.g., Ball_by_Ball with
      136,590 rows).
   2. Selective Projection: Projects only necessary surrogate keys and metrics,
      avoiding wildcard selections and eliminating redundant dimension scans.
   3. Intermediate Result Reuse: Isolates multi-season cohorts and benchmarks
      in reusable CTEs to avoid duplicate table scans across analytical pipelines.
   4. Aggregation Before Dimension Joins: Aggregates fact tables (striker runs,
      bowler dismissals) on surrogate keys before joining descriptive dimension
      tables (Player, Venue, Bowling_Style), minimizing join row volume.
   5. Filter Pushdown: Applies categorical and threshold filters (e.g., dismissal
      kinds, extras types) at the source rather than post-aggregation.
   6. Semantic Equivalence: Preserves 100% of canonical project definitions,
      filters, seasons, player scopes, and empirical calculations, verified
      via direct execution comparison against baseline query outputs.
   ===================================================================== */


/* =====================================================================
   OBJECTIVE QUESTIONS
   ===================================================================== */

-- O1
-- List the different dtypes of columns in table "ball_by_ball" (using
-- information schema)
SELECT 
    COLUMN_NAME, 
    DATA_TYPE, 
    IS_NULLABLE, 
    COLUMN_KEY 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE LOWER(TABLE_NAME) = 'ball_by_ball' 
  AND (TABLE_SCHEMA = 'ipl' OR TABLE_SCHEMA = DATABASE())
ORDER BY ORDINAL_POSITION;



-- O2
-- What is the total number of runs scored in 1st season by RCB (bonus: also
-- include the extra runs using the extra runs table)
WITH rcb_info AS (
    SELECT Team_Id 
    FROM Team 
    WHERE Team_Name = 'Royal Challengers Bangalore'
),
season1_matches AS (
    SELECT Match_Id 
    FROM Matches 
    WHERE Season_Id = 1
),
rcb_season1_deliveries AS (
    SELECT bbb.Match_Id, bbb.Over_Id, bbb.Ball_Id, bbb.Innings_No
    FROM Ball_by_Ball bbb
    JOIN season1_matches sm ON bbb.Match_Id = sm.Match_Id
    JOIN rcb_info rcb ON bbb.Team_Batting = rcb.Team_Id
)
SELECT 
    SUM(bs.Runs_Scored) AS bat_runs,
    SUM(COALESCE(er.Extra_Runs, 0)) AS extra_runs,
    SUM(bs.Runs_Scored) + SUM(COALESCE(er.Extra_Runs, 0)) AS total_with_extras
FROM rcb_season1_deliveries d
LEFT JOIN Batsman_Scored bs ON d.Match_Id = bs.Match_Id 
    AND d.Over_Id = bs.Over_Id 
    AND d.Ball_Id = bs.Ball_Id 
    AND d.Innings_No = bs.Innings_No
LEFT JOIN Extra_Runs er ON d.Match_Id = er.Match_Id 
    AND d.Over_Id = er.Over_Id 
    AND d.Ball_Id = er.Ball_Id 
    AND d.Innings_No = er.Innings_No;



-- O3
-- How many players were more than age of 25 during season 2014?
WITH matches_2014 AS (
    SELECT Match_Id, Match_Date
    FROM Matches m
    JOIN Season s ON m.Season_Id = s.Season_Id
    WHERE s.Season_Year = 2014
)
SELECT 
    COUNT(DISTINCT p.Player_Id) AS players_over_25_in_2014
FROM Player p
JOIN Player_Match pm ON p.Player_Id = pm.Player_Id
JOIN matches_2014 m ON pm.Match_Id = m.Match_Id
WHERE TIMESTAMPDIFF(YEAR, p.DOB, m.Match_Date) > 25;



-- O4
-- How many matches did RCB win in season 2013?
WITH rcb_team AS (
    SELECT Team_Id 
    FROM Team 
    WHERE Team_Name = 'Royal Challengers Bangalore'
),
target_season AS (
    SELECT Season_Id 
    FROM Season 
    WHERE Season_Year = 2013
),
rcb_2013_wins AS (
    SELECT m.Match_Id
    FROM Matches m
    JOIN rcb_team t ON m.Match_Winner = t.Team_Id
    JOIN target_season s ON m.Season_Id = s.Season_Id
)
SELECT COUNT(*) AS rcb_wins_2013
FROM rcb_2013_wins;



-- O5
-- Top 10 players by strike rate in seasons 6 to 9 (min 50 balls faced)
WITH target_matches AS (
    SELECT Match_Id
    FROM Matches
    WHERE Season_Id IN (6, 7, 8, 9)
),
striker_balls AS (
    SELECT 
        bbb.Striker AS Player_Id,
        COUNT(bbb.Ball_Id) AS balls_faced
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
        AND bbb.Over_Id = er.Over_Id 
        AND bbb.Ball_Id = er.Ball_Id 
        AND bbb.Innings_No = er.Innings_No
    WHERE (er.Extra_Type_Id IS NULL OR er.Extra_Type_Id != 2)
    GROUP BY bbb.Striker
    HAVING balls_faced >= 50
),
striker_runs AS (
    SELECT 
        bbb.Striker AS Player_Id,
        SUM(bs.Runs_Scored) AS runs
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    WHERE bbb.Striker IN (SELECT Player_Id FROM striker_balls)
    GROUP BY bbb.Striker
)
SELECT 
    p.Player_Name,
    sr.runs,
    sb.balls_faced,
    ROUND((sr.runs * 100.0) / sb.balls_faced, 2) AS strike_rate
FROM striker_balls sb
JOIN striker_runs sr ON sb.Player_Id = sr.Player_Id
JOIN Player p ON sb.Player_Id = p.Player_Id
ORDER BY strike_rate DESC
LIMIT 10;



-- O6
-- Top 10 players with highest runs in seasons 6 to 9
WITH target_matches AS (
    SELECT Match_Id
    FROM Matches
    WHERE Season_Id IN (6, 7, 8, 9)
),
batsman_match_runs AS (
    SELECT 
        bbb.Striker AS Player_Id,
        SUM(bs.Runs_Scored) AS total_runs,
        COUNT(DISTINCT bbb.Match_Id) AS matches
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    GROUP BY bbb.Striker
)
SELECT 
    p.Player_Name,
    bmr.total_runs,
    bmr.matches,
    ROUND(bmr.total_runs * 1.0 / bmr.matches, 2) AS avg_runs_per_match
FROM batsman_match_runs bmr
JOIN Player p ON bmr.Player_Id = p.Player_Id
ORDER BY bmr.total_runs DESC;



-- O7
-- Top 10 players with highest wickets in seasons 6 to 9
WITH target_matches AS (
    SELECT Match_Id
    FROM Matches
    WHERE Season_Id IN (6, 7, 8, 9)
),
bowler_wickets AS (
    SELECT 
        bbb.Bowler AS Player_Id,
        COUNT(wt.Player_Out) AS total_wickets,
        COUNT(DISTINCT bbb.Match_Id) AS matches
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
    WHERE wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    GROUP BY bbb.Bowler
)
SELECT 
    p.Player_Name,
    bw.total_wickets,
    bw.matches,
    ROUND(bw.total_wickets * 1.0 / bw.matches, 2) AS avg_wickets_per_match
FROM bowler_wickets bw
JOIN Player p ON bw.Player_Id = p.Player_Id
ORDER BY bw.total_wickets DESC;



-- O8
-- All-rounders who have better than average runs and wickets in seasons 6 to 9
WITH target_matches AS (
    SELECT Match_Id
    FROM Matches
    WHERE Season_Id IN (6, 7, 8, 9)
),
batsman_stats AS (
    SELECT 
        bbb.Striker AS Player_Id,
        ROUND(SUM(bs.Runs_Scored) * 1.0 / COUNT(DISTINCT bbb.Match_Id), 2) AS avg_runs
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    GROUP BY bbb.Striker
),
bowler_stats AS (
    SELECT 
        bbb.Bowler AS Player_Id,
        ROUND(COUNT(wt.Player_Out) * 1.0 / COUNT(DISTINCT bbb.Match_Id), 2) AS avg_wkts
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
    WHERE wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    GROUP BY bbb.Bowler
),
benchmark AS (
    SELECT 
        (SELECT AVG(avg_runs) FROM batsman_stats) AS bench_runs,
        (SELECT AVG(avg_wkts) FROM bowler_stats) AS bench_wkts
)
SELECT 
    p.Player_Name,
    b.avg_runs,
    w.avg_wkts
FROM batsman_stats b
JOIN bowler_stats w ON b.Player_Id = w.Player_Id
JOIN Player p ON b.Player_Id = p.Player_Id
CROSS JOIN benchmark bm
WHERE b.avg_runs > bm.bench_runs
  AND w.avg_wkts > bm.bench_wkts
ORDER BY b.avg_runs DESC, w.avg_wkts DESC;



-- O9
-- Create table "rcb_record" with venue-wise wins and losses in seasons 6 to 9
DROP TABLE IF EXISTS rcb_record;

CREATE TABLE rcb_record AS
WITH rcb_venue_matches AS (
    SELECT Venue_Id, Match_Winner
    FROM Matches
    WHERE (Team_1 = 2 OR Team_2 = 2)
      AND Season_Id IN (6, 7, 8, 9)
      AND Match_Winner IS NOT NULL
)
SELECT 
    v.Venue_Id,
    v.Venue_Name,
    COUNT(CASE WHEN m.Match_Winner = 2 THEN 1 END) AS wins,
    COUNT(CASE WHEN m.Match_Winner != 2 THEN 1 END) AS losses
FROM rcb_venue_matches m
JOIN Venue v ON m.Venue_Id = v.Venue_Id
GROUP BY v.Venue_Id, v.Venue_Name;

SELECT * FROM rcb_record ORDER BY wins DESC, losses ASC;



-- O10
-- Bowling style analysis (total wickets, number of bowlers, wickets per bowler)
WITH target_matches AS (
    SELECT Match_Id
    FROM Matches
    WHERE Season_Id IN (6, 7, 8, 9)
),
bowler_wickets AS (
    SELECT 
        bbb.Bowler AS Player_Id,
        COUNT(wt.Player_Out) AS wickets
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
    WHERE wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    GROUP BY bbb.Bowler
)
SELECT 
    bs.Bowling_skill AS bowling_style,
    SUM(bw.wickets) AS total_wickets,
    COUNT(DISTINCT p.Player_Id) AS num_bowlers,
    ROUND(SUM(bw.wickets) * 1.0 / COUNT(DISTINCT p.Player_Id), 2) AS wickets_per_bowler
FROM Bowling_Style bs
JOIN Player p ON bs.Bowling_Id = p.Bowling_skill
JOIN bowler_wickets bw ON p.Player_Id = bw.Player_Id
GROUP BY bs.Bowling_Id, bs.Bowling_skill
ORDER BY total_wickets DESC;



-- O11
-- YoY comparison of RCB runs and wickets (2013-2016 vs prior season)
WITH target_matches AS (
    SELECT m.Match_Id, s.Season_Year
    FROM Matches m
    JOIN Season s ON m.Season_Id = s.Season_Id
    WHERE m.Season_Id IN (5, 6, 7, 8, 9)
),
season_runs AS (
    SELECT 
        tm.Season_Year,
        SUM(bs.Runs_Scored) + COALESCE(SUM(er.Extra_Runs), 0) AS runs
    FROM Ball_by_Ball bbb
    JOIN target_matches tm ON bbb.Match_Id = tm.Match_Id
    LEFT JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
        AND bbb.Over_Id = er.Over_Id 
        AND bbb.Ball_Id = er.Ball_Id 
        AND bbb.Innings_No = er.Innings_No
    WHERE bbb.Team_Batting = 2
    GROUP BY tm.Season_Year
),
season_wkts AS (
    SELECT 
        tm.Season_Year,
        COUNT(wt.Player_Out) AS wkts
    FROM Ball_by_Ball bbb
    JOIN target_matches tm ON bbb.Match_Id = tm.Match_Id
    JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
    WHERE bbb.Team_Bowling = 2 
      AND wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    GROUP BY tm.Season_Year
),
yoy AS (
    SELECT 
        r.Season_Year,
        r.runs,
        w.wkts,
        r.runs - LAG(r.runs) OVER (ORDER BY r.Season_Year) AS runs_vs_prev,
        w.wkts - LAG(w.wkts) OVER (ORDER BY r.Season_Year) AS wkts_vs_prev
    FROM season_runs r
    JOIN season_wkts w ON r.Season_Year = w.Season_Year
)
SELECT 
    Season_Year,
    runs,
    wkts,
    runs_vs_prev,
    wkts_vs_prev,
    CASE 
        WHEN runs_vs_prev > 0 AND wkts_vs_prev > 0 THEN 'Better in Both'
        WHEN runs_vs_prev > 0 OR wkts_vs_prev > 0 THEN 'Better'
        ELSE 'Worse'
    END AS performance_status
FROM yoy
WHERE Season_Year >= 2013
ORDER BY Season_Year;



-- O12
-- Create 3 KPIs for RCB strategy

-- KPI 1: RCB win % by season (2013-2016)
SELECT 
    s.Season_Year,
    COUNT(m.Match_Id) AS played,
    COUNT(CASE WHEN m.Match_Winner = 2 THEN 1 END) AS wins,
    ROUND((COUNT(CASE WHEN m.Match_Winner = 2 THEN 1 END) * 100.0) / COUNT(m.Match_Id), 2) AS win_pct
FROM Matches m
JOIN Season s ON m.Season_Id = s.Season_Id
WHERE (m.Team_1 = 2 OR m.Team_2 = 2)
  AND s.Season_Year BETWEEN 2013 AND 2016
GROUP BY s.Season_Year
ORDER BY s.Season_Year;

-- KPI 2: Boundary reliance (% of RCB runs from 4s and 6s)
SELECT 
    ROUND(
        (SUM(CASE WHEN bs.Runs_Scored IN (4, 6) THEN bs.Runs_Scored ELSE 0 END) * 100.0) / 
        SUM(bs.Runs_Scored), 2
    ) AS pct_runs_from_boundaries
FROM Ball_by_Ball bbb
JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
    AND bbb.Over_Id = bs.Over_Id 
    AND bbb.Ball_Id = bs.Ball_Id 
    AND bbb.Innings_No = bs.Innings_No
WHERE bbb.Team_Batting = 2;

-- KPI 3: Top 5 RCB run-scorers
WITH rcb_striker_runs AS (
    SELECT 
        bbb.Striker AS Player_Id,
        SUM(bs.Runs_Scored) AS runs
    FROM Ball_by_Ball bbb
    JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    WHERE bbb.Team_Batting = 2
    GROUP BY bbb.Striker
)
SELECT 
    p.Player_Name,
    r.runs
FROM rcb_striker_runs r
JOIN Player p ON r.Player_Id = p.Player_Id
ORDER BY r.runs DESC
LIMIT 5;



-- O13
-- Bowler venue performance ranking (dense_rank)
WITH target_matches AS (
    SELECT m.Match_Id, m.Venue_Id, v.Venue_Name
    FROM Matches m
    JOIN Venue v ON m.Venue_Id = v.Venue_Id
    WHERE m.Season_Id IN (6, 7, 8, 9)
),
bowler_venue AS (
    SELECT 
        tm.Venue_Name,
        bbb.Bowler AS Player_Id,
        COUNT(wt.Player_Out) AS wickets,
        ROUND(COUNT(wt.Player_Out) * 1.0 / COUNT(DISTINCT bbb.Match_Id), 2) AS avg_wickets
    FROM Ball_by_Ball bbb
    JOIN target_matches tm ON bbb.Match_Id = tm.Match_Id
    LEFT JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
        AND wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    GROUP BY tm.Venue_Id, tm.Venue_Name, bbb.Bowler
)
SELECT 
    bv.Venue_Name,
    p.Player_Name,
    bv.wickets,
    bv.avg_wickets,
    DENSE_RANK() OVER (PARTITION BY bv.Venue_Name ORDER BY bv.avg_wickets DESC) AS venue_rank
FROM bowler_venue bv
JOIN Player p ON bv.Player_Id = p.Player_Id
ORDER BY bv.Venue_Name, venue_rank;



-- O14
-- Consistency of top batsmen across seasons 6-9
WITH target_matches AS (
    SELECT Match_Id, Season_Id
    FROM Matches
    WHERE Season_Id IN (6, 7, 8, 9)
),
player_seasons AS (
    SELECT 
        bbb.Striker AS Player_Id,
        tm.Season_Id,
        SUM(bs.Runs_Scored) AS season_runs
    FROM Ball_by_Ball bbb
    JOIN target_matches tm ON bbb.Match_Id = tm.Match_Id
    JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    GROUP BY bbb.Striker, tm.Season_Id
)
SELECT 
    p.Player_Name,
    COUNT(DISTINCT ps.Season_Id) AS seasons_played,
    ROUND(AVG(ps.season_runs), 2) AS avg_runs_per_season,
    MIN(ps.season_runs) AS worst_season,
    MAX(ps.season_runs) AS best_season,
    ROUND(STDDEV(ps.season_runs), 2) AS runs_stddev
FROM player_seasons ps
JOIN Player p ON ps.Player_Id = p.Player_Id
GROUP BY ps.Player_Id, p.Player_Name
HAVING seasons_played = 4
ORDER BY avg_runs_per_season DESC;



-- O15
-- Venue-specific batsman strike rates (min 60 balls at venue)
WITH target_matches AS (
    SELECT m.Match_Id, m.Venue_Id, v.Venue_Name
    FROM Matches m
    JOIN Venue v ON m.Venue_Id = v.Venue_Id
    WHERE m.Season_Id IN (6, 7, 8, 9)
),
venue_striker_runs AS (
    SELECT 
        bbb.Striker AS Player_Id,
        tm.Venue_Name,
        SUM(bs.Runs_Scored) AS runs,
        COUNT(bbb.Ball_Id) AS balls
    FROM Ball_by_Ball bbb
    JOIN target_matches tm ON bbb.Match_Id = tm.Match_Id
    JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    GROUP BY bbb.Striker, tm.Venue_Id, tm.Venue_Name
    HAVING balls >= 60
)
SELECT 
    p.Player_Name,
    vs.Venue_Name,
    vs.runs,
    vs.balls,
    ROUND((vs.runs * 100.0) / vs.balls, 2) AS strike_rate
FROM venue_striker_runs vs
JOIN Player p ON vs.Player_Id = p.Player_Id
ORDER BY strike_rate DESC
LIMIT 25;




/* =====================================================================
   SUBJECTIVE QUESTIONS
   ===================================================================== */

-- S1
-- How does toss win:run ratio look like for each venue? Does toss decision
-- (bat/field) affect match outcomes at specific venues?

-- Part 1: Overall Toss Decision Impact
SELECT 
    td.Toss_Name AS toss_decision,
    COUNT(m.Match_Id) AS total_matches,
    COUNT(CASE WHEN m.Toss_Winner = m.Match_Winner THEN 1 END) AS toss_winner_won_match,
    ROUND((COUNT(CASE WHEN m.Toss_Winner = m.Match_Winner THEN 1 END) * 100.0) / COUNT(m.Match_Id), 2) AS toss_winner_win_pct,
    COUNT(CASE 
        WHEN (m.Toss_Decide = 1 AND m.Match_Winner != m.Toss_Winner) OR (m.Toss_Decide = 2 AND m.Match_Winner = m.Toss_Winner) 
        THEN 1 
    END) AS chasing_wins,
    ROUND((COUNT(CASE 
        WHEN (m.Toss_Decide = 1 AND m.Match_Winner != m.Toss_Winner) OR (m.Toss_Decide = 2 AND m.Match_Winner = m.Toss_Winner) 
        THEN 1 
    END) * 100.0) / COUNT(m.Match_Id), 2) AS chasing_win_pct
FROM Matches m
JOIN Toss_Decision td ON m.Toss_Decide = td.Toss_Id
WHERE m.Match_Winner IS NOT NULL
GROUP BY td.Toss_Id, td.Toss_Name;

-- Part 2: Venue-Specific Toss Decision Impact (Min 15 Matches)
WITH valid_matches AS (
    SELECT Venue_Id, Toss_Winner, Match_Winner, Toss_Decide
    FROM Matches
    WHERE Match_Winner IS NOT NULL
)
SELECT 
    v.Venue_Name,
    COUNT(m.Venue_Id) AS total_matches,
    ROUND((COUNT(CASE WHEN m.Toss_Winner = m.Match_Winner THEN 1 END) * 100.0) / COUNT(m.Venue_Id), 2) AS toss_winner_win_pct,
    ROUND((COUNT(CASE 
        WHEN (m.Toss_Decide = 1 AND m.Match_Winner != m.Toss_Winner) OR (m.Toss_Decide = 2 AND m.Match_Winner = m.Toss_Winner) 
        THEN 1 
    END) * 100.0) / COUNT(m.Venue_Id), 2) AS chasing_win_pct
FROM valid_matches m
JOIN Venue v ON m.Venue_Id = v.Venue_Id
GROUP BY v.Venue_Id, v.Venue_Name
HAVING total_matches >= 15
ORDER BY chasing_win_pct DESC;

-- Toss & Decision Analysis Methodology:
-- 1. Compares toss decisions with match outcomes and chasing performance across completed matches to assess historical patterns.
-- 2. Evaluates venue-specific toss conversion rates (minimum 15 matches) to determine where local ground conditions align with batting or bowling first.
-- 3. Provides tactical context for toss strategy based on observed venue-level chasing success.



-- S2
-- Best death-overs bowlers for RCB acquisition
WITH target_matches AS (
    SELECT Match_Id
    FROM Matches
    WHERE Season_Id IN (7, 8, 9)
),
bowler_deliveries AS (
    SELECT 
        bbb.Bowler AS Player_Id,
        COUNT(bbb.Ball_Id) AS balls_bowled,
        COUNT(wt.Player_Out) AS wickets_taken,
        SUM(COALESCE(bs.Runs_Scored, 0)) + SUM(COALESCE(er.Extra_Runs, 0)) AS runs_conceded
    FROM Ball_by_Ball bbb
    JOIN target_matches m ON bbb.Match_Id = m.Match_Id
    LEFT JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
        AND bbb.Over_Id = er.Over_Id 
        AND bbb.Ball_Id = er.Ball_Id 
        AND bbb.Innings_No = er.Innings_No
    LEFT JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
        AND wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    GROUP BY bbb.Bowler
    HAVING balls_bowled >= 300
)
SELECT 
    p.Player_Name,
    bd.wickets_taken,
    ROUND(bd.runs_conceded * 6.0 / bd.balls_bowled, 2) AS economy_rate,
    ROUND(bd.balls_bowled * 1.0 / NULLIF(bd.wickets_taken, 0), 2) AS bowling_strike_rate
FROM bowler_deliveries bd
JOIN Player p ON bd.Player_Id = p.Player_Id
WHERE bd.wickets_taken >= 25
ORDER BY economy_rate ASC, bd.wickets_taken DESC
LIMIT 10;

-- Bowler Recruitment Evaluation:
-- 1. Uses wickets, economy rate, and bowling strike rate across seasons 7-9 (min 300 balls, min 25 wickets) to identify bowlers whose performance profile fits RCB's defensive requirements.
-- 2. Evaluates performance profiles using quantifiable metrics to identify disciplined options with demonstrated boundary containment.
-- 3. Informs data-driven acquisition recommendations by ranking candidates on economy and wicket volume.



-- S3
-- What are some of the parameters that should be focused on while selecting
-- the players?
WITH target_players AS (
    SELECT Player_Id, Player_Name
    FROM Player
    WHERE Player_Name IN ('V Kohli', 'AB de Villiers', 'CH Gayle', 'MS Dhoni', 'RG Sharma')
)
SELECT 
    tp.Player_Name,
    CASE 
        WHEN bbb.Over_Id BETWEEN 1 AND 6 THEN 'Powerplay (1-6)'
        WHEN bbb.Over_Id BETWEEN 7 AND 15 THEN 'Middle Overs (7-15)'
        ELSE 'Death Overs (16-20)'
    END AS match_phase,
    COUNT(bbb.Ball_Id) AS balls_faced,
    SUM(bs.Runs_Scored) AS total_runs,
    ROUND((SUM(bs.Runs_Scored) * 100.0) / COUNT(bbb.Ball_Id), 2) AS strike_rate,
    ROUND((SUM(CASE WHEN bs.Runs_Scored IN (4, 6) THEN 1 ELSE 0 END) * 100.0) / COUNT(bbb.Ball_Id), 2) AS boundary_freq_pct
FROM target_players tp
JOIN Ball_by_Ball bbb ON tp.Player_Id = bbb.Striker
JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
    AND bbb.Over_Id = bs.Over_Id 
    AND bbb.Ball_Id = bs.Ball_Id 
    AND bbb.Innings_No = bs.Innings_No
GROUP BY tp.Player_Id, tp.Player_Name, match_phase
ORDER BY tp.Player_Name, match_phase;

-- Recommended Selection Metrics:
-- 1. Batsmen:
--    - Phase Strike Rate (evaluating acceleration in Powerplay vs Middle vs Death overs).
--    - Boundary Frequency (% of deliveries resulting in boundaries) and Dot Ball %.
--    - Pace vs spin scoring distributions to balance batting order matchups.
-- 2. Bowlers:
--    - Phase Economy (restricting run flow in Death Overs and Powerplay).
--    - Bowling Strike Rate (balls required per dismissal).
--    - Dot Ball Percentage (sustained pressure leading to wicket opportunities).
-- 3. Venue Compatibility: Aligning bowling repertoire (cutters, hard lengths) with specific ground conditions.



-- S4
-- Top all-rounders for RCB squad balance
WITH batting_profile AS (
    SELECT 
        bbb.Striker AS Player_Id,
        SUM(bs.Runs_Scored) AS total_runs,
        ROUND((SUM(bs.Runs_Scored) * 100.0) / COUNT(bbb.Ball_Id), 2) AS batting_strike_rate
    FROM Ball_by_Ball bbb
    JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    GROUP BY bbb.Striker
    HAVING total_runs >= 500
),
bowling_profile AS (
    SELECT 
        bbb.Bowler AS Player_Id,
        COUNT(wt.Player_Out) AS total_wickets,
        ROUND((SUM(COALESCE(bs.Runs_Scored, 0)) + SUM(COALESCE(er.Extra_Runs, 0))) * 6.0 / COUNT(bbb.Ball_Id), 2) AS economy_rate
    FROM Ball_by_Ball bbb
    LEFT JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
        AND bbb.Over_Id = er.Over_Id 
        AND bbb.Ball_Id = er.Ball_Id 
        AND bbb.Innings_No = er.Innings_No
    LEFT JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
        AND wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    GROUP BY bbb.Bowler
    HAVING total_wickets >= 20
)
SELECT 
    p.Player_Name,
    b.total_runs,
    b.batting_strike_rate,
    w.total_wickets,
    w.economy_rate,
    ROUND((b.total_runs * w.total_wickets) / 100.0, 2) AS versatility_index
FROM batting_profile b
JOIN bowling_profile w ON b.Player_Id = w.Player_Id
JOIN Player p ON b.Player_Id = p.Player_Id
ORDER BY versatility_index DESC
LIMIT 10;

-- All-Rounder Evaluation Framework:
-- 1. Project-defined versatility index = (total_runs * total_wickets) / 100.
-- 2. The project-defined versatility index combines batting runs and bowling wickets to identify players contributing in both disciplines (min 500 runs, min 20 wickets).
-- 3. Identifies multi-dimensional players who lengthen the batting lineup while contributing reliable bowling overs.



-- S5
-- Are there players whose presence positively influences the morale and
-- performance of the team? (justify your answer using visualization)

-- Analysis 1: League-wide Match-Winners (Most Man of the Match Awards, Top 10)
WITH mom_awards_summary AS (
    SELECT 
        Man_of_the_Match AS Player_Id,
        COUNT(Match_Id) AS mom_awards,
        COUNT(DISTINCT Season_Id) AS seasons_awarded
    FROM Matches
    WHERE Man_of_the_Match IS NOT NULL
    GROUP BY Man_of_the_Match
)
SELECT 
    p.Player_Name,
    m.mom_awards,
    m.seasons_awarded
FROM mom_awards_summary m
JOIN Player p ON m.Player_Id = p.Player_Id
ORDER BY m.mom_awards DESC
LIMIT 10;

-- Analysis 2: RCB Core Pillars (Player Appearances, Wins, and Win %, Min 20 Matches, Top 10)
WITH rcb_player_stats AS (
    SELECT 
        pm.Player_Id,
        COUNT(pm.Match_Id) AS matches_played_for_rcb,
        COUNT(CASE WHEN m.Match_Winner = 2 THEN 1 END) AS rcb_wins,
        ROUND((COUNT(CASE WHEN m.Match_Winner = 2 THEN 1 END) * 100.0) / COUNT(pm.Match_Id), 2) AS rcb_win_pct
    FROM Player_Match pm
    JOIN Matches m ON pm.Match_Id = m.Match_Id
    WHERE pm.Team_Id = 2
    GROUP BY pm.Player_Id
    HAVING matches_played_for_rcb >= 20
)
SELECT 
    p.Player_Name,
    rps.matches_played_for_rcb,
    rps.rcb_wins,
    rps.rcb_win_pct
FROM rcb_player_stats rps
JOIN Player p ON rps.Player_Id = p.Player_Id
ORDER BY rps.rcb_win_pct DESC
LIMIT 10;

-- Morale and Impact Drivers:
-- 1. Evaluates match-winning contributions through Man of the Match awards across all seasons.
-- 2. Examines team performance consistency by analyzing RCB win percentage when individual players featured in the playing XI (minimum 20 matches).
-- 3. Visual Representation: Ranked Lollipop chart of individual awards alongside bar chart comparisons of team win percentages.



-- S6
-- Phase-wise bowling performance for RCB
SELECT 
    CASE 
        WHEN bbb.Over_Id BETWEEN 1 AND 6 THEN 'Powerplay (1-6)'
        WHEN bbb.Over_Id BETWEEN 7 AND 15 THEN 'Middle Overs (7-15)'
        ELSE 'Death Overs (16-20)'
    END AS match_phase,
    COUNT(bbb.Ball_Id) AS balls_bowled,
    SUM(COALESCE(bs.Runs_Scored, 0)) + SUM(COALESCE(er.Extra_Runs, 0)) AS runs_conceded,
    COUNT(wt.Player_Out) AS wickets_taken,
    ROUND((SUM(COALESCE(bs.Runs_Scored, 0)) + SUM(COALESCE(er.Extra_Runs, 0))) * 6.0 / COUNT(bbb.Ball_Id), 2) AS phase_economy
FROM Ball_by_Ball bbb
LEFT JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
    AND bbb.Over_Id = bs.Over_Id 
    AND bbb.Ball_Id = bs.Ball_Id 
    AND bbb.Innings_No = bs.Innings_No
LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
    AND bbb.Over_Id = er.Over_Id 
    AND bbb.Ball_Id = er.Ball_Id 
    AND bbb.Innings_No = er.Innings_No
LEFT JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
    AND bbb.Over_Id = wt.Over_Id 
    AND bbb.Ball_Id = wt.Ball_Id 
    AND bbb.Innings_No = wt.Innings_No
    AND wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
WHERE bbb.Team_Bowling = 2
GROUP BY match_phase
ORDER BY match_phase;

-- Bowling Phase Vulnerability Diagnostics:
-- 1. Evaluates phase-specific economy and wicket volume for RCB across Powerplay, Middle, and Death overs.
-- 2. Identifies run-rate inflation in the Death Overs (9.56 economy rate across 3,697 deliveries) and wicket-taking efficiency across earlier phases.
-- 3. Guides bowling resource allocation to optimize containment and strike capability by match phase.



-- S7
-- High-scoring venues analysis
WITH match_scoring AS (
    SELECT 
        m.Match_Id,
        m.Venue_Id,
        SUM(bs.Runs_Scored) + COALESCE(SUM(er.Extra_Runs), 0) AS total_match_runs,
        SUM(CASE WHEN bs.Runs_Scored IN (4, 6) THEN bs.Runs_Scored ELSE 0 END) AS boundary_runs
    FROM Matches m
    JOIN Ball_by_Ball bbb ON m.Match_Id = bbb.Match_Id
    LEFT JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
        AND bbb.Over_Id = er.Over_Id 
        AND bbb.Ball_Id = er.Ball_Id 
        AND bbb.Innings_No = er.Innings_No
    GROUP BY m.Match_Id, m.Venue_Id
)
SELECT 
    v.Venue_Name,
    COUNT(ms.Match_Id) AS matches_played,
    ROUND(AVG(ms.total_match_runs), 2) AS avg_match_runs,
    MAX(ms.total_match_runs) AS max_match_runs,
    ROUND(AVG((ms.boundary_runs * 100.0) / NULLIF(ms.total_match_runs, 0)), 2) AS avg_boundary_run_pct
FROM match_scoring ms
JOIN Venue v ON ms.Venue_Id = v.Venue_Id
GROUP BY v.Venue_Id, v.Venue_Name
HAVING matches_played >= 10
ORDER BY avg_match_runs DESC;

-- Venue Scoring Analysis Insights:
-- 1. High-scoring venues identified by average match runs (min 10 matches): Brabourne Stadium (349.18 avg runs, 54.78% boundary contribution) and M Chinnaswamy Stadium (317.93 avg runs, 60.46% boundary contribution).
-- 2. Evaluates boundary contribution percentages across grounds to identify venues where boundary containment is critical.
-- 3. Informs tactical field placements and bowling strategies adapted to specific ground dimensions.



-- S8
-- RCB home vs away win record
SELECT 
    CASE 
        WHEN m.Venue_Id = 1 THEN 'Home (M Chinnaswamy Stadium)'
        ELSE 'Away / Neutral Venues'
    END AS venue_type,
    COUNT(CASE WHEN m.Match_Winner IS NOT NULL THEN 1 END) AS total_matches,
    COUNT(CASE WHEN m.Match_Winner = 2 THEN 1 END) AS matches_won,
    COUNT(CASE WHEN m.Match_Winner != 2 AND m.Match_Winner IS NOT NULL THEN 1 END) AS matches_lost,
    ROUND((COUNT(CASE WHEN m.Match_Winner = 2 THEN 1 END) * 100.0) / COUNT(CASE WHEN m.Match_Winner IS NOT NULL THEN 1 END), 2) AS win_percentage
FROM Matches m
WHERE (m.Team_1 = 2 OR m.Team_2 = 2) AND m.Match_Winner IS NOT NULL
GROUP BY venue_type
ORDER BY venue_type;

-- Home vs Away Performance Analysis:
-- 1. Evaluates RCB's completed-match win rate at home (M Chinnaswamy Stadium: 54 matches, 29 wins, 53.70% win rate) versus away/neutral venues (83 matches, 41 wins, 49.40% win rate).
-- 2. Compares home performance with away fixtures to assess historical home-ground advantage.
-- 3. Guides recruitment and tactical planning tailored to Chinnaswamy's short boundaries and high-scoring conditions.



-- S9
-- RCB season-by-season balance (runs scored vs conceded, net differential, wickets)
WITH rcb_season_batting AS (
    SELECT 
        m.Season_Id,
        s.Season_Year,
        SUM(bs.Runs_Scored) + COALESCE(SUM(er.Extra_Runs), 0) AS runs_scored,
        COUNT(DISTINCT m.Match_Id) AS total_matches,
        COUNT(DISTINCT CASE WHEN m.Match_Winner = 2 THEN m.Match_Id END) AS wins
    FROM Matches m
    JOIN Season s ON m.Season_Id = s.Season_Id
    JOIN Ball_by_Ball bbb ON m.Match_Id = bbb.Match_Id
    LEFT JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
        AND bbb.Over_Id = er.Over_Id 
        AND bbb.Ball_Id = er.Ball_Id 
        AND bbb.Innings_No = er.Innings_No
    WHERE bbb.Team_Batting = 2
    GROUP BY m.Season_Id, s.Season_Year
),
rcb_season_bowling AS (
    SELECT 
        m.Season_Id,
        SUM(bs.Runs_Scored) + COALESCE(SUM(er.Extra_Runs), 0) AS runs_conceded,
        COUNT(wt.Player_Out) AS wickets_taken
    FROM Matches m
    JOIN Ball_by_Ball bbb ON m.Match_Id = bbb.Match_Id
    LEFT JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
        AND bbb.Over_Id = bs.Over_Id 
        AND bbb.Ball_Id = bs.Ball_Id 
        AND bbb.Innings_No = bs.Innings_No
    LEFT JOIN Extra_Runs er ON bbb.Match_Id = er.Match_Id 
        AND bbb.Over_Id = er.Over_Id 
        AND bbb.Ball_Id = er.Ball_Id 
        AND bbb.Innings_No = er.Innings_No
    LEFT JOIN Wicket_Taken wt ON bbb.Match_Id = wt.Match_Id 
        AND bbb.Over_Id = wt.Over_Id 
        AND bbb.Ball_Id = wt.Ball_Id 
        AND bbb.Innings_No = wt.Innings_No
        AND wt.Kind_Out IN (1, 2, 4, 6, 7, 8)
    WHERE bbb.Team_Bowling = 2
    GROUP BY m.Season_Id
)
SELECT 
    bat.Season_Year,
    bat.total_matches,
    bat.wins,
    ROUND((bat.wins * 100.0) / bat.total_matches, 2) AS win_pct,
    bat.runs_scored,
    bowl.runs_conceded,
    (bat.runs_scored - bowl.runs_conceded) AS net_run_differential,
    bowl.wickets_taken
FROM rcb_season_batting bat
JOIN rcb_season_bowling bowl ON bat.Season_Id = bowl.Season_Id
ORDER BY bat.Season_Year;

-- Historical Season Balance & Net Run Differential:
-- 1. Analyzes season-by-season performance distinguishing total runs scored, total runs conceded, and net run differential (e.g., 2016 season: 2,977 scored, 2,711 conceded, +266 net run differential).
-- 2. Note: Net run differential represents runs scored minus runs conceded within a season, distinct from year-over-year run change (Query O11).
-- 3. Historical net run differential serves as a supporting metric when assessing team balance and season trajectory.



-- S10
-- Whole-match franchise diagnostic (win rate, avg scored, avg conceded)
SELECT 
    t.Team_Name,
    COUNT(DISTINCT m.Match_Id) AS total_matches,
    ROUND((COUNT(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 END) * 100.0) / COUNT(DISTINCT m.Match_Id), 2) AS all_time_win_rate,
    ROUND(SUM(CASE WHEN bbb.Team_Batting = t.Team_Id THEN bs.Runs_Scored ELSE 0 END) * 1.0 / COUNT(DISTINCT m.Match_Id), 2) AS avg_runs_scored_per_match,
    ROUND(SUM(CASE WHEN bbb.Team_Bowling = t.Team_Id THEN bs.Runs_Scored ELSE 0 END) * 1.0 / COUNT(DISTINCT m.Match_Id), 2) AS avg_runs_conceded_per_match
FROM Team t
JOIN Matches m ON t.Team_Id IN (m.Team_1, m.Team_2)
JOIN Ball_by_Ball bbb ON m.Match_Id = bbb.Match_Id
JOIN Batsman_Scored bs ON bbb.Match_Id = bs.Match_Id 
    AND bbb.Over_Id = bs.Over_Id 
    AND bbb.Ball_Id = bs.Ball_Id 
    AND bbb.Innings_No = bs.Innings_No
WHERE t.Team_Id = 2
GROUP BY t.Team_Id, t.Team_Name;

-- Strategic Diagnostic Framework:
-- 1. Aggregates all-time franchise performance: total matches, overall win rate, average runs scored per match, and average runs conceded per match.
-- 2. Potential Next-Step Analysis (Future Work):
--    - Advanced Player Valuation: Replacement-level player valuation (RAA) and win-above-expectation (WAE) metrics normalized for venue par.
--    - Tactical Phase Decomposition: Granular ball-by-ball bowler-batsman matchup modeling across distinct phases.
--    - Auction Simulation: Optimization-based squad construction modeling within auction purse constraints.



-- S11
-- Update Delhi franchise name and verify
UPDATE Team
SET Team_Name = 'Delhi Daredevils'
WHERE Team_Name = 'Delhi Capitals' 
   OR Team_Name = 'Delhi_Capitals';

-- Verification Query:
SELECT Team_Id, Team_Name 
FROM Team 
WHERE Team_Id = 6;

-- Franchise Name Normalization:
-- 1. Renames the franchise according to the task requirement in table Team and verifies the updated Team_Name.
-- 2. Maintains relational integrity across foreign key references in Matches, Ball_by_Ball, and Player_Match.
