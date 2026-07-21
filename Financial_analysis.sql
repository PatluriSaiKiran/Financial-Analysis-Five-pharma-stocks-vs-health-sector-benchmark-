CREATE TABLE dim_ticker (
 ticker_id serial  PRIMARY KEY,
 ticker VARCHAR (10) UNIQUE NOT NULL,
 company_name VARCHAR(100),
 exchange VARCHAR(20),
 currency VARCHAR(5),
 is_benchmark BOOLEAN DEFAULT FALSE 
)

INSERT INTO dim_ticker (ticker, company_name, exchange, currency, is_benchmark) VALUES
    ('AZN.L', 'AstraZeneca',              'LSE',  'GBP', FALSE),
    ('GSK.L', 'GSK',                      'LSE',  'GBP', FALSE),
    ('PFE',   'Pfizer',                   'NYSE', 'USD', FALSE),
    ('JNJ',   'Johnson & Johnson',        'NYSE', 'USD', FALSE),
    ('MRK',   'Merck',                    'NYSE', 'USD', FALSE),
    ('XLV',   'Health Care Sector SPDR',  'NYSE', 'USD', TRUE);

SELECT * FROM dim_ticker

CREATE TABLE pharma_fact_indicators (
    date             DATE,
    ticker           VARCHAR(10),
    currency         VARCHAR(5),
    open             NUMERIC(12, 4),
    high             NUMERIC(12, 4),
    low              NUMERIC(12, 4),
    close            NUMERIC(12, 4),
    volume           BIGINT,
    daily_return     NUMERIC(8, 4),
    sma_20           NUMERIC(12, 4),
    bollinger_upper  NUMERIC(12, 4),
    bollinger_lower  NUMERIC(12, 4),
    rsi_14           NUMERIC(6, 3),
    volatility_20d   NUMERIC(8, 4),
    drawdown_pct     NUMERIC(8, 4)
);
SELECT * FROM pharma_fact_indicators;

CREATE TABLE fact_price_indicators (
    date             DATE,
    ticker_id        INT,
    open             NUMERIC(12, 4),
    high             NUMERIC(12, 4),
    low              NUMERIC(12, 4),
    close            NUMERIC(12, 4),
    volume           BIGINT,
    daily_return     NUMERIC(8, 4),
    sma_20           NUMERIC(12, 4),
    bollinger_upper  NUMERIC(12, 4),
    bollinger_lower  NUMERIC(12, 4),
    rsi_14           NUMERIC(6, 3),
    volatility_20d   NUMERIC(8, 4),
    drawdown_pct     NUMERIC(8, 4)
);

INSERT INTO fact_price_indicators  (
    date, ticker_id, open, high, low, close, volume,
    daily_return, sma_20, bollinger_upper, bollinger_lower,
    rsi_14, volatility_20d, drawdown_pct
)
SELECT
    s.date, dt.ticker_id, s.open, s.high, s.low, s.close, s.volume,
    s.daily_return, s.sma_20, s.bollinger_upper, s.bollinger_lower,
    s.rsi_14, s.volatility_20d, s.drawdown_pct
FROM pharma_fact_indicators s
JOIN dim_ticker dt ON dt.ticker = s.ticker;

SELECT count(*) FROM fact_price_indicators

--WHICH TICKER IS THE RISKIEST EACH MONTH 
SELECT
    dt. ticker,
    DATE_TRUNC('month', f.date) AS month,
    AVG(f.volatility_20d) AS avg_monthly_volatility,
    RANK() OVER ( PARTITION BY DATE_TRUNC('month', f.date) ORDER BY AVG(f.volatility_20d) DESC ) AS volatility_rank
FROM fact_price_indicators f
JOIN dim_ticker dt ON dt.ticker_id = f.ticker_id
WHERE dt.is_benchmark = FALSE
GROUP BY dt.ticker, DATE_TRUNC('month', f.date)
ORDER BY month, volatility_rank;


-- MAX DRAWDOWN PERIOD 
SELECT DISTINCT ON (dt.ticker)
    dt. ticker,
    f.date AS max_drawdown_date,
    f.drawdown_pct AS max_drawdown_pct
FROM fact_price_indicators f
JOIN dim_ticker dt ON dt.ticker_id = f.ticker_id
WHERE dt.is_benchmark = FALSE
ORDER BY dt. ticker, f.drawdown_pct ASC; 

-- Corr
SELECT
    dt1.ticker AS ticker_a,
    dt2.ticker AS ticker_b,
    CORR(f1.daily_return, f2.daily_return) AS return_correlation,
    COUNT(*) AS overlapping_days
FROM fact_price_indicators f1
JOIN fact_price_indicators f2
    ON f1.date = f2.date AND f1.ticker_id < f2.ticker_id
JOIN dim_ticker dt1 ON dt1.ticker_id = f1.ticker_id
JOIN dim_ticker dt2 ON dt2.ticker_id = f2.ticker_id
WHERE dt1.is_benchmark = FALSE AND dt2.is_benchmark = FALSE
GROUP BY dt1.ticker, dt2.ticker
ORDER BY return_correlation DESC;


---
WITH signals AS (
    SELECT
        f.date,
        f.ticker_id,
        f.rsi_14,
        f.close,
        LEAD(f.close, 5) OVER (
            PARTITION BY f.ticker_id ORDER BY f.date
        ) AS close_5d_fwd
    FROM fact_price_indicators f
),
signal_returns AS (
    SELECT
        s.ticker_id,
        s.date,
        CASE WHEN s.rsi_14 < 30 THEN 'oversold'
             WHEN s.rsi_14 > 70 THEN 'overbought'
             ELSE 'none' END AS signal,
        (s.close_5d_fwd - s.close) / s.close * 100 AS fwd_return_5d
    FROM signals s
    WHERE s.close_5d_fwd IS NOT NULL
)
SELECT
    dt.ticker,
    sr.signal,
    COUNT(*) AS n_occurrences,
    ROUND(AVG(sr.fwd_return_5d), 2) AS avg_fwd_return_5d,
    ROUND(100.0 * SUM(CASE WHEN sr.fwd_return_5d > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_rate_pct
FROM signal_returns sr
JOIN dim_ticker dt ON dt.ticker_id = sr.ticker_id
WHERE sr.signal != 'none'
GROUP BY dt. ticker, sr. signal
ORDER BY dt. ticker, sr. signal;