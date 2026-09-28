"""
==============================================================================
프로젝트: KB Bridge 대시보드 API 엔드포인트 연계 예시 (Flask)
담당: 2번 담당자 -> 대시보드/백엔드 개발팀 전달용
API: GET /api/products
==============================================================================
"""

import json
import os
from flask import Flask, jsonify, request

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(BASE_DIR, "..", "data", "dashboard", "api_products.json")
if not os.path.exists(DATA_FILE):
    DATA_FILE = os.path.join(BASE_DIR, "api_products.json")

# 메모리에 미리 로드 (성능 최적화)
if os.path.exists(DATA_FILE):
    with open(DATA_FILE, "r", encoding="utf-8") as f:
        PRODUCTS_DATA = json.load(f)
else:
    PRODUCTS_DATA = []


@app.route("/api/products", methods=["GET"])
def get_products():
    """
    대시보드 전달용 금융상품 요약 API
    Query Parameters:
      - region_code (int): 행정동 코드 필터 (예: 11110515)
      - industry (str): 업종 필터 (예: '음식·음료')
      - product_type (str): 상품 필터 (예: '예금', '적금', 'ISA', '펀드')
    """
    region_code = request.args.get("region_code", type=int)
    industry = request.args.get("industry", type=str)
    product_type = request.args.get("product_type", type=str)

    results = PRODUCTS_DATA

    if region_code:
        results = [r for r in results if r["region_code"] == region_code]
    if industry:
        results = [r for r in results if r["industry"] == industry]
    if product_type:
        results = [r for r in results if r["product_type"] == product_type]

    return jsonify({
        "status": "success",
        "total_count": len(results),
        "data": results
    })


if __name__ == "__main__":
    app.run(debug=True, port=5000)
