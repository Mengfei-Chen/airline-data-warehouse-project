--先创建数据库表 First create the database table
DROP TABLE IF EXISTS stg_airline_raw;

CREATE TABLE stg_airline_raw (
    passenger_id_text           TEXT,
    first_name                  TEXT,
    last_name                   TEXT,
    gender                      TEXT,
    age_text                    TEXT,
    nationality                 TEXT,
    airport_name                TEXT,
    airport_country_code        TEXT,
    country_name                TEXT,
    airport_continent_code      TEXT,
    continent_name              TEXT,
    departure_date_text         TEXT,
    arrival_airport_code        TEXT,
    pilot_name                  TEXT,
    flight_status               TEXT
);

--检查 SQL Check SQL
SELECT COUNT(*) AS row_count
FROM stg_airline_raw; 

--再做一个样本检查 Perform another sample check
SELECT *
FROM stg_airline_raw
LIMIT 10;

--创建一个清洗后的暂存表 Create a cleaned temporary table
DROP TABLE IF EXISTS stg_airline_clean;

CREATE TABLE stg_airline_clean AS
SELECT
    passenger_id_text,
    first_name,
    last_name,
    gender,
    CASE
        WHEN age_text ~ '^\d+$' THEN age_text::INT
        ELSE NULL
    END AS age,
    nationality,
    airport_name,
    airport_country_code,
    country_name,
    airport_continent_code,
    continent_name,
    departure_date_text,
    CASE
        WHEN departure_date_text ~ '^\d{1,2}/\d{1,2}/\d{4}$'
            THEN TO_DATE(departure_date_text, 'MM/DD/YYYY')
        WHEN departure_date_text ~ '^\d{1,2}-\d{1,2}-\d{4}$'
            THEN TO_DATE(departure_date_text, 'MM-DD-YYYY')
        ELSE NULL
    END AS departure_date,
    arrival_airport_code,
    pilot_name,
    flight_status
FROM stg_airline_raw;

--检查日期有没有成功解析 Check if the date was successfully parsed
SELECT
    COUNT(*) AS total_rows,
    COUNT(departure_date) AS parsed_date_rows,
    COUNT(*) - COUNT(departure_date) AS null_date_rows
FROM stg_airline_clean;

--看清洗后的日期 Check the date after cleaning
SELECT
    departure_date_text,
    departure_date
FROM stg_airline_clean
LIMIT 20;

--创建dim_date Create dim_date
DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date AS
SELECT DISTINCT
    TO_CHAR(departure_date, 'YYYYMMDD')::INT AS date_key,
    departure_date AS full_date,
    EXTRACT(DAY FROM departure_date)::INT AS day,
    EXTRACT(MONTH FROM departure_date)::INT AS month,
    TO_CHAR(departure_date, 'Month') AS month_name,
    EXTRACT(QUARTER FROM departure_date)::INT AS quarter,
    EXTRACT(YEAR FROM departure_date)::INT AS year,
    TO_CHAR(departure_date, 'Day') AS weekday_name,
    CASE
        WHEN EXTRACT(ISODOW FROM departure_date) IN (6, 7) THEN 'Yes'
        ELSE 'No'
    END AS weekend_flag
FROM stg_airline_clean
WHERE departure_date IS NOT NULL;

--一共有多少行 How many lines 
SELECT COUNT(*) AS date_row_count
FROM dim_date;

--前几行长什么样 The first few lines
SELECT *
FROM dim_date
ORDER BY full_date
LIMIT 10;

--创建 dim_passenger Create dim_passenger
DROP TABLE IF EXISTS dim_passenger;

CREATE TABLE dim_passenger AS
SELECT
    ROW_NUMBER() OVER (ORDER BY passenger_id_text) AS passenger_key,
    passenger_id_text AS passenger_id,
    first_name,
    last_name,
    gender,
    age,
    CASE
        WHEN age IS NULL THEN 'Unknown'
        WHEN age < 18 THEN 'Child'
        WHEN age BETWEEN 18 AND 29 THEN 'Young Adult'
        WHEN age BETWEEN 30 AND 49 THEN 'Adult'
        WHEN age BETWEEN 50 AND 64 THEN 'Middle Aged'
        ELSE 'Senior'
    END AS age_group,
    nationality
FROM (
    SELECT DISTINCT
        passenger_id_text,
        first_name,
        last_name,
        gender,
        age,
        nationality
    FROM stg_airline_clean
) t;

-- Total number of rows
SELECT COUNT(*) AS passenger_row_count
FROM dim_passenger;

--看前几行 Look at the first few lines
SELECT *
FROM dim_passenger
LIMIT 10;

--看 age_group 分布 See the age_group distribution
SELECT age_group, COUNT(*) AS cnt
FROM dim_passenger
GROUP BY age_group
ORDER BY cnt DESC;

--创建 dim_departure_airport create dim_departure_airport
DROP TABLE IF EXISTS dim_departure_airport;

CREATE TABLE dim_departure_airport AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY airport_name, airport_country_code, country_name, airport_continent_code, continent_name
    ) AS departure_airport_key,
    airport_name,
    airport_country_code,
    country_name,
    airport_continent_code,
    continent_name
FROM (
    SELECT DISTINCT
        airport_name,
        airport_country_code,
        country_name,
        airport_continent_code,
        continent_name
    FROM stg_airline_clean
) t;

--创建 dim_flight_status create dim_flight_status
DROP TABLE IF EXISTS dim_flight_status;

CREATE TABLE dim_flight_status AS
SELECT
    ROW_NUMBER() OVER (ORDER BY flight_status) AS status_key,
    flight_status
FROM (
    SELECT DISTINCT flight_status
    FROM stg_airline_clean
) t;

--检查 1
SELECT COUNT(*) AS departure_airport_row_count
FROM dim_departure_airport;

--看前几行
SELECT *
FROM dim_departure_airport
LIMIT 10;

--检查2
SELECT COUNT(*) AS status_row_count
FROM dim_flight_status;

--看status 内容
SELECT *
FROM dim_flight_status
ORDER BY status_key;

--创建 dim_arrival_airport 
DROP TABLE IF EXISTS dim_arrival_airport;

CREATE TABLE dim_arrival_airport AS
SELECT
    ROW_NUMBER() OVER (ORDER BY arrival_airport_code) AS arrival_airport_key,
    arrival_airport_code
FROM (
    SELECT DISTINCT arrival_airport_code
    FROM stg_airline_clean
) t;

--创建 dim_pilot
DROP TABLE IF EXISTS dim_pilot;

CREATE TABLE dim_pilot AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pilot_name) AS pilot_key,
    pilot_name
FROM (
    SELECT DISTINCT pilot_name
    FROM stg_airline_clean
) t;

--检查 1：arrival 机场维表总行数
SELECT COUNT(*) AS arrival_airport_row_count
FROM dim_arrival_airport;

--检查 2：看前几行
SELECT *
FROM dim_arrival_airport
LIMIT 10;

--检查 3：pilot 维表总行数
SELECT COUNT(*) AS pilot_row_count
FROM dim_pilot;

--检查 4：看前几行
SELECT *
FROM dim_pilot
LIMIT 10;

--创建事实表 fact_flight
DROP TABLE IF EXISTS fact_flight;

CREATE TABLE fact_flight AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY
            s.passenger_id_text,
            s.departure_date,
            s.airport_name,
            s.arrival_airport_code,
            s.pilot_name,
            s.flight_status
    ) AS flight_fact_key,
    p.passenger_key,
    d.date_key,
    da.departure_airport_key,
    aa.arrival_airport_key,
    pi.pilot_key,
    fs.status_key,
    1 AS passenger_count
FROM stg_airline_clean s
JOIN dim_passenger p
    ON s.passenger_id_text = p.passenger_id
   AND s.first_name = p.first_name
   AND s.last_name = p.last_name
   AND s.gender = p.gender
   AND (
        (s.age = p.age)
        OR (s.age IS NULL AND p.age IS NULL)
   )
   AND s.nationality = p.nationality
JOIN dim_date d
    ON s.departure_date = d.full_date
JOIN dim_departure_airport da
    ON s.airport_name = da.airport_name
   AND s.airport_country_code = da.airport_country_code
   AND s.country_name = da.country_name
   AND s.airport_continent_code = da.airport_continent_code
   AND s.continent_name = da.continent_name
JOIN dim_arrival_airport aa
    ON s.arrival_airport_code = aa.arrival_airport_code
JOIN dim_pilot pi
    ON s.pilot_name = pi.pilot_name
JOIN dim_flight_status fs
    ON s.flight_status = fs.flight_status;

--检查 1：事实表总行数
SELECT COUNT(*) AS fact_row_count
FROM fact_flight;

--看前几行
SELECT * FROM fact_flight
LIMIT 10;

--确定measure
SELECT passenger_count, COUNT(*) AS cnt
FROM fact_flight
GROUP BY passenger_count;

--第一个业务查询
--不同 Flight Status 的总体分布
SELECT
    fs.flight_status,
    SUM(f.passenger_count) AS total_records
FROM fact_flight f
JOIN dim_flight_status fs
    ON f.status_key = fs.status_key
GROUP BY fs.flight_status
ORDER BY total_records DESC;

--交叉检查
SELECT SUM(total_records) AS grand_total
FROM (
    SELECT
        fs.flight_status,
        SUM(f.passenger_count) AS total_records
    FROM fact_flight f
    JOIN dim_flight_status fs
        ON f.status_key = fs.status_key
    GROUP BY fs.flight_status
) t;

--第二个业务查询
--洲际级航班状态分析查询
SELECT
    da.continent_name,
    fs.flight_status,
    SUM(f.passenger_count) AS total_records
FROM fact_flight f
JOIN dim_departure_airport da
    ON f.departure_airport_key = da.departure_airport_key
JOIN dim_flight_status fs
    ON f.status_key = fs.status_key
GROUP BY da.continent_name, fs.flight_status
ORDER BY da.continent_name, total_records DESC;

--检查
SELECT
    da.continent_name,
    SUM(f.passenger_count) AS continent_total
FROM fact_flight f
JOIN dim_departure_airport da
    ON f.departure_airport_key = da.departure_airport_key
GROUP BY da.continent_name
ORDER BY continent_total DESC;

--第三个业务查询
--按月分析航班状态分布
SELECT
    d.month,
    TRIM(d.month_name) AS month_name,
    fs.flight_status,
    SUM(f.passenger_count) AS total_records
FROM fact_flight f
JOIN dim_date d
    ON f.date_key = d.date_key
JOIN dim_flight_status fs
    ON f.status_key = fs.status_key
GROUP BY d.month, TRIM(d.month_name), fs.flight_status
ORDER BY d.month, fs.flight_status;

--总量检查
SELECT
    d.month,
    TRIM(d.month_name) AS month_name,
    SUM(f.passenger_count) AS month_total
FROM fact_flight f
JOIN dim_date d
    ON f.date_key = d.date_key
GROUP BY d.month, TRIM(d.month_name)
ORDER BY d.month;

--第四个业务查询
--按年龄组分析航班状态分布
SELECT
    p.age_group,
    fs.flight_status,
    SUM(f.passenger_count) AS total_records
FROM fact_flight f
JOIN dim_passenger p
    ON f.passenger_key = p.passenger_key
JOIN dim_flight_status fs
    ON f.status_key = fs.status_key
GROUP BY p.age_group, fs.flight_status
ORDER BY p.age_group, fs.flight_status；

--总量检查
SELECT
    p.age_group,
    SUM(f.passenger_count) AS age_group_total
FROM fact_flight f
JOIN dim_passenger p
    ON f.passenger_key = p.passenger_key
GROUP BY p.age_group
ORDER BY age_group_total DESC;
