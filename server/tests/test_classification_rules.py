import unittest

from main import _sanitize_candidate
from statement_parser import _category_id


class ClassificationRuleTests(unittest.TestCase):
    def test_ai_fallback_classifies_platforms_and_fresh_juice(self):
        self.assertEqual(
            _sanitize_candidate(
                {"type": "expense", "merchant": "滴滴出行", "categoryId": "other"}
            )["categoryId"],
            "transport",
        )
        self.assertEqual(
            _sanitize_candidate(
                {
                    "type": "expense",
                    "merchant": "美团",
                    "description": "某某餐厅订单",
                    "categoryId": "other",
                }
            )["categoryId"],
            "food",
        )
        self.assertEqual(
            _sanitize_candidate(
                {"type": "expense", "merchant": "鲜榨果汁", "categoryId": "other"}
            )["categoryId"],
            "food",
        )

    def test_statement_import_classifies_fresh_juice(self):
        self.assertEqual(_category_id("鲜榨果汁 商户消费", "expense"), "food")

    def test_restaurant_names_are_food(self):
        for merchant in ("老街重庆小面", "兰州牛肉面馆", "阿姨麻辣烫", "巷口粥铺"):
            with self.subTest(merchant=merchant):
                self.assertEqual(
                    _sanitize_candidate(
                        {"type": "expense", "merchant": merchant, "categoryId": "other"}
                    )["categoryId"],
                    "food",
                )

    def test_shared_bike_and_hardware_have_deterministic_categories(self):
        self.assertEqual(
            _sanitize_candidate(
                {"type": "expense", "merchant": "小遛", "categoryId": "other"}
            )["categoryId"],
            "transport",
        )
        self.assertEqual(
            _sanitize_candidate(
                {
                    "type": "expense",
                    "merchant": "五金店",
                    "description": "购买螺丝钉",
                    "categoryId": "housing",
                }
            )["categoryId"],
            "shopping",
        )
        self.assertEqual(_category_id("小遛共享电动车", "expense"), "transport")
        self.assertEqual(_category_id("购买螺丝钉", "expense"), "shopping")


if __name__ == "__main__":
    unittest.main()
