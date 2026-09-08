import tempfile
import unittest
from pathlib import Path

from openpyxl import Workbook

from statement_parser import parse_statement_file


class StatementParserTests(unittest.TestCase):
    def test_alipay_gb18030_csv_skips_neutral_and_closed_rows(self):
        content = "\n".join([
            "支付宝账单",
            "交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注",
            "2026-08-20 10:00:00,日用百货,网购商户,/,商品,支出,88.00,余额,交易成功,1,1,",
            "2026-08-20 11:00:00,退款,网购商户,/,退款-商品,不计收支,88.00,余额,退款成功,2,2,",
            "2026-08-20 12:00:00,日用百货,关闭商户,/,商品,支出,30.00,余额,交易关闭,3,3,",
            "2026-08-20 13:00:00,账户存取,中性商户,/,转存,不计收支,50.00,余额,交易成功,4,4,",
        ])
        with tempfile.TemporaryDirectory() as raw_dir:
            path = Path(raw_dir) / "alipay.csv"
            path.write_bytes(content.encode("gb18030"))
            result = parse_statement_file(path)

        self.assertEqual(result["platform"], "alipay")
        self.assertEqual(len(result["candidates"]), 2)
        self.assertEqual(result["skipped"], 2)
        self.assertEqual(result["candidates"][1]["type"], "income")
        self.assertEqual(result["candidates"][1]["categoryId"], "refund")

    def test_wechat_xlsx_parses_excel_date_and_bank_card(self):
        with tempfile.TemporaryDirectory() as raw_dir:
            path = Path(raw_dir) / "wechat.xlsx"
            workbook = Workbook()
            sheet = workbook.active
            sheet.append(["微信支付账单明细"])
            sheet.append([
                "交易时间", "交易类型", "交易对方", "商品", "收/支", "金额(元)",
                "支付方式", "当前状态", "交易单号", "商户单号", "备注",
            ])
            sheet.append([
                "2026-08-28 20:26:30", "商户消费", "滴滴出行", "打车", "支出", 13.3,
                "宁波银行储蓄卡(6128)", "支付成功", "1", "2", "/",
            ])
            sheet.append([
                "2026-08-28 21:00:00", "零钱提现", "银行", "/", "/", 100,
                "银行卡", "提现到账", "3", "/", "/",
            ])
            workbook.save(path)
            result = parse_statement_file(path)

        self.assertEqual(result["platform"], "wechat")
        self.assertEqual(len(result["candidates"]), 1)
        candidate = result["candidates"][0]
        self.assertEqual(candidate["amountCents"], 1330)
        self.assertEqual(candidate["categoryId"], "transport")
        self.assertEqual(candidate["paymentMethod"], "bank_card")
        self.assertEqual(candidate["transactionTime"], "2026-08-28T20:26:30")


if __name__ == "__main__":
    unittest.main()
