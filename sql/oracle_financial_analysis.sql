-- ==============================================================================
-- 프로젝트: KB Bridge 소상공인 금융상품 및 상권 분석 프로젝트
-- 담당: 2번 담당자 — 데이터 구조 점검 및 SQL 금융상품 분석
-- 데이터베이스: Oracle Database 19c / 21c 호환
-- 작성일시: 2026-09-28
-- 주요 목적:
--   1) 원본 보존 테이블 생성 및 정제 분석 뷰 구축 (날짜 변환, 상품 제약)
--   2) 금융상품 전체 요약 (건수, 고객수, 가입금액, 평균, 상품별 비중)
--   3) 업종·지역별 다차원 금융상품 요약 (대시보드 API 연계 스키마)
--   4) 상권 데이터 결합 분석 (Fan-out 방지 선집계 결합 패턴)
-- ==============================================================================

-- ==============================================================================
-- [1단계] Oracle 원본 보존 테이블 및 분석 뷰 생성
-- ==============================================================================

-- 1-1. 상권 추정매출 원본 테이블 (46,380행 적재용)
-- 원본 CSV 컬럼 순서 및 타입 완벽 보존
DROP TABLE TB_MARKET_SALES CASCADE CONSTRAINTS;

CREATE TABLE TB_MARKET_SALES (
    STD_YYQU_CD      NUMBER(5)      NOT NULL,  -- 기준_년분기_코드 (예: 20231 ~ 20254)
    ADMD_CD          NUMBER(10)     NOT NULL,  -- 행정동_코드 (예: 11110515)
    ADMD_NM          VARCHAR2(100)  NOT NULL,  -- 행정동_코드_명 (예: 청운효자동)
    INDUTY_GRP_NM    VARCHAR2(50)   NOT NULL,  -- 업종군 (11개 업종)
    THSMON_SELNG_AMT NUMBER(19)     NOT NULL,  -- 당월_매출_금액 (분기 내 월평균 또는 분기 집계액)
    THSMON_SELNG_CO  NUMBER(12)     NOT NULL,  -- 당월_매출_건수
    CONSTRAINT PK_TB_MARKET_SALES PRIMARY KEY (STD_YYQU_CD, ADMD_CD, INDUTY_GRP_NM)
);

COMMENT ON TABLE TB_MARKET_SALES IS '서울시 소상공인 상권 추정매출 원본 테이블 (2023-2025)';
COMMENT ON COLUMN TB_MARKET_SALES.STD_YYQU_CD IS '기준 년분기 코드 (YYYYQ)';
COMMENT ON COLUMN TB_MARKET_SALES.ADMD_CD IS '행정동 코드 (식별자)';
COMMENT ON COLUMN TB_MARKET_SALES.ADMD_NM IS '행정동명 (화면 표시용)';
COMMENT ON COLUMN TB_MARKET_SALES.INDUTY_GRP_NM IS '업종군명';
COMMENT ON COLUMN TB_MARKET_SALES.THSMON_SELNG_AMT IS '당월 매출 금액 (원)';
COMMENT ON COLUMN TB_MARKET_SALES.THSMON_SELNG_CO IS '당월 매출 건수';


-- 1-2. 금융상품·고객 원본 테이블 (6,000행 적재용)
DROP TABLE TB_FINANCIAL_SUBSCRIPTIONS CASCADE CONSTRAINTS;

CREATE TABLE TB_FINANCIAL_SUBSCRIPTIONS (
    SUBSCRIPTION_ID        VARCHAR2(30)   NOT NULL,  -- 가입 ID (고유 식별자, 6000건 고유)
    CUSTOMER_ID            VARCHAR2(30)   NOT NULL,  -- 고객 ID (2000명 고유)
    PRODUCT                VARCHAR2(20)   NOT NULL,  -- 금융상품 (예금, 적금, ISA, 펀드)
    AMOUNT                 NUMBER(19)     NOT NULL,  -- 가입금액 (원)
    JOINED_DATE            VARCHAR2(10)   NOT NULL,  -- 가입일자 (YYYY-MM-DD 문자열)
    ADMD_CD                NUMBER(10)     NOT NULL,  -- 행정동_코드
    REGION                 VARCHAR2(100)  NOT NULL,  -- 지역 (행정동명)
    INDUTY                 VARCHAR2(50)   NOT NULL,  -- 업종
    MKT_STD_YYQU_CD        NUMBER(5)      NOT NULL,  -- 상권_기준_년분기_코드 (20254)
    MKT_SELNG_AMT          NUMBER(19)     NOT NULL,  -- 상권_매출_금액 (반복 스냅샷)
    MKT_SELNG_CO           NUMBER(12)     NOT NULL,  -- 상권_매출_건수 (반복 스냅샷)
    MKT_SELNG_RATE         NUMBER(10, 2)  NOT NULL,  -- 상권_매출_증감률 (전분기 대비 %)
    VIRTUAL_CUST_SELNG_AMT  NUMBER(19)     NOT NULL,  -- 가상_고객_매출_금액 (고객별 반복)
    VIRTUAL_CUST_SELNG_RATE NUMBER(10, 2)  NOT NULL,  -- 가상_고객_매출_증감률
    LOAN_HOLD_YN           VARCHAR2(1)    NOT NULL,  -- 대출_보유_여부 ('Y', 'N')
    LOAN_TYPE              VARCHAR2(50)   NOT NULL,  -- 대출_종류 ('없음', '운전자금대출' 등)
    LOAN_BALANCE           NUMBER(19)     NOT NULL,  -- 대출_잔액 (원, 고객별 반복)
    MKT_COMP_KEY           VARCHAR2(100)  NOT NULL,  -- 상권_비교키 (파생키)
    CONSTRAINT PK_TB_FIN_SUBS PRIMARY KEY (SUBSCRIPTION_ID),
    CONSTRAINT CK_FIN_PRODUCT CHECK (PRODUCT IN ('예금', '적금', 'ISA', '펀드')),
    CONSTRAINT CK_FIN_LOAN_YN CHECK (LOAN_HOLD_YN IN ('Y', 'N'))
);

COMMENT ON TABLE TB_FINANCIAL_SUBSCRIPTIONS IS '소상공인 금융상품 가입 및 고객 원본 테이블';


-- 1-3. 금융상품 분석 뷰 (VW_FINANCIAL_ANALYSIS)
-- 문자열 날짜를 DATE 형으로 변환하고 식별자 정제 및 상품 검증
CREATE OR REPLACE VIEW VW_FINANCIAL_ANALYSIS AS
SELECT
    s.SUBSCRIPTION_ID,
    s.CUSTOMER_ID,
    s.PRODUCT,
    s.AMOUNT,
    TO_DATE(s.JOINED_DATE, 'YYYY-MM-DD') AS JOINED_DATE,
    TO_CHAR(TO_DATE(s.JOINED_DATE, 'YYYY-MM-DD'), 'YYYY') AS JOINED_YEAR,
    TO_CHAR(TO_DATE(s.JOINED_DATE, 'YYYY-MM-DD'), 'YYYY-MM') AS JOINED_YM,
    s.ADMD_CD AS REGION_CODE,
    s.REGION AS REGION_NAME,
    s.INDUTY AS INDUSTRY,
    s.MKT_STD_YYQU_CD AS MKT_QUARTER_CODE,
    -- 주의: 아래 상권/고객 컬럼들은 상품 행 단위 합산 시 중복 왜곡이 발생하므로 단일 참조용으로만 사용
    s.MKT_SELNG_AMT,
    s.MKT_SELNG_CO,
    s.MKT_SELNG_RATE,
    s.VIRTUAL_CUST_SELNG_AMT,
    s.VIRTUAL_CUST_SELNG_RATE,
    s.LOAN_HOLD_YN,
    s.LOAN_TYPE,
    s.LOAN_BALANCE
FROM TB_FINANCIAL_SUBSCRIPTIONS s;


-- 1-4. 상권 추정매출 분석 뷰 (VW_MARKET_SALES_CLEAN)
CREATE OR REPLACE VIEW VW_MARKET_SALES_CLEAN AS
SELECT
    STD_YYQU_CD AS QUARTER_CODE,
    ADMD_CD AS REGION_CODE,
    ADMD_NM AS REGION_NAME,
    INDUTY_GRP_NM AS INDUSTRY,
    THSMON_SELNG_AMT AS MARKET_SALES_AMT,
    THSMON_SELNG_CO AS MARKET_SALES_CNT,
    ROUND(THSMON_SELNG_AMT / NULLIF(THSMON_SELNG_CO, 0), 0) AS MARKET_AVG_TICKET_AMT
FROM TB_MARKET_SALES;


-- ==============================================================================
-- [2단계] 상품 전체 요약 (Product Overall Summary)
-- 지표: 가입건수, 이용고객수, 가입금액 합계, 건당 평균, 고객당 평균, 건수비중, 고객비중, 금액비중
-- ==============================================================================

SELECT
    PRODUCT AS product_type,
    COUNT(*) AS subscription_count,
    COUNT(DISTINCT CUSTOMER_ID) AS unique_customer_count,
    SUM(AMOUNT) AS total_amount,
    ROUND(AVG(AMOUNT), 2) AS avg_subscription_amount,
    ROUND(SUM(AMOUNT) / COUNT(DISTINCT CUSTOMER_ID), 2) AS avg_amount_per_customer,
    -- 비중 계산 (윈도우 함수 SUM() OVER () 활용)
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS subscription_share_pct,
    ROUND(COUNT(DISTINCT CUSTOMER_ID) * 100.0 / (SELECT COUNT(DISTINCT CUSTOMER_ID) FROM TB_FINANCIAL_SUBSCRIPTIONS), 2) AS customer_share_pct,
    ROUND(SUM(AMOUNT) * 100.0 / SUM(SUM(AMOUNT)) OVER (), 2) AS amount_share_pct
FROM VW_FINANCIAL_ANALYSIS
GROUP BY PRODUCT
ORDER BY total_amount DESC;


-- ==============================================================================
-- [3단계] 업종·지역별 상품 요약 (Multi-Dimensional Summaries)
-- ==============================================================================

-- 3-1. 행정동 코드 + 지역 + 업종 + 상품 단위 요약 (Section 11 대시보드 API 반환 스키마와 100% 일치)
WITH base_product_agg AS (
    SELECT
        REGION_CODE,
        REGION_NAME,
        INDUSTRY,
        PRODUCT AS PRODUCT_TYPE,
        COUNT(*) AS SUBSCRIPTION_COUNT,
        COUNT(DISTINCT CUSTOMER_ID) AS UNIQUE_CUSTOMER_COUNT,
        SUM(AMOUNT) AS TOTAL_AMOUNT,
        ROUND(AVG(AMOUNT), 2) AS AVG_SUBSCRIPTION_AMOUNT,
        ROUND(SUM(AMOUNT) / COUNT(DISTINCT CUSTOMER_ID), 2) AS AVG_AMOUNT_PER_CUSTOMER
    FROM VW_FINANCIAL_ANALYSIS
    GROUP BY REGION_CODE, REGION_NAME, INDUSTRY, PRODUCT
),
group_totals AS (
    -- 동일 (행정동_코드, 업종) 그룹 내 총계 산출 (비중 계산 분모)
    SELECT
        REGION_CODE,
        INDUSTRY,
        COUNT(*) AS GRP_SUB_TOTAL,
        COUNT(DISTINCT CUSTOMER_ID) AS GRP_CUST_TOTAL,
        SUM(AMOUNT) AS GRP_AMT_TOTAL
    FROM VW_FINANCIAL_ANALYSIS
    GROUP BY REGION_CODE, INDUSTRY
)
SELECT
    b.REGION_CODE,
    b.REGION_NAME,
    b.INDUSTRY,
    b.PRODUCT_TYPE,
    b.SUBSCRIPTION_COUNT,
    b.UNIQUE_CUSTOMER_COUNT,
    b.TOTAL_AMOUNT,
    b.AVG_SUBSCRIPTION_AMOUNT,
    b.AVG_AMOUNT_PER_CUSTOMER,
    ROUND(b.SUBSCRIPTION_COUNT * 100.0 / g.GRP_SUB_TOTAL, 2) AS SUBSCRIPTION_SHARE_PCT,
    ROUND(b.UNIQUE_CUSTOMER_COUNT * 100.0 / g.GRP_CUST_TOTAL, 2) AS CUSTOMER_SHARE_PCT,
    ROUND(b.TOTAL_AMOUNT * 100.0 / g.GRP_AMT_TOTAL, 2) AS AMOUNT_SHARE_PCT
FROM base_product_agg b
INNER JOIN group_totals g
    ON b.REGION_CODE = g.REGION_CODE
   AND b.INDUSTRY = g.INDUSTRY
ORDER BY b.REGION_CODE, b.INDUSTRY, b.PRODUCT_TYPE;


-- 3-2. 업종 전체 금융상품 요약 (11개 업종별 포트폴리오 분석)
SELECT
    INDUSTRY,
    PRODUCT AS PRODUCT_TYPE,
    COUNT(*) AS SUBSCRIPTION_COUNT,
    COUNT(DISTINCT CUSTOMER_ID) AS UNIQUE_CUSTOMER_COUNT,
    SUM(AMOUNT) AS TOTAL_AMOUNT,
    ROUND(AVG(AMOUNT), 2) AS AVG_SUBSCRIPTION_AMOUNT,
    ROUND(SUM(AMOUNT) / COUNT(DISTINCT CUSTOMER_ID), 2) AS AVG_AMOUNT_PER_CUSTOMER,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY INDUSTRY), 2) AS SUBSCRIPTION_SHARE_PCT,
    ROUND(SUM(AMOUNT) * 100.0 / SUM(SUM(AMOUNT)) OVER (PARTITION BY INDUSTRY), 2) AS AMOUNT_SHARE_PCT
FROM VW_FINANCIAL_ANALYSIS
GROUP BY INDUSTRY, PRODUCT
ORDER BY INDUSTRY, TOTAL_AMOUNT DESC;


-- 3-3. 지역 전체 금융상품 요약 (418개 행정동별 포트폴리오 분석)
SELECT
    REGION_CODE,
    REGION_NAME,
    PRODUCT AS PRODUCT_TYPE,
    COUNT(*) AS SUBSCRIPTION_COUNT,
    COUNT(DISTINCT CUSTOMER_ID) AS UNIQUE_CUSTOMER_COUNT,
    SUM(AMOUNT) AS TOTAL_AMOUNT,
    ROUND(AVG(AMOUNT), 2) AS AVG_SUBSCRIPTION_AMOUNT,
    ROUND(SUM(AMOUNT) / COUNT(DISTINCT CUSTOMER_ID), 2) AS AVG_AMOUNT_PER_CUSTOMER,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY REGION_CODE), 2) AS SUBSCRIPTION_SHARE_PCT,
    ROUND(SUM(AMOUNT) * 100.0 / SUM(SUM(AMOUNT)) OVER (PARTITION BY REGION_CODE), 2) AS AMOUNT_SHARE_PCT
FROM VW_FINANCIAL_ANALYSIS
GROUP BY REGION_CODE, REGION_NAME, PRODUCT
ORDER BY REGION_CODE, TOTAL_AMOUNT DESC;


-- 3-4. Oracle GROUPING SETS를 활용한 다차원 계층 집계 단일 쿼리
-- (업종x지역x상품, 업종x상품, 지역x상품, 상품 전체를 한 번에 인출)
SELECT
    GROUPING_ID(INDUSTRY, REGION_CODE, PRODUCT) AS GROUPING_LEVEL,
    CASE
        WHEN GROUPING(INDUSTRY) = 1 AND GROUPING(REGION_CODE) = 1 THEN '전체'
        WHEN GROUPING(REGION_CODE) = 1 THEN INDUSTRY
        ELSE INDUSTRY
    END AS INDUSTRY,
    CASE
        WHEN GROUPING(REGION_CODE) = 1 THEN '전체지역'
        ELSE TO_CHAR(REGION_CODE)
    END AS REGION_CODE,
    PRODUCT,
    COUNT(*) AS SUBSCRIPTION_COUNT,
    COUNT(DISTINCT CUSTOMER_ID) AS UNIQUE_CUSTOMER_COUNT,
    SUM(AMOUNT) AS TOTAL_AMOUNT,
    ROUND(AVG(AMOUNT), 2) AS AVG_SUBSCRIPTION_AMOUNT,
    ROUND(SUM(AMOUNT) / COUNT(DISTINCT CUSTOMER_ID), 2) AS AVG_AMOUNT_PER_CUSTOMER
FROM VW_FINANCIAL_ANALYSIS
GROUP BY GROUPING SETS (
    (INDUSTRY, REGION_CODE, PRODUCT),  -- 세부 집계
    (INDUSTRY, PRODUCT),               -- 업종별 소계
    (REGION_CODE, PRODUCT),             -- 지역별 소계
    (PRODUCT)                          -- 상품별 총계
)
ORDER BY GROUPING_LEVEL, INDUSTRY, REGION_CODE, TOTAL_AMOUNT DESC;


-- ==============================================================================
-- [4단계] 상권 데이터 결합 분석 (Safe CTE Pre-Aggregation Join)
-- 원칙: 금융상품 데이터와 상권 매출 데이터를 각 소스 레벨에서 선집계 후
--      (기준분기, 행정동코드, 업종) 복합키로 1:1 결합하여 중복합산(Fan-out) 완벽 차단
-- ==============================================================================

WITH fin_zone_agg AS (
    -- 상권 단위(기준분기 + 행정동코드 + 업종) 금융상품 지표 집계
    SELECT
        MKT_QUARTER_CODE AS QUARTER_CODE,
        REGION_CODE,
        REGION_NAME,
        INDUSTRY,
        COUNT(*) AS FIN_SUB_COUNT,
        COUNT(DISTINCT CUSTOMER_ID) AS FIN_CUST_COUNT,
        SUM(AMOUNT) AS FIN_TOTAL_AMOUNT,
        ROUND(AVG(AMOUNT), 2) AS FIN_AVG_SUB_AMOUNT,
        -- 상품별 가입액 피벗
        SUM(CASE WHEN PRODUCT = '예금' THEN AMOUNT ELSE 0 END) AS AMT_DEPOSIT,
        SUM(CASE WHEN PRODUCT = '적금' THEN AMOUNT ELSE 0 END) AS AMT_SAVINGS,
        SUM(CASE WHEN PRODUCT = 'ISA'  THEN AMOUNT ELSE 0 END) AS AMT_ISA,
        SUM(CASE WHEN PRODUCT = '펀드' THEN AMOUNT ELSE 0 END) AS AMT_FUND
    FROM VW_FINANCIAL_ANALYSIS
    GROUP BY MKT_QUARTER_CODE, REGION_CODE, REGION_NAME, INDUSTRY
),
mkt_zone_sales AS (
    -- 상권 테이블에서 2025년 4분기 기준 데이터 추출 (1 행정동 x 1 업종당 정확히 1행)
    SELECT
        QUARTER_CODE,
        REGION_CODE,
        REGION_NAME,
        INDUSTRY,
        MARKET_SALES_AMT,
        MARKET_SALES_CNT,
        MARKET_AVG_TICKET_AMT
    FROM VW_MARKET_SALES_CLEAN
    WHERE QUARTER_CODE = 20254
)
SELECT
    f.QUARTER_CODE,
    f.REGION_CODE,
    f.REGION_NAME,
    f.INDUSTRY,
    -- 금융 지표
    f.FIN_SUB_COUNT,
    f.FIN_CUST_COUNT,
    f.FIN_TOTAL_AMOUNT,
    f.FIN_AVG_SUB_AMOUNT,
    f.AMT_DEPOSIT,
    f.AMT_SAVINGS,
    f.AMT_ISA,
    f.AMT_FUND,
    -- 상권 지표 (중복 없이 정확한 1:1 값)
    m.MARKET_SALES_AMT,
    m.MARKET_SALES_CNT,
    m.MARKET_AVG_TICKET_AMT,
    -- 결합 파생 분석 지표: 상권 매출액 대비 금융상품 가입액 비율 (%)
    ROUND(f.FIN_TOTAL_AMOUNT * 100.0 / NULLIF(m.MARKET_SALES_AMT, 0), 4) AS FIN_TO_MKT_SALES_RATIO_PCT
FROM fin_zone_agg f
INNER JOIN mkt_zone_sales m
    ON f.QUARTER_CODE = m.QUARTER_CODE
   AND f.REGION_CODE  = m.REGION_CODE
   AND f.INDUSTRY     = m.INDUSTRY
ORDER BY f.FIN_TOTAL_AMOUNT DESC;
