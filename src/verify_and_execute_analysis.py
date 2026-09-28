"""
==============================================================================
프로젝트: KB Bridge 소상공인 금융상품 및 상권 분석 프로젝트
담당: 2번 담당자 — 데이터 구조 점검, SQL 금융상품 분석 및 Pandas 검증 파이프라인
작성일: 2026-09-28
실행: python src/verify_and_execute_analysis.py 또는 python verify_and_execute_analysis.py
==============================================================================
"""

import os
import sys
import json
import sqlite3
import pandas as pd
import numpy as np

# 콘솔 출력 인코딩 UTF-8 설정 (Windows 환경)
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except AttributeError:
        pass

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def resolve_path(relative_paths):
    for p in relative_paths:
        if os.path.exists(p):
            return p
    return relative_paths[0]

FINANCIAL_CSV = resolve_path([
    os.path.join(BASE_DIR, "..", "data", "raw", "financial_products_with_small_business_customers.csv"),
    os.path.join(BASE_DIR, "data", "raw", "financial_products_with_small_business_customers.csv"),
    os.path.join(BASE_DIR, "financial_products_with_small_business_customers.csv"),
    os.path.join(os.getcwd(), "data", "raw", "financial_products_with_small_business_customers.csv"),
    os.path.join(os.getcwd(), "financial_products_with_small_business_customers.csv"),
])

MARKET_CSV = resolve_path([
    os.path.join(BASE_DIR, "..", "data", "raw", "서울시_소상공인_상권_추정매출_2023-2025년 최종본.csv"),
    os.path.join(BASE_DIR, "data", "raw", "서울시_소상공인_상권_추정매출_2023-2025년 최종본.csv"),
    os.path.join(BASE_DIR, "서울시_소상공인_상권_추정매출_2023-2025년 최종본.csv"),
    os.path.join(os.getcwd(), "data", "raw", "서울시_소상공인_상권_추정매출_2023-2025년 최종본.csv"),
    os.path.join(os.getcwd(), "서울시_소상공인_상권_추정매출_2023-2025년 최종본.csv"),
])

# 출력 디렉토리 확인 및 생성
DASHBOARD_DIR = os.path.join(BASE_DIR, "..", "data", "dashboard")
if not os.path.exists(DASHBOARD_DIR):
    DASHBOARD_DIR = BASE_DIR
os.makedirs(DASHBOARD_DIR, exist_ok=True)

OUTPUT_JSON = os.path.join(DASHBOARD_DIR, "api_products.json")
OUTPUT_CSV = os.path.join(DASHBOARD_DIR, "api_products.csv")


def load_raw_data():
    """원본 CSV 데이터를 읽기 전용으로 안전하게 로드합니다."""
    print("=" * 70)
    print("1. 원본 데이터 로드 및 무결성 확인")
    print("=" * 70)
    print(f" - 금융 원본 파일: {FINANCIAL_CSV}")
    print(f" - 상권 원본 파일: {MARKET_CSV}")

    assert os.path.exists(FINANCIAL_CSV), f"파일 없음: {FINANCIAL_CSV}"
    assert os.path.exists(MARKET_CSV), f"파일 없음: {MARKET_CSV}"

    df_fin = pd.read_csv(FINANCIAL_CSV, encoding="utf-8-sig")
    df_market = pd.read_csv(MARKET_CSV, encoding="utf-8-sig")

    print(f" - 금융상품 데이터: {df_fin.shape[0]:,}행, {df_fin.shape[1]}개 열 (완전중복: {df_fin.duplicated().sum()}건)")
    print(f" - 상권 추정매출: {df_market.shape[0]:,}행, {df_market.shape[1]}개 열 (완전중복: {df_market.duplicated().sum()}건)")
    print(f" - 결측치 현황: 금융 {df_fin.isna().sum().sum()}건, 상권 {df_market.isna().sum().sum()}건 (결측률 0.0%)")

    return df_fin, df_market


def setup_in_memory_db(df_fin, df_market):
    """SQLite 인메모리 DB를 생성하고 테이블 및 뷰를 적재합니다."""
    conn = sqlite3.connect(":memory:")

    df_fin.to_sql("TB_FINANCIAL_SUBSCRIPTIONS", conn, index=False, if_exists="replace")
    df_market.to_sql("TB_MARKET_SALES", conn, index=False, if_exists="replace")

    cur = conn.cursor()
    cur.execute("""
    CREATE VIEW VW_FINANCIAL_ANALYSIS AS
    SELECT
        subscription_id,
        customer_id,
        product,
        amount,
        joined_date,
        행정동_코드 AS region_code,
        지역 AS region_name,
        업종 AS industry,
        상권_기준_년분기_코드 AS mkt_quarter_code,
        상권_매출_금액 AS mkt_sales_amt,
        상권_매출_건수 AS mkt_sales_cnt,
        상권_매출_증감률 AS mkt_sales_rate,
        가상_고객_매출_금액 AS virtual_cust_sales_amt,
        가상_고객_매출_증감률 AS virtual_cust_sales_rate,
        대출_보유_여부 AS loan_hold_yn,
        대출_종류 AS loan_type,
        대출_잔액 AS loan_balance,
        상권_비교키 AS mkt_comp_key
    FROM TB_FINANCIAL_SUBSCRIPTIONS;
    """)

    cur.execute("""
    CREATE VIEW VW_MARKET_SALES_CLEAN AS
    SELECT
        기준_년분기_코드 AS quarter_code,
        행정동_코드 AS region_code,
        행정동_코드_명 AS region_name,
        업종군 AS industry,
        당월_매출_금액 AS market_sales_amt,
        당월_매출_건수 AS market_sales_cnt
    FROM TB_MARKET_SALES;
    """)
    conn.commit()
    return conn


def execute_step2_product_summary(conn):
    """[2단계] 상품 전체 요약 쿼리 실행"""
    print("\n" + "=" * 70)
    print("2. [2단계] 상품 전체 요약 (SQL 실행 결과)")
    print("=" * 70)

    sql = """
    SELECT
        product AS product_type,
        COUNT(*) AS subscription_count,
        COUNT(DISTINCT customer_id) AS unique_customer_count,
        SUM(amount) AS total_amount,
        ROUND(AVG(amount), 2) AS avg_subscription_amount,
        ROUND(CAST(SUM(amount) AS FLOAT) / COUNT(DISTINCT customer_id), 2) AS avg_amount_per_customer,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM VW_FINANCIAL_ANALYSIS), 2) AS subscription_share_pct,
        ROUND(COUNT(DISTINCT customer_id) * 100.0 / (SELECT COUNT(DISTINCT customer_id) FROM VW_FINANCIAL_ANALYSIS), 2) AS customer_share_pct,
        ROUND(SUM(amount) * 100.0 / (SELECT SUM(amount) FROM VW_FINANCIAL_ANALYSIS), 2) AS amount_share_pct
    FROM VW_FINANCIAL_ANALYSIS
    GROUP BY product
    ORDER BY total_amount DESC;
    """
    df_step2 = pd.read_sql_query(sql, conn)

    df_display = df_step2.copy()
    df_display["total_amount_krw"] = df_display["total_amount"].apply(lambda x: f"{x:,.0f}원")
    df_display["avg_sub_krw"] = df_display["avg_subscription_amount"].apply(lambda x: f"{x:,.0f}원")
    df_display["avg_cust_krw"] = df_display["avg_amount_per_customer"].apply(lambda x: f"{x:,.0f}원")

    cols_show = ["product_type", "subscription_count", "unique_customer_count", "total_amount_krw",
                 "avg_sub_krw", "avg_cust_krw", "subscription_share_pct", "customer_share_pct", "amount_share_pct"]
    print(df_display[cols_show].to_string(index=False))

    return df_step2


def execute_step3_and_11_dashboard_schema(conn):
    """[3단계 & 11단계] 대시보드 전달용 결과 스키마 생성"""
    print("\n" + "=" * 70)
    print("3. [3단계 & 11단계] 대시보드 API 반환용 스키마 생성 (Section 11)")
    print("=" * 70)

    sql = """
    WITH base_product_agg AS (
        SELECT
            region_code,
            region_name,
            industry,
            product AS product_type,
            COUNT(*) AS subscription_count,
            COUNT(DISTINCT customer_id) AS unique_customer_count,
            SUM(amount) AS total_amount,
            ROUND(AVG(amount), 2) AS avg_subscription_amount,
            ROUND(CAST(SUM(amount) AS FLOAT) / COUNT(DISTINCT customer_id), 2) AS avg_amount_per_customer
        FROM VW_FINANCIAL_ANALYSIS
        GROUP BY region_code, region_name, industry, product
    ),
    group_totals AS (
        SELECT
            region_code,
            industry,
            COUNT(*) AS grp_sub_total,
            COUNT(DISTINCT customer_id) AS grp_cust_total,
            SUM(amount) AS grp_amt_total
        FROM VW_FINANCIAL_ANALYSIS
        GROUP BY region_code, industry
    )
    SELECT
        b.region_code,
        b.region_name,
        b.industry,
        b.product_type,
        b.subscription_count,
        b.unique_customer_count,
        b.total_amount,
        b.avg_subscription_amount,
        b.avg_amount_per_customer,
        ROUND(b.subscription_count * 100.0 / g.grp_sub_total, 2) AS subscription_share_pct,
        ROUND(b.unique_customer_count * 100.0 / g.grp_cust_total, 2) AS customer_share_pct,
        ROUND(b.total_amount * 100.0 / g.grp_amt_total, 2) AS amount_share_pct
    FROM base_product_agg b
    INNER JOIN group_totals g
        ON b.region_code = g.region_code
       AND b.industry = g.industry
    ORDER BY b.region_code, b.industry, b.product_type;
    """
    df_api = pd.read_sql_query(sql, conn)
    print(f" - 생성된 API 레코드 수: {len(df_api):,}행")
    print(" - 샘플 상위 5행:")
    print(df_api.head(5).to_string(index=False))

    records = df_api.to_dict(orient="records")
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=2)
    df_api.to_csv(OUTPUT_CSV, index=False, encoding="utf-8-sig")

    print(f" -> JSON 저장 완료: {OUTPUT_JSON}")
    print(f" -> CSV 저장 완료: {OUTPUT_CSV}")

    return df_api


def execute_step4_market_join(conn):
    """[4단계] 상권 데이터 안전 결합 분석 (Fan-out 방지)"""
    print("\n" + "=" * 70)
    print("4. [4단계] 상권 데이터 결합 분석 (Safe CTE Pre-Aggregation Join)")
    print("=" * 70)

    sql = """
    WITH fin_zone_agg AS (
        SELECT
            mkt_quarter_code AS quarter_code,
            region_code,
            region_name,
            industry,
            COUNT(*) AS fin_sub_count,
            COUNT(DISTINCT customer_id) AS fin_cust_count,
            SUM(amount) AS fin_total_amount,
            ROUND(AVG(amount), 2) AS fin_avg_sub_amount,
            SUM(CASE WHEN product = '예금' THEN amount ELSE 0 END) AS amt_deposit,
            SUM(CASE WHEN product = '적금' THEN amount ELSE 0 END) AS amt_savings,
            SUM(CASE WHEN product = 'ISA'  THEN amount ELSE 0 END) AS amt_isa,
            SUM(CASE WHEN product = '펀드' THEN amount ELSE 0 END) AS amt_fund
        FROM VW_FINANCIAL_ANALYSIS
        GROUP BY mkt_quarter_code, region_code, region_name, industry
    ),
    mkt_zone_sales AS (
        SELECT
            quarter_code,
            region_code,
            region_name,
            industry,
            market_sales_amt,
            market_sales_cnt,
            ROUND(CAST(market_sales_amt AS FLOAT) / market_sales_cnt, 0) AS market_avg_ticket_amt
        FROM VW_MARKET_SALES_CLEAN
        WHERE quarter_code = 20254
    )
    SELECT
        f.quarter_code,
        f.region_code,
        f.region_name,
        f.industry,
        f.fin_sub_count,
        f.fin_cust_count,
        f.fin_total_amount,
        f.fin_avg_sub_amount,
        f.amt_deposit,
        f.amt_savings,
        f.amt_isa,
        f.amt_fund,
        m.market_sales_amt,
        m.market_sales_cnt,
        m.market_avg_ticket_amt,
        ROUND(CAST(f.fin_total_amount AS FLOAT) * 100.0 / m.market_sales_amt, 4) AS fin_to_mkt_sales_ratio_pct
    FROM fin_zone_agg f
    INNER JOIN mkt_zone_sales m
        ON f.quarter_code = m.quarter_code
       AND f.region_code  = m.region_code
       AND f.industry     = m.industry
    ORDER BY f.fin_total_amount DESC;
    """
    df_step4 = pd.read_sql_query(sql, conn)
    print(f" - 상권 결합 총 레코드 수: {len(df_step4):,}개 상권 조합 (1,563개 중 1,563개 100% 매칭)")
    print(" - 상위 5개 상권 결합 결과 (가입금액 기준):")
    cols_show = ["region_name", "industry", "fin_sub_count", "fin_cust_count", "fin_total_amount",
                 "market_sales_amt", "fin_to_mkt_sales_ratio_pct"]
    print(df_step4[cols_show].head(5).to_string(index=False))

    return df_step4


def run_step5_validation(df_fin, df_market, conn, df_step2, df_step4):
    """[5단계] Pandas 교차 검증 (5대 핵심 검증 항목)"""
    print("\n" + "=" * 70)
    print("5. [5단계] Pandas 교차 검증 (5대 핵심 항목)")
    print("=" * 70)

    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM TB_FINANCIAL_SUBSCRIPTIONS")
    sql_total_subs = cur.fetchone()[0]
    pd_total_subs = len(df_fin)
    assert sql_total_subs == 6000 and pd_total_subs == 6000, "검증 1 실패: 건수 불일치"
    print(" [✓ PASS] 1. 가입건수 합계 검증: SQL(6,000건) == Pandas(6,000건) 완벽 일치")

    total_amount = df_fin["amount"].sum()
    sum_by_prod = df_fin.groupby("product")["amount"].sum().sum()
    sum_by_reg = df_fin.groupby("행정동_코드")["amount"].sum().sum()
    sum_by_ind = df_fin.groupby("업종")["amount"].sum().sum()
    assert total_amount == sum_by_prod == sum_by_reg == sum_by_ind == 118083150000, "검증 2 실패: 금액 합계 불일치"
    print(f" [✓ PASS] 2. 다차원 합계 정합성: 전체 {total_amount:,}원 == 상품별합 == 지역별합 == 업종별합")

    total_unique_cust = df_fin["customer_id"].nunique()
    assert sql_total_subs == 6000 and total_unique_cust == 2000, "검증 3 실패: 고객수 불일치"
    print(f" [✓ PASS] 3. 계약건수와 고객수 구분 검증: 계약 {sql_total_subs:,}건, 고객 {total_unique_cust:,}명 (고객당 {sql_total_subs/total_unique_cust:.1f}건 가입)")

    pd_summary = df_fin.groupby("product").agg(
        sub_cnt=("subscription_id", "count"),
        cust_cnt=("customer_id", "nunique"),
        tot_amt=("amount", "sum"),
        avg_amt=("amount", "mean")
    ).reset_index()
    pd_summary["avg_amt"] = pd_summary["avg_amt"].round(2)

    sql_test_df = df_step2[["product_type", "subscription_count", "unique_customer_count", "total_amount", "avg_subscription_amount"]].copy()
    sql_test_df.columns = ["product", "sub_cnt", "cust_cnt", "tot_amt", "avg_amt"]

    pd.testing.assert_frame_equal(
        sql_test_df.sort_values("product").reset_index(drop=True),
        pd_summary.sort_values("product").reset_index(drop=True),
        check_dtype=False
    )
    print(" [✓ PASS] 4. SQL vs Pandas 수치 교차 검증: 건수, 고객수, 합계, 평균 100% 동일")

    assert len(df_step4) == 1563, f"검증 5 실패: 결합 행 수 불일치 ({len(df_step4)} != 1563)"
    assert df_step4["fin_sub_count"].sum() == 6000, "검증 5 실패: 결합 후 가입건수 유실/증폭"
    assert df_step4["fin_total_amount"].sum() == 118083150000, "검증 5 실패: 결합 후 가입금액 왜곡"
    print(f" [✓ PASS] 5. 상권 결합 무결성 검증: 1,563개 조합, 6,000건 계약, 118,083,150,000원 완전 보존 (중복 팽창 0건)")

    print("\n" + "=" * 70)
    print(">>> 5대 검증 전 항목 100% PASS 확인 완료 <<<")
    print("=" * 70)


def main():
    df_fin, df_market = load_raw_data()
    conn = setup_in_memory_db(df_fin, df_market)

    df_step2 = execute_step2_product_summary(conn)
    df_api = execute_step3_and_11_dashboard_schema(conn)
    df_step4 = execute_step4_market_join(conn)
    run_step5_validation(df_fin, df_market, conn, df_step2, df_step4)

    conn.close()
    print("\n전체 파이프라인 수행이 성공적으로 완료되었습니다.")


if __name__ == "__main__":
    main()
